#include "../MCLAApp/runtime/MCLAShaderConstants.h"
#include <cassert>
#include <cstdio>
#include <random>

int main() {
  using namespace mcla::native;
  ShaderDefinitionSnapshot cache;
  auto check=[&](const std::vector<uint8_t>& bytes,uint32_t first) {
    std::array<ShaderFloatDefinition,256> reference;
    size_t count=0;
    const bool valid=DecodeShaderFloatDefinitionsInto(bytes,first,reference,count);
    std::span<const ShaderFloatDefinition> cached;
    assert(cache.Resolve(bytes,first,cached)==valid);
    if (!valid) { assert(cached.empty()); return; }
    assert(cached.size()==count);
    for (size_t i=0;i<count;++i) {
      assert(cached[i].destination==reference[i].destination);
      assert(cached[i].source==reference[i].source);
      assert(cached[i].bytes==reference[i].bytes);
    }
  };
  std::mt19937 random(0x4D434C41);
  unsigned mutations=0;
  for (unsigned trial=0;trial<300;++trial) {
    const unsigned first=trial%2?256:0;
    const unsigned count=trial==0?256:random()%257;
    std::vector<uint8_t> bytes;
    for (unsigned i=0;i<count;++i) {
      const unsigned reg=first+random()%256;
      const unsigned words=1+random()%(1024-(reg-first)*4);
      const unsigned source=(random()%8192)*4;
      bytes.insert(bytes.end(),{uint8_t(reg>>8),uint8_t(reg),uint8_t(words>>8),uint8_t(words),
          uint8_t(source>>24),uint8_t(source>>16),uint8_t(source>>8),uint8_t(source)});
    }
    bytes.insert(bytes.end(),{0,0,0,0});
    check(bytes,first);
    const auto hits=cache.hits();
    check(bytes,first); assert(cache.hits()==hits+1);
    // Mutating every consumed byte is checked against an independent decode.
    for (size_t i=0;i<bytes.size();++i) {
      bytes[i]^=1; check(bytes,first); bytes[i]^=1; check(bytes,first);
      ++mutations;
    }
    auto trailing=bytes; trailing.insert(trailing.end(),32,0xCC);
    const auto before=cache.hits();
    check(trailing,first); assert(cache.hits()==before+1);
    check(bytes,first==256?0:256);
    check(bytes,first);
    auto truncated=bytes; truncated.pop_back(); check(truncated,first);
    check(bytes,first);
    cache.Reset(); const auto decodes=cache.decodes();
    check(bytes,first); assert(cache.decodes()==decodes+1);
  }
  check({},0); check({0,0,0,0},1);
  // A malformed table cannot leave a valid prefix cache behind.
  check({0,0,0,1,0,0,0,1,0,0,0,0},0);
  puts("Shader definition snapshot: randomized differential mutations, max entries, truncation, stage and trailing-section checks passed");
  std::printf("Consumed bytes independently mutated: %u\n",mutations);
}
