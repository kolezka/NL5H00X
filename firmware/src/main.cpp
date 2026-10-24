#include <Arduino.h>
#include <ArduinoOTA.h>
#include <ESPmDNS.h>
#include <Update.h>
#include <WebServer.h>
#include <WiFi.h>
#include <driver/gpio.h>
#include <errno.h>
#include <esp_system.h>
#include <lwip/sockets.h>
#include <stdio.h>
#include <sys/socket.h>

#include "auth_gate.h"
#include "byte_queue.h"
#include "ring_buffer.h"
#include "status_page.h"
#include "../include/config.h"

namespace {

// UART1 on plain GPIOs. GPIO16 is the C6 ROM log pin, so it must never reach projector RX.
constexpr int kProjectorRxPin = 20;
constexpr int kProjectorTxPin = 19;
constexpr uint32_t kProjectorBaud = 115200;
constexpr uint32_t kProjectorOffAfterLowMs = 500;
constexpr uint32_t kProjectorOnAfterHighMs = 50;
constexpr uint16_t kConsolePort = 2323;
constexpr uint16_t kOtaPort = 3232;
constexpr char kHostname[] = "projector-uart";
constexpr uint32_t kStationConnectTimeoutMs = 30000;
constexpr uint32_t kAccessPointRetryStationMs = 5 * 60 * 1000;
constexpr uint32_t kAuthenticationTimeoutMs = 30000;
constexpr std::size_t kHistoryCapacity = 16384;
constexpr std::size_t kNetworkOutputCapacity = 32768;
constexpr std::size_t kMaximumNetworkWrite = 1024;
constexpr int kKeepAliveIdleSeconds = 15;
constexpr int kKeepAliveIntervalSeconds = 5;
constexpr int kKeepAliveProbeCount = 3;

HardwareSerial projectorUart(1);
bool projectorUartAttached = false;
uint32_t projectorLineHighAtMs = 0;
uint32_t projectorLineLowAtMs = 0;
WiFiServer consoleServer(kConsolePort, 1);
WiFiClient consoleClient;
RingBuffer<kHistoryCapacity> uartHistory;
ByteQueue<kNetworkOutputCapacity> networkOutput;
PasswordGate passwordGate(UART_CONSOLE_PASSWORD);
uint32_t clientConnectedAtMs = 0;
bool runningFallbackAccessPoint = false;
uint32_t lastClientActivityMs = 0;
WebServer statusServer(80);
uint64_t uartReceivedBytes = 0;
uint64_t uartSentBytes = 0;
uint32_t lastUartByteMs = 0;
bool uartEverReceived = false;

const char* resetReasonText() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "power on";
    case ESP_RST_BROWNOUT: return "BROWNOUT (supply too weak)";
    case ESP_RST_SW: return "software restart";
    case ESP_RST_PANIC: return "crash";
    case ESP_RST_INT_WDT:
    case ESP_RST_TASK_WDT:
    case ESP_RST_WDT: return "watchdog";
    case ESP_RST_EXT: return "reset pin";
    default: return "other";
  }
}

bool clientIsAuthenticated() {
  return consoleClient && consoleClient.connected() && passwordGate.authenticated();
}

bool configureKeepAlive(WiFiClient& client) {
  const int enabled = 1;
  const int idleSeconds = kKeepAliveIdleSeconds;
  const int intervalSeconds = kKeepAliveIntervalSeconds;
  const int probeCount = kKeepAliveProbeCount;

  return client.setSocketOption(SOL_SOCKET, SO_KEEPALIVE, &enabled, sizeof(enabled)) == 0 &&
         client.setSocketOption(IPPROTO_TCP, TCP_KEEPIDLE, &idleSeconds,
                                sizeof(idleSeconds)) == 0 &&
         client.setSocketOption(IPPROTO_TCP, TCP_KEEPINTVL, &intervalSeconds,
                                sizeof(intervalSeconds)) == 0 &&
         client.setSocketOption(IPPROTO_TCP, TCP_KEEPCNT, &probeCount,
                                sizeof(probeCount)) == 0;
}

void closeClient() {
  consoleClient.stop();
  networkOutput.clear();
  passwordGate.reset();
  clientConnectedAtMs = 0;
  lastClientActivityMs = millis();
}

bool queueClientOutput(const uint8_t* const bytes, const std::size_t size) {
  if (!consoleClient || !consoleClient.connected()) {
    return false;
  }

  if (!networkOutput.append(bytes, size)) {
    closeClient();
    return false;
  }

  return true;
}

template <std::size_t Size>
bool queueClientOutput(const char (&text)[Size]) {
  return queueClientOutput(reinterpret_cast<const uint8_t*>(text), Size - 1);
}

void captureProjectorOutput() {
  uint8_t bytes[256];

  while (projectorUart.available() > 0) {
    const std::size_t available = static_cast<std::size_t>(projectorUart.available());
    const std::size_t requested = available < sizeof(bytes) ? available : sizeof(bytes);
    const std::size_t received = projectorUart.read(bytes, requested);

    for (std::size_t index = 0; index < received; ++index) {
      uartHistory.push(bytes[index]);
    }
    if (received > 0) {
      uartReceivedBytes += received;
      lastUartByteMs = millis();
      uartEverReceived = true;
    }

    if (clientIsAuthenticated() && received > 0) {
      queueClientOutput(bytes, received);
    }
  }
}

// The bridge may run from the projector's IR receiver supply, so keep current peaks low.
void limitTransmitPower() {
  WiFi.setTxPower(WIFI_POWER_11dBm);
}

bool connectToStation() {
  if (WIFI_STA_SSID[0] == '\0') {
    return false;
  }

  WiFi.mode(WIFI_STA);
  limitTransmitPower();
  WiFi.setHostname(kHostname);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_STA_SSID, WIFI_STA_PASSWORD);

  const uint32_t startedAtMs = millis();
  while (WiFi.status() != WL_CONNECTED &&
         millis() - startedAtMs < kStationConnectTimeoutMs) {
    captureProjectorOutput();
    delay(1);
  }

  return WiFi.status() == WL_CONNECTED;
}

void startFallbackAccessPoint() {
  WiFi.disconnect(true, false);
  WiFi.mode(WIFI_AP);
  limitTransmitPower();
  WiFi.softAPsetHostname(kHostname);

  while (!WiFi.softAP(AP_FALLBACK_SSID, AP_FALLBACK_PASSWORD, 1, false, 1)) {
    captureProjectorOutput();
    delay(250);
  }
  runningFallbackAccessPoint = true;
}

void startNetworkConsole() {
  WiFi.persistent(false);
  if (connectToStation()) {
    Serial.printf("Joined %s as %s, console on port %u\n", WIFI_STA_SSID,
                  WiFi.localIP().toString().c_str(), kConsolePort);
  } else {
    startFallbackAccessPoint();
    Serial.printf("Station failed, AP %s at %s, console on port %u\n", AP_FALLBACK_SSID,
                  WiFi.softAPIP().toString().c_str(), kConsolePort);
  }

  MDNS.begin(kHostname);
  MDNS.addService("projector-uart", "tcp", kConsolePort);
  MDNS.enableArduino(kOtaPort, true);

  consoleServer.begin();
  consoleServer.setNoDelay(true);
  lastClientActivityMs = millis();
}

// The router may boot slower than the projector, so the AP is never a final state.
void retryStationFromIdleAccessPoint() {
  if (!runningFallbackAccessPoint || WIFI_STA_SSID[0] == '\0' ||
      (consoleClient && consoleClient.connected())) {
    return;
  }

  if (millis() - lastClientActivityMs >= kAccessPointRetryStationMs) {
    ESP.restart();
  }
}

void acceptPendingClient() {
  if (!consoleServer.hasClient()) {
    return;
  }

  WiFiClient candidate = consoleServer.accept();
  if (!candidate) {
    return;
  }

  candidate.setNoDelay(true);
  if (consoleClient && consoleClient.connected()) {
    candidate.stop();
    return;
  }

  if (!configureKeepAlive(candidate)) {
    candidate.stop();
    return;
  }

  closeClient();
  consoleClient = candidate;
  clientConnectedAtMs = millis();

  // Reset reason and uptime show a weak supply without a meter: brownouts or a short uptime.
  char banner[160];
  const int length = snprintf(banner, sizeof(banner),
                              "NL5H00X UART console, local network only.\r\n"
                              "Bridge uptime %lu s, last reset: %s\r\n"
                              "Password: ",
                              static_cast<unsigned long>(millis() / 1000), resetReasonText());
  if (length > 0) {
    queueClientOutput(reinterpret_cast<const uint8_t*>(banner),
                      static_cast<std::size_t>(length) < sizeof(banner)
                          ? static_cast<std::size_t>(length)
                          : sizeof(banner) - 1);
  }
}

bool replayHistory() {
  if (!queueClientOutput("\r\nAuthenticated. Retained UART output follows.\r\n"
                         "--- retained UART output ---\r\n")) {
    return false;
  }

  bool queued = true;
  uartHistory.forEachChunk([&queued](const uint8_t* const bytes, const std::size_t size) {
    if (queued) {
      queued = queueClientOutput(bytes, size);
    }
  });

  return queued &&
         queueClientOutput("\r\n--- live UART, input goes to the projector ---\r\n");
}

void serviceClientOutput() {
  if (!consoleClient || !consoleClient.connected() || networkOutput.empty()) {
    return;
  }

  const std::size_t contiguous = networkOutput.contiguousSize();
  const std::size_t requested =
      contiguous < kMaximumNetworkWrite ? contiguous : kMaximumNetworkWrite;
  const ssize_t sent =
      send(consoleClient.fd(), networkOutput.data(), requested, MSG_DONTWAIT);

  if (sent > 0) {
    networkOutput.consume(static_cast<std::size_t>(sent));
    return;
  }

  if (sent == 0 || (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) {
    closeClient();
  }
}

void serviceClientInput() {
  if (!consoleClient) {
    return;
  }

  if (!consoleClient.connected()) {
    closeClient();
    return;
  }

  lastClientActivityMs = millis();

  if (!passwordGate.authenticated() &&
      millis() - clientConnectedAtMs >= kAuthenticationTimeoutMs) {
    closeClient();
    return;
  }

  while (consoleClient.available() > 0) {
    if (passwordGate.authenticated() && projectorUart.availableForWrite() <= 0) {
      return;
    }

    const int incoming = consoleClient.read();
    if (incoming < 0) {
      return;
    }

    if (passwordGate.authenticated()) {
      projectorUart.write(static_cast<uint8_t>(incoming));
      ++uartSentBytes;
      continue;
    }

    const PasswordResult result = passwordGate.consume(static_cast<char>(incoming));
    if (result == PasswordResult::kAuthenticated) {
      if (!replayHistory()) {
        return;
      }
      continue;
    }

    if (result == PasswordResult::kRejected || result == PasswordResult::kOverlong) {
      closeClient();
      return;
    }
  }
}

// Status only, no UART content: the log stays behind the console password.
void sendStatusJson() {
  const bool station = !runningFallbackAccessPoint;
  const String ip = station ? WiFi.localIP().toString() : WiFi.softAPIP().toString();
  const String clientIp =
      consoleClient && consoleClient.connected() ? consoleClient.remoteIP().toString() : String();
  char lastByteAge[16];
  if (uartEverReceived) {
    snprintf(lastByteAge, sizeof(lastByteAge), "%lu",
             static_cast<unsigned long>((millis() - lastUartByteMs) / 1000));
  } else {
    snprintf(lastByteAge, sizeof(lastByteAge), "null");
  }

  char json[512];
  const int length = snprintf(
      json, sizeof(json),
      "{\"mode\":\"%s\",\"ssid\":\"%s\",\"ip\":\"%s\",\"rssi_dbm\":%d,"
      "\"uptime_s\":%lu,\"reset_reason\":\"%s\",\"free_heap\":%lu,"
      "\"uart_rx_bytes\":%llu,\"uart_tx_bytes\":%llu,\"uart_last_byte_age_s\":%s,"
      "\"client_ip\":\"%s\",\"client_authenticated\":%s,\"projector_powered\":%s}",
      station ? "station" : "access_point", station ? WIFI_STA_SSID : AP_FALLBACK_SSID,
      ip.c_str(), station ? WiFi.RSSI() : 0, static_cast<unsigned long>(millis() / 1000),
      resetReasonText(), static_cast<unsigned long>(ESP.getFreeHeap()),
      static_cast<unsigned long long>(uartReceivedBytes),
      static_cast<unsigned long long>(uartSentBytes), lastByteAge, clientIp.c_str(),
      clientIsAuthenticated() ? "true" : "false", projectorUartAttached ? "true" : "false");

  if (length <= 0 || static_cast<std::size_t>(length) >= sizeof(json)) {
    statusServer.send(500, "text/plain", "status too long");
    return;
  }
  statusServer.sendHeader("Cache-Control", "no-store");
  statusServer.send(200, "application/json", json);
}

// Browser firmware upload. Same OTA_PASSWORD as espota, sent as HTTP basic auth on the LAN.
bool webUpdateAuthorized = false;
String webUpdateError;

void receiveFirmwareChunk() {
  HTTPUpload& upload = statusServer.upload();
  if (upload.status == UPLOAD_FILE_START) {
    webUpdateError = "";
    webUpdateAuthorized = statusServer.authenticate("admin", OTA_PASSWORD);
    if (!webUpdateAuthorized) {
      return;
    }
    Serial.printf("Web update started: %s\n", upload.filename.c_str());
    closeClient();
    if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
      webUpdateError = Update.errorString();
    }
  } else if (!webUpdateAuthorized || !webUpdateError.isEmpty()) {
    if (upload.status == UPLOAD_FILE_ABORTED && Update.isRunning()) {
      Update.abort();
    }
  } else if (upload.status == UPLOAD_FILE_WRITE) {
    if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
      webUpdateError = Update.errorString();
    }
  } else if (upload.status == UPLOAD_FILE_END) {
    if (!Update.end(true)) {
      webUpdateError = Update.errorString();
    }
  } else if (upload.status == UPLOAD_FILE_ABORTED) {
    Update.abort();
    webUpdateError = "upload aborted";
  }
}

void finishFirmwareUpload() {
  if (!webUpdateAuthorized) {
    statusServer.send(401, "text/plain", "wrong OTA password");
    return;
  }
  if (!webUpdateError.isEmpty()) {
    Serial.printf("Web update failed: %s\n", webUpdateError.c_str());
    statusServer.send(500, "text/plain", "update failed: " + webUpdateError);
    return;
  }
  statusServer.sendHeader("Connection", "close");
  statusServer.send(200, "text/plain", "update written, restarting");
  delay(500);
  ESP.restart();
}

void startStatusServer() {
  statusServer.on("/", HTTP_GET, [] { statusServer.send(200, "text/html", kStatusPage); });
  statusServer.on("/status.json", HTTP_GET, sendStatusJson);
  statusServer.on("/update", HTTP_POST, finishFirmwareUpload, receiveFirmwareChunk);
  statusServer.onNotFound([] { statusServer.send(404, "text/plain", "not found"); });
  statusServer.begin();
  MDNS.addService("http", "tcp", 80);
}

// The update blocks loop() for its whole duration, so drop the console client up front.
void startOta() {
  ArduinoOTA.setHostname(kHostname);
  ArduinoOTA.setPort(kOtaPort);
  ArduinoOTA.setPassword(OTA_PASSWORD);
  // mDNS is already running for the console; a second MDNS.begin() would fail.
  ArduinoOTA.setMdnsEnabled(false);
  ArduinoOTA.onStart([] {
    Serial.println("OTA update started");
    closeClient();
  });
  ArduinoOTA.onEnd([] { Serial.println("OTA update done, restarting"); });
  ArduinoOTA.onError([](const ota_error_t error) {
    Serial.printf("OTA update failed: %u\n", static_cast<unsigned>(error));
  });
  ArduinoOTA.begin();
}

// There are no series resistors and the bridge stays powered in standby, so an idle-high
// TX pin would feed the sleeping SoC through its RX pin. Release TX while the projector is off.
void attachProjectorUart() {
  projectorUart.setRxBufferSize(4096);
  projectorUart.begin(kProjectorBaud, SERIAL_8N1, kProjectorRxPin, kProjectorTxPin);
  // Pull-down so an unpowered projector reads as a low line instead of a floating one.
  gpio_pullup_dis(static_cast<gpio_num_t>(kProjectorRxPin));
  gpio_pulldown_en(static_cast<gpio_num_t>(kProjectorRxPin));
  projectorUartAttached = true;
  Serial.println("Projector line high, UART attached");
}

void detachProjectorUart() {
  projectorUart.end();
  pinMode(kProjectorTxPin, INPUT);
  pinMode(kProjectorRxPin, INPUT_PULLDOWN);
  projectorUartAttached = false;
  Serial.println("Projector line low, UART released");
}

// A powered projector holds its TX idle high; a byte is low for under 100 us at 115200.
void followProjectorPower() {
  const uint32_t nowMs = millis();
  if (gpio_get_level(static_cast<gpio_num_t>(kProjectorRxPin)) != 0) {
    projectorLineHighAtMs = nowMs;
  } else {
    projectorLineLowAtMs = nowMs;
  }

  if (projectorUartAttached && nowMs - projectorLineHighAtMs >= kProjectorOffAfterLowMs) {
    detachProjectorUart();
  } else if (!projectorUartAttached && nowMs - projectorLineLowAtMs >= kProjectorOnAfterHighMs) {
    attachProjectorUart();
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  detachProjectorUart();
  startNetworkConsole();
  startStatusServer();
  startOta();
}

void loop() {
  ArduinoOTA.handle();
  followProjectorPower();
  captureProjectorOutput();
  statusServer.handleClient();
  acceptPendingClient();
  serviceClientInput();
  serviceClientOutput();
  retryStationFromIdleAccessPoint();
  delay(1);
}
