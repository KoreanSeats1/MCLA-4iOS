#include "../MCLAApp/runtime/MCLADrawReuse.h"
#include <cassert>
#include <cstdio>
#include <random>
int main() {
  std::mt19937_64 random(0x4D434C41);
  std::array<uint8_t,4096> source{},copy{};
  for(auto& b:source)b=uint8_t(random());
  for(unsigned iteration=0;iteration<10000;++iteration) {
    std::array<uint64_t,4> mask{};
    for(auto& bits:mask)bits=iteration==0?UINT64_MAX:iteration==1?0:random();
    copy.fill(0xCC);
    mcla::metal::CopyConstantRegisters(copy.data(),source.data(),mask.data());
    for(unsigned i=0;i<4096;++i) {
      bool read=(mask[i/1024]>>((i%1024)/16))&1;
      assert(copy[i]==(read?source[i]:0xCC));
    }
  }
  copy.fill(0);mcla::metal::CopyConstantRegisters(copy.data(),source.data(),nullptr);
  assert(copy==source);
  // Every metadata, frame, resource epoch, shader/decl and fetch word matters.
  auto check=[&]<size_t N>() {
    mcla::metal::ExactDrawKey<N> key;
    std::array<uint64_t,N> words{};
    for(auto& word:words)word=random();
    assert(!key.Matches(words));key.Remember(words);assert(key.Matches(words));
    for(unsigned i=0;i<N;++i)for(unsigned bit=0;bit<64;++bit) {
      auto changed=words;changed[i]^=uint64_t(1)<<bit;
      assert(!key.Matches(changed));
    }
    key.Reset();assert(!key.Matches(words));
  };
  check.operator()<9>();check.operator()<10>();check.operator()<20>();check.operator()<95>();
  puts("10,000 differential constant masks, full-bank fallback and every draw-key bit passed");
}
