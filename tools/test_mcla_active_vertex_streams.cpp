#include "../MCLAApp/runtime/MCLAActiveVertexStreams.h"
#include <array>
#include <cassert>
#include <cstdio>
#include <random>
struct Element {unsigned stream,usage,usage_index;};
struct Attribute {unsigned semantic;};
// Independent semantic table from the renderer's established declaration ABI.
unsigned ReferenceSemantic(unsigned usage,unsigned index) {
  switch(usage) {
    case 0:case 9:return index<4?index:~0u;
    case 3:return index<4?4+index:~0u;
    case 6:return index<4?8+index:~0u;
    case 7:return index==0?12:~0u;
    case 5:return index<4?13+index:16+index;
    case 10:return index?32:17;
    case 2:return 18;
    case 1:return 19;
    default:return ~0u;
  }
}
int main() {
  using namespace mcla::metal;
  std::mt19937 rng(0x4d535452);
  for(unsigned trial=0;trial<30000;++trial) {
    std::array<Element,64> elements;
    std::array<Attribute,32> attributes;
    for(auto& e:elements)e={rng()%19,rng()%14,rng()%8};
    for(auto& a:attributes)a={rng()%40};
    const unsigned ne=rng()%65,na=rng()%33;
    uint32_t expected=0;bool valid=true;
    for(unsigned i=0;i<na;++i) {
      for(unsigned j=0;j<ne;++j) {
        if(ReferenceSemantic(elements[j].usage,elements[j].usage_index)!=attributes[i].semantic)continue;
        if(elements[j].stream>=16)valid=false;
        else expected|=1u<<elements[j].stream;
        break;
      }
    }
    auto result=ActiveVertexStreams(std::span<const Element>(elements.data(),ne),
                                   std::span<const Attribute>(attributes.data(),na));
    assert(bool(result)==valid);if(result)assert(*result==expected);
  }
  // Deferred inactive bindings must refresh on the draw that needs them,
  // including explicit unbinds and in-place declaration changes.
  std::array<unsigned,16> guest{},original{},optimized{};
  std::array<Element,2> elements{{{0,0,0},{1,5,0}}};
  std::array<Attribute,1> position{{{0}}},uv{{{13}}};
  auto prepare=[&](auto attrs) {
    original=guest;
    auto mask=*ActiveVertexStreams(std::span<const Element>(elements),
                                  std::span<const Attribute>(attrs));
    for(unsigned i=0;i<16;++i)if(mask&(1u<<i))optimized[i]=guest[i];
    for(unsigned i=0;i<16;++i)if(mask&(1u<<i))assert(optimized[i]==original[i]);
  };
  guest[0]=10;guest[1]=20;prepare(position);
  guest[1]=30;prepare(position);prepare(uv);assert(optimized[1]==30);
  guest[1]=0;prepare(position);prepare(uv);assert(optimized[1]==0);
  elements[1].stream=7;guest[7]=70;prepare(uv);assert(optimized[7]==70);
  elements[0].stream=2;guest[2]=200;prepare(position);assert(optimized[2]==200);
  // Duplicate semantics select the first element; absent semantics are constants.
  elements={Element{3,0,0},Element{5,0,0}};
  assert(*ActiveVertexStreams(std::span<const Element>(elements),std::span<const Attribute>(position))==(1u<<3));
  Attribute absent{39};
  assert(*ActiveVertexStreams(std::span<const Element>(elements),std::span<const Attribute>(&absent,1))==0);
  puts("30,000 active-stream differential cases and binding transition/mutation/unbind checks passed");
}
