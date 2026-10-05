#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace mcla::touch {

inline int16_t Stick(float value) {
    if (!std::isfinite(value)) return 0;
    const float bounded = std::clamp(value, -1.0f, 1.0f);
    return static_cast<int16_t>(std::lround(bounded < 0.0f
        ? bounded * 32768.0f : bounded * 32767.0f));
}

inline uint8_t Trigger(bool pressed) { return pressed ? 255 : 0; }

inline uint8_t MergeTrigger(uint8_t physical, uint8_t touch) {
    return std::max(physical, touch);
}

} // namespace mcla::touch
