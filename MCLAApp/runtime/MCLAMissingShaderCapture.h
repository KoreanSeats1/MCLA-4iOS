#pragma once
#include <array>
#include <cstddef>
#include <cstdint>

namespace mcla::native {
// Called only for genuinely missing programs under the submission mutex.
// Bound both capture memory and repeated rejected-draw diagnostic work.
class MissingShaderCaptureBudget {
  std::array<std::array<uint64_t,2>,64> pairs_{};
  size_t count_=0;
public:
  bool Take(uint64_t vertex,uint64_t pixel) {
    const std::array<uint64_t,2> pair{vertex,pixel};
    for (size_t i=0;i<count_;++i) if (pairs_[i]==pair) return false;
    if (count_==pairs_.size()) return false;
    pairs_[count_++]=pair; return true;
  }
};
} // namespace mcla::native
