#pragma once

#include <cstddef>
#include <cstdint>

template <std::size_t Capacity>
class ByteQueue {
 public:
  static_assert(Capacity > 0, "ByteQueue capacity must be positive");

  bool append(const uint8_t* const bytes, const std::size_t count) {
    if (count > Capacity - size_) {
      return false;
    }

    for (std::size_t index = 0; index < count; ++index) {
      data_[(head_ + size_ + index) % Capacity] = bytes[index];
    }
    size_ += count;
    return true;
  }

  void clear() {
    head_ = 0;
    size_ = 0;
  }

  const uint8_t* data() const { return &data_[head_]; }

  std::size_t contiguousSize() const {
    if (size_ == 0) {
      return 0;
    }
    return size_ < Capacity - head_ ? size_ : Capacity - head_;
  }

  void consume(const std::size_t count) {
    if (count >= size_) {
      clear();
      return;
    }

    head_ = (head_ + count) % Capacity;
    size_ -= count;
  }

  bool empty() const { return size_ == 0; }

 private:
  uint8_t data_[Capacity]{};
  std::size_t head_ = 0;
  std::size_t size_ = 0;
};
