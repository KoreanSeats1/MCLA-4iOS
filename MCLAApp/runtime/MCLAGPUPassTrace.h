#pragma once
#import <Metal/Metal.h>
#include "MCLAGraphicsFoundation.h"
#include <algorithm>
#include <array>
#include <cstring>
#include <memory>
#include <vector>

namespace mcla::metal {
// Optional sparse instrumentation: no extra encoders, command buffers,
// barriers or CPU/GPU waits. Owner resolves BEFORE releasing the flight slot.
class GPUPassTrace {
public:
  static constexpr unsigned kMaxPasses=512, kSamples=kMaxPasses*4;
  id<MTLCounterSampleBuffer> buffer=nil;
  std::vector<MCLAGPUPassTiming> passes;
  MTLTimestamp cpuStart=0,gpuStart=0;
  uint64_t frame=0;
  int status=1;
  bool guestPass=false;

  static id<MTLCounterSampleBuffer> CreateBuffer(id<MTLDevice> device) {
    if(![device supportsCounterSampling:MTLCounterSamplingPointAtStageBoundary])return nil;
    for(id<MTLCounterSet> set in device.counterSets) {
      if(![set.name isEqualToString:MTLCommonCounterSetTimestamp])continue;
      auto desc=[MTLCounterSampleBufferDescriptor new];
      desc.counterSet=set;desc.storageMode=MTLStorageModeShared;desc.sampleCount=kSamples;
      desc.label=@"MCLA sparse pass timestamps";
      return [device newCounterSampleBufferWithDescriptor:desc error:nil];
    }
    return nil;
  }
  GPUPassTrace(id<MTLDevice> device,id<MTLCounterSampleBuffer> samples,uint64_t id)
      :buffer(samples),frame(id) {
    passes.reserve(kMaxPasses);
    [device sampleTimestamps:&cpuStart gpuTimestamp:&gpuStart];
  }
  MCLAGPUPassTiming* Add(const char* kind) {
    guestPass=false;
    if(passes.size()==kMaxPasses) {status=2;return nullptr;}
    MCLAGPUPassTiming row{};row.frame=frame;row.pass=uint32_t(passes.size());
    row.vertexMilliseconds=row.fragmentMilliseconds=row.spanMilliseconds=-1;
    strncpy(row.kind,kind,sizeof(row.kind)-1);
    passes.push_back(row);
    return &passes.back();
  }
  void Render(MTLRenderPassDescriptor* desc,const char* kind,bool guest=false) {
    auto* row=Add(kind);if(!row)return;
    auto texture=desc.colorAttachments[0].texture ?: desc.depthAttachment.texture;
    row->width=uint32_t(texture.width);row->height=uint32_t(texture.height);
    row->format=uint32_t(texture.pixelFormat);
    auto a=desc.sampleBufferAttachments[0];a.sampleBuffer=buffer;
    a.startOfVertexSampleIndex=row->pass*4;a.endOfVertexSampleIndex=row->pass*4+1;
    a.startOfFragmentSampleIndex=row->pass*4+2;a.endOfFragmentSampleIndex=row->pass*4+3;
    guestPass=guest;
  }
  void Blit(MTLBlitPassDescriptor* desc,const char* kind) {
    auto* row=Add(kind);if(!row)return;
    auto a=desc.sampleBufferAttachments[0];a.sampleBuffer=buffer;
    a.startOfEncoderSampleIndex=row->pass*4;a.endOfEncoderSampleIndex=row->pass*4+1;
    row->mixedShaders=2; // identifies a blit; fragment samples are not written
  }
  void Draw(uint64_t vs,uint64_t ps) {
    if(!guestPass||passes.empty())return;
    auto& row=passes.back();
    if(!row.draws) {row.vertexShader=vs;row.pixelShader=ps;}
    else if(row.vertexShader!=vs||row.pixelShader!=ps)row.mixedShaders=1;
    ++row.draws;
  }
  std::vector<MCLAGPUPassTiming> Resolve(id<MTLDevice> device,bool success) {
    MTLTimestamp cpuEnd=0,gpuEnd=0;
    [device sampleTimestamps:&cpuEnd gpuTimestamp:&gpuEnd];
    // Apple's sampleTimestamps CPU values are NANOSECONDS, not mach ticks.
    // Calibrate both clocks around this command buffer; don't assume GPU Hz.
    const double factor=cpuEnd>cpuStart && gpuEnd>gpuStart ?
        double(cpuEnd-cpuStart)/double(gpuEnd-gpuStart)/1e6 : 0;
    NSData* data=success && !passes.empty() ?
        [buffer resolveCounterRange:NSMakeRange(0,passes.size()*4)] : nil;
    const auto* samples=static_cast<const MTLCounterResultTimestamp*>(data.bytes);
    for(auto& row:passes) {
      if(data.length<(row.pass*4+4)*sizeof(MTLCounterResultTimestamp))continue;
      const bool blit=row.mixedShaders==2;
      for(unsigned j=0;j<(blit?2:4);++j)row.ticks[j]=samples[row.pass*4+j].timestamp;
      row.millisecondsPerTick=factor;
      auto elapsed=[&](uint64_t a,uint64_t b) {
        return factor>0 && a && b && a!=MTLCounterErrorValue &&
            b!=MTLCounterErrorValue && b>=a ? double(b-a)*factor : -1.;
      };
      row.vertexMilliseconds=blit?-1:elapsed(row.ticks[0],row.ticks[1]);
      row.fragmentMilliseconds=blit?-1:elapsed(row.ticks[2],row.ticks[3]);
      row.spanMilliseconds=blit?elapsed(row.ticks[0],row.ticks[1]):
          (row.vertexMilliseconds>=0 && row.fragmentMilliseconds>=0 ?
           elapsed(std::min(row.ticks[0],row.ticks[2]),std::max(row.ticks[1],row.ticks[3])):-1);
    }
    return std::move(passes);
  }
};
} // namespace mcla::metal
