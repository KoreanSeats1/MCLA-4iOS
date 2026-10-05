// xcrun clang++ -std=c++20 -fobjc-arc tools/test_mcla_metal_pixel_history.mm \
//   -framework Foundation -framework Metal -o /tmp/mcla-pixel-history-test
#include "../MCLAApp/runtime/MCLAMetalPixelHistory.h"
#include <array>
#include <cassert>
#include <cstdio>
#include <unistd.h>

int main() { @autoreleasepool {
  auto device=MTLCreateSystemDefaultDevice(); assert(device);
  auto queue=[device newCommandQueue];
  auto command=[queue commandBuffer];
  auto d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
      width:4 height:4 mipmapped:NO];
  d.storageMode=MTLStorageModePrivate; d.usage=MTLTextureUsageRenderTarget;
  auto target=[device newTextureWithDescriptor:d]; assert(target);
  mcla::metal::PixelHistory probe;
  // Boundary clamp and independent second coordinate, including reset while
  // earlier immutable GPU results still belong to the completion handler.
  probe.Reset(@{@"x":@1.0,@"y":@0.0,@"reference_x":@0.0,@"reference_y":@1.0});
  for(unsigned i=0;i<2;++i) {
    auto pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=target;
    pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    pass.colorAttachments[0].clearColor=MTLClearColorMake(i?8:.25,.5,1,1);
    auto encoder=[command renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
    assert(probe.Record(device,command,target,@{@"draw":@(i)}));
  }
  char temporary[]="/private/tmp/mcla-pixel-history-XXXXXX";
  assert(mkdtemp(temporary));
  NSString *path=[[NSString stringWithUTF8String:temporary] stringByAppendingPathComponent:@"history"];
  probe.Finish(command,path,123,456);
  probe.Reset(@{});
  [command commit]; [command waitUntilCompleted];
  assert(command.status==MTLCommandBufferStatusCompleted);
  NSString *jsonPath=[path stringByAppendingPathExtension:@"json"];
  for(unsigned i=0;i<100 && ![NSFileManager.defaultManager fileExistsAtPath:jsonPath];++i) usleep(10000);
  auto json=[NSData dataWithContentsOfFile:jsonPath]; assert(json);
  NSDictionary *meta=[NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
  assert([meta[@"gpu_completed"] boolValue] && [meta[@"token"] unsignedIntValue]==123);
  NSArray *records=meta[@"records"]; assert(records.count==2);
  auto data=[NSData dataWithContentsOfFile:[path stringByAppendingPathExtension:@"bin"]];
  assert(data.length==1024);
  for(unsigned i=0;i<2;++i) {
    assert([records[i][@"points"][0][0] unsignedIntValue]==3);
    assert([records[i][@"points"][0][1] unsignedIntValue]==0);
    assert([records[i][@"points"][1][0] unsignedIntValue]==0);
    assert([records[i][@"points"][1][1] unsignedIntValue]==3);
    for(unsigned p=0;p<2;++p) {
      std::array<__fp16,4> value{};
      memcpy(value.data(),(const uint8_t *)data.bytes+i*512+p*256,8);
      assert(float(value[0])==(i?8.f:.25f));
      assert(float(value[1])==.5f && float(value[2])==1 && float(value[3])==1);
    }
  }
  std::printf("PASS: ordered HDR pixel readback, point bounds, reset lifetime; %s\n",path.UTF8String);
} }
