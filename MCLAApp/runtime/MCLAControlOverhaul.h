#pragma once
#include <algorithm>
#include <cmath>
#include <array>
#include <optional>
#include <span>
#include "MCLAMetalPresentation.h"

namespace mcla::metal {
// Bounds in the HUD movie's authored 1280x720 coordinates, before safe framing.
struct HudBounds { float left, top, right, bottom; };
inline std::optional<HudBounds> HudPointBounds(std::span<const std::array<float,2>> points) {
    if (points.size()<3 || points.size()>4096) return std::nullopt;
    HudBounds box{INFINITY,INFINITY,-INFINITY,-INFINITY};
    for (const auto& p:points) {
        if (!std::isfinite(p[0]) || !std::isfinite(p[1])) return std::nullopt;
        box.left=std::min(box.left,p[0]); box.right=std::max(box.right,p[0]);
        box.top=std::min(box.top,p[1]); box.bottom=std::max(box.bottom,p[1]);
    }
    return box;
}
struct HudMove { float scale = 1, x = 0, y = 0; const char* name = "unchanged"; bool right = false; };
// Deliberately conservative: mixed batches and full-screen/menu backgrounds
// remain in place. This is a draw-level experiment, not movie identification.
inline HudMove RaisedHudMove(const HudBounds& b) {
    if (!std::isfinite(b.left) || !std::isfinite(b.top) ||
        !std::isfinite(b.right) || !std::isfinite(b.bottom) ||
        b.left > b.right || b.top > b.bottom) return {};
    // Classify the map's visual footprint, including its rotating/padded
    // decorations. A padded square's AABB grows as it rotates; testing its
    // unrotated width or only the street-fill rectangle makes it jump back.
    const float width=b.right-b.left, height=b.bottom-b.top;
    const float centerX=(b.left+b.right)*.5f, centerY=(b.top+b.bottom)*.5f;
    const bool mapOutline = std::fabs(centerX-191.5f)<=16 &&
        std::fabs(centerY-576.f)<=16 && width>=300 && width<=500 &&
        height>=300 && height<=500 && std::fabs(width-height)<=8;
    const bool mapDecoration = width<=240 && height<=240 &&
        centerX>=0 && centerX<=384 && centerY>=350 && centerY<=780;
    if (mapOutline || mapDecoration ||
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
