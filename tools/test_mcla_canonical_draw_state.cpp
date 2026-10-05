#include "../MCLAApp/runtime/MCLACanonicalDrawState.h"
#include <cassert>
#include <cstdio>
#include <random>

int main() {
  constexpr size_t size=0x5780;
  std::array<uint8_t,size> source{}, reference{}, full{}, compact{};
  std::mt19937_64 random(0x4D434C41);
  for (unsigned iteration=0;iteration<1000;++iteration) {
    for (auto& byte:source) byte=uint8_t(random());
    std::array<uint64_t,4> vs{},ps{};
    for (auto& mask:vs) mask=random();
    for (auto& mask:ps) mask=random();
    const auto* v=iteration%3?vs.data():nullptr;
    const auto* p=iteration%5?ps.data():nullptr;
    reference.fill(0xCC); full.fill(0xCC); compact.fill(0xA5);
    // Original full canonicalization, independent of the new helper.
    std::memcpy(reference.data(),source.data(),1920);
    mcla::metal::CopyConstantRegisters(reference.data()+1920,source.data()+1920,v);
    mcla::metal::CopyConstantRegisters(reference.data()+6016,source.data()+6016,p);
    std::memcpy(reference.data()+10112,source.data()+10112,size-10112);
    auto copy=[&](unsigned out,unsigned in,unsigned bytes) {
      std::memcpy(reference.data()+out,source.data()+in,bytes);
    };
    copy(12428,12436,4);copy(12432,12440,16);copy(12448,12456,4);
    copy(12452,12460,68);copy(12536,12544,104);
    copy(11844,11852,4);copy(11848,11856,4);copy(11868,11876,8);
    copy(12640,12648,24);copy(12668,12676,16);
    copy(10832,11196,4);copy(10836,11192,4);copy(10840,11204,4);copy(10844,11200,4);
    copy(10436,10424,8);
    const uint8_t zero[4]={},one[4]={0,0,0,1};
    std::memcpy(reference.data()+10432,zero,4);
    std::memcpy(reference.data()+11848,one,4);
    mcla::metal::CopyCanonicalDrawState(full.data(),source.data(),size,v,p,false);
    assert(full==reference);
    mcla::metal::CopyCanonicalDrawState(compact.data(),source.data(),size,v,p,true);
    auto equal=[&](unsigned offset,unsigned bytes) {
      assert(std::memcmp(compact.data()+offset,reference.data()+offset,bytes)==0);
    };
    equal(1152,624);equal(10112,736);equal(11844,8);equal(11868,8);
    equal(12428,92);equal(12536,104);equal(12640,24);equal(12668,16);
    for (unsigned bank=0;bank<2;++bank) {
      const auto* mask=bank?p:v;unsigned start=bank?6016:1920;
      for (unsigned reg=0;reg<256;++reg)
        if (!mask || ((mask[reg/64]>>(reg%64))&1)) equal(start+reg*16,16);
    }
    assert(compact[0]==0xA5 && compact[size-1]==0xA5);
  }
  puts("1,000 randomized full-snapshot equivalence and poisoned compact-state comparisons passed");
}
