#include "../MCLAApp/runtime/MCLAIntroSkip.h"
#include <array>
#include <cassert>
#include <cstdio>
int main() {
  using mcla::native::RequestInitializedIntroSkip;
  std::array<uint8_t,16> state{};
  auto before=state;assert(!RequestInitializedIntroSkip(state));assert(state==before);
  for(unsigned i=0;i<16;++i)state[i]=uint8_t(i+1);
  before=state;
  assert(!RequestInitializedIntroSkip(std::span(state).first(15)));assert(state==before);
  assert(RequestInitializedIntroSkip(state));
  for(unsigned i=0;i<16;++i)assert(state[i]==(i==13?1:before[i]));
  before=state;assert(RequestInitializedIntroSkip(state));assert(state==before);
  puts("Intro skip requires initialized player and preserves timer/context/completion fields");
}
