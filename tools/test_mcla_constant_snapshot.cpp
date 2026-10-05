#include "../MCLAApp/runtime/MCLAConstantSnapshot.h"
#include <cassert>
#include <iostream>
#include <random>
int main() {
  using mcla::metal::ConstantSnapshot;
  ConstantSnapshot cache;
  std::array<uint8_t,4096> bytes{};
  uint64_t sparse[4]={1,2,0,1ull<<63}, all[4]={~0ull,~0ull,~0ull,~0ull};
  assert(!cache.Matches(bytes.data(),sparse));
  cache.Remember(bytes.data(),sparse);
  assert(cache.Matches(bytes.data(),sparse));
  bytes[16]=7; // Unused register is irrelevant.
  assert(cache.Matches(bytes.data(),sparse));
  assert(!cache.Matches(bytes.data(),all)); // Newly used registers must upload.
  bytes[4095]=1; // c255 is covered, including its last byte.
  assert(!cache.Matches(bytes.data(),sparse));
  cache.Remember(bytes.data(),all);
  assert(cache.Matches(bytes.data(),sparse));
  bytes[0]=0x80; // Bitwise, including signed zero/NaN payload changes.
  assert(!cache.Matches(bytes.data(),all));
  cache.Remember(bytes.data(),all);
  cache.Reset(); // A recycled flight must not reuse old GPU addresses.
  assert(!cache.Matches(bytes.data(),all));
  std::mt19937 random(3917);
  for (unsigned trial=0;trial<10000;++trial) {
    uint64_t mask[4];for(auto& m:mask)m=(uint64_t(random())<<32)|random();
    for(auto& b:bytes)b=uint8_t(random());
    cache.Remember(bytes.data(),mask);
    assert(cache.Matches(bytes.data(),mask));
    unsigned offset=random()%4096;
    bytes[offset]^=1;
    bool used=(mask[offset/1024]>>(offset/16%64))&1;
    assert(cache.Matches(bytes.data(),mask)==!used);
  }
  std::cout << "constant snapshot: exact mutations, masks, dynamic banks, frame reset passed\n";
}
