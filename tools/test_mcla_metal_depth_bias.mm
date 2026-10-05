// Validate the host D32F bias units used by the guest raster-state helper.
#import <Metal/Metal.h>
#include "../MCLAApp/runtime/MCLAMetalRasterState.h"
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <initializer_list>

static void Require(bool value, const char* reason) {
  if (!value) { std::fprintf(stderr, "FAIL: %s\n", reason); std::exit(1); }
}
int main() { @autoreleasepool {
  auto device = MTLCreateSystemDefaultDevice();
  Require(device != nil, "Metal device unavailable");
  NSError* error = nil;
  auto lib = [device newLibraryWithSource:@R"METAL(
#include <metal_stdlib>
using namespace metal;
vertex float4 biasVertex(uint vid [[vertex_id]], constant float& z [[buffer(0)]]) {
  float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
  return float4(p[vid], z, 1);
}
)METAL" options:nil error:&error];
  if (!lib) std::fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
  Require(lib != nil, "compile depth bias shader");
  auto td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
      MTLPixelFormatDepth32Float_Stencil8 width:8 height:8 mipmapped:NO];
  td.storageMode = MTLStorageModePrivate;
  td.usage = MTLTextureUsageRenderTarget;
  auto depth = [device newTextureWithDescriptor:td];
  auto pd = [MTLRenderPipelineDescriptor new];
  pd.vertexFunction = [lib newFunctionWithName:@"biasVertex"];
  pd.depthAttachmentPixelFormat = depth.pixelFormat;
  auto pipeline = [device newRenderPipelineStateWithDescriptor:pd error:&error];
  Require(pipeline != nil, "create depth bias pipeline");
  auto dd = [MTLDepthStencilDescriptor new];
  dd.depthWriteEnabled = YES;
  dd.depthCompareFunction = MTLCompareFunctionAlways;
  auto ds = [device newDepthStencilStateWithDescriptor:dd];
  auto queue = [device newCommandQueue];
  auto bytes = [device newBufferWithLength:256*8 options:MTLResourceStorageModeShared];
  auto measure = [&](float z, float bias) {
    auto cmd = [queue commandBuffer];
    auto rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.depthAttachment.texture = depth;
    rp.depthAttachment.clearDepth = 1;
    rp.depthAttachment.loadAction = MTLLoadActionClear;
    rp.depthAttachment.storeAction = MTLStoreActionStore;
    auto enc = [cmd renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:pipeline];
    [enc setDepthStencilState:ds];
    [enc setVertexBytes:&z length:sizeof(z) atIndex:0];
    [enc setDepthBias:bias slopeScale:0 clamp:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [enc endEncoding];
    auto copy = [cmd blitCommandEncoder];
    [copy copyFromTexture:depth sourceSlice:0 sourceLevel:0
             sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(8,8,1)
                 toBuffer:bytes destinationOffset:0 destinationBytesPerRow:256
     destinationBytesPerImage:256*8 options:MTLBlitOptionDepthFromDepthStencil];
    [copy endEncoding];
    [cmd commit]; [cmd waitUntilCompleted];
    Require(cmd.status == MTLCommandBufferStatusCompleted, "complete depth bias draw");
    float result;
    std::memcpy(&result, (char*)bytes.contents + 4*256 + 4*sizeof(float), sizeof(result));
    return result;
  };
  const auto b = mcla::metal::GuestRasterDepthBias(1u << 11, 0, true,
      0, 1.f/float((1u<<24)-1u), 0, 0);
  Require(b.constant == 1.f, "one guest D24 quantum maps to host unit one");
  for (float z : {.75f, .00025f}) {
    float plain = measure(z, 0);
    float positive = measure(z, b.constant);
    float negative = measure(z, -b.constant);
    float next = std::nextafter(plain, 1.f);
    std::printf("z=%.9g +bias=%.9g delta=%.9g float_ulp=%.9g\n",
        plain, positive, positive-plain, next-plain);
    Require(plain == z, "unbiased flat triangle depth");
    Require(positive == next, "Metal bias one is one float depth ULP");
    Require(negative == std::nextafter(plain, 0.f), "negative host depth bias sign");
  }
  std::puts("PASS: D32F Metal constant bias is a depth-relative ULP, not a normalized offset");
} }
