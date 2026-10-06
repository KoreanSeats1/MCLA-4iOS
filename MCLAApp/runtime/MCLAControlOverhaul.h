#pragma once
#include <algorithm>
#include <cmath>
#include "MCLAMetalPresentation.h"

namespace mcla::metal {
// Bounds in the HUD movie's authored 1280x720 coordinates, before safe framing.
struct HudBounds { float left, top, right, bottom; };
struct HudMove { float scale = 1, x = 0, y = 0; const char* name = "unchanged"; bool right = false; };
// Deliberately conservative: mixed batches and full-screen/menu backgrounds
// remain in place. This is a draw-level experiment, not movie identification.
inline HudMove RaisedHudMove(const HudBounds& b) {
    if (!std::isfinite(b.left) || !std::isfinite(b.top) ||
        !std::isfinite(b.right) || !std::isfinite(b.bottom) ||
        b.left > b.right || b.top > b.bottom) return {};
    // The ring's transparent texture padding makes its quad larger than the
    // street fill: captured bounds 23.3,407.6..359.8,744.2. Move this centered
    // square with the identical map transform, including its padded edges.
    const float width=b.right-b.left, height=b.bottom-b.top;
    const bool mapOutline = b.left >= 16 && b.right <= 368 &&
        b.top >= 400 && b.bottom <= 752 && width >= 320 && width <= 350 &&
        height >= 320 && height <= 350 && std::fabs(width-height) <= 2;
    if (mapOutline ||
        (b.left >= 28 && b.right <= 330 && b.top >= 440 && b.bottom <= 710))
        return {.90f, 28-72*.90f, 76-440*.90f, "minimap"};
    if (b.left >= 900 && b.right <= 1260 && b.top >= 480 && b.bottom <= 710)
        return {1.f, 1252-1260.f, 76-480.f, "gauges", true};
    return {};
}
// Keep authored pixel density while anchoring to device corners rather than
// the centered 16:9 frame (which leaves a large top gutter on iPad).
inline SafeFrame AnchoredHudFrame(SafeFrame frame, unsigned targetWidth, const HudMove& move) {
    if (move.scale == 1 && move.x == 0 && move.y == 0) return frame;
    frame.left=move.right ? targetWidth-frame.width : 0;
    frame.top=0;
    return frame;
}
// Translate both viewport and scissor; clamp the latter to its attachment.
inline unsigned MovedHudEdge(double edge, double scale, double offset, unsigned extent) {
    return unsigned(std::clamp(std::floor(edge * scale + offset), 0.0, double(extent)));
}
}
