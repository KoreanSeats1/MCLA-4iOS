#include "../MCLAApp/runtime/MCLAVertexFixup.h"
#include "../MCLAApp/runtime/MCLAGeometryScratch.h"
#include "../MCLAApp/runtime/MCLAResourceBindingReuse.h"
#include <array>
#include <cassert>
#include <chrono>
#include <cstdio>
#include <random>
#include <vector>
struct Attribute { unsigned semantic,numeric; };
// Independent reference: original renderer's per-vertex conversion loop.
__attribute__((noinline)) void Reference(uint8_t* dst,const uint8_t* src,size_t size,
    unsigned start,unsigned stride,uint32_t type,unsigned semantic,
    const Attribute* attributes,size_t count) {
  unsigned half=0;
  switch(type) {
  case 0x2C2359:case 0x2C2159:case 0x2C2059:case 0x2C235F:half=2;break;
  case 0x1A235A:case 0x1A215A:case 0x1A205A:case 0x1A2360:half=4;break;
  }
  for(size_t at=start;at+std::max(4u,half*2)<=size;at+=stride) {
    if(half) {
      for(unsigned h=0;h<half;++h) {
        uint16_t v;memcpy(&v,src+at+h*2,2);v=__builtin_bswap16(v);
        memcpy(dst+at+h*2,&v,2);
      }
    } else if(type==0x1A2187) {
      uint32_t v;memcpy(&v,dst+at,4);v=(v&0x3FFFFFFF)|0x40000000;
      memcpy(dst+at,&v,4);
    } else if(type==0x182886) {
      for(size_t i=0;i<count;++i)
        if(attributes[i].semantic==semantic && attributes[i].numeric==1)
          std::swap(dst[at],dst[at+2]);
    }
  }
}
int main() {
  using namespace mcla::metal;
  std::mt19937 random(0x4d434c41);
  constexpr uint32_t types[]={0x2C2359,0x2C2159,0x2C2059,0x2C235F,
    0x1A235A,0x1A215A,0x1A205A,0x1A2360,0x1A2187,0x182886,0,0x2C83A4};
  for(unsigned trial=0;trial<20000;++trial) {
    const size_t size=random()%4097;
    std::vector<uint8_t> src(size),actual(size),expected(size);
    for(auto& b:src)b=uint8_t(random());
    SwapVertexWords(actual.data(),src.data(),size);expected=actual;
    std::array<Attribute,20> attributes;
    for(auto& a:attributes)a={random()%5,random()%3};
    // Multiple ordered elements, overlapping/unaligned fields and short tails.
    for(unsigned element=0;element<8;++element) {
      auto type=types[random()%std::size(types)];
      unsigned start=random()%70,stride=1+random()%64,semantic=random()%5;
      Reference(expected.data(),src.data(),size,start,stride,type,semantic,attributes.data(),attributes.size());
      auto plan=PlanVertexFixup(type,semantic,attributes.data(),attributes.size());
      ApplyVertexFixup(actual.data(),src.data(),size,start,stride,plan);
    }
    assert(actual==expected);
    std::array<uint8_t,1056> defaults,baseline,optimized,group;
    for(auto& b:defaults)b=uint8_t(random());
    for(auto& b:group)b=uint8_t(random());
    baseline=defaults;optimized.fill(0xa5);
    const bool hit=trial%2;
    InitializeSharedConstants(optimized.data(),defaults.data(),hit);
    if(hit) {
      memcpy(baseline.data(),group.data(),520);memcpy(optimized.data(),group.data(),520);
      memcpy(baseline.data()+752,group.data()+752,104);
      memcpy(optimized.data()+752,group.data()+752,104);
    }
    assert(baseline==optimized);
  }
  // Host microbenchmark: one color attribute with a single matching semantic.
  std::vector<uint8_t> src(16384*32,0x1b),old=src,next=src;
  std::array<Attribute,20> attributes{};
  for(unsigned i=0;i<20;++i)attributes[i]={i,1};
  const auto plan=PlanVertexFixup(0x182886,9,attributes.data(),20);
  auto time=[&](auto f) {
    const auto start=std::chrono::steady_clock::now();
    for(unsigned i=0;i<200;++i)f();
    return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
  };
  const auto before=time([&]{Reference(old.data(),src.data(),src.size(),8,32,0x182886,9,attributes.data(),20);});
  const auto after=time([&]{ApplyVertexFixup(next.data(),src.data(),src.size(),8,32,plan);});
  assert(old==next);
  printf("160,000 differential element conversions and 20,000 shared blocks passed; host color-loop benchmark %.3f -> %.3f ms (%.2fx)\n",before,after,before/after);
}
