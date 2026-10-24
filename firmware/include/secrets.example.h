#pragma once

// Copy this file to secrets.h, then replace every placeholder before flashing.
// secrets.h is intentionally ignored by Git.
// Leave these two empty for AP-only mode, or fill in both for home Wi-Fi.
#define WIFI_STA_SSID ""
#define WIFI_STA_PASSWORD ""

// Used only if the ESP32 cannot join the station network at boot. The bridge
// restarts and retries the station network after 5 idle minutes on this AP.
#define AP_FALLBACK_SSID "projector-uart-setup"
#define AP_FALLBACK_PASSWORD "replace-with-strong-ap-password"

// Sent in plaintext over TCP. Use a unique long value on a trusted network.
#define UART_CONSOLE_PASSWORD "replace-with-a-long-unique-console-password"

// Required to flash new firmware over Wi-Fi. Pass the same value to
// `pio run -e ota -t upload` through PROJECTOR_OTA_PASSWORD.
#define OTA_PASSWORD "replace-with-a-long-unique-ota-password"
