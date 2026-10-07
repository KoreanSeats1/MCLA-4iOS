#pragma once
#include "MCLAVertexFixup.h"
#include <array>
#include <compare>
#include <map>
#include <optional>

namespace mcla::metal {
// Identity follows the ordered writes, not the shader or declaration handle.
// MCLA also converts unused half/DEC3N fields; keep that title-specific behavior.
struct VertexConversionRecipe {
  struct Write {
    uint32_t offset=0, halfCount=0, packed=0, swapColor=0;
    auto operator<=>(const Write&) const = default;
  };
  std::array<Write,64> writes{};
  uint32_t count=0, stride=0, quadScaleWord=0;
  // Rectangle expansion reads declaration semantics separately. Keep its
  // complete declaration generation distinct instead of guessing equivalence.
  uint64_t rectangleDeclaration=0, rectangleRevision=0;
  auto operator<=>(const VertexConversionRecipe&) const = default;
};
template<class Declaration,class Shader,class Semantic>
std::optional<VertexConversionRecipe> BuildVertexConversionRecipe(
    const Declaration& decl,const Shader& shader,uint32_t stream,uint32_t stride,
    bool suppressColor,uint32_t quadScaleWord,Semantic semantic) {
  if(!stride || decl.element_count>64)return std::nullopt;
  VertexConversionRecipe result;result.stride=stride;result.quadScaleWord=quadScaleWord;
  for(unsigned i=0;i<decl.element_count;++i) {
    const auto& el=decl.elements[i];
    if(el.stream!=stream)continue;
    auto plan=PlanVertexFixup(el.type,semantic(el.usage,el.usage_index),
                              shader.attributes,shader.count);
    if(suppressColor)plan.swapColor=false;
    if(!plan.active())continue;
    result.writes[result.count++]={el.offset,plan.halfCount,plan.packed,plan.swapColor};
  }
  return result;
}
class VertexConversionRecipes {
  static constexpr size_t kLimit=4096;
  std::map<VertexConversionRecipe,uint64_t> identities_;
  std::map<std::array<uint64_t,6>,uint64_t> sources_;
  uint64_t next_=0, equivalents_=0;
  std::array<uint64_t,6> lastSource_{};
  uint64_t lastIdentity_=0;
public:
  template<class Build> uint64_t Identity(const std::array<uint64_t,6>& source,Build build) {
    if(lastIdentity_ && lastSource_==source)return lastIdentity_;
    if(auto it=sources_.find(source);it!=sources_.end()) {
      lastSource_=source;return lastIdentity_=it->second;
    }
    auto recipe=build();if(!recipe)return 0;
    // Clearing metadata never recycles an identity held by an upload cache.
    if(sources_.size()>=kLimit || identities_.size()>=kLimit) {
      sources_.clear();identities_.clear();
    }
    auto [it,inserted]=identities_.try_emplace(*recipe,next_+1);
    if(inserted)++next_;else ++equivalents_;
    sources_.emplace(source,it->second);lastSource_=source;
    return lastIdentity_=it->second;
  }
  uint64_t equivalents() const {return equivalents_;}
  size_t size() const {return identities_.size();}
};
} // namespace mcla::metal
