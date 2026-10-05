// Host-side integration test of the real capture writer, no game/device launch.
#import <Foundation/Foundation.h>
#include <cassert>
#include <cstdio>
static NSString* testDocuments;
static NSArray<NSString*>* TestDirectories(NSSearchPathDirectory,
    NSSearchPathDomainMask, BOOL) { return @[testDocuments]; }
#define NSSearchPathForDirectoriesInDomains TestDirectories
#include "../MCLAApp/runtime/MCLAGraphicsFoundation.mm"
#undef NSSearchPathForDirectoriesInDomains

int main() { @autoreleasepool {
  char path[] = "/tmp/mcla-performance-test-XXXXXX";
  assert(mkdtemp(path));testDocuments = @(path);
  MCLAGraphicsConfigureNativeAspect(2736,1260,true);
  MCLAGraphicsConfigureOutput(900,true);
  auto layer=[CAMetalLayer layer];
  MCLAGraphicsResizeMetalLayer((__bridge void*)layer,2736,1260,1);
  auto size=layer.drawableSize;
  MCLAGraphicsSetFSREnabled(false);
  assert(!MCLAGraphicsFSREnabled() && MCLAGraphicsRenderHeight()==900);
  MCLAGraphicsResizeMetalLayer((__bridge void*)layer,2736,1260,1);
  assert(CGSizeEqualToSize(size,layer.drawableSize) && size.width==2736 && size.height==1260);
  MCLAGraphicsSetFSREnabled(true);assert(MCLAGraphicsFSREnabled());
  assert(MCLAGraphicsStartPerformanceCapture());
  assert(MCLAGraphicsPerformanceCaptureActive());
  assert(!MCLAGraphicsStartPerformanceCapture());
  for (uint64_t id=10;id<13;++id) {
    MCLAPerformanceFrame f{}; f.frame=id;f.submitMilliseconds=33.333f;
    f.rendererMilliseconds=12; f.nativeDrawMilliseconds=14;
    f.cacheMaintenanceMilliseconds=.25f;f.resourceInvalidationMilliseconds=.125f;
    f.cacheEvictions=7;f.invalidationCalls=3;f.invalidatedKeys=2;f.oldestCacheAgeFrames=1801;
    f.sceneWidth=1560;f.sceneHeight=720;f.outputWidth=2736;f.outputHeight=1260;
    f.vertexReuses=123;f.textureGroupReuses=456;f.gpuPassTraceStatus=id==10?1:0;
    f.fsrEnabled=id%2;
    f.submissionThreadWallMilliseconds=33.0f;
    f.submissionThreadCPUMilliseconds=21.0f;
    f.drawProfileSamples=4;
    for(unsigned section=0;section<9;++section) {
      f.drawStageWallMicroseconds[section]=float(section)+.25f;
      f.drawStageCPUMicroseconds[section]=float(section)+.125f;
    }
    MCLAGraphicsNotePerformanceFrame(&f);
  }
  // Deliberately out of order: the writer must not pair frame 10 with 12.
  MCLAGraphicsNotePerformanceGPU(12,22,3,1);
  MCLAGraphicsNotePerformanceGPU(10,11,2,.5);
  MCLAGraphicsNotePerformancePresented(10,100);
  MCLAGraphicsNotePerformanceGPU(9,999,999,999); // Unknown frame ignored.
  MCLAGPUPassTiming pass{};pass.frame=10;pass.pass=2;pass.width=1280;pass.height=720;
  strcpy(pass.kind,"fsr-easu");pass.spanMilliseconds=1.25;pass.vertexShader=0xABC;
  MCLAGraphicsNoteGPUPasses(&pass,1);
  pass.frame=9;MCLAGraphicsNoteGPUPasses(&pass,1); // Unknown frame ignored.
  MCLAGraphicsFinishPerformanceCapture();
  assert(!MCLAGraphicsPerformanceCaptureActive());
  NSString* directory = [testDocuments stringByAppendingPathComponent:@"Diagnostics"];
  NSString* csv = nil;NSString* summary=nil;NSString* gpuCSV=nil;
  for (int attempt=0;attempt<100 && (!csv || !summary || !gpuCSV);++attempt) {
    for (NSString* file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil]) {
      NSString* content=[NSString stringWithContentsOfFile:[directory stringByAppendingPathComponent:file]
          encoding:NSUTF8StringEncoding error:nil];
      if ([file hasSuffix:@"-gpu-passes.csv"])gpuCSV=content;
      else if ([file.pathExtension isEqual:@"csv"])csv=content;
      if ([file.pathExtension isEqual:@"txt"])summary=content;
    }
    if (!csv || !summary) [NSThread sleepForTimeInterval:.01];
  }
  assert(csv && summary);
  NSArray* lines=[csv componentsSeparatedByString:@"\n"];
  NSArray* header=[lines[0] componentsSeparatedByString:@","];
  auto column=[&](NSString* name) { NSUInteger i=[header indexOfObject:name]; assert(i!=NSNotFound);return i; };
  const auto gpu=column(@"paired_gpu_ms"), thermal=column(@"thermal_state");
  for (unsigned i=1;i<=3;++i) {
    NSArray* row=[lines[i] componentsSeparatedByString:@","];
    assert(row.count==header.count);
    double expected=i==1?11:i==2?-1:22;
    assert([row[gpu] doubleValue]==expected);
    assert([row[thermal] intValue]>=0 && [row[thermal] intValue]<=3);
    assert([row[column(@"cache_maintenance_ms")] doubleValue]==.25);
    assert([row[column(@"resource_invalidation_ms")] doubleValue]==.125);
    assert([row[column(@"cache_evictions")] intValue]==7);
    assert([row[column(@"oldest_cache_age_frames")] intValue]==1801);
    assert([row[column(@"vertex_reuses_total")] intValue]==123);
    assert([row[column(@"texture_group_reuses_total")] intValue]==456);
    assert([row[column(@"gpu_pass_trace_status")] intValue]==(i==1?1:0));
    assert([row[column(@"fsr_enabled")] intValue]==((i+9)%2));
    assert([row[column(@"submission_thread_wall_ms")] doubleValue]==33.0);
    assert([row[column(@"submission_thread_cpu_ms")] doubleValue]==21.0);
    assert([row[column(@"draw_profile_samples")] intValue]==4);
    assert([row[column(@"draw_state_wall_us")] doubleValue]==.25);
    assert([row[column(@"draw_textures_cpu_us")] doubleValue]==7.125);
  }
  assert([summary containsString:@"Capture schema: 5"]);
  assert([summary containsString:@"execution CPU p50/p95: 21.00 / 21.00 ms"]);
  assert(gpuCSV && [gpuCSV containsString:@"10,2,fsr-easu,1280,720"]);
  assert(![gpuCSV containsString:@"9,2,fsr-easu"]);
  assert([summary containsString:@"GPU pass rows: 1;"]);
  assert([summary containsString:@"evicted keys: 21"]);
  assert([summary containsString:@"2 completed rows"]);
  printf("Capture CSV/summary, thermal state, exact frame pairing, missing callback and async save passed: %s\n",path);
} }
