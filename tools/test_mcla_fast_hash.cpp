#include "../MCLAApp/runtime/MCLAFastHash.h"
#include <array>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <initializer_list>
#include <span>

int main() {
  std::array<uint8_t, 256> bytes{};
  for (size_t i = 0; i < bytes.size(); ++i) bytes[i] = uint8_t(i * 37);
  const uint64_t seed = 0x1234567890ABCDEFull;
  for (size_t size : {size_t(4), size_t(8), size_t(24), size_t(40),
                      size_t(80), size_t(128), size_t(256)}) {
    const auto first = mcla::metal::FastHash(bytes.data(), size, seed);
    assert(first == mcla::metal::FastHash(bytes.data(), size, seed));
    assert(first != mcla::metal::FastHash(bytes.data(), size, seed + 1));
    bytes[size - 1] ^= 1;
    assert(first != mcla::metal::FastHash(bytes.data(), size, seed));
    bytes[size - 1] ^= 1;
  }
  volatile uint64_t sink = 0;
  const auto begin = std::chrono::steady_clock::now();
  for (unsigned i = 0; i < 1000000; ++i)
    sink = mcla::metal::FastHash(bytes.data(), 128, uint64_t(i));
  const auto elapsed = std::chrono::duration<double, std::milli>(
      std::chrono::steady_clock::now() - begin).count();
  const auto oldBegin = std::chrono::steady_clock::now();
  for (unsigned i = 0; i < 1000000; ++i) {
    uint64_t hash = uint64_t(i);
    for (auto byte : std::span(bytes.data(), size_t(128)))
      hash = (hash ^ byte) * 1099511628211ull;
    sink = hash;
  }
  const auto oldElapsed = std::chrono::duration<double, std::milli>(
      std::chrono::steady_clock::now() - oldBegin).count();
  std::printf("MCLA cache-key test passed; 1M 128-byte keys: XXH3 %.2f ms, FNV %.2f ms; sink=%llu\n",
              elapsed, oldElapsed, static_cast<unsigned long long>(sink));
}
