#pragma once
#import <Metal/Metal.h>
#include <array>
#include <cstdint>

namespace mcla::metal {

// Retain the border color as well as address/filter/LOD state. Two shadow
// samplers differing only by white versus black border are not interchangeable.
inline std::array<uint32_t, 5> SamplerCacheFields(uint32_t dword0,
    uint32_t dword3, uint32_t dword4, uint32_t dword5, unsigned filterOverride) {
  return {dword0, dword3, dword4 & 0x3FCu, dword5 & 3u, filterOverride};
}

inline MTLSamplerAddressMode SamplerAddressMode(unsigned mode) {
  switch (mode) {
  case 0: return MTLSamplerAddressModeRepeat;
  case 1: return MTLSamplerAddressModeMirrorRepeat;
  case 2: return MTLSamplerAddressModeClampToEdge;
  case 3: return MTLSamplerAddressModeMirrorClampToEdge;
  case 6: return MTLSamplerAddressModeClampToBorderColor;
  // Metal lacks halfway and mirrored-border modes. These are explicit
  // approximations, matching XeniOS's Metal normalization, not exact support.
  case 5:
  case 7: return MTLSamplerAddressModeMirrorClampToEdge;
  default: return MTLSamplerAddressModeClampToEdge;
  }
}

// Returns false if an unsupported guest mode requires approximation. MCLA's
// ordinary ABGR black/white border modes are exact. Chroma-centred YCbCr black
// cannot be represented by Metal's three fixed border colors.
inline bool ApplySamplerAddressing(MTLSamplerDescriptor *descriptor,
    unsigned x, unsigned y, unsigned z, unsigned borderColor) {
  descriptor.sAddressMode = SamplerAddressMode(x);
  descriptor.tAddressMode = SamplerAddressMode(y);
  descriptor.rAddressMode = SamplerAddressMode(z);
  descriptor.borderColor = borderColor == 1
      ? MTLSamplerBorderColorOpaqueWhite
      : MTLSamplerBorderColorTransparentBlack;
  auto exactMode = [](unsigned mode) {
    return mode <= 3 || mode == 6;
  };
  bool usesBorder = x == 6 || y == 6 || z == 6;
  return exactMode(x) && exactMode(y) && exactMode(z) &&
      (!usesBorder || borderColor <= 1);
}

} // namespace mcla::metal
