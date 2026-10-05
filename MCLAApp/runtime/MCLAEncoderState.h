#pragma once
#include <array>
#include <cstring>
#include <type_traits>

namespace mcla::metal {
// Explicit scalar arrays avoid struct padding. Compare representations so
// signed zero and NaN payload changes are not silently suppressed.
template <class T, size_t N> class EncoderState {
  static_assert(std::is_arithmetic_v<T>);
  std::array<T, N> values_{};
  bool valid_ = false;
public:
  bool Update(const std::array<T, N>& next) {
    if (valid_ && std::memcmp(values_.data(), next.data(), sizeof(T) * N) == 0)
      return false;
    values_ = next;
    valid_ = true;
    return true;
  }
  void Reset() { valid_ = false; }
};
} // namespace mcla::metal
