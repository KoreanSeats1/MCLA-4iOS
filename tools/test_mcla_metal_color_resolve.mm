// Real Metal regression for CopyColor's region/mip/slice contract. Compile:
// xcrun clang++ -std=c++20 -fobjc-arc tools/test_mcla_metal_color_resolve.mm \
//   -framework Foundation -framework Metal -o /tmp/mcla-metal-color-resolve-test
//
// Uses the production shaders and mirrors CopyColor's command encoding because
// the renderer is private and depends on the running guest. This tests mapping
// and preservation, not guest descriptor lifetime or uninitialized mip content.
#import <Metal/Metal.h>
#include "../MCLAApp/runtime/MCLAMetalHelpers.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

static void Require(bool ok, const char *message) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}

struct Region {
  unsigned sx, sy, width, height, dx, dy, level, slice;
  float scale;
};

// Exact binary input values plus independent x/y ramps reveal checker blending,
// vertical inversion, swapped components, or even a half-texel coordinate shift.
static std::array<float, 4> SourcePixel(unsigned x, unsigned y) {
  return {float((x + y) & 1), float(x) / 8.f, float(y) / 8.f,
          (x & 1) ? .75f : .25f};
}

static void EncodeColorCopy(id<MTLCommandBuffer> command,
                            id<MTLRenderPipelineState> pipeline,
                            id<MTLTexture> source, id<MTLTexture> destination,
                            const Region &r) {
  const NSUInteger destinationWidth =
      std::max<NSUInteger>(1, destination.width >> r.level);
  const NSUInteger destinationHeight =
      std::max<NSUInteger>(1, destination.height >> r.level);
  const NSUInteger outputWidth =
      std::min<NSUInteger>(r.width, destinationWidth - r.dx);
  const NSUInteger outputHeight =
      std::min<NSUInteger>(r.height, destinationHeight - r.dy);
  auto pass = [MTLRenderPassDescriptor renderPassDescriptor];
  auto color = pass.colorAttachments[0];
  color.texture = destination;
  color.level = r.level;
  color.slice = r.slice;
  const bool fullDestination = r.dx == 0 && r.dy == 0 &&
      outputWidth == destinationWidth && outputHeight == destinationHeight;
  color.loadAction = fullDestination ? MTLLoadActionDontCare : MTLLoadActionLoad;
  color.storeAction = MTLStoreActionStore;
  auto encoder = [command renderCommandEncoderWithDescriptor:pass];
  Require(encoder != nil, "create copy encoder");
  [encoder setRenderPipelineState:pipeline];
  [encoder setFragmentTexture:source atIndex:0];
  const float parameters[8] = {
      r.scale, float(r.sx) / source.width, float(r.sy) / source.height, 0.f,
      float(r.width) / source.width, float(r.height) / source.height, 0.f, 0.f};
  [encoder setFragmentBytes:parameters length:sizeof(parameters) atIndex:0];
  [encoder setViewport:MTLViewport{double(r.dx), double(r.dy),
                                 double(outputWidth), double(outputHeight), 0, 1}];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [encoder endEncoding];
}

int main() { @autoreleasepool {
  auto device = MTLCreateSystemDefaultDevice();
  Require(device != nil, "Metal device unavailable");
  NSError *error = nil;
  auto library = [device newLibraryWithSource:kMCLAMetalHelpers options:nil
                                      error:&error];
  if (!library) std::fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
  Require(library != nil, "compile production Metal helpers");

  auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
      MTLPixelFormatRGBA16Float width:8 height:8 mipmapped:NO];
  desc.storageMode = MTLStorageModeShared;
  desc.usage = MTLTextureUsageShaderRead;
  auto source = [device newTextureWithDescriptor:desc];
  std::array<__fp16, 8 * 8 * 4> sourceBytes{};
  for (unsigned y = 0; y < 8; ++y) for (unsigned x = 0; x < 8; ++x) {
    auto color = SourcePixel(x, y);
    for (unsigned c = 0; c < 4; ++c)
      sourceBytes[(y * 8 + x) * 4 + c] = color[c];
  }
  [source replaceRegion:MTLRegionMake2D(0, 0, 8, 8) mipmapLevel:0
              withBytes:sourceBytes.data() bytesPerRow:8 * 4 * sizeof(__fp16)];

  desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
      MTLPixelFormatRGBA8Unorm width:16 height:16 mipmapped:YES];
  desc.storageMode = MTLStorageModeShared;
  desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  desc.textureType = MTLTextureType2DArray;
  desc.arrayLength = 3;
  desc.mipmapLevelCount = 3;
  auto destination = [device newTextureWithDescriptor:desc];
  Require(source && destination, "allocate source and destination");

  const std::array<uint8_t, 4> sentinel{17, 39, 73, 211};
  std::vector<std::vector<uint8_t>> expected(3 * 3);
  for (unsigned slice = 0; slice < 3; ++slice) {
    for (unsigned level = 0; level < 3; ++level) {
      const unsigned size = 16 >> level;
      auto &pixels = expected[slice * 3 + level];
      pixels.resize(size * size * 4);
      for (unsigned p = 0; p < size * size; ++p)
        std::copy(sentinel.begin(), sentinel.end(), pixels.begin() + p * 4);
      [destination replaceRegion:MTLRegionMake2D(0, 0, size, size)
                     mipmapLevel:level slice:slice withBytes:pixels.data()
                     bytesPerRow:size * 4 bytesPerImage:size * size * 4];
    }
  }

  auto pipelineDescriptor = [MTLRenderPipelineDescriptor new];
  pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"copyVertex"];
  pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"copyFragment"];
  pipelineDescriptor.colorAttachments[0].pixelFormat = destination.pixelFormat;
  auto pipeline = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                                       error:&error];
  if (!pipeline) std::fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
  Require(pipeline != nil, "create color conversion pipeline");
  auto queue = [device newCommandQueue];
  Require(queue != nil, "create command queue");

  const std::array<Region, 4> cases{{
      {2, 1, 4, 3, 1, 3, 1, 2, 1.f}, // nonzero origins, mip, and array slice
      {5, 6, 1, 1, 3, 0, 2, 1, 1.f}, // exact single texel with no interpolation
      {0, 0, 8, 8, 0, 0, 1, 0, 1.f}, // full destination DontCare branch
      {3, 4, 2, 2, 5, 1, 1, 1, .5f}, // exponent-like scaling plus partial write
  }};
  for (unsigned test = 0; test < cases.size(); ++test) {
    const auto &r = cases[test];
    auto command = [queue commandBuffer];
    EncodeColorCopy(command, pipeline, source, destination, r);
    [command commit];
    [command waitUntilCompleted];
    if (command.error)
      std::fprintf(stderr, "%s\n", command.error.localizedDescription.UTF8String);
    Require(command.status == MTLCommandBufferStatusCompleted, "complete GPU copy");
    const unsigned dstWidth = 16 >> r.level;
    auto &updated = expected[r.slice * 3 + r.level];
    for (unsigned y = 0; y < r.height; ++y) for (unsigned x = 0; x < r.width; ++x) {
      auto color = SourcePixel(r.sx + x, r.sy + y);
      for (unsigned c = 0; c < 4; ++c)
        updated[((r.dy + y) * dstWidth + r.dx + x) * 4 + c] =
            uint8_t(std::lround(std::clamp(color[c] * r.scale, 0.f, 1.f) * 255.f));
    }
    // Verify *all* levels/slices after every write, including earlier writes.
    for (unsigned slice = 0; slice < 3; ++slice) {
      for (unsigned level = 0; level < 3; ++level) {
        const unsigned size = 16 >> level;
        std::vector<uint8_t> actual(size * size * 4);
        [destination getBytes:actual.data() bytesPerRow:size * 4
                bytesPerImage:size * size * 4
                   fromRegion:MTLRegionMake2D(0, 0, size, size)
                  mipmapLevel:level slice:slice];
        const auto &wanted = expected[slice * 3 + level];
        for (unsigned p = 0; p < size * size; ++p) for (unsigned c = 0; c < 4; ++c) {
          // UNORM midpoint rounding can differ by one LSB across GPU families.
          // Checker RGB endpoints remain exact and expose subpixel blending.
          const int tolerance = wanted[p * 4 + c] == 0 ||
                                wanted[p * 4 + c] == 255 ? 0 : 1;
          if (std::abs(int(actual[p * 4 + c]) - wanted[p * 4 + c]) > tolerance) {
            std::fprintf(stderr,
                "test=%u slice=%u mip=%u x=%u y=%u channel=%u got=%u expected=%u\n",
                test, slice, level, p % size, p / size, c,
                actual[p * 4 + c], wanted[p * 4 + c]);
            Require(false, "color region mapping, conversion, or preservation");
          }
        }
      }
    }
  }
  std::puts("PASS: Metal color resolve RGBA16F->RGBA8, checker/single-pixel UVs, source/destination offsets, mip/slice isolation, exponent scaling, and neighbor preservation");
} }
