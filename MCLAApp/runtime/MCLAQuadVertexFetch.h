#pragma once
#include <cstdint>
#include <cstring>
#include <optional>
#include <span>
#include <vector>

namespace mcla::native {
// Audited original microcode and translated math: every live fetch in these
// foliage shaders reads floor(VertexID/4); the remaining arithmetic selects
// VertexID%4. Do not infer this contract merely from a buffer overrun or from
// the presence of ANY computed fetch (other index functions are possible).
inline constexpr std::optional<uint32_t> QuadFetchScaleWord(uint64_t shader) {
  switch (shader) {
    case 0xD36D9DAFC2C3F4B1ull: return 255*4;     // c255.x
    case 0x28160E3F809C1C64ull: return 255*4+3;   // c255.w
    case 0xB11D7CEC72A529CFull: return 254*4+1;   // c254.y
    default: return std::nullopt;
  }
}

inline constexpr uint64_t QuadFetchRequiredBytes(uint32_t offset, uint32_t stride,
                                                uint32_t start, uint32_t count) {
  return uint64_t(offset) + ((uint64_t(start)+count+3)/4)*stride;
}

// Expand the already format/endian-converted host payload. Keep the prefix
// and the ORIGINAL draw start/base vertex: GPU VertexID must still be the
// guest index, not a rebased zero. Persistent upload caching amortizes this
// over every draw using the same buffer generation/declaration/shader/stream.
inline std::optional<std::vector<uint8_t>> ExpandQuadFetchPayload(
    std::span<const uint8_t> source, uint32_t offset, uint32_t stride) {
  if (!stride || offset >= source.size()) return std::nullopt;
  const uint64_t vertices = (source.size()-offset)/stride;
  const uint64_t size = uint64_t(offset) + vertices*stride*4;
  constexpr uint64_t kMaximumExpandedBytes = 64ull*1024*1024;
  if (!vertices || size > kMaximumExpandedBytes) return std::nullopt;
  std::vector<uint8_t> result(size);
  std::memcpy(result.data(), source.data(), offset);
  for (uint64_t i=0; i<vertices; ++i)
    for (uint32_t corner=0; corner<4; ++corner)
      std::memcpy(result.data()+offset+(i*4+corner)*stride,
                  source.data()+offset+i*stride, stride);
  return result;
}
}
