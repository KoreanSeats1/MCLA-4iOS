#pragma once

#include <array>
#include <cmath>
#include <cstdint>

namespace mcla::metal {

// MCLA's PA_SU_VTX_CNTL shadow remains at this offset in the canonical
// snapshot. Guest rex_sub_82414F30 / rex_sub_82414F58 write/read bit 0 here.
inline constexpr uint32_t kPixelCenterRegisterOffset = 10688;

// The shader adds offset * clip.w to clip.xy. D3DZero needs +0.5 screen
// pixels; OGLHalf is already aligned to Metal's sample centers. Use the
// viewport, not its backing texture: atlas tiles can occupy a sub-viewport.
inline std::array<float, 2> HalfPixelOffset(uint32_t vertexControl,
                                           float viewportWidth,
                                           float viewportHeight) {
  if ((vertexControl & 1u) || !std::isfinite(viewportWidth) ||
      !std::isfinite(viewportHeight) || viewportWidth <= 0.f ||
      viewportHeight <= 0.f)
    return {0.f, 0.f};
  return {1.f / viewportWidth, -1.f / viewportHeight};
}

} // namespace mcla::metal
