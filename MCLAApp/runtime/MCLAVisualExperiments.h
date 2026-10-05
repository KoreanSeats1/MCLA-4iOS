#pragma once
#include <array>
#include <bit>
#include <cmath>
#include <span>
namespace mcla::metal {
enum VisualExperiment : unsigned {
    PackedVertexColor = 1, FullScreenFades = 2, StableMaterialLOD = 4, RaisedDrivingHUD = 8
};
// Only complete clip-space rectangles qualify, not HUD tiles or menu cards.
// Rectangle-list input omits its fourth corner; other primitives need all four.
inline bool FullScreenOverlay(std::span<const std::array<float,4>> clips,
                              bool rectangleList) {
    if (clips.size() < 3 || clips.size() > 6) return false;
    unsigned corners = 0;
    for (const auto& p : clips) {
        if (!std::isfinite(p[3]) || p[3] <= 0) return false;
        const float x=p[0]/p[3], y=p[1]/p[3];
        if (!std::isfinite(x) || !std::isfinite(y) ||
            std::fabs(std::fabs(x)-1.f) > .02f ||
            std::fabs(std::fabs(y)-1.f) > .02f) return false;
        corners |= 1u << ((x > 0 ? 1 : 0) | (y > 0 ? 2 : 0));
    }
    return rectangleList ? std::popcount(corners) >= 3 : corners == 15;
}
}
