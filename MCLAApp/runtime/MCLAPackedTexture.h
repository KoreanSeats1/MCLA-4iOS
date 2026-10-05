#pragma once
#include <cstdint>
namespace mcla::metal {
// Xenos R5G5B5A1: red in bits 0–4, blue in 10–14, alpha in bit 15.
// Input is already endian-corrected by CopySwapBlock.
inline void DecodeR5G5B5A1(const uint8_t* source, uint8_t* rgba) {
    const uint16_t value = uint16_t(source[0]) | uint16_t(source[1]) << 8;
    for (unsigned channel = 0; channel < 3; ++channel)
        rgba[channel] = uint8_t((((value >> (channel * 5)) & 31) * 255 + 15) / 31);
    rgba[3] = (value & 0x8000) ? 255 : 0;
}
}
