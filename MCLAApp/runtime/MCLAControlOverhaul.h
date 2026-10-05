#pragma once
#include <algorithm>
#include <cmath>

namespace mcla::metal {
// Bounds in the HUD movie's authored 1280x720 coordinates, before safe framing.
struct HudBounds { float left, top, right, bottom; };
struct HudMove { float scale = 1, x = 0, y = 0; const char* name = "unchanged"; };
// Deliberately conservative: mixed batches and full-screen/menu backgrounds
// remain in place. This is a draw-level experiment, not movie identification.
inline HudMove RaisedHudMove(const HudBounds& b) {
    if (!std::isfinite(b.left) || !std::isfinite(b.top) ||
        !std::isfinite(b.right) || !std::isfinite(b.bottom) ||
        b.left > b.right || b.top > b.bottom) return {};
    if (b.left >= 28 && b.right <= 330 && b.top >= 440 && b.bottom <= 710)
        return {.78f, 72*(1-.78f), 80-440*.78f, "minimap"};
    if (b.left >= 900 && b.right <= 1260 && b.top >= 480 && b.bottom <= 710)
        return {.85f, 1260*(1-.85f), 90-480*.85f, "gauges"};
    return {};
}
// Translate both viewport and scissor; clamp the latter to its attachment.
inline unsigned MovedHudEdge(double edge, double scale, double offset, unsigned extent) {
    return unsigned(std::clamp(std::floor(edge * scale + offset), 0.0, double(extent)));
}
}
