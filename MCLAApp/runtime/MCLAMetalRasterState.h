#pragma once

#include <cmath>
#include <cstdint>
#include <limits>

namespace mcla::metal {

struct RasterDepthBias {
  float constant = 0.f;
  float slope = 0.f;
};

// A Xenos rectangle list is an area primitive: its three guest vertices don't
// define a triangle winding. Once the handwritten backend expands that area to
// two ordinary Metal triangles, applying the retained guest cull bits may
// reject the synthetic winding. MCLA's minimap circle punch is such a draw.
inline uint32_t GuestCullMode(uint32_t rasterControl,
                              uint32_t primitiveType) {
  return primitiveType == 8u ? 0u : rasterControl & 3u;
}

// The guest offsets are PA_SU_POLY_OFFSET_FRONT_{SCALE,OFFSET} and
// PA_SU_POLY_OFFSET_BACK_{SCALE,OFFSET}, at device shadow byte offsets
// 11192/11196/11200/11204. rasterControl is PA_SU_SC_MODE_CNTL (10568).
//
// Mirrors the XeniOS Metal backend's guest-authored polygon offset mapping:
// GetPreferredFacePolygonOffset + GetD3D10IntegerPolygonOffset. Metal's
// floating-point depth constant is measured in representable depth steps,
// NOT a normalized [0,1] offset. For guest D24 hosted as D32F, this preserves
// separation, but matches the absolute D24 offset only in the [0.5,1) range.
// In particular, this is not a calibration of a near-zero shadow atlas.
// Do not mix in a title-specific or artistic shadow bias here.
//
// Apply the returned values (including zeros) to EVERY draw, with clamp=0,
// so state from one shadow/decal draw cannot leak to the following draw.
inline RasterDepthBias GuestRasterDepthBias(
    uint32_t rasterControl, uint32_t depthFormat, bool triangles,
    float frontScale, float frontOffset, float backScale, float backOffset) {
  if (!triangles || depthFormat > 1) return {};
  float scale = 0.f, offset = 0.f;
  if ((rasterControl & (1u << 11)) && !(rasterControl & 1u)) {
    scale = frontScale;
    offset = frontOffset;
  }
  if ((rasterControl & (1u << 12)) && !(rasterControl & 2u) &&
      scale == 0.f && offset == 0.f) {
    scale = backScale;
    offset = backOffset;
  }
  // Reject invalid shadow reads before any float-to-integer conversion. The
  // plausibility guard is also used by LARecomp's native D3D12 pipeline.
  constexpr float kPlausibleLimit = 1.0e4f;
  if (!std::isfinite(scale) || !std::isfinite(offset) ||
      std::fabs(scale) > kPlausibleLimit || std::fabs(offset) > kPlausibleLimit)
    return {};
  const float factor = depthFormat == 1 ? float(1u << 21)
                                      : float((1u << 24) - 1u);
  const double units = double(std::ceil(std::fabs(offset) * factor)) *
                       (depthFormat == 1 ? 8.0 : 1.0);
  if (units > double(std::numeric_limits<int32_t>::max())) return {};
  return {offset < 0.f ? -float(units) : float(units), scale / 16.f};
}

}  // namespace mcla::metal
