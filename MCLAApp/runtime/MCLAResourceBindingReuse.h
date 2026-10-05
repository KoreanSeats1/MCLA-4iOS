#pragma once
#include <array>
#include <bit>
#include <cstdint>
#include <cstring>

namespace mcla::metal {
// Hits overwrite all texture indices and LODs from the immutable group.
// Initialize only the other bytes to avoid copying 624 bytes twice per draw.
inline void InitializeSharedConstants(uint8_t* dst,const uint8_t* defaults,bool groupHit) {
  if(!groupHit) { std::memcpy(dst,defaults,1056);return; }
  std::memcpy(dst+520,defaults+520,232);
  std::memcpy(dst+856,defaults+856,200);
}
template <size_t N> class ExactByteSnapshot {
  std::array<uint8_t,N> bytes_{};
  bool valid_ = false;
public:
  bool Matches(const uint8_t* bytes) const {
    return valid_ && std::memcmp(bytes_.data(),bytes,N)==0;
  }
  void Remember(const uint8_t* bytes) {
    std::memcpy(bytes_.data(),bytes,N); valid_=true;
  }
  void Reset() { valid_=false; }
};

// Only shader-readable slots affect a texture group. Remember all six fetch
// words and the authoritative wrapper for every used slot. Frame/serial guard
// the upload-ring lifetime and resolved textures/guest writes respectively.
class TextureGroupSnapshot {
  std::array<std::array<uint8_t,28>,26> slots_{};
  uint64_t frame_=0, serial_=0;
  uint32_t mask_=0;
  bool valid_=false;
public:
  bool Matches(uint64_t frame,uint64_t serial,uint32_t mask,
               const uint8_t* fetches,const uint8_t* handles) const {
    if (!valid_ || frame_!=frame || serial_!=serial || mask_!=mask) return false;
    for (uint32_t bits=mask&0x3FFFFFF;bits;bits&=bits-1) {
      const unsigned slot=std::countr_zero(bits);
      if (std::memcmp(slots_[slot].data(),fetches+slot*24,24) ||
          std::memcmp(slots_[slot].data()+24,handles+slot*4,4)) return false;
    }
    return true;
  }
  void Remember(uint64_t frame,uint64_t serial,uint32_t mask,
                const uint8_t* fetches,const uint8_t* handles) {
    for (uint32_t bits=mask&0x3FFFFFF;bits;bits&=bits-1) {
      const unsigned slot=std::countr_zero(bits);
      std::memcpy(slots_[slot].data(),fetches+slot*24,24);
      std::memcpy(slots_[slot].data()+24,handles+slot*4,4);
    }
    frame_=frame; serial_=serial; mask_=mask; valid_=true;
  }
  void Reset() { valid_=false; }
};
} // namespace mcla::metal
