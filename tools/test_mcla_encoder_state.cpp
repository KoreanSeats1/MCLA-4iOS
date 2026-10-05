#include "../MCLAApp/runtime/MCLAEncoderState.h"
#include <bit>
#include <cassert>
#include <cstdint>
#include <cstdio>

int main() {
  mcla::metal::EncoderState<double,6> viewport;
  const std::array<double,6> initial{0,0,1560,720,0,1};
  assert(viewport.Update(initial));
  assert(!viewport.Update(initial));
  for (unsigned i=0;i<initial.size();++i) {
    auto changed=initial; changed[i]+=1;
    assert(viewport.Update(changed));
    assert(!viewport.Update(changed));
    assert(viewport.Update(initial));
  }
  // A new render encoder must receive even an unchanged state.
  viewport.Reset(); assert(viewport.Update(initial));
  auto negativeZero=initial; negativeZero[0]=-0.0;
  assert(viewport.Update(negativeZero));
  assert(!viewport.Update(negativeZero));
  auto nan=initial; nan[0]=std::bit_cast<double>(uint64_t(0x7ff8000000000001));
  assert(viewport.Update(nan)); assert(!viewport.Update(nan));
  nan[0]=std::bit_cast<double>(uint64_t(0x7ff8000000000002));
  assert(viewport.Update(nan));
  mcla::metal::EncoderState<uint32_t,7> depth;
  std::array<uint32_t,7> key{1,2,3,4,5,1,1};
  assert(depth.Update(key)); assert(!depth.Update(key));
  for (auto& word:key) { word^=1; assert(depth.Update(key)); }
  puts("Encoder reset, each state component, signed zero, NaN payload and depth keys passed");
}
