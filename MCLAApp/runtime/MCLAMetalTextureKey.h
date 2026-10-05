#pragma once
#include <array>
#include <cstdint>

namespace mcla::metal {
// A sampler change does not change decoded texels. Keep the source, layout,
// numeric format, swizzle and mip extent; strip only sampling-only fields.
constexpr std::array<uint32_t,6> TextureContentKey(std::array<uint32_t,6> words) {
  words[0] &= ~(0x1FFu << 10); // clamp xyz
  words[3] &= ~(0xFFFu << 19); // mag/min/mip, anisotropic/arbitrary filtering
  words[4] &= 0x3FCu;         // retain mip min/max, not filter/LOD bias
  words[5] &= 0xFFFFFE00u;    // dimension, packed mips and mip address
  return words;
}
}
