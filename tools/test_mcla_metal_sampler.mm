// Host Metal regression for the production MCLA sampler address translation.
#include "../MCLAApp/runtime/MCLAMetalSampler.h"
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>

static void Require(bool ok, const char *message) {
  if (!ok) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}

int main() { @autoreleasepool {
  using namespace mcla::metal;
  Require(SamplerCacheFields(0, 0, 0, 0, 0) !=
          SamplerCacheFields(0, 0, 0, 1, 0), "border color participates in key");
  Require(SamplerCacheFields(0, 0, 0, 1, 0) ==
          SamplerCacheFields(0, 0, 0, 0xABCDEF01, 0),
          "texture mip address does not participate in sampler key");
  auto descriptor = [MTLSamplerDescriptor new];
  Require(ApplySamplerAddressing(descriptor, 0, 1, 3, 0), "exact supported modes");
  Require(descriptor.sAddressMode == MTLSamplerAddressModeRepeat &&
          descriptor.tAddressMode == MTLSamplerAddressModeMirrorRepeat &&
          descriptor.rAddressMode == MTLSamplerAddressModeMirrorClampToEdge,
          "repeat and mirror modes are distinct");
  for (unsigned mode : {4u, 5u, 7u})
    Require(!ApplySamplerAddressing(descriptor, mode, 2, 2, 0),
            "unsupported halfway/mirror-border reported as approximate");
  Require(!ApplySamplerAddressing(descriptor, 6, 2, 2, 2),
          "unsupported custom chroma border reported as approximate");
  auto device = MTLCreateSystemDefaultDevice();
  Require(device != nil, "Metal device unavailable");
  NSError *error = nil;
  auto library = [device newLibraryWithSource:@R"METAL(
    #include <metal_stdlib>
    using namespace metal;
    kernel void sample_test(texture2d<float> image [[texture(0)]],
        sampler samp [[sampler(0)]], device float4 *out [[buffer(0)]],
        uint index [[thread_position_in_grid]]) {
      const float2 coords[] = {float2(-0.375, 0.5), float2(1.1, 0.5),
        float2(0.5, -0.1), float2(0.5, 1.1), float2(0.375, 0.5)};
      out[index] = image.sample(samp, coords[index], level(0.0));
    }
  )METAL" options:nil error:&error];
  if (!library) std::fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
  Require(library != nil, "compile sampler regression shader");
  auto pipeline = [device newComputePipelineStateWithFunction:
      [library newFunctionWithName:@"sample_test"] error:&error];
  Require(pipeline != nil, "compile sampler regression pipeline");
  auto td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
      MTLPixelFormatRGBA32Float width:4 height:1 mipmapped:NO];
  td.storageMode = MTLStorageModeShared;
  auto texture = [device newTextureWithDescriptor:td];
  const float texels[] = {.2,.2,.2,.2, .4,.4,.4,.4, .6,.6,.6,.6, .8,.8,.8,.8};
  [texture replaceRegion:MTLRegionMake2D(0, 0, 4, 1) mipmapLevel:0
      withBytes:texels bytesPerRow:sizeof(texels)];
  auto output = [device newBufferWithLength:5 * 4 * sizeof(float)
      options:MTLResourceStorageModeShared];
  auto queue = [device newCommandQueue];
  auto run = [&](unsigned clamp, unsigned border, const std::array<float, 5>& expected) {
    Require(ApplySamplerAddressing(descriptor, clamp, clamp, 2, border),
            "test exercises exact sampler address mode");
    descriptor.minFilter = descriptor.magFilter = MTLSamplerMinMagFilterNearest;
    descriptor.mipFilter = MTLSamplerMipFilterNotMipmapped;
    auto sampler = [device newSamplerStateWithDescriptor:descriptor];
    Require(sampler != nil, "allocate sampler");
    auto command = [queue commandBuffer];
    auto encoder = [command computeCommandEncoder];
    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:texture atIndex:0];
    [encoder setSamplerState:sampler atIndex:0];
    [encoder setBuffer:output offset:0 atIndex:0];
    [encoder dispatchThreads:MTLSizeMake(5, 1, 1)
        threadsPerThreadgroup:MTLSizeMake(5, 1, 1)];
    [encoder endEncoding];
    [command commit]; [command waitUntilCompleted];
    Require(command.status == MTLCommandBufferStatusCompleted, "complete GPU samples");
    auto result = static_cast<const float *>(output.contents);
    for (unsigned i = 0; i < 5; ++i) for (unsigned c = 0; c < 4; ++c) {
      if (std::abs(result[i * 4 + c] - expected[i]) > 0.00001f) {
        std::fprintf(stderr, "mode=%u border=%u sample=%u channel=%u got=%g expected=%g\n",
            clamp, border, i, c, result[i * 4 + c], expected[i]);
        Require(false, "sampled border, edge and interior values");
      }
    }
  };
  run(6, 1, {1.f, 1.f, 1.f, 1.f, .4f});
  run(6, 0, {0.f, 0.f, 0.f, 0.f, .4f});
  run(2, 1, {.2f, .8f, .6f, .6f, .4f});
  // Mirror-once at negative coordinates differs from clamping to the edge.
  run(3, 0, {.4f, .8f, .6f, .6f, .4f});
  std::puts("PASS: MCLA Metal sampler key, supported modes, and GPU border samples");
} }
