#pragma once
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <utility>

namespace mcla::metal {
struct VertexFixup {
  unsigned halfCount=0;
  bool packed=false, swapColor=false;
  bool active() const { return halfCount || packed || swapColor; }
};
inline unsigned VertexHalfCount(uint32_t type) {
  switch(type) {
  case 0x2C2359: case 0x2C2159: case 0x2C2059: case 0x2C235F: return 2;
  case 0x1A235A: case 0x1A215A: case 0x1A205A: case 0x1A2360: return 4;
  default:return 0;
  }
}
template<class Attribute>
VertexFixup PlanVertexFixup(uint32_t type,uint32_t semantic,
                           const Attribute* attributes,size_t count) {
  VertexFixup result{VertexHalfCount(type),type==0x1A2187,false};
  if(type==0x182886) {
    // Preserve even duplicate semantic matches: the original swaps once for
    // every matching numeric attribute, so only parity affects the bytes.
    for(size_t i=0;i<count;++i)
      if(attributes[i].semantic==semantic && attributes[i].numeric==1)
        result.swapColor=!result.swapColor;
  }
  return result;
}
inline void ApplyVertexFixup(uint8_t* dst,const uint8_t* src,size_t size,
                             size_t start,unsigned stride,VertexFixup plan) {
  if(!stride || !plan.active())return;
  const size_t width=std::max(4u,plan.halfCount*2);
  if(size<width)return;
  for(size_t at=start;at<=size-width;at+=stride) {
    if(plan.halfCount) {
      for(unsigned h=0;h<plan.halfCount;++h) {
        uint16_t word;std::memcpy(&word,src+at+h*2,2);
        word=__builtin_bswap16(word);std::memcpy(dst+at+h*2,&word,2);
      }
    } else if(plan.packed) {
      uint32_t word;std::memcpy(&word,dst+at,4);
      word=(word&0x3FFFFFFF)|0x40000000;
      std::memcpy(dst+at,&word,4);
    } else std::swap(dst[at],dst[at+2]);
  }
}
}
