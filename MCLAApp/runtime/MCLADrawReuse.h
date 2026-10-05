#pragma once
#include <array>
#include <bit>
#include <cstdint>
#include <cstring>

namespace mcla::metal {
// Copy only shader-readable float registers. A null mask deliberately means
// full copy (clear commands, probes and callers without shader metadata).
inline void CopyConstantRegisters(uint8_t* dst, const uint8_t* src,
                                  const uint64_t* mask) {
  if (!mask) { std::memcpy(dst, src, 4096); return; }
  for (unsigned block = 0; block != 4; ++block) {
    uint64_t bits = mask[block];
    while (bits) {
      const unsigned first = std::countr_zero(bits);
      const unsigned count = std::countr_one(bits >> first);
      std::memcpy(dst + (block * 64 + first) * 16,
                  src + (block * 64 + first) * 16, count * 16);
      bits &= count == 64 ? 0 : ~(((uint64_t(1) << count) - 1) << first);
    }
  }
}
// No hash-only identity or padding bytes: keys are explicit fixed-size words.
template <size_t N> struct ExactDrawKey {
  std::array<uint64_t, N> words{};
  bool valid = false;
  bool Matches(const std::array<uint64_t, N>& next) const {
    return valid && words == next;
  }
  void Remember(const std::array<uint64_t, N>& next) { words = next; valid = true; }
  void Reset() { valid = false; }
};
} // namespace mcla::metal
