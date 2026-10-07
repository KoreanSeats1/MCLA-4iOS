#pragma once
#include "MCLADrawReuse.h"
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
      } else for(uint64_t bits=mask[b];bits;) {
        const unsigned first=std::countr_zero(bits),count=std::countr_one(bits>>first);
        const unsigned offset=(b*64+first)*16;
        if(std::memcmp(bytes_.data()+offset,source+offset,count*16))return false;
        bits &= count==64?0:~(((uint64_t(1)<<count)-1)<<first);
      }
    }
    return true;
  }
  void Remember(const uint8_t* source, const uint64_t mask[4]) {
    CopyConstantRegisters(bytes_.data(),source,mask);
    std::memcpy(valid_.data(),mask,sizeof(valid_));
    initialized_ = true;
  }
};
} // namespace mcla::metal
