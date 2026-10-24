#pragma once

#if __has_include("secrets.h")
#include "secrets.h"
#else
#error "Missing firmware/include/secrets.h. Copy secrets.example.h to secrets.h and set all values."
#endif

#if __has_include("secrets.h")
#if !defined(WIFI_STA_SSID) || !defined(WIFI_STA_PASSWORD) || !defined(AP_FALLBACK_SSID) || \
    !defined(AP_FALLBACK_PASSWORD) || !defined(UART_CONSOLE_PASSWORD)
#error "firmware/include/secrets.h must define all five required configuration values"
#elif !defined(OTA_PASSWORD)
#error "firmware/include/secrets.h must define OTA_PASSWORD, see secrets.example.h"
#else
namespace firmware_config {

constexpr bool stringsEqual(const char* left, const char* right) {
  return *left == *right && (*left == '\0' || stringsEqual(left + 1, right + 1));
}

}  // namespace firmware_config

static_assert(sizeof(WIFI_STA_SSID) <= 33,
              "WIFI_STA_SSID must contain at most 32 characters");
static_assert(sizeof(WIFI_STA_SSID) == 1 ||
                  (sizeof(WIFI_STA_PASSWORD) >= 9 && sizeof(WIFI_STA_PASSWORD) <= 64),
              "Set both station values, using an 8 to 63 character Wi-Fi password, or leave both empty");
static_assert(sizeof(WIFI_STA_SSID) > 1 || sizeof(WIFI_STA_PASSWORD) == 1,
              "WIFI_STA_PASSWORD must be empty when WIFI_STA_SSID is empty");
static_assert(sizeof(AP_FALLBACK_SSID) > 1, "AP_FALLBACK_SSID cannot be empty");
static_assert(sizeof(AP_FALLBACK_SSID) <= 33,
              "AP_FALLBACK_SSID must contain at most 32 characters");
static_assert(sizeof(AP_FALLBACK_PASSWORD) >= 9 && sizeof(AP_FALLBACK_PASSWORD) <= 64,
              "AP_FALLBACK_PASSWORD must contain 8 to 63 characters");
static_assert(sizeof(UART_CONSOLE_PASSWORD) >= 13,
              "UART_CONSOLE_PASSWORD must be at least 12 characters");
static_assert(sizeof(UART_CONSOLE_PASSWORD) <= 65,
              "UART_CONSOLE_PASSWORD must contain at most 64 characters");
static_assert(!firmware_config::stringsEqual(AP_FALLBACK_PASSWORD,
                                             "replace-with-strong-ap-password"),
              "Replace the fallback AP password placeholder before flashing");
static_assert(!firmware_config::stringsEqual(UART_CONSOLE_PASSWORD,
                                             "replace-with-a-long-unique-console-password"),
              "Replace the console password placeholder before flashing");
static_assert(sizeof(OTA_PASSWORD) >= 13 && sizeof(OTA_PASSWORD) <= 65,
              "OTA_PASSWORD must contain 12 to 64 characters");
static_assert(!firmware_config::stringsEqual(OTA_PASSWORD,
                                             "replace-with-a-long-unique-ota-password"),
              "Replace the OTA password placeholder before flashing");
#endif
#endif
