#import <Foundation/Foundation.h>
#include "../MCLAApp/runtime/MCLAGPUPassTrace.h"
#include <cassert>
#include <cstdio>
int main() { @autoreleasepool {
  auto device=MTLCreateSystemDefaultDevice();
  if(!device) {puts("No Metal device; GPU test NOT run");return 2;}
  using Trace=mcla::metal::GPUPassTrace;
  std::array<id<MTLCounterSampleBuffer>,3> counters;
  for(auto& c:counters)c=Trace::CreateBuffer(device);
  if(!counters[0]) {puts("Stage-boundary timestamp counters unavailable; NOT verified");return 2;}
  NSError* error=nil;
  auto library=[device newLibraryWithSource:@R"(
    #include <metal_stdlib>
    using namespace metal;
    vertex float4 vs(uint id [[vertex_id]]) {
      float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};
      return float4(p[id],0,1);
    }
    fragment float4 ps(){return float4(0.25,0.5,0.75,1);}
  )" options:nil error:&error];assert(library && !error);
  auto pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[library newFunctionWithName:@"vs"];
  pd.fragmentFunction=[library newFunctionWithName:@"ps"];pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
  auto pipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error];assert(pipeline && !error);
  auto queue=[device newCommandQueue];
  std::array<id<MTLCommandBuffer>,3> commands;
  std::array<id<MTLBuffer>,3> outputs;
  std::array<std::shared_ptr<Trace>,3> traces;
  // Reuse all three counter slots after resolving. No game, no device launch.
  for(unsigned round=0;round<2;++round) {
    for(unsigned slot=0;slot<3;++slot) {
      auto td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:256 height:256 mipmapped:NO];
      td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;
      auto texture=[device newTextureWithDescriptor:td];
      commands[slot]=[queue commandBuffer];
      outputs[slot]=[device newBufferWithLength:256*256*4 options:MTLResourceStorageModeShared];
      traces[slot]=std::make_shared<Trace>(device,counters[slot],round*3+slot+1);
      auto rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=texture;
      rp.colorAttachments[0].loadAction=MTLLoadActionClear;rp.colorAttachments[0].storeAction=MTLStoreActionStore;
      traces[slot]->Render(rp,"guest-color",true);
      auto encoder=[commands[slot] renderCommandEncoderWithDescriptor:rp];
      [encoder setRenderPipelineState:pipeline];
      for(unsigned i=0;i<10;++i) {
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        traces[slot]->Draw(0x123,0x456);
      }
      [encoder endEncoding];
      auto bp=[MTLBlitPassDescriptor blitPassDescriptor];traces[slot]->Blit(bp,"resolve-blit");
      auto blit=[commands[slot] blitCommandEncoderWithDescriptor:bp];
      [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
          sourceSize:MTLSizeMake(256,256,1) toBuffer:outputs[slot] destinationOffset:0
          destinationBytesPerRow:1024 destinationBytesPerImage:256*1024];
      [blit endEncoding];
    }
    for(auto cb:commands)[cb commit];
    for(unsigned slot=0;slot<3;++slot) {
      [commands[slot] waitUntilCompleted];assert(commands[slot].status==MTLCommandBufferStatusCompleted);
      auto rows=traces[slot]->Resolve(device,true);assert(rows.size()==2);
      assert(rows[0].frame==round*3+slot+1 && rows[0].draws==10 && rows[0].mixedShaders==0);
      assert(rows[0].vertexMilliseconds>=0 && rows[0].fragmentMilliseconds>=0);
      assert(rows[0].spanMilliseconds>=0 && rows[1].spanMilliseconds>=0);
      assert(rows[1].fragmentMilliseconds==-1 && rows[1].vertexMilliseconds==-1);
      auto bytes=static_cast<const uint8_t*>(outputs[slot].contents);
      for(unsigned i=0;i<256*256;++i)assert(bytes[i*4]==64 && bytes[i*4+1]==128 && bytes[i*4+2]==191);
      printf("frame=%llu render=%.4fms blit=%.4fms scale=%.9g\n",
          rows[0].frame,rows[0].spanMilliseconds,rows[1].spanMilliseconds,rows[0].millisecondsPerTick);
    }
  }
  Trace bounded(device,counters[0],999);
  for(unsigned i=0;i<Trace::kMaxPasses+3;++i)bounded.Add("capped");
  assert(bounded.passes.size()==Trace::kMaxPasses && bounded.status==2);
  auto failed=bounded.Resolve(device,false);for(auto& r:failed)assert(r.spanMilliseconds==-1);
  puts("PASS: calibrated render/blit timestamps, exact pixels, 3-flight reuse, cap and failed completion");
} }
