// Real Metal pixel-center regression. A pixel-aligned fullscreen pass must
// copy a one-texel checkerboard exactly, including its last row and column.
// A D3DZero pass shifts +0.5 screen pixels using VIEWPORT dimensions.
#import <Metal/Metal.h>
#include "../MCLAApp/runtime/MCLAMetalPixelCenter.h"
#include <array>
#include <cstdio>
#include <cstdlib>
#include <limits>

static void Require(bool ok, const char *message) {
  if (!ok) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}

int main() { @autoreleasepool {
  using mcla::metal::HalfPixelOffset;
  Require(HalfPixelOffset(4, 8, 4) == std::array<float,2>{.125f,-.25f},
          "D3DZero offset uses viewport width and height independently");
  Require(HalfPixelOffset(5, 8, 4) == std::array<float,2>{0,0},
          "OGLHalf screen-space pass has no additional offset");
  for (float invalid : {0.f, -1.f, std::numeric_limits<float>::infinity(),
                        std::numeric_limits<float>::quiet_NaN()}) {
    Require(HalfPixelOffset(4, invalid, 8) == std::array<float,2>{0,0},
            "invalid viewport width is inert");
    Require(HalfPixelOffset(4, 8, invalid) == std::array<float,2>{0,0},
            "invalid viewport height is inert");
  }
  auto device = MTLCreateSystemDefaultDevice();
  Require(device != nil, "Metal device unavailable");
  NSString *source = @R"METAL(
#include <metal_stdlib>
using namespace metal;
struct Output { float4 position [[position]]; float2 uv; };
vertex Output vertexMain(uint i [[vertex_id]],
                         constant float2& halfPixel [[buffer(0)]]) {
  float2 p = float2((i << 1) & 2, i & 2);
  Output result{float4(p * 2 - 1, 0, 1), float2(p.x, 1-p.y)};
  // Identical offset contract to the translated title vertex shaders.
  result.position.xy += halfPixel * result.position.w;
  return result;
}
fragment float4 fragmentMain(Output i [[stage_in]],
                             texture2d<float> source [[texture(0)]]) {
  constexpr sampler s(coord::normalized, filter::linear,
                      address::clamp_to_edge);
  return source.sample(s, i.uv);
}
)METAL";
  NSError *error = nil;
  auto library = [device newLibraryWithSource:source options:nil error:&error];
  if (!library) std::fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
  Require(library != nil, "compile checkerboard test shaders");
  auto descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
      MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
  descriptor.storageMode = MTLStorageModeShared;
  descriptor.usage = MTLTextureUsageShaderRead;
  auto checkerboard = [device newTextureWithDescriptor:descriptor];
  std::array<uint8_t,8*8*4> pixels{};
  for (unsigned y=0;y<8;++y) for(unsigned x=0;x<8;++x) {
    auto* pixel=pixels.data()+(y*8+x)*4;
    pixel[0]=pixel[1]=pixel[2]=((x+y)&1u)?255:0;
    pixel[3]=255;
  }
  [checkerboard replaceRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0
                   withBytes:pixels.data() bytesPerRow:8*4];
  // Deliberately larger than the viewport, so 1/target dimensions fails.
  descriptor.width=descriptor.height=16;
  descriptor.usage=MTLTextureUsageRenderTarget;
  auto target=[device newTextureWithDescriptor:descriptor];
  auto pipelineDescriptor=[MTLRenderPipelineDescriptor new];
  pipelineDescriptor.vertexFunction=[library newFunctionWithName:@"vertexMain"];
  pipelineDescriptor.fragmentFunction=[library newFunctionWithName:@"fragmentMain"];
  pipelineDescriptor.colorAttachments[0].pixelFormat=target.pixelFormat;
  auto pipeline=[device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
  Require(checkerboard && target && pipeline, "allocate test GPU resources");
  auto queue=[device newCommandQueue];
  for (uint32_t vertexControl : {5u,4u}) {
    auto command=[queue commandBuffer];
    auto pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=target;
    pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    pass.colorAttachments[0].clearColor=MTLClearColorMake(.2,.4,.6,.8);
    auto encoder=[command renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:pipeline];
    auto offset=HalfPixelOffset(vertexControl,8,8);
    [encoder setVertexBytes:offset.data() length:sizeof(offset) atIndex:0];
    [encoder setFragmentTexture:checkerboard atIndex:0];
    [encoder setViewport:MTLViewport{2,3,8,8,0,1}];
    [encoder setScissorRect:MTLScissorRect{2,3,8,8}];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    [command commit]; [command waitUntilCompleted];
    Require(command.status==MTLCommandBufferStatusCompleted,"complete GPU work");
    std::array<uint8_t,16*16*4> result{};
    [target getBytes:result.data() bytesPerRow:16*4
         fromRegion:MTLRegionMake2D(0,0,16,16) mipmapLevel:0];
    for(unsigned y=0;y<16;++y) for(unsigned x=0;x<16;++x) {
      const auto* pixel=result.data()+(y*16+x)*4;
      if(x<2 || x>=10 || y<3 || y>=11) {
        Require(pixel[0]==51 && pixel[1]==102 && pixel[2]==153 && pixel[3]==204,
                "viewport neighbors preserve clear sentinel");
      } else if (vertexControl&1u) {
        const uint8_t expected=((x-2+y-3)&1u)?255:0;
        Require(pixel[0]==expected && pixel[1]==expected &&
                pixel[2]==expected && pixel[3]==255,
                "OGLHalf checkerboard copy is texel-exact including border");
      } else if(x>2 && y>3) {
        // +0.5 pixels puts each interior sample between four checker texels.
        Require(pixel[0]>=127 && pixel[0]<=128 && pixel[1]==pixel[0] &&
                pixel[2]==pixel[0] && pixel[3]==255,
                "D3DZero shifts exactly half a viewport pixel in both axes");
      }
    }
  }
  std::puts("PASS: Metal conditional pixel-center offset, texel-exact fullscreen checkerboard, viewport dimensions, and neighbor preservation");
} }
