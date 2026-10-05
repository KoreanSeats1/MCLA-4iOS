// Host GPU comparison only. Never launches the game or mobile applications.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <ImageIO/ImageIO.h>
#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <random>
#include <vector>
int main(int argc,char** argv) { @autoreleasepool {
  assert(argc==3);
  auto device=MTLCreateSystemDefaultDevice();if(!device)return 2;
  auto queue=[device newCommandQueue];
  NSError* error=nil;
  auto vertex=[device newLibraryWithSource:@R"(
    #include <metal_stdlib>
    using namespace metal;
    vertex float4 v(uint id [[vertex_id]]) {
      float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};
      return float4(p[id],0,1);
    })" options:nil error:&error];assert(vertex);
  std::array<id<MTLRenderPipelineState>,2> pipelines;
  for(unsigned i=0;i<2;++i) {
    auto source=[NSString stringWithContentsOfFile:@(argv[i+1]) encoding:NSUTF8StringEncoding error:&error];assert(source);
    auto library=[device newLibraryWithSource:source options:nil error:&error];
    if(!library){puts(error.localizedDescription.UTF8String);return 3;}
    auto pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[vertex newFunctionWithName:@"v"];
    pd.fragmentFunction=[library newFunctionWithName:@"mclaFsrEasu"];
    pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
    pipelines[i]=[device newRenderPipelineStateWithDescriptor:pd error:&error];assert(pipelines[i]);
  }
  auto sd=[MTLSamplerDescriptor new];sd.minFilter=sd.magFilter=MTLSamplerMinMagFilterLinear;
  sd.sAddressMode=sd.tAddressMode=MTLSamplerAddressModeClampToEdge;
  auto sampler=[device newSamplerStateWithDescriptor:sd];
  auto texture=[&](unsigned w,unsigned h,MTLTextureUsage usage) {
    auto d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
    d.storageMode=MTLStorageModeShared;d.usage=usage;return [device newTextureWithDescriptor:d];
  };
  std::mt19937 rng(123);
  CGImageRef fixture=nullptr;
  if(const char* path=std::getenv("MCLA_FSR_FIXTURE")) {
    auto source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:@(path)],nullptr);
    assert(source);fixture=CGImageSourceCreateImageAtIndex(source,0,nullptr);CFRelease(source);assert(fixture);
  }
  for(auto sizes:std::array<std::array<unsigned,4>,8>{{
      {17,13,37,29},{1560,720,2736,1260},{1952,900,2736,1260},
      {2344,1080,2736,1260},{1280,880,2816,1940},{1568,1080,2816,1940},
      {128,128,128,128},{1920,1080,1560,720}}}) {
    auto [w,h,ow,oh]=sizes;
    std::vector<uint8_t> input(w*h*4);
    for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;++x) {
      const unsigned at=(y*w+x)*4;
      for(unsigned c=0;c<3;++c) {
        // Four quadrants: noise, smooth ramps, high-contrast diagonal edges,
        // pure black/white. Exercise borders, saturation, flat and textured areas.
        input[at+c]=y<h/2 ? (x<w/2 ? uint8_t(rng()) : uint8_t(x*255/w)) :
            (x<w/2 ? (((x+y+c*3)%17<8)?255:0) : ((x+y)%3?0:255));
      }
      input[at+3]=255;
    }
    if(fixture) {
      auto color=CGColorSpaceCreateDeviceRGB();
      auto context=CGBitmapContextCreate(input.data(),w,h,8,w*4,color,
          uint32_t(kCGImageAlphaPremultipliedLast)|uint32_t(kCGBitmapByteOrder32Big));
      assert(context);CGContextDrawImage(context,CGRectMake(0,0,w,h),fixture);
      CGContextRelease(context);CGColorSpaceRelease(color);
    }
    auto src=texture(w,h,MTLTextureUsageShaderRead);
    [src replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0 withBytes:input.data() bytesPerRow:w*4];
    std::array<id<MTLTexture>,2> dst{texture(ow,oh,MTLTextureUsageRenderTarget),texture(ow,oh,MTLTextureUsageRenderTarget)};
    auto run=[&](unsigned variant,unsigned repeats) {
      auto cb=[queue commandBuffer];
      auto rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=dst[variant];
      rp.colorAttachments[0].loadAction=MTLLoadActionDontCare;rp.colorAttachments[0].storeAction=MTLStoreActionStore;
      // One draw per pass like the app; no relying on occlusion/overdraw elimination.
      for(unsigned i=0;i<repeats;++i) {
        auto e=[cb renderCommandEncoderWithDescriptor:rp];[e setRenderPipelineState:pipelines[variant]];
        [e setFragmentTexture:src atIndex:0];[e setFragmentSamplerState:sampler atIndex:0];
        const float c[8]={0,0,0,0,float(w)/ow,float(h)/oh,1.f/w,1.f/h};
        [e setFragmentBytes:c length:sizeof(c) atIndex:0];
        [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];
      }
      [cb commit];[cb waitUntilCompleted];assert(cb.status==MTLCommandBufferStatusCompleted);
      return (cb.GPUEndTime-cb.GPUStartTime)*1000/repeats;
    };
    run(0,1);run(1,1);
    std::array<std::vector<uint8_t>,2> pixels;
    for(unsigned i=0;i<2;++i) {
      pixels[i].resize(ow*oh*4);
      [dst[i] getBytes:pixels[i].data() bytesPerRow:ow*4 fromRegion:MTLRegionMake2D(0,0,ow,oh) mipmapLevel:0];
    }
    unsigned maxError=0;uint64_t sum=0,changed=0;
    for(size_t i=0;i<pixels[0].size();++i) {
      unsigned delta=std::abs(int(pixels[0][i])-int(pixels[1][i]));
      maxError=std::max(maxError,delta);sum+=delta;changed+=delta!=0;
    }
    printf("%ux%u -> %ux%u maxLSB=%u meanLSB=%.8f changed=%llu\n",w,h,ow,oh,maxError,double(sum)/pixels[0].size(),changed);
    assert(maxError<=1 && double(sum)/pixels[0].size()<.03);
    std::array<std::vector<double>,2> times;
    for(unsigned round=0;round<40;++round)for(unsigned j=0;j<2;++j) {
      unsigned v=(round+j)&1;times[v].push_back(run(v,16));
    }
    for(auto& t:times)std::sort(t.begin(),t.end());
    printf("  host GPU reference=%.4fms optimized=%.4fms ratio=%.3f\n",times[0][20],times[1][20],times[1][20]/times[0][20]);
  }
  if(fixture)CGImageRelease(fixture);
  puts("PASS: reference image agreement and alternating host GPU benchmark completed");
} }
