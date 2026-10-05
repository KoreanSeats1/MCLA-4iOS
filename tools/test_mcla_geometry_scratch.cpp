#include "../MCLAApp/runtime/MCLAGeometryScratch.h"
#include <cassert>
#include <cstdio>
#include <random>

int main() {
  using namespace mcla::metal;
  GeometryScratch<uint8_t> scratch(4096);
  std::mt19937 random(0x4D434C41);
  for (unsigned trial=0;trial<10000;++trial) {
    const size_t size=random()%8193;
    std::vector<uint8_t> src(size),expected(size);
    for (auto& byte:src) byte=uint8_t(random());
    // Original zero-filled vector + byte order conversion, including tails.
    for (size_t i=0;i+4<=size;i+=4)
      for (size_t j=0;j<4;++j) expected[i+j]=src[i+3-j];
    {
      auto lease=scratch.Use(size);
      auto& data=lease.values();
      SwapVertexWords(data.data(),src.data(),size);
      assert(data==expected);
    }
    assert(scratch.capacity()<=4096);
  }
  { auto lease=scratch.Use(128); }
  auto growths=scratch.growths();
  for (unsigned i=0;i<1000;++i) { auto lease=scratch.Use(128); }
  assert(scratch.growths()==growths);
  { auto lease=scratch.Use(128,false); }
  assert(scratch.capacity()==0);
  auto earlyReturn=[&] { auto lease=scratch.Use(8192); return; };
  earlyReturn(); assert(scratch.capacity()==0);
  GeometryScratch<uint32_t> indices(4096),expansion(4096);
  {
    auto a=indices.Use(3);auto b=expansion.Use(6);
    a.values()={5,6,7};b.values()={5,6,7,7,6,8};
    a.values().swap(b.values());
    assert((a.values()==std::vector<uint32_t>{5,6,7,7,6,8}));
  }
  assert(indices.capacity() && expansion.capacity());
  // All index elements are overwritten after resize; no prior draw leaks.
  { auto lease=indices.Use(0);assert(lease.values().empty()); }
  puts("10,000 differential vertex conversions, odd tails, capacity reuse, early-return bounds and index scratch swaps passed");
}
