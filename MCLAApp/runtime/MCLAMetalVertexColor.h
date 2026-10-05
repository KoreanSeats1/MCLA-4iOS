#pragma once
#import <Metal/Metal.h>
#include <cstdint>
namespace mcla::metal {
// These two post-tonemap glow shaders pass COLOR0 through as xyzw; unlike
// the bloom seed's zyxw fetch, they require the declaration's BGRA view.
// Live pixel history shows their blue additive output over a red signal.
inline bool PackedColorShaderCorrection(uint64_t shader, bool correction) {
    return correction && shader != 0xF52B50DA9C0F8997ull &&
                         shader != 0x1B7B507E54AADA8Aull;
}
// Xenos k_8_8_8_8 fetch reads low-to-high byte components. The recompiled
// instruction already applies its guest destination swizzle. BGRA would add
// an extra red/blue swap before that instruction (visible on colored smoke).
inline MTLVertexFormat PackedColorVertexFormat(unsigned numeric, bool correction) {
    if (numeric == 1) return MTLVertexFormatUChar4;
    return correction ? MTLVertexFormatUChar4Normalized : MTLVertexFormatUChar4Normalized_BGRA;
}
}
