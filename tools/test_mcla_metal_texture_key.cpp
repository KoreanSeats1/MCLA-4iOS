#include "../MCLAApp/runtime/MCLAMetalTextureKey.h"
#include <cassert>
#include <cstdio>
int main() {
  using mcla::metal::TextureContentKey;
  std::array<uint32_t,6> a{};
  auto sampler=a;
  sampler[0]=0x1FFu<<10;sampler[3]=0xFFFu<<19;
  sampler[4]=~0x3FCu;sampler[5]=0x1FFu;
  assert(TextureContentKey(a)==TextureContentKey(sampler));
  for(auto [word,bit]:std::array<std::array<unsigned,2>,12>{{
      {0,22},{0,31},{1,0},{1,6},{1,12},{2,0},
      {3,1},{3,13},{4,2},{4,6},{5,9},{5,12}}}) {
    auto changed=a;changed[word]|=1u<<bit;
    assert(TextureContentKey(a)!=TextureContentKey(changed));
  }
  std::puts("PASS: sampler changes preserve texels; layout/source/swizzle/mip changes invalidate.");
}
