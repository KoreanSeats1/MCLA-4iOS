#include "../MCLAApp/runtime/MCLANativeGpuCompatibility.h"
#include <algorithm>
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>

using namespace mcla::native;

static std::set<size_t> InputLocationOffsets(const std::vector<uint32_t>& words) {
  std::set<uint32_t> inputs;
  std::set<size_t> result;
  for (size_t i = 5; i < words.size(); i += words[i] >> 16) {
    assert(words[i] >> 16);
    if ((words[i] & 0xFFFF) == 59 && words[i + 3] == 1) inputs.insert(words[i + 2]);
  }
  for (size_t i = 5; i < words.size(); i += words[i] >> 16) {
    if ((words[i] & 0xFFFF) == 71 && words[i + 2] == 30 && inputs.contains(words[i + 1])) {
      result.insert(i + 3);
    }
  }
  return result;
}

int main(int argc, char** argv) {
  assert(DepthTextureFormat(22) == VK_FORMAT_D32_SFLOAT_S8_UINT);
  assert(DepthTextureFormat(23) == VK_FORMAT_D32_SFLOAT_S8_UINT);
  assert(AdditionalSurfaceFormat(0x2D200196, true) == DepthTextureFormat(22));
  assert(AdditionalSurfaceFormat(0x18287F86, false) == VK_FORMAT_R8G8B8A8_UNORM);
  assert(AdditionalSurfaceFormat(0x1A22AB60, false) == VK_FORMAT_R16G16B16A16_SFLOAT);
  assert(AdditionalSurfaceFormat(0x1A22AB60, true) == VK_FORMAT_UNDEFINED);
  assert(AdditionalSurfaceFormat(0x18287F86, true) == VK_FORMAT_UNDEFINED);
  assert(AdditionalSurfaceFormat(0x2D200196, false) == VK_FORMAT_UNDEFINED);
  assert(DepthTextureFormat(6) == VK_FORMAT_UNDEFINED);
  const auto depthFormat = DepthTextureFormat(22);
  assert(CanCopyDepthPlacement(depthFormat, depthFormat, 640, 640, 640, 640,
                              VK_SAMPLE_COUNT_1_BIT, VK_SAMPLE_COUNT_1_BIT));
  assert(!CanCopyDepthPlacement(depthFormat, depthFormat, 640, 640, 640, 320,
                               VK_SAMPLE_COUNT_1_BIT, VK_SAMPLE_COUNT_1_BIT));
  assert(!CanCopyDepthPlacement(depthFormat, depthFormat, 640, 640, 640, 640,
                               VK_SAMPLE_COUNT_1_BIT, VK_SAMPLE_COUNT_2_BIT));
  assert(!CanCopyDepthPlacement(depthFormat, VK_FORMAT_D24_UNORM_S8_UINT,
                               640, 640, 640, 640,
                               VK_SAMPLE_COUNT_1_BIT, VK_SAMPLE_COUNT_1_BIT));
  assert(InlineTexcoordFormat(true, 5, VK_FORMAT_R32_SFLOAT, 16, 24, 2) == VK_FORMAT_R32G32_SFLOAT);
  assert(InlineTexcoordFormat(false, 5, VK_FORMAT_R32_SFLOAT, 16, 24, 2) == VK_FORMAT_R32_SFLOAT);
  assert(InlineTexcoordFormat(true, 5, VK_FORMAT_R32_SFLOAT, 16, 20, 2) == VK_FORMAT_R32_SFLOAT);
  assert(InlineTexcoordFormat(true, 5, VK_FORMAT_R32_SFLOAT, UINT32_MAX, 24, 2) == VK_FORMAT_R32_SFLOAT);
  assert(InlineTexcoordFormat(true, 5, VK_FORMAT_R32_SFLOAT, 16, 24, 1) == VK_FORMAT_R32_SFLOAT);
  assert(InlineTexcoordFormat(true, 0, VK_FORMAT_R32_SFLOAT, 16, 24, 2) == VK_FORMAT_R32_SFLOAT);
  std::array<std::array<int32_t,4>,2> tiles{{{0,0,1280,512},{0,512,1280,720}}};
  auto canvas=VerticalTiledCanvas(tiles);
  assert(canvas && canvas->width==1280 && canvas->height==720);
  tiles[1][1]=500; assert(!VerticalTiledCanvas(tiles)); // Overlap.
  tiles[1][1]=520; assert(!VerticalTiledCanvas(tiles)); // Gap.
  tiles[1][1]=512; tiles[1][2]=640; assert(!VerticalTiledCanvas(tiles));
  tiles[1][2]=1280; tiles[1][3]=32768; assert(!VerticalTiledCanvas(tiles));
  assert(!VerticalTiledCanvas({tiles.data(),1}));

  // An input at semantic 32 coexists with an output at location 32.
  // Decorations precede variable declarations, just like DXC modules.
  const std::vector<uint32_t> fixture = {
    0x07230203, 0x00010000, 0, 20, 0,
    (4u << 16) | 71, 5, 30, 32,
    (4u << 16) | 71, 6, 30, 0,
    (4u << 16) | 71, 7, 30, 32,
    (4u << 16) | 71, 8, 11, 42,  // BuiltIn, no location.
    (4u << 16) | 59, 2, 5, 1,
    (4u << 16) | 59, 2, 6, 1,
    (4u << 16) | 59, 3, 7, 3,
    (4u << 16) | 59, 2, 8, 1,
  };
  auto compact = fixture;
  const auto map = CompactVertexLocations(compact, 31);
  assert(map && map->size() == 2);
  assert((*map)[0].semantic == 0 && (*map)[0].native == 0);
  assert((*map)[1].semantic == 32 && (*map)[1].native == 1);
  assert(compact[8] == 1 && compact[16] == 32);
  const auto allowed = InputLocationOffsets(fixture);
  for (size_t i = 0; i < compact.size(); ++i) assert(compact[i] == fixture[i] || allowed.contains(i));
  auto rejected = fixture;
  assert(!CompactVertexLocations(rejected, 1) && rejected == fixture);
  rejected[12] = 32;  // Duplicate input semantic: reject, don't alias inputs.
  const auto duplicate = rejected;
  assert(!CompactVertexLocations(rejected, 31) && rejected == duplicate);
  rejected = fixture;
  rejected.pop_back();
  const auto truncated = rejected;
  assert(!CompactVertexLocations(rejected, 31) && rejected == truncated);

  unsigned modules = 0, highLocations = 0;
  assert(argc == 2);
  for (const auto& entry : std::filesystem::directory_iterator(argv[1])) {
    const auto name = entry.path().filename().string();
    if (!name.starts_with("vs-") || entry.path().extension() != ".spv") continue;
    std::ifstream file(entry.path(), std::ios::binary | std::ios::ate);
    const auto size = file.tellg();
    assert(size >= 20 && size % 4 == 0);
    std::vector<uint32_t> words(size_t(size) / 4);
    file.seekg(0);
    file.read(reinterpret_cast<char*>(words.data()), size);
    assert(file);
    const auto original = words;
    const auto offsets = InputLocationOffsets(words);
    const auto mapping = CompactVertexLocations(words, 31);
    assert(mapping && mapping->size() == offsets.size());
    std::set<uint32_t> dense;
    for (size_t offset : offsets) {
      assert(words[offset] < 31 && dense.insert(words[offset]).second);
      const auto found = std::find_if(mapping->begin(), mapping->end(),
          [&](const auto& pair) { return pair.semantic == original[offset]; });
      assert(found != mapping->end() && found->native == words[offset]);
      highLocations += original[offset] >= 31;
    }
    for (size_t i = 0; i < words.size(); ++i) assert(words[i] == original[i] || offsets.contains(i));
    ++modules;
  }
  assert(modules >= 197 && highLocations);
  std::cout << "PASS: matching depth/surface formats, transactional SPIR-V validation, "
            << modules << " vertex modules, " << highLocations
            << " out-of-range semantic locations compacted; outputs/instructions unchanged\n";
}
