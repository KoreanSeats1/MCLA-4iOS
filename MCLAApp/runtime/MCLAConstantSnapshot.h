#pragma once
#include <array>
#include <bit>
#include <cstdint>
#include <cstring>

namespace mcla::metal {
// Exact-byte validation, not a shader/guest-pointer identity cache. Constants
// can change without a binding change (including NaNs and signed zero).
// Dynamic-index shaders already carry all 256 bits in their generated mask.
class ConstantSnapshot {
  std::array<uint8_t, 4096> bytes_{};
  std::array<uint64_t, 4> valid_{};
  bool initialized_ = false;
public:
  void Reset() { initialized_ = false; }
  bool Matches(const uint8_t* source, const uint64_t mask[4]) const {
    if (!initialized_) return false;
    for (unsigned b = 0; b < 4; ++b) {
      if (mask[b] & ~valid_[b]) return false;
      if (mask[b] == UINT64_MAX) {
        if (std::memcmp(bytes_.data() + b * 1024, source + b * 1024, 1024))
          return false;
      } else for (uint64_t bits = mask[b]; bits; bits &= bits - 1) {
        const unsigned offset = (b * 64 + std::countr_zero(bits)) * 16;
        if (std::memcmp(bytes_.data() + offset, source + offset, 16)) return false;
      }
    }
    return true;
  }
  void Remember(const uint8_t* source, const uint64_t mask[4]) {
    for (unsigned b = 0; b < 4; ++b) {
      valid_[b] = mask[b];
      if (mask[b] == UINT64_MAX)
        std::memcpy(bytes_.data() + b * 1024, source + b * 1024, 1024);
      else for (uint64_t bits = mask[b]; bits; bits &= bits - 1) {
        const unsigned offset = (b * 64 + std::countr_zero(bits)) * 16;
        std::memcpy(bytes_.data() + offset, source + offset, 16);
      }
    }
    initialized_ = true;
  }
};
} // namespace mcla::metal
