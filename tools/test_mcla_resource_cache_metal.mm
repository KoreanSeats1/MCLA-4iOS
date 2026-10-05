#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "../MCLAApp/runtime/MCLAResourceCacheIndex.h"
#include <cassert>
#include <iostream>
#include <unordered_map>

// Exercise the renderer's ownership rule: metadata/value eviction must not
// invalidate a GPU-address resource declared to an uncommitted/in-flight CB.
int main() { @autoreleasepool {
  auto device=MTLCreateSystemDefaultDevice();
  if(!device){std::cerr<<"No Metal device; GPU lifetime test not run\n";return 2;}
  NSError* error=nil;
  auto library=[device newLibraryWithSource:@R"(
    #include <metal_stdlib>
    using namespace metal;
    kernel void check(constant ulong& address [[buffer(0)]],
                      device uint* output [[buffer(1)]],uint i [[thread_position_in_grid]]) {
      output[i]=reinterpret_cast<device const uint*>(address)[i];
    })" options:nil error:&error];
  assert(library && !error);
  auto pipeline=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"check"] error:&error];
  assert(pipeline && !error);
  auto queue=[device newCommandQueue];
  std::unordered_map<uint64_t,id<MTLBuffer>> values;
  mcla::metal::ResourceCacheIndex index;
  std::array<id<MTLCommandBuffer>,3> commands;
  std::array<id<MTLBuffer>,3> results;
  for(unsigned flight=0;flight<3;++flight) {
    std::array<uint32_t,256> input;
    for(unsigned i=0;i<input.size();++i)input[i]=0x12340000+flight*256+i;
    values[flight]=[device newBufferWithBytes:input.data() length:sizeof(input) options:MTLResourceStorageModeShared];
    index.Touch(flight,flight);index.AddOwner(flight,flight+1);index.BindAlias(flight,flight+100);
    results[flight]=[device newBufferWithLength:sizeof(input) options:MTLResourceStorageModeShared];
    commands[flight]=[queue commandBuffer];
    auto encoder=[commands[flight] computeCommandEncoder];
    [encoder setComputePipelineState:pipeline];
    uint64_t address=values.at(flight).gpuAddress;
    [encoder setBytes:&address length:sizeof(address) atIndex:0];
    [encoder setBuffer:results[flight] offset:0 atIndex:1];
    [encoder useResource:values.at(flight) usage:MTLResourceUsageRead];
    [encoder dispatchThreads:MTLSizeMake(256,1,1) threadsPerThreadgroup:MTLSizeMake(64,1,1)];
    [encoder endEncoding];
    // No source strong references remain in the test, only CB retention.
    index.Erase(flight);values.erase(flight);
    assert(!index.FindAlias(flight+100));
  }
  for(auto command:commands)[command commit];
  for(unsigned flight=0;flight<3;++flight) {
    [commands[flight] waitUntilCompleted];
    assert(commands[flight].status==MTLCommandBufferStatusCompleted);
    auto* actual=static_cast<const uint32_t*>(results[flight].contents);
    for(unsigned i=0;i<256;++i)assert(actual[i]==0x12340000+flight*256+i);
  }
  std::cout<<"PASS: GPU-address data survives CPU cache eviction before submission across three command buffers\n";
} }
