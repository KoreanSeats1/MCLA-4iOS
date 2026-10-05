#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>
#include "../MCLAApp/runtime/MCLAQuadVertexFetch.h"

// Inspect ORIGINAL, non-normalized BE microcode. The normalization hash strips
// vfetch operands; it must never be used as the bytes for this audit.
int main(int argc, char** argv) {
  if (argc != 2) return 2;
  unsigned shaders = 0, computed = 0;
  for (const auto& entry : std::filesystem::directory_iterator(argv[1])) {
    if (!entry.path().filename().string().starts_with("vs-") ||
        entry.path().extension() != ".bin") continue;
    std::ifstream input(entry.path(), std::ios::binary);
    const std::vector<uint8_t> bytes{std::istreambuf_iterator<char>(input), {}};
    const size_t n = bytes.size()/4;
    auto word = [&](size_t i) {
      const auto* p = bytes.data() + i*4;
      return uint32_t(p[0])<<24 | uint32_t(p[1])<<16 | uint32_t(p[2])<<8 | p[3];
    };
    size_t limit = n;
    bool folds = false;
    for (size_t i=0; i+2<limit; i+=3) {
      const uint32_t d0=word(i), d1=word(i+1), d2=word(i+2);
      const uint32_t w0[]={d0,(d1>>16)|(d2<<16)}, w1[]={d1&65535,d2>>16};
      for (unsigned k=0;k<2;++k) {
        const auto op=(w1[k]>>12)&15;
        if (!((op>=1 && op<=7) || op==13 || op==14)) continue;
        const auto address=w0[k]&4095, count=(w0[k]>>12)&7, seq=(w0[k]>>16)&4095;
        if (!address) continue;
        limit=std::min(limit,size_t(address)*3);
        for (unsigned j=0;j<std::min(count,6u);++j) {
          if (!((seq>>(2*j))&1)) continue;
          const size_t base=(size_t(address)+j)*3;
          if (base+2>=n) return 3;
          const auto fetch=word(base);
          if ((fetch&31)!=0 || (word(base+1)&4095)==4095) continue;
          if (((fetch>>5)&63) || ((fetch>>30)&3)) {
            std::cout<<entry.path().filename().string()<<" instruction="<<base/3
                     <<" source=r"<<((fetch>>5)&63)<<'.'<<"xyzw"[(fetch>>30)&3]
                     <<" stride="<<(word(base+2)&255)<<'\n';
            folds=true;
          }
        }
      }
    }
    const auto hash=std::stoull(entry.path().stem().string().substr(3),nullptr,16);
    if (folds != mcla::native::QuadFetchScaleWord(hash).has_value()) {
      std::cerr<<"Unaudited computed-fetch contract: "<<entry.path()<<'\n';
      return 4;
    }
    ++shaders; computed+=folds;
  }
  std::cout<<"Audited "<<shaders<<" vertex shaders; computed fetch="<<computed<<'\n';
  return shaders && computed==3 ? 0 : 5;
}
