#pragma once

#include <cstdint>
#include <array>
#include <map>
#include <optional>
#include <span>
#include <vector>
#include <vulkan/vulkan.h>

namespace mcla::native {

// MCLA uses UNORM24 shadow targets as well as float24 depth. iPad does not
// support the D24 sampled-image tuple. Keep the guest format/packing identity
// unchanged, but use D32+S8 for BOTH the rendering and sampled resolve images.
inline constexpr VkFormat DepthTextureFormat(uint32_t guestFormat) {
  return guestFormat == 22 || guestFormat == 23
             ? VK_FORMAT_D32_SFLOAT_S8_UINT : VK_FORMAT_UNDEFINED;
}

inline constexpr VkFormat AdditionalSurfaceFormat(uint32_t format, bool depth) {
  if (depth) {
    return format == 0x2D200196u ? DepthTextureFormat(22) : VK_FORMAT_UNDEFINED;
  }
  // Captured X8R8G8B8 and half-resolution HDR post-processing variants.
  switch (format) {
    case 0x18287F86u: return VK_FORMAT_R8G8B8A8_UNORM;
    case 0x1A22AB60u: return VK_FORMAT_R16G16B16A16_SFLOAT;
    default: return VK_FORMAT_UNDEFINED;
  }
}

// Placement identity is checked by the caller. A raw depth/stencil copy may
// only materialize an identical physical topology; never reinterpret samples.
inline constexpr bool CanCopyDepthPlacement(
    VkFormat sourceFormat, VkFormat destinationFormat,
    uint32_t sourceWidth, uint32_t sourceHeight, uint32_t destinationWidth,
    uint32_t destinationHeight, VkSampleCountFlagBits sourceSamples,
    VkSampleCountFlagBits destinationSamples) {
  return sourceFormat == VK_FORMAT_D32_SFLOAT_S8_UINT &&
         sourceFormat == destinationFormat && sourceWidth && sourceHeight &&
         sourceWidth == destinationWidth && sourceHeight == destinationHeight &&
         sourceSamples == destinationSamples;
}

inline constexpr VkFormat InlineTexcoordFormat(bool inlineDraw, uint32_t usage,
    VkFormat format, uint32_t offset, uint32_t stride, uint32_t shaderComponents) {
  // MCLA's inline composite carries UV.xy even when the currently bound
  // buffer-fed declaration says FLOAT1. Match LARecomp's verified inline path.
  return inlineDraw && usage == 5 && format == VK_FORMAT_R32_SFLOAT &&
                 shaderComponents >= 2 && offset <= stride && stride - offset >= 8
             ? VK_FORMAT_R32G32_SFLOAT : format;
}

struct TiledCanvas { uint32_t width; uint32_t height; };
inline std::optional<TiledCanvas> VerticalTiledCanvas(
    std::span<const std::array<int32_t, 4>> rectangles) {
  if (rectangles.size() < 2 || rectangles.size() > 16) return std::nullopt;
  int32_t width = rectangles.front()[2], bottom = 0;
  if (width <= 0 || width > 16384) return std::nullopt;
  for (const auto& r : rectangles) {
    if (r[0] != 0 || r[1] != bottom || r[2] != width || r[3] <= bottom || r[3] > 16384)
      return std::nullopt;
    bottom = r[3];
  }
  return TiledCanvas{uint32_t(width), uint32_t(bottom)};
}

struct VertexLocationMapping {
  uint32_t semantic;  // Original XenosRecomp semantic key, e.g. COLOR1 = 32.
  uint32_t native;    // Dense host input location, NOT the semantic key.
};

// Rewrite only OpDecorate Location on Input variables. Outputs, built-ins,
// types, IDs and all shader instructions remain byte-for-byte unchanged.
// Reflection must keep the returned semantic/native mapping when matching
// the guest declaration. Validate everything before modifying the module.
inline std::optional<std::vector<VertexLocationMapping>> CompactVertexLocations(
    std::span<uint32_t> words, uint32_t maximumAttributes) {
  if (words.size() < 5 || words[0] != 0x07230203u || !words[3]) return std::nullopt;
  struct Variable { bool input = false; bool builtin = false; size_t location = 0; };
  std::map<uint32_t, Variable> variables;
  for (size_t cursor = 5; cursor < words.size();) {
    const auto count = words[cursor] >> 16;
    const auto opcode = words[cursor] & 0xFFFFu;
    if (!count || count > words.size() - cursor) return std::nullopt;
    if (opcode == 59) {  // OpVariable
      if (count < 4 || words[cursor + 2] >= words[3]) return std::nullopt;
      variables[words[cursor + 2]].input = words[cursor + 3] == 1;
    } else if (opcode == 71) {  // OpDecorate
      if (count < 3 || words[cursor + 1] >= words[3]) return std::nullopt;
      auto& variable = variables[words[cursor + 1]];
      if (words[cursor + 2] == 30) {  // Location
        if (count != 4 || variable.location) return std::nullopt;
        variable.location = cursor + 3;
      } else if (words[cursor + 2] == 11) {  // BuiltIn
        variable.builtin = true;
      }
    }
    cursor += count;
  }
  std::map<uint32_t, size_t> locations;
  for (const auto& [id, variable] : variables) {
    if (!variable.input || variable.builtin || !variable.location) continue;
    if (!locations.emplace(words[variable.location], variable.location).second) return std::nullopt;
  }
  if (locations.size() > maximumAttributes) return std::nullopt;
  std::vector<VertexLocationMapping> mapping;
  for (const auto& [semantic, offset] : locations) {
    const auto native = uint32_t(mapping.size());
    mapping.push_back({semantic, native});
    words[offset] = native;
  }
  return mapping;
}

}  // namespace mcla::native
