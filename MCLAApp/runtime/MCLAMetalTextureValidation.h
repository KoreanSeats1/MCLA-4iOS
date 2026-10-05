#pragma once
#include <array>
#include <cstdint>
#include <cstring>
#include <span>

namespace mcla::metal {
// Snapshot actual decoded blocks, including mip and array/cube layers. This
// bounds recurring validation cost; it is a backstop, not a complete write watch.
struct TextureBlockSample {
  uint32_t address = 0;
  uint32_t size = 0;
  std::array<uint8_t, 16> bytes{};
};
constexpr bool SampleTextureBlock(uint64_t block, uint64_t total) {
  if (!total || block >= total) return false;
  if (total <= 8) return true;
  for (unsigned i = 0; i < 8; ++i)
    if (block == (total - 1) * i / 7) return true;
  return false;
}
template <typename Read>
bool TextureSamplesMatch(std::span<const TextureBlockSample> samples, Read read) {
  for (const auto &s : samples) {
    if (!s.size || s.size > s.bytes.size()) return false;
    const auto *current = read(s.address, s.size);
    if (!current || std::memcmp(current, s.bytes.data(), s.size)) return false;
  }
  return true;
}
}
