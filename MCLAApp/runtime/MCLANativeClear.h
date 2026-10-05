#pragma once

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
#include <limits>
#include <optional>
#include <span>
#include <vector>

namespace mcla::native {

struct ClearRectangle {
  int32_t left, top, right, bottom;
  bool operator==(const ClearRectangle&) const = default;
};

// Bound malformed guest lists before multiplication, validation or allocation.
// A null list does not use count; an explicit zero-count list is a no-op.
inline constexpr uint32_t kMaximumClearRectangles = 4096;
inline std::optional<uint32_t> ClearRectangleBytes(uint32_t count, bool hasList) {
  if (!hasList) return 0;
  if (count > kMaximumClearRectangles) return std::nullopt;
  return count * 16;
}

// Device offsets here are RAW MCLA, not canonical. Verified from CE guest
// rex_sub_824195E8 -> rex_sub_824194C0 -> rex_sub_82418E48: every rectangle
// intersects the integer-truncated viewport, then the optional API scissor.
// An empty intersection must NOT become a ClearCommand: its legacy empty
// rectangle encoding means "full surface" to the renderer.
inline std::optional<std::vector<ClearRectangle>> DecodeClearRectangles(
    std::span<const uint8_t> device, uint32_t count, bool hasList,
    std::span<const uint8_t> rectangles, uint32_t surfaceWidth,
    uint32_t surfaceHeight) {
  const auto bytes = ClearRectangleBytes(count, hasList);
  if (!bytes || rectangles.size() < *bytes || device.size() < 13188)
    return std::nullopt;
  if (hasList && !count) return std::vector<ClearRectangle>{};
  const auto word = [](std::span<const uint8_t> data, uint32_t at) {
    return uint32_t(data[at]) << 24 | uint32_t(data[at+1]) << 16 |
           uint32_t(data[at+2]) << 8 | uint32_t(data[at+3]);
  };
  const auto signedWord = [&](std::span<const uint8_t> data, uint32_t at) {
    return std::bit_cast<int32_t>(word(data, at));
  };
  std::array<int32_t,4> viewport{};
  for (unsigned i=0;i<4;++i) {
    const double value=std::bit_cast<float>(word(device,12648+i*4));
    if (!std::isfinite(value) || value < std::numeric_limits<int32_t>::min() ||
        value > std::numeric_limits<int32_t>::max()) return std::nullopt;
    viewport[i]=int32_t(value); // PPC fctiwz, truncation toward zero.
  }
  const int64_t right=int64_t(viewport[0])+viewport[2];
  const int64_t bottom=int64_t(viewport[1])+viewport[3];
  if (right > INT32_MAX || right < INT32_MIN ||
      bottom > INT32_MAX || bottom < INT32_MIN) return std::nullopt;
  ClearRectangle clip{viewport[0],viewport[1],int32_t(right),int32_t(bottom)};
  if (word(device,11856)) {
    clip.left=std::max(clip.left,signedWord(device,12676));
    clip.top=std::max(clip.top,signedWord(device,12680));
    clip.right=std::min(clip.right,signedWord(device,12684));
    clip.bottom=std::min(clip.bottom,signedWord(device,12688));
  }
  if (clip.right<=clip.left || clip.bottom<=clip.top)
    return std::vector<ClearRectangle>{};
  ClearRectangle defaultRectangle{};
  if (!hasList) {
    // The guest's null-rectangle path substitutes the complete tiled canvas
    // when tiling is active, or when every non-null binding matches the cached
    // tiled bindings. This is independent of subsequent viewport clipping.
    bool tiled=(device[10940]&0x10u)!=0;
    if (!tiled && (device[10940]&0x20u)) {
      tiled=true;
      for(unsigned i=0;i<5;++i) {
        const auto binding=word(device,12440+i*4);
        if(binding && binding!=word(device,12728+i*4)) tiled=false;
      }
    }
    if (tiled) {
      surfaceWidth=word(device,13180);
      surfaceHeight=word(device,13184);
    }
    if (surfaceWidth>INT32_MAX || surfaceHeight>INT32_MAX)
      return std::nullopt;
    defaultRectangle={0,0,int32_t(surfaceWidth),int32_t(surfaceHeight)};
    count=1;
  }
  std::vector<ClearRectangle> result;
  result.reserve(count);
  for (uint32_t i=0;i<count;++i) {
    ClearRectangle r=defaultRectangle;
    if(hasList) r={signedWord(rectangles,i*16),signedWord(rectangles,i*16+4),
                   signedWord(rectangles,i*16+8),signedWord(rectangles,i*16+12)};
    r.left=std::max(r.left,clip.left);
    r.top=std::max(r.top,clip.top);
    r.right=std::min(r.right,clip.right);
    r.bottom=std::min(r.bottom,clip.bottom);
    if(r.right>r.left && r.bottom>r.top) result.push_back(r);
  }
  return result;
}

} // namespace mcla::native
