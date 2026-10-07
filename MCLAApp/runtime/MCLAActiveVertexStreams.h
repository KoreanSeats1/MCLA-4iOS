#pragma once
#include <cstdint>
#include <optional>
#include <span>
namespace mcla::metal {
inline uint32_t VertexSemantic(uint8_t usage, uint8_t index) {
  if ((usage == 0 || usage == 9) && index < 4)
    return index;
  if (usage == 3 && index < 4)
    return 4 + index;
  if (usage == 6 && index < 4)
    return 8 + index;
  if (usage == 7 && index == 0)
    return 12;
  if (usage == 5)
    return index < 4 ? 13 + index : 16 + index;
  if (usage == 10)
    return index ? 32 : 17;
  if (usage == 2)
    return 18;
  if (usage == 1)
    return 19;
  return UINT32_MAX;
}
// Match the renderer's first declaration element for each shader semantic.
// Missing attributes use constant buffers, and need no guest vertex stream.
template<class Element,class Attribute>
std::optional<uint32_t> ActiveVertexStreams(std::span<const Element> elements,
                                           std::span<const Attribute> attributes) {
  uint32_t result=0;
  for(const auto& a:attributes) {
    for(const auto& e:elements) {
      if(VertexSemantic(e.usage,e.usage_index)!=a.semantic)continue;
      if(e.stream>=16)return std::nullopt;
      result|=1u<<e.stream;break;
    }
  }
  return result;
}
} // namespace mcla::metal
