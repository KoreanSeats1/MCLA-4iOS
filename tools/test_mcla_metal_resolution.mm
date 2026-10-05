// Host GPU regression for the production scene-size / resolve policy. Does not
// launch MCLA, an emulator, or any app on the user's iPad.
#import <Metal/Metal.h>
#include "../MCLAApp/runtime/MCLAMetalHelpers.h"
#include "../MCLAApp/runtime/MCLAMetalPresentation.h"
#include "../MCLAApp/runtime/MCLAMetalPixelCenter.h"
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

static void Require(bool ok, const char* message) {
  if (!ok) { std::fprintf(stderr,"FAIL: %s\n",message); std::exit(1); }
}
int main() { @autoreleasepool {
  using namespace mcla::metal;
  auto device=MTLCreateSystemDefaultDevice();
  Require(device!=nil,"Metal device available");
  NSError* error=nil;
  // Read the exact emitted shader helper, not a separate test implementation.
  NSString* emitted=[NSString stringWithContentsOfFile:
      @"artifacts/mcla-metal-shaders/ps-1828537C26EB239A.metal"
      encoding:NSUTF8StringEncoding error:&error];
  Require(emitted!=nil,"generated production shader available");
  auto start=[emitted rangeOfString:@"uint mclaTextureIndex("];
  auto end=[emitted rangeOfString:@"float3 mclaPWLGammaToLinear("];
  Require(start.location!=NSNotFound && end.location>start.location,"production scale helpers found");
  NSString* source=[kMCLAMetalHelpers stringByAppendingString:
      [emitted substringWithRange:NSMakeRange(start.location,end.location-start.location)]];
  source=[source stringByAppendingString:@R"METAL(
kernel void descriptorProbe(texture2d<float> tex [[texture(0)]],
                            constant uint& descriptor [[buffer(0)]],
                            device uint4* output [[buffer(1)]]) {
  uint2 dims=mclaLogicalTexture2DDimensions(tex,descriptor);
  output[0]=uint4(mclaTextureIndex(descriptor),dims,descriptor>>31);
}
fragment float4 rasterProbe(CopyOut i [[stage_in]], constant float2& scale [[buffer(0)]]) {
  // Every physical pixel is independently shaded, with guest-coordinate ABI
  // exported as B. Adjacent native pixels must not become duplicated texels.
  uint2 pixel=uint2(i.position.xy);
  float2 guest=(i.position.xy-.5f)*scale+.5f;
  return float4(float(pixel.x&1u),float(pixel.y&1u),guest.x/1280.f,1);
}
)METAL"];
  auto lib=[device newLibraryWithSource:source options:nil error:&error];
  if(!lib)std::fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);
  Require(lib!=nil,"compile production helpers and GPU probes");
  auto makePipeline=[&](NSString* fragment){
    auto pd=[MTLRenderPipelineDescriptor new];
    pd.vertexFunction=[lib newFunctionWithName:@"copyVertex"];
    pd.fragmentFunction=[lib newFunctionWithName:fragment];
    pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
    auto p=[device newRenderPipelineStateWithDescriptor:pd error:&error];
    Require(p!=nil,"render pipeline creation"); return p;
  };
  auto raster=makePipeline(@"rasterProbe"), copy=makePipeline(@"copyFragment");
  auto compute=[device newComputePipelineStateWithFunction:
      [lib newFunctionWithName:@"descriptorProbe"] error:&error];
  Require(compute!=nil,"descriptor pipeline creation");
  auto result=[device newBufferWithLength:16 options:MTLResourceStorageModeShared];
  auto queue=[device newCommandQueue];
  for(unsigned height : {720u,900u,1080u}) {
    auto size=SceneExtent(1280,720,height);
    auto td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
        width:size.width height:size.height mipmapped:NO];
    td.storageMode=MTLStorageModeShared;
    td.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
    auto scene=[device newTextureWithDescriptor:td];
    auto resolved=[device newTextureWithDescriptor:td];
    Require(scene && resolved,"physical scene allocation");
    for(unsigned gamma : {0u,0x80000000u}) {
      auto command=[queue commandBuffer];
      auto encoder=[command computeCommandEncoder];
      unsigned descriptor=17u|SceneTextureFlags(1280,720,height)|gamma;
      [encoder setComputePipelineState:compute];
      [encoder setTexture:scene atIndex:0];
      [encoder setBytes:&descriptor length:4 atIndex:0];
      [encoder setBuffer:result offset:0 atIndex:1];
      [encoder dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
      [encoder endEncoding];[command commit];[command waitUntilCompleted];
      Require(command.status==MTLCommandBufferStatusCompleted,"descriptor GPU completion");
      const auto* values=(const uint32_t*)result.contents;
      Require(values[0]==17 && values[1]==1280 && values[2]==720 && values[3]==(gamma>>31),
          "physical texture / logical texel ABI, slot index and gamma remain independent");
    }
    auto command=[queue commandBuffer];
    auto pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=scene;
    pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    auto encoder=[command renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:raster];
    const float inverse[2]={1280.f/size.width,720.f/size.height};
    [encoder setFragmentBytes:inverse length:sizeof(inverse) atIndex:0];
    [encoder setViewport:MTLViewport{0,0,double(size.width),double(size.height),0,1}];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    // Same 512+208 guest-row split used by full-scene depth/color resolves.
    for(unsigned tile=0;tile<2;++tile) {
      auto span=ScaleResolveSpan(720,size.height,720,size.height,tile?512:0,tile?512:0,tile?208:512);
      pass.colorAttachments[0].texture=resolved;
      pass.colorAttachments[0].loadAction=tile?MTLLoadActionLoad:MTLLoadActionClear;
      encoder=[command renderCommandEncoderWithDescriptor:pass];
      [encoder setRenderPipelineState:copy];
      [encoder setFragmentTexture:scene atIndex:0];
      const float parameters[8]={1,0,float(span.source)/size.height,0,1,float(span.sourceSize)/size.height,0,0};
      [encoder setFragmentBytes:parameters length:sizeof(parameters) atIndex:0];
      [encoder setViewport:MTLViewport{0,double(span.destination),double(size.width),double(span.destinationSize),0,1}];
      [encoder setScissorRect:MTLScissorRect{0,span.destination,size.width,span.destinationSize}];
      [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
      [encoder endEncoding];
    }
    [command commit];[command waitUntilCompleted];
    Require(command.status==MTLCommandBufferStatusCompleted,"tiled GPU resolve completed");
    std::vector<uint8_t> pixels(size.width*size.height*4);
    [resolved getBytes:pixels.data() bytesPerRow:size.width*4
        fromRegion:MTLRegionMake2D(0,0,size.width,size.height) mipmapLevel:0];
    for(unsigned y=0;y<size.height;++y)for(unsigned x=0;x<size.width;++x) {
      const auto* p=&pixels[(y*size.width+x)*4];
      const float guestX=x*inverse[0]+.5f;
      Require(p[0]==255*(x&1u) && p[1]==255*(y&1u) && p[3]==255,
          "every native pixel retains detail; tiled resolve has no gap or seam");
      Require(std::abs(int(p[2])-int(std::lround(255*guestX/1280)))<=1,
          "fragment position remains in guest coordinates");
    }
    const auto half=HalfPixelOffset(4,float(size.width),float(size.height));
    Require(std::abs(half[0]*size.width-1.f)<1e-5 &&
            std::abs(half[1]*size.height+1.f)<1e-5,"pixel-center offset follows physical viewport");
    std::printf("PASS: real Metal %ux%u raster detail, tiled resolve, guest coordinates, texture-scale/gamma ABI\n",size.width,size.height);
  }
} }
