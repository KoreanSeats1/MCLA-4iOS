#pragma once
#include <cstdint>
#include <memory>
namespace rex::system { class IGraphicsSystem; }
namespace rex::graphics::gta4_native { struct SurfaceDescriptor; }
std::unique_ptr<rex::system::IGraphicsSystem> MCLACreateNativeRenderer();
const uint8_t* MCLANativeCanonicalDevice(const uint8_t* device,
    const uint64_t* vertexConstants = nullptr, const uint64_t* pixelConstants = nullptr,
    bool compactDraw = false);
uint64_t MCLANativeSurfaceRevision();
struct MCLANativeFrameTiming {
  double drawMilliseconds, previousPacingMilliseconds;
};
MCLANativeFrameTiming MCLANativeTakeFrameTiming();
void MCLANativeCanonicalSurface(rex::graphics::gta4_native::SurfaceDescriptor& surface);
void MCLANativeBeginTiling(const uint8_t* base, uint32_t device,
                          uint32_t count, uint32_t rectangles);
// Returns true only when missing shader microcode needs diagnostic capture.
bool MCLANativeDraw(const uint8_t* base, uint32_t device, uint32_t primitive,
                    uint32_t count, uint32_t start, int32_t baseVertex,
                    bool indexed, uint32_t stride, uint32_t data,
                    uint64_t vs, uint64_t ps);
void MCLANativeClear(uint8_t* base, uint32_t device, uint32_t rectangleCount,
                     uint32_t rectangles, uint32_t flags,
                     uint32_t color, float depth, uint32_t stencil);
bool MCLANativeResolve(uint8_t* base, uint32_t device, uint32_t flags,
                       uint32_t rect, uint32_t texture, uint32_t point,
                       uint32_t level, uint32_t slice, uint32_t color,
                       double depth, uint32_t stencil, uint32_t parameters);
bool MCLANativeResolveStackArguments(const uint8_t* base, uint32_t stack,
                                     uint32_t* stencil, uint32_t* parameters);
bool MCLANativePresent(uint8_t* base, uint32_t device, uint32_t texture);
void MCLANativeResourceUnlock(uint8_t* base, uint32_t resource, uint32_t mipAddress,
                              uint32_t caller);
void MCLANativeResourceRelease(uint32_t resource);
