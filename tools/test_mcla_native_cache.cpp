#include <shader/shader_cache.h>
#include <gta4_frame_limiter.h>
#include <algorithm>
#include <cassert>
#include <cstring>
#include <iostream>
#include <vector>

// Host-side structural/ABI regression checks, not a substitute for spirv-val
// or rendering the title on the device.
static std::vector<uint32_t> Words(uint32_t offset, uint32_t size) {
  assert(size >= 20 && size % 4 == 0);
  assert(uint64_t(offset) + size <= g_spirvCacheDecompressedSize);
  std::vector<uint32_t> result(size / 4);
  std::memcpy(result.data(), g_compressedSpirvCache + offset, size);
  assert(result.front() == 0x07230203);
  return result;
}

static std::vector<uint32_t> WithoutEarlyTests(const std::vector<uint32_t>& source) {
  std::vector<uint32_t> result(source.begin(), source.begin() + 5);
  for (size_t i = 5; i < source.size();) {
    const uint32_t count = source[i] >> 16;
    assert(count && i + count <= source.size());
    const bool early = (source[i] & 0xffff) == 16 && count == 3 && source[i + 2] == 9;
    if (!early) result.insert(result.end(), source.begin() + i, source.begin() + i + count);
    i += count;
  }
  return result;
}

int main() {
  assert(g_shaderCacheEntryCount >= 410);
  assert(g_spirvCacheCompressedSize == g_spirvCacheDecompressedSize);
  unsigned vertex = 0, pixel = 0;
  bool missingVertexFixed = false, missingPixelFixed = false;
  for (size_t i = 0; i < g_shaderCacheEntryCount; ++i) {
    const auto& entry = g_shaderCacheEntries[i];
    if (i) assert(g_shaderCacheEntries[i - 1].hash < entry.hash);
    assert((entry.usedTextureMask & ~0x03ffffffu) == 0);
    const auto early = Words(entry.spirvOffset, entry.spirvSize);
    const auto stripped = WithoutEarlyTests(early);
    if (std::strstr(entry.filename, "mcla_ps_")) {
      ++pixel;
      const auto late = Words(entry.lateSpirvOffset, entry.lateSpirvSize);
      assert(late == stripped && WithoutEarlyTests(late) == late);
      assert(entry.specConstantsMask == 0x702);
    } else {
      ++vertex;
      assert(std::strstr(entry.filename, "mcla_vs_"));
      assert(!entry.lateSpirvSize && entry.specConstantsMask == 1);
    }
    missingVertexFixed |= entry.hash == 0x3F410086009913D6ull;
    missingPixelFixed |= entry.hash == 0x24DF5D90EB724450ull;
  }
  assert(missingVertexFixed && missingPixelFixed);
  for (const uint64_t hash : {0x9BA5F9642B3740EDull, 0x7FB3EA2740CD2772ull,
                            0x1DD25CFF4C2B1C71ull, 0xB71476C00ABD8C8Cull,
                            0xCE0D4EE79106D6B9ull}) {
    assert(std::any_of(g_shaderCacheEntries, g_shaderCacheEntries + g_shaderCacheEntryCount,
        [hash](const auto& entry) { return entry.hash == hash; }));
  }
  auto decision = gta4::frame_limiter::Plan({}, 30, 1'000'000'000);
  for (unsigned i = 1; i < 30; ++i) {
    decision = gta4::frame_limiter::Plan(decision.next_state, 30,
                                       decision.next_state.next_deadline_ns);
  }
  assert(decision.next_state.next_deadline_ns == 2'000'000'000);
  decision = gta4::frame_limiter::Plan(decision.next_state, 30, 5'000'000'000);
  assert(decision.late_reset && !decision.should_wait(5'000'000'000));
  assert(gta4::frame_limiter::Plan(decision.next_state, 0, 0).next_state.frames_per_second == 0);
  std::cout << "PASS: " << vertex << " vertex, " << pixel
            << " pixel, late-fragment equivalence, missing-pair coverage, frame pacing\n";
}
