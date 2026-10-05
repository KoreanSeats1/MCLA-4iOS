#pragma once
#import <Metal/Metal.h>
namespace mcla::metal {
// Xenos k_8_8_8_8 fetch reads low-to-high byte components. The recompiled
// instruction already applies its guest destination swizzle. BGRA would add
// an extra red/blue swap before that instruction (visible on colored smoke).
inline MTLVertexFormat PackedColorVertexFormat(unsigned numeric, bool correction) {
    if (numeric == 1) return MTLVertexFormatUChar4;
    return correction ? MTLVertexFormatUChar4Normalized : MTLVertexFormatUChar4Normalized_BGRA;
}
}
