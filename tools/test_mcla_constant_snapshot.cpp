#include "../MCLAApp/runtime/MCLAConstantSnapshot.h"
#include <cassert>
#include <chrono>
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
  // Independently reproduce the previous register-by-register algorithm.
  struct Reference {
    std::array<uint8_t,4096> bytes{};
    __attribute__((noinline)) void Remember(const uint8_t* src,const uint64_t* mask) {
      for(unsigned b=0;b<4;++b)for(uint64_t bits=mask[b];bits;bits&=bits-1) {
        unsigned at=(b*64+std::countr_zero(bits))*16;
        memcpy(bytes.data()+at,src+at,16);
      }
    }
    __attribute__((noinline)) bool Matches(const uint8_t* src,const uint64_t* mask) {
      for(unsigned b=0;b<4;++b)for(uint64_t bits=mask[b];bits;bits&=bits-1) {
        unsigned at=(b*64+std::countr_zero(bits))*16;
        if(memcmp(bytes.data()+at,src+at,16))return false;
      }
      return true;
    }
  } reference;
  for(unsigned trial=0;trial<10000;++trial) {
    uint64_t mask[4];for(auto& m:mask)m=(uint64_t(random())<<32)|random();
    for(auto& b:bytes)b=uint8_t(random());
    reference.Remember(bytes.data(),mask);cache.Remember(bytes.data(),mask);
    for(unsigned i=0;i<4;++i)bytes[random()%4096]^=1;
    assert(cache.Matches(bytes.data(),mask)==reference.Matches(bytes.data(),mask));
  }
  uint64_t clustered[4]={0x00000000001FFFFFull,0x000000FFFFF00000ull,0,0xFF00000000000000ull};
  auto benchmark=[&](auto& bank) {
    auto begin=std::chrono::steady_clock::now();unsigned matches=0;
    for(unsigned i=0;i<200000;++i) {
      bytes[4095]^=1;bank.Remember(bytes.data(),clustered);
      matches+=bank.Matches(bytes.data(),clustered);
    }
    assert(matches==200000);
    return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
  };
  const double before=benchmark(reference),after=benchmark(cache);
  std::cout<<"Clustered constant remember/compare host fixture: "<<before<<" -> "<<after<<" ms (not device frame time)\n";
  std::cout << "constant snapshot: exact mutations, masks, dynamic banks, frame reset passed\n";
}
