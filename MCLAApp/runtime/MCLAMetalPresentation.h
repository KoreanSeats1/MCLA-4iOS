#pragma once
#include <algorithm>
#include <cstdint>

namespace mcla::metal {
struct OutputSize { uint32_t width,height; };
struct SafeFrame { uint32_t left, top, width, height; };
// Game-authored 2D HUD coordinates remain 16:9 even when the camera scene
// expands to a device's native aspect. Center that authored frame without
// changing its pixel density or the 3D scene extent.
constexpr SafeFrame HudSafeFrame(uint32_t width, uint32_t height) {
  if (!width || !height) return {0,0,width,height};
  if (uint64_t(width)*9 > uint64_t(height)*16) {
    const uint32_t safeWidth = uint32_t(uint64_t(height)*16/9);
    return {(width-safeWidth)/2,0,safeWidth,height};
  }
  const uint32_t safeHeight = uint32_t(uint64_t(width)*9/16);
  return {0,(height-safeHeight)/2,width,safeHeight};
}
constexpr uint32_t RenderHeight(uint32_t height) {
  return height == 900 || height == 1080 ? height : 720;
}
constexpr OutputSize RenderSize(uint32_t height) {
  height = RenderHeight(height);
  return {height * 16 / 9, height};
}
// Keep the title's 1280x720 logical surface ABI, but allocate extra physical
// scene pixels for the device's shape. Camera hooks supply the corresponding
// projection; title UI/post targets keep their authored logical dimensions.
constexpr OutputSize SceneSize(uint32_t height, uint32_t guestWidth,
                               uint32_t guestHeight) {
  height = RenderHeight(height);
  return {uint32_t((uint64_t(guestWidth) * height + 360) / 720),
          uint32_t((uint64_t(guestHeight) * height + 360) / 720)};
}
// Scene resolution and FSR are independent, as in Theft4 Lab. No GTA-specific
// video-mode hooks: MCLA keeps its guest ABI at 720p and scales host storage.
constexpr OutputSize OutputForSettings(uint32_t renderHeight, bool fsr,
                                        uint32_t width,uint32_t height,
                                        uint32_t guestWidth=1280,
                                        uint32_t guestHeight=720) {
  if(!fsr || !width || !height)
    return SceneSize(renderHeight, guestWidth, guestHeight);
  if(guestWidth!=1280 || guestHeight!=720) {
    const uint32_t divisor=std::max({1u,(width+3839u)/3840u,
                                      (height+2159u)/2160u});
    return {(width+divisor/2)/divisor,(height+divisor/2)/divisor};
  }
  const uint32_t fitHeight=std::min(height, uint32_t(uint64_t(width)*9/16));
  const uint32_t divisor=std::max(1u,(fitHeight+2159u)/2160u);
  const uint32_t outputHeight=fitHeight/divisor;
  return {outputHeight*16/9,outputHeight};
}
constexpr OutputSize SceneExtent(uint32_t width, uint32_t height,
                                  uint32_t renderHeight,
                                  uint32_t guestWidth=1280,
                                  uint32_t guestHeight=720) {
  // Deliberately leave shadow atlases, material textures, reflection probes,
  // exposure and quarter-resolution post targets at their authored sizes.
  return width == 1280 && height == 720
      ? SceneSize(renderHeight, guestWidth, guestHeight)
                                       : OutputSize{width,height};
}
// Map endpoints, not widths: adjacent guest tiles must share precisely the
// same boundary at fractional 1.25x / 1.5x scales, including mip levels.
constexpr uint32_t ScaleEdge(uint32_t edge, uint32_t logical, uint32_t physical) {
  return logical ? uint32_t((uint64_t(std::min(edge,logical))*physical + logical/2)/logical) : 0;
}
struct ResolveSpan { uint32_t source, destination, sourceSize, destinationSize; };
constexpr ResolveSpan ScaleResolveSpan(uint32_t sourceLogical, uint32_t sourcePhysical,
    uint32_t destinationLogical, uint32_t destinationPhysical,
    uint32_t sourceStart, uint32_t destinationStart, uint32_t length) {
  if(sourceStart >= sourceLogical || destinationStart >= destinationLogical)return {};
  length = std::min(length, std::min(sourceLogical-sourceStart, destinationLogical-destinationStart));
  const auto s = ScaleEdge(sourceStart, sourceLogical, sourcePhysical);
  const auto d = ScaleEdge(destinationStart, destinationLogical, destinationPhysical);
  return {s,d,ScaleEdge(sourceStart+length,sourceLogical,sourcePhysical)-s,
              ScaleEdge(destinationStart+length,destinationLogical,destinationPhysical)-d};
}
// High descriptor bits carry gamma (31) and produced-scene texel scale (30:29).
// Material textures and unscaled shadow atlases always have zero scale bits.
constexpr uint32_t SceneTextureFlags(uint32_t width, uint32_t height,
                                      uint32_t renderHeight,
                                      uint32_t guestWidth=1280,
                                      uint32_t guestHeight=720) {
  if(width != 1280 || height != 720)return 0;
  const uint32_t aspect=(guestWidth!=1280 || guestHeight!=720) ? 0x10000000u : 0u;
  return aspect | (renderHeight == 900 ? 0x40000000u :
                   renderHeight == 1080 ? 0x20000000u : 0u);
}
struct PresentationClock {
  static constexpr double period=1.0/30.0;
  double next=0;
  uint64_t resyncs=0;
  uint32_t frameRate=30;
  double Plan(double now, uint32_t requestedRate=30) {
    const uint32_t rate=requestedRate==60 ? 60 : 30;
    if(rate!=frameRate) { next=0; frameRate=rate; }
    const double period=1.0/double(rate);
    // Keep one frame of predictable compositor lead. Normal frames retain the
    // same phase rather than following variable CPU/GPU completion times.
    if(next==0 || next<now+0.003 || next>now+period*3) {
      if(next!=0)++resyncs;
      next=now+period;
    }
    const double result=next;
    next+=period;
    return result;
  }
};
}
