#include "../MCLAApp/runtime/MCLAResourceBindingReuse.h"
#include "../MCLAApp/runtime/MCLADrawReuse.h"
#include <cassert>
#include <cstdio>
#include <random>

int main() {
  using namespace mcla::metal;
  TextureGroupSnapshot textures;
  std::array<uint8_t,26*24> fetches{};
  std::array<uint8_t,26*4> handles{};
  std::mt19937 random(0x4D434C41);
  for (unsigned trial=0;trial<1000;++trial) {
    for (auto& byte:fetches) byte=uint8_t(random());
    for (auto& byte:handles) byte=uint8_t(random());
    const uint32_t mask=trial==0?0:trial==1?0x3FFFFFF:random()&0x3FFFFFF;
    textures.Remember(12,34,mask,fetches.data(),handles.data());
    assert(textures.Matches(12,34,mask,fetches.data(),handles.data()));
    // Exhaustively mutate every fetch and handle byte: only used slots matter.
    for (unsigned slot=0;slot<26;++slot) {
      for (unsigned byte=0;byte<24;++byte) {
        fetches[slot*24+byte]^=1;
        assert(textures.Matches(12,34,mask,fetches.data(),handles.data())==!(mask&(1u<<slot)));
        fetches[slot*24+byte]^=1;
      }
      for (unsigned byte=0;byte<4;++byte) {
        handles[slot*4+byte]^=1;
        assert(textures.Matches(12,34,mask,fetches.data(),handles.data())==!(mask&(1u<<slot)));
        handles[slot*4+byte]^=1;
      }
    }
    assert(!textures.Matches(13,34,mask,fetches.data(),handles.data()));
    assert(!textures.Matches(12,35,mask,fetches.data(),handles.data()));
    assert(!textures.Matches(12,34,mask^1,fetches.data(),handles.data()));
    textures.Reset();
    assert(!textures.Matches(12,34,mask,fetches.data(),handles.data()));
  }
  ExactByteSnapshot<1056> shared;
  std::array<uint8_t,1056> bytes{};
  assert(!shared.Matches(bytes.data()));
  shared.Remember(bytes.data());
  for (unsigned i=0;i<bytes.size();++i) {
    bytes[i]^=0x80;
    assert(!shared.Matches(bytes.data()));
    bytes[i]^=0x80;
    assert(shared.Matches(bytes.data()));
  }
  shared.Reset(); assert(!shared.Matches(bytes.data()));
  // Constant-bank uploads can change while the shared block stays identical.
  // All three GPU addresses must participate in encoder pointer binding.
  ExactDrawKey<3> pointers;
  const std::array<uint64_t,3> addresses{0x1000,0x2000,0x3000};
  pointers.Remember(addresses);
  for (unsigned i=0;i<3;++i) {
    auto next=addresses; next[i]+=256; assert(!pointers.Matches(next));
  }
  pointers.Reset(); assert(!pointers.Matches(addresses));
  puts("728,000 texture-byte mutations, frame/serial/mask invalidation, every shared byte and all push addresses passed");
}
