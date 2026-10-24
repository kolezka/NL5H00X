#pragma once

#include <cstddef>

enum class PasswordResult {
  kWaiting,
  kRejected,
  kOverlong,
  kAuthenticated,
};

class PasswordGate {
 public:
  static constexpr std::size_t kMaxLineLength = 64;

  explicit PasswordGate(const char* password) : password_(password) {
    while (password_[passwordLength_] != '\0' && passwordLength_ < kMaxLineLength) {
      ++passwordLength_;
    }
  }

  PasswordResult consume(const char byte) {
    if (authenticated_) {
      return PasswordResult::kAuthenticated;
    }

    if (byte == '\r') {
      return PasswordResult::kWaiting;
    }

    if (byte == '\n') {
      const PasswordResult result = lineTooLong_ ? PasswordResult::kOverlong : finishLine();
      resetLine();
      return result;
    }

    if (lineLength_ == kMaxLineLength) {
      lineTooLong_ = true;
      return PasswordResult::kWaiting;
    }

    line_[lineLength_++] = byte;
    return PasswordResult::kWaiting;
  }

  bool authenticated() const { return authenticated_; }

  void reset() {
    authenticated_ = false;
    resetLine();
  }

 private:
  PasswordResult finishLine() {
    if (lineLength_ != passwordLength_) {
      return PasswordResult::kRejected;
    }

    for (std::size_t index = 0; index < passwordLength_; ++index) {
      if (line_[index] != password_[index]) {
        return PasswordResult::kRejected;
      }
    }

    authenticated_ = true;
    return PasswordResult::kAuthenticated;
  }

  void resetLine() {
    lineLength_ = 0;
    lineTooLong_ = false;
  }

  const char* password_;
  std::size_t passwordLength_ = 0;
  char line_[kMaxLineLength]{};
  std::size_t lineLength_ = 0;
  bool lineTooLong_ = false;
  bool authenticated_ = false;
};
