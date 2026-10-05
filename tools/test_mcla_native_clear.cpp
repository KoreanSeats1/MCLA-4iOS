#include "../MCLAApp/runtime/MCLANativeClear.h"
#include <cassert>
#include <cstdio>

using namespace mcla::native;
using Device=std::array<uint8_t,0x5780>;
template<class Bytes> static void Word(Bytes& bytes,uint32_t at,uint32_t word) {
  bytes[at]=uint8_t(word>>24);bytes[at+1]=uint8_t(word>>16);
  bytes[at+2]=uint8_t(word>>8);bytes[at+3]=uint8_t(word);
}
static void Viewport(Device& d,float x,float y,float w,float h) {
  unsigned i=0;
  for(float v:{x,y,w,h})Word(d,12648+4*i++,std::bit_cast<uint32_t>(v));
}
template<class Bytes> static void Rectangle(Bytes& b,uint32_t index,ClearRectangle r) {
  unsigned i=0;
  for(int32_t v:{r.left,r.top,r.right,r.bottom})Word(b,index*16+4*i++,std::bit_cast<uint32_t>(v));
}
static void Expect(const std::optional<std::vector<ClearRectangle>>& result,
                   std::initializer_list<ClearRectangle> expected) {
  assert(result);
  assert(*result==std::vector<ClearRectangle>(expected));
}
int main() {
  Device d{};
  Viewport(d,10.9f,20.9f,100.9f,80.9f);
  // Null list ignores count and intersects full surface with truncated viewport.
  Expect(DecodeClearRectangles(d,UINT32_MAX,false,{},1280,720),{{10,20,110,100}});
  Expect(DecodeClearRectangles(d,0,false,{},70,50),{{10,20,70,50}});
  Expect(DecodeClearRectangles(d,0,false,{},0,0),{});
  // Explicit zero count must be a no-op, not a default/full clear.
  Expect(DecodeClearRectangles(d,0,true,{},1280,720),{});
  std::array<uint8_t,48> rectangles{};
  Rectangle(rectangles,0,{-100,-100,50,60});
  Rectangle(rectangles,1,{70,75,200,200});
  Rectangle(rectangles,2,{20,30,20,40}); // zero area
  Expect(DecodeClearRectangles(d,3,true,rectangles,1280,720),
         {{10,20,50,60},{70,75,110,100}});
  // Optional API scissor is signed and separate from the viewport.
  Word(d,11856,1);
  Word(d,12676,30);Word(d,12680,40);Word(d,12684,90);Word(d,12688,85);
  Expect(DecodeClearRectangles(d,3,true,rectangles,1280,720),
         {{30,40,50,60},{70,75,90,85}});
  Expect(DecodeClearRectangles(d,0,false,{},1280,720),{{30,40,90,85}});
  Word(d,12684,29); // inverted scissor: no commands submitted
  Expect(DecodeClearRectangles(d,3,true,rectangles,1280,720),{});
  Word(d,11856,0);
  Viewport(d,-10.9f,-20.9f,100,80);
  Rectangle(rectangles,0,{-50,-50,50,60});
  Expect(DecodeClearRectangles(d,1,true,rectangles,1280,720),{{-10,-20,50,60}});
  Expect(DecodeClearRectangles(d,0,false,{},1280,720),{{0,0,90,60}});
  // Empty, inverted and disjoint rectangles never acquire full-clear semantics.
  Rectangle(rectangles,0,{100,100,200,200});
  Rectangle(rectangles,1,{40,40,30,30});
  Expect(DecodeClearRectangles(d,3,true,rectangles,1280,720),{});
  Viewport(d,0,0,0,80);
  Expect(DecodeClearRectangles(d,0,false,{},1280,720),{});
  Viewport(d,0,0,-1,80);
  Expect(DecodeClearRectangles(d,0,false,{},1280,720),{});
  // Reject malformed spans/counts before reading guest memory.
  assert(!ClearRectangleBytes(UINT32_MAX,true));
  assert(ClearRectangleBytes(kMaximumClearRectangles,true)==65536u);
  assert(ClearRectangleBytes(UINT32_MAX,false)==0u);
  assert(!DecodeClearRectangles(d,kMaximumClearRectangles+1,true,{},1280,720));
  assert(!DecodeClearRectangles(d,2,true,{rectangles.data(),31},1280,720));
  assert(!DecodeClearRectangles({d.data(),13187},0,false,{},1280,720));
  for(float invalid:{std::numeric_limits<float>::quiet_NaN(),
                     std::numeric_limits<float>::infinity(),2147483648.f}) {
    Viewport(d,invalid,0,100,80);
    assert(!DecodeClearRectangles(d,0,false,{},1280,720));
  }
  Viewport(d,2147483520.f,0,256,80); // finite individual values, addition overflow
  assert(!DecodeClearRectangles(d,0,false,{},1280,720));
  Viewport(d,0,0,1280,720);
  // Guest null-rectangle tiling overrides the raw EDRAM tile dimensions.
  d[10940]=0x10;
  Word(d,13180,1280);Word(d,13184,720);
  Expect(DecodeClearRectangles(d,0,false,{},1280,512),{{0,0,1280,720}});
  d[10940]=0x20;
  Word(d,12440,0x1234);Word(d,12728,0x1234);
  Expect(DecodeClearRectangles(d,0,false,{},1280,512),{{0,0,1280,720}});
  Word(d,12728,0x5678); // changed binding invalidates cached canvas
  Expect(DecodeClearRectangles(d,0,false,{},1280,512),{{0,0,1280,512}});
  d[10940]=0x10;
  Word(d,13180,UINT32_MAX);
  assert(!DecodeClearRectangles(d,0,false,{},1280,512));
  std::puts("PASS: native Clear default/explicit lists, count/read bounds, signed viewport/scissor intersections, empty/invalid rejection, and tiled canvas");
}
