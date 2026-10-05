#pragma once

#include <cstddef>
#include <cstdint>
#include <xxhash.h>

namespace mcla::metal {
// Renderer-local cache keys only. These are never serialized, so use the same
// fast seeded hash as Theft4's native renderer instead of a byte-serial FNV
// dependency chain on every draw and resource lookup.
inline uint64_t FastHash(const void* bytes, size_t size,
                         uint64_t seed = 0xCBF29CE484222325ull) {
  return XXH3_64bits_withSeed(bytes, size, seed);
}
} // namespace mcla::metal
