#pragma once
#include <cstdint>
namespace mcla::metal {
// Match the title reference renderer's measured storage mapping. Its tiled
// 8_8_8_8 grading/noise surfaces are already decoded in host channel order;
// composing their 0x60A fetch with BGRA cancels the extra red/blue exchange.
// Linear light-color/index tables still require the original guest swizzle.
inline uint32_t DecodedTextureHostSwizzle(uint32_t format, bool tiled,
                                         uint32_t endian, uint32_t swizzle,
                                         bool tiledColorCorrection = true) {
    if (format == 2 || format == 59 || format == 36) return 0; // R-only
    if (format == 60 || format == 49) return 0x248; // RG, zero, one
    if (tiledColorCorrection && format == 6 && tiled && endian == 2 && swizzle == 0x60A)
        return 0x60A;
    return 0x688;
}
inline uint32_t ComposeTextureSwizzle(uint32_t guest, uint32_t host) {
    uint32_t result=0;
    for(unsigned i=0;i<4;++i) {
        unsigned v=(guest>>(3*i))&7;
        v=v<4 ? (host>>(3*v))&7 : v&5;
        result|=v<<(3*i);
    }
    return result;
}
}
