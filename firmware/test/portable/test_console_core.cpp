#include <cstdlib>
#include <iostream>
#include <string>

#include "../../src/auth_gate.h"
#include "../../src/byte_queue.h"
#include "../../src/ring_buffer.h"

namespace {

void require(const bool condition, const char* const message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
  }
}

void ring_buffer_replays_bytes_in_arrival_order() {
  RingBuffer<4> buffer;
  buffer.push('A');
  buffer.push('B');
  buffer.push('C');

  std::string replay;
  buffer.forEach([&replay](const uint8_t byte) { replay += static_cast<char>(byte); });

  require(replay == "ABC", "ring buffer must replay bytes in arrival order");
}

void ring_buffer_evicts_the_oldest_byte_when_full() {
  RingBuffer<4> buffer;
  for (const char byte : std::string("ABCDE")) {
    buffer.push(static_cast<uint8_t>(byte));
  }

  std::string replay;
  buffer.forEach([&replay](const uint8_t byte) { replay += static_cast<char>(byte); });

  require(buffer.size() == 4, "ring buffer must retain its fixed capacity");
  require(replay == "BCDE", "ring buffer must evict the oldest byte on overflow");
}

void ring_buffer_exposes_wrapped_history_as_ordered_chunks() {
  RingBuffer<4> buffer;
  for (const char byte : std::string("ABCDE")) {
    buffer.push(static_cast<uint8_t>(byte));
  }

  std::string replay;
  buffer.forEachChunk([&replay](const uint8_t* const bytes, const std::size_t size) {
    replay.append(reinterpret_cast<const char*>(bytes), size);
  });

  require(replay == "BCDE", "wrapped ring buffer chunks must preserve arrival order");
}

void byte_queue_preserves_order_across_wraparound() {
  ByteQueue<5> queue;
  const uint8_t first[] = {'A', 'B', 'C', 'D'};
  require(queue.append(first, sizeof(first)), "queue must accept data that fits");
  queue.consume(3);

  const uint8_t second[] = {'E', 'F', 'G'};
  require(queue.append(second, sizeof(second)), "queue must reuse consumed space");

  std::string output;
  while (!queue.empty()) {
    output.append(reinterpret_cast<const char*>(queue.data()), queue.contiguousSize());
    queue.consume(queue.contiguousSize());
  }

  require(output == "DEFG", "queue must preserve byte order across wraparound");
}

void byte_queue_rejects_overflow_without_discarding_queued_data() {
  ByteQueue<4> queue;
  const uint8_t initial[] = {'A', 'B', 'C'};
  const uint8_t overflow[] = {'D', 'E'};
  require(queue.append(initial, sizeof(initial)), "queue must accept initial data");
  require(!queue.append(overflow, sizeof(overflow)), "queue must reject an overflowing append");

  std::string output;
  while (!queue.empty()) {
    output.append(reinterpret_cast<const char*>(queue.data()), queue.contiguousSize());
    queue.consume(queue.contiguousSize());
  }

  require(output == "ABC", "rejected overflow must leave queued data unchanged");
}

void password_gate_rejects_a_wrong_line_and_accepts_a_later_correct_line() {
  PasswordGate gate("correct horse battery staple");
  PasswordResult result = PasswordResult::kWaiting;

  for (const char byte : std::string("wrong\n")) {
    result = gate.consume(byte);
  }

  require(result == PasswordResult::kRejected, "wrong password line must be rejected");
  require(!gate.authenticated(), "wrong password must not authenticate the client");

  for (const char byte : std::string("correct horse battery staple\r\n")) {
    result = gate.consume(byte);
  }

  require(result == PasswordResult::kAuthenticated,
          "correct password line must authenticate after a prior rejection");
  require(gate.authenticated(), "successful password line must open the gate");
}

void password_gate_rejects_an_overlong_line_without_authenticating() {
  PasswordGate gate("short-password");
  PasswordResult result = PasswordResult::kWaiting;

  for (std::size_t index = 0; index < PasswordGate::kMaxLineLength + 1; ++index) {
    result = gate.consume('x');
  }
  result = gate.consume('\n');

  require(result == PasswordResult::kOverlong, "overlong password line must be rejected");
  require(!gate.authenticated(), "overlong password line must not open the gate");
}

}  // namespace

int main() {
  ring_buffer_replays_bytes_in_arrival_order();
  ring_buffer_evicts_the_oldest_byte_when_full();
  ring_buffer_exposes_wrapped_history_as_ordered_chunks();
  byte_queue_preserves_order_across_wraparound();
  byte_queue_rejects_overflow_without_discarding_queued_data();
  password_gate_rejects_a_wrong_line_and_accepts_a_later_correct_line();
  password_gate_rejects_an_overlong_line_without_authenticating();
  std::cout << "PASS: portable console core\n";
  return 0;
}
