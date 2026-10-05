// Real Metal regression: partial packed-depth writes with different source and
// destination origins must preserve neighboring pixels and other mip levels.
#import <Metal/Metal.h>
#include "../MCLAApp/runtime/MCLAMetalHelpers.h"
#include <array>
#include <cstdio>
#include <cstdlib>

static void Require(bool ok, const char *message) {
  if (!ok) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}
int main() { @autoreleasepool {
  auto device = MTLCreateSystemDefaultDevice();
  Require(device != nil, "Metal device unavailable");
  NSError *error = nil;
  auto lib = [device newLibraryWithSource:kMCLAMetalHelpers options:nil error:&error];
  if (!lib) std::fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
  Require(lib != nil, "compile production Metal helpers");
  auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
      MTLPixelFormatDepth32Float_Stencil8 width:8 height:8 mipmapped:NO];
  desc.storageMode = MTLStorageModePrivate;
  desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead |
               MTLTextureUsagePixelFormatView;
  auto depth = [device newTextureWithDescriptor:desc];
  auto stencil = [depth newTextureViewWithPixelFormat:MTLPixelFormatX32_Stencil8];
  desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
      MTLPixelFormatRGBA8Unorm width:16 height:16 mipmapped:YES];
  desc.storageMode = MTLStorageModeShared;
  desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  auto output = [device newTextureWithDescriptor:desc];
  Require(depth && stencil && output, "allocate test textures");
  auto queue = [device newCommandQueue];
  auto command = [queue commandBuffer];
  auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.depthAttachment.texture = depth;
  rp.depthAttachment.loadAction = MTLLoadActionClear;
  rp.depthAttachment.storeAction = MTLStoreActionStore;
  rp.depthAttachment.clearDepth = 0.0;
  rp.stencilAttachment.texture = depth;
  rp.stencilAttachment.loadAction = MTLLoadActionClear;
  rp.stencilAttachment.storeAction = MTLStoreActionStore;
  rp.stencilAttachment.clearStencil = 0x35;
  [[command renderCommandEncoderWithDescriptor:rp] endEncoding];
  // Only the right half has depth=1. Source offset errors move this boundary.
  rp.depthAttachment.loadAction = rp.stencilAttachment.loadAction = MTLLoadActionLoad;
  auto pd = [MTLRenderPipelineDescriptor new];
  pd.vertexFunction = [lib newFunctionWithName:@"copyVertex"];
  pd.fragmentFunction = [lib newFunctionWithName:@"clearDepthFragment"];
  pd.depthAttachmentPixelFormat = pd.stencilAttachmentPixelFormat = depth.pixelFormat;
  auto clearPipeline = [device newRenderPipelineStateWithDescriptor:pd error:&error];
  auto ds = [MTLDepthStencilDescriptor new];
  ds.depthCompareFunction = MTLCompareFunctionAlways;
  ds.depthWriteEnabled = YES;
  auto encoder = [command renderCommandEncoderWithDescriptor:rp];
  [encoder setRenderPipelineState:clearPipeline];
  [encoder setDepthStencilState:[device newDepthStencilStateWithDescriptor:ds]];
  [encoder setScissorRect:MTLScissorRect{4, 0, 4, 8}];
  float one = 1.f;
  [encoder setFragmentBytes:&one length:sizeof(one) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [encoder endEncoding];
  // Sentinel bytes across both mip levels let us detect collateral writes.
  for (unsigned level = 0; level < 2; ++level) {
    rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = output;
    rp.colorAttachments[0].level = level;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(.2, .4, .6, .8);
    [[command renderCommandEncoderWithDescriptor:rp] endEncoding];
  }
  pd = [MTLRenderPipelineDescriptor new];
  pd.vertexFunction = [lib newFunctionWithName:@"copyVertex"];
  pd.fragmentFunction = [lib newFunctionWithName:@"packDepth"];
  pd.colorAttachments[0].pixelFormat = output.pixelFormat;
  auto pipeline = [device newRenderPipelineStateWithDescriptor:pd error:&error];
  Require(pipeline != nil, "create packed-depth pipeline");
  // Resolve source (3,1)-(7,4) to mip 1, destination (2,3)-(6,6).
  rp.colorAttachments[0].loadAction = MTLLoadActionLoad;
  encoder = [command renderCommandEncoderWithDescriptor:rp];
  [encoder setRenderPipelineState:pipeline];
  [encoder setFragmentTexture:depth atIndex:0];
  [encoder setFragmentTexture:stencil atIndex:1];
  const uint32_t args[] = {0, 0x688, 3, 1, 2, 3, 4, 3, 4, 3};
  [encoder setFragmentBytes:args length:sizeof(args) atIndex:0];
  [encoder setViewport:MTLViewport{2, 3, 4, 3, 0, 1}];
  [encoder setScissorRect:MTLScissorRect{2, 3, 4, 3}];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [encoder endEncoding];
  [command commit]; [command waitUntilCompleted];
  Require(command.status == MTLCommandBufferStatusCompleted, "complete GPU work");
  for (unsigned level = 0; level < 2; ++level) {
    unsigned size = 16 >> level;
    std::array<uint8_t, 16 * 16 * 4> pixels{};
    [output getBytes:pixels.data() bytesPerRow:size * 4
              fromRegion:MTLRegionMake2D(0, 0, size, size) mipmapLevel:level];
    for (unsigned y = 0; y < size; ++y) for (unsigned x = 0; x < size; ++x) {
      std::array<uint8_t, 4> expected{51, 102, 153, 204};
      if (level == 1 && x >= 2 && x < 6 && y >= 3 && y < 6)
        expected = x == 2 ? std::array<uint8_t,4>{0x35,0,0,0}
                          : std::array<uint8_t,4>{0x35,255,255,255};
      for (unsigned c = 0; c < 4; ++c) {
        if (pixels[(y * size + x) * 4 + c] != expected[c]) {
          std::fprintf(stderr, "mip=%u x=%u y=%u channel=%u got=%u expected=%u\n",
              level,x,y,c,pixels[(y*size+x)*4+c],expected[c]);
          Require(false, "packed depth region, channels, and preservation");
        }
      }
    }
  }
  std::puts("PASS: Metal packed-depth source offset, destination offset, stencil bytes, mip isolation, and neighbor preservation");
  // Upscaled scene storage may resolve into an unscaled target or odd mip.
  // Exercise the production nearest-depth coordinate mapping at 2x in both
  // axes; the first two destination columns must read source column three.
  command = [queue commandBuffer];
  rp.colorAttachments[0].loadAction = MTLLoadActionClear;
  rp.colorAttachments[0].clearColor = MTLClearColorMake(.2,.4,.6,.8);
  encoder = [command renderCommandEncoderWithDescriptor:rp];
  [encoder setRenderPipelineState:pipeline];
  [encoder setFragmentTexture:depth atIndex:0];
  [encoder setFragmentTexture:stencil atIndex:1];
  const uint32_t scaledArgs[] = {0,0x688,3,1,0,0,4,3,8,6};
  [encoder setFragmentBytes:scaledArgs length:sizeof(scaledArgs) atIndex:0];
  [encoder setViewport:MTLViewport{0,0,8,6,0,1}];
  [encoder setScissorRect:MTLScissorRect{0,0,8,6}];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [encoder endEncoding];[command commit];[command waitUntilCompleted];
  Require(command.status==MTLCommandBufferStatusCompleted,"scaled packed-depth GPU work");
  std::array<uint8_t,8*8*4> scaled{};
  [output getBytes:scaled.data() bytesPerRow:8*4
       fromRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:1];
  for(unsigned y=0;y<8;++y)for(unsigned x=0;x<8;++x) {
    const auto expected=y>=6 ? std::array<uint8_t,4>{51,102,153,204} :
        x<2 ? std::array<uint8_t,4>{0x35,0,0,0} : std::array<uint8_t,4>{0x35,255,255,255};
    for(unsigned c=0;c<4;++c)Require(scaled[(y*8+x)*4+c]==expected[c],
        "scaled packed depth and stencil preserve source footprint and neighbors");
  }
  std::puts("PASS: scaled packed-depth region with independently sized source/destination");
} }
