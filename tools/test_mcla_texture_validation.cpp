#include "../MCLAApp/runtime/MCLAMetalTextureValidation.h"
#include <cassert>
#include <cstdio>
#include <vector>

int main() {
  using namespace mcla::metal;
  // Validate base, separately located mip data, and a second array layer.
  std::array<uint8_t, 4096> guest{};
  for (unsigned i=0;i<guest.size();++i) guest[i]=uint8_t(i*17);
  std::vector<TextureBlockSample> samples;
  for (uint32_t address : {0u, 1024u, 3072u}) {
    TextureBlockSample sample{address,16};
    std::memcpy(sample.bytes.data(),guest.data()+address,16);
    samples.push_back(sample);
  }
  auto read=[&](uint32_t a,uint32_t n)->const uint8_t* {
    return uint64_t(a)+n<=guest.size()?guest.data()+a:nullptr;
  };
  assert(TextureSamplesMatch(samples,read));
  for (const auto &sample:samples) for (unsigned byte=0;byte<16;++byte) {
    guest[sample.address+byte]^=0x80;
    assert(!TextureSamplesMatch(samples,read));
    guest[sample.address+byte]^=0x80;
  }
  samples[0].address=4095;
  assert(!TextureSamplesMatch(samples,read));
  samples[0].size=17;
  assert(!TextureSamplesMatch(samples,read));
  for (uint64_t count : {1u,4u,8u,9u,127u,4096u}) {
    unsigned sampled=0;
    for(uint64_t block=0;block<count;++block) sampled+=SampleTextureBlock(block,count);
    assert(sampled==std::min<uint64_t>(8,count));
    assert(SampleTextureBlock(0,count));
    assert(SampleTextureBlock(count-1,count));
    assert(!SampleTextureBlock(count,count));
  }
  assert(!SampleTextureBlock(0,0));
  std::puts("PASS: bounded block samples detect changed base/mip/layer contents and reject unreadable ranges");
}
