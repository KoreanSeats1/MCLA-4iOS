// Actual GPU regression for the production partial-clear shaders and the
// renderer's Load + scissor + independent depth/stencil write-state contract.
#import <Metal/Metal.h>
#include "../MCLAApp/runtime/MCLAMetalHelpers.h"
#include <array>
#include <cstdio>
#include <cstdlib>

static void Require(bool ok, const char *message) {
  if (!ok) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}
static bool Inside(unsigned x, unsigned y) {
  return x >= 2 && x < 5 && y >= 1 && y < 5;
}

int main() { @autoreleasepool {
  auto device = MTLCreateSystemDefaultDevice();
  Require(device != nil, "Metal device unavailable");
  NSError *error = nil;
  auto library = [device newLibraryWithSource:kMCLAMetalHelpers options:nil error:&error];
  if (!library) std::fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
  Require(library != nil, "compile production helpers");
  auto descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
      MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
  descriptor.storageMode = MTLStorageModeShared;
  descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  auto color = [device newTextureWithDescriptor:descriptor];
  auto output = [device newTextureWithDescriptor:descriptor];
  descriptor.pixelFormat = MTLPixelFormatDepth32Float_Stencil8;
  descriptor.storageMode = MTLStorageModePrivate;
  descriptor.usage |= MTLTextureUsagePixelFormatView;
  auto depth = [device newTextureWithDescriptor:descriptor];
  auto stencil = [depth newTextureViewWithPixelFormat:MTLPixelFormatX32_Stencil8];
  Require(color && output && depth && stencil, "allocate test targets");
  auto makePipeline = [&](NSString *fragment, bool depthTarget) {
    auto pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [library newFunctionWithName:@"copyVertex"];
    pd.fragmentFunction = [library newFunctionWithName:fragment];
    if (depthTarget)
      pd.depthAttachmentPixelFormat = pd.stencilAttachmentPixelFormat = depth.pixelFormat;
    else pd.colorAttachments[0].pixelFormat = color.pixelFormat;
    auto pipeline = [device newRenderPipelineStateWithDescriptor:pd error:&error];
    if (!pipeline) std::fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
    Require(pipeline != nil, "build production helper pipeline");
    return pipeline;
  };
  auto clearColor = makePipeline(@"clearColorFragment", false);
  auto clearDepth = makePipeline(@"clearDepthFragment", true);
  auto packDepth = makePipeline(@"packDepth", false);
  auto queue = [device newCommandQueue];
  auto command = [queue commandBuffer];
  auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = color;
  rp.colorAttachments[0].loadAction = MTLLoadActionClear;
  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  rp.colorAttachments[0].clearColor = MTLClearColorMake(.2, .4, .6, .8);
  [[command renderCommandEncoderWithDescriptor:rp] endEncoding];
  rp.colorAttachments[0].loadAction = MTLLoadActionLoad;
  auto encoder = [command renderCommandEncoderWithDescriptor:rp];
  [encoder setRenderPipelineState:clearColor];
  [encoder setScissorRect:MTLScissorRect{2, 1, 3, 4}];
  const float replacement[4] = {.8f, .6f, .4f, .2f};
  [encoder setFragmentBytes:replacement length:sizeof(replacement) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [encoder endEncoding];
  [command commit]; [command waitUntilCompleted];
  Require(command.status == MTLCommandBufferStatusCompleted, "GPU color clear completed");
  std::array<uint8_t, 8 * 8 * 4> pixels{};
  [color getBytes:pixels.data() bytesPerRow:8 * 4
      fromRegion:MTLRegionMake2D(0, 0, 8, 8) mipmapLevel:0];
  for (unsigned y = 0; y < 8; ++y) for (unsigned x = 0; x < 8; ++x) {
    auto expected = Inside(x, y) ? std::array<uint8_t,4>{204,153,102,51}
                                : std::array<uint8_t,4>{51,102,153,204};
    for (unsigned c = 0; c < 4; ++c)
      Require(pixels[(y * 8 + x) * 4 + c] == expected[c],
              "color partial clear preserves all pixels outside scissor");
  }
  std::puts("PASS: color-only partial clear and surrounding RGBA preservation");

  for (unsigned flags : {16u, 32u, 48u}) {
    command = [queue commandBuffer];
    rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.depthAttachment.texture = rp.stencilAttachment.texture = depth;
    rp.depthAttachment.loadAction = rp.stencilAttachment.loadAction = MTLLoadActionClear;
    rp.depthAttachment.storeAction = rp.stencilAttachment.storeAction = MTLStoreActionStore;
    rp.depthAttachment.clearDepth = .25;
    rp.stencilAttachment.clearStencil = 0x35;
    [[command renderCommandEncoderWithDescriptor:rp] endEncoding];
    rp.depthAttachment.loadAction = rp.stencilAttachment.loadAction = MTLLoadActionLoad;
    auto state = [MTLDepthStencilDescriptor new];
    state.depthCompareFunction = MTLCompareFunctionAlways;
    state.depthWriteEnabled = (flags & 16) != 0;
    if (flags & 32) {
      auto sd = [MTLStencilDescriptor new];
      sd.stencilCompareFunction = MTLCompareFunctionAlways;
      sd.stencilFailureOperation = sd.depthFailureOperation = MTLStencilOperationKeep;
      sd.depthStencilPassOperation = MTLStencilOperationReplace;
      sd.readMask = sd.writeMask = 0xFF;
      state.frontFaceStencil = state.backFaceStencil = sd;
    }
    auto depthState = [device newDepthStencilStateWithDescriptor:state];
    Require(depthState != nil, "allocate depth/stencil write state");
    encoder = [command renderCommandEncoderWithDescriptor:rp];
    [encoder setRenderPipelineState:clearDepth];
    [encoder setDepthStencilState:depthState];
    [encoder setStencilReferenceValue:0xA6];
    [encoder setScissorRect:MTLScissorRect{2, 1, 3, 4}];
    const float replacementDepth = .75f;
    [encoder setFragmentBytes:&replacementDepth length:sizeof(replacementDepth) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    // Production depth packing provides exact byte readback of both planes.
    rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = output;
    rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    encoder = [command renderCommandEncoderWithDescriptor:rp];
    [encoder setRenderPipelineState:packDepth];
    [encoder setFragmentTexture:depth atIndex:0];
    [encoder setFragmentTexture:stencil atIndex:1];
    const uint32_t args[] = {0, 0x688, 0, 0, 0, 0, 8, 8, 8, 8};
    [encoder setFragmentBytes:args length:sizeof(args) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    [command commit]; [command waitUntilCompleted];
    Require(command.status == MTLCommandBufferStatusCompleted, "GPU depth/stencil clear completed");
    [output getBytes:pixels.data() bytesPerRow:8 * 4
        fromRegion:MTLRegionMake2D(0, 0, 8, 8) mipmapLevel:0];
    for (unsigned y = 0; y < 8; ++y) for (unsigned x = 0; x < 8; ++x) {
      uint32_t d = Inside(x,y) && (flags & 16) ? 0xBFFFFF : 0x400000;
      uint32_t s = Inside(x,y) && (flags & 32) ? 0xA6 : 0x35;
      uint32_t expected = (d << 8) | s;
      for (unsigned c = 0; c < 4; ++c) {
        if (pixels[(y * 8 + x) * 4 + c] != uint8_t(expected >> (c * 8))) {
          std::fprintf(stderr, "flags=%u x=%u y=%u channel=%u got=%u expected=%u\n",
              flags,x,y,c,pixels[(y*8+x)*4+c],uint8_t(expected>>(c*8)));
          Require(false, "independent depth/stencil planes and scissor preservation");
        }
      }
    }
    std::printf("PASS: flags=%u partial clear, retained plane and surrounding depth/stencil\n", flags);
  }
} }
