#pragma once

#include <cstddef>
#include <cstdint>

template <std::size_t Capacity>
class RingBuffer {
 public:
  static_assert(Capacity > 0, "RingBuffer capacity must be positive");

  void push(const uint8_t byte) {
    if (size_ == Capacity) {
      head_ = (head_ + 1) % Capacity;
      --size_;
    }

    data_[(head_ + size_) % Capacity] = byte;
    ++size_;
  }

  std::size_t size() const { return size_; }

  void clear() {
    head_ = 0;
    size_ = 0;
  }

  template <typename Visitor>
  void forEach(Visitor visitor) const {
    for (std::size_t index = 0; index < size_; ++index) {
      visitor(data_[(head_ + index) % Capacity]);
    }
  }

  template <typename Visitor>
  void forEachChunk(Visitor visitor) const {
    if (size_ == 0) {
      return;
    }

    const std::size_t firstChunkSize =
        size_ < Capacity - head_ ? size_ : Capacity - head_;
    visitor(&data_[head_], firstChunkSize);

    const std::size_t secondChunkSize = size_ - firstChunkSize;
    if (secondChunkSize > 0) {
      visitor(data_, secondChunkSize);
    }
  }

 private:
  uint8_t data_[Capacity]{};
  std::size_t head_ = 0;
  std::size_t size_ = 0;
};
