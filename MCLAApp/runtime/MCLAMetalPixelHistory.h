#pragma once

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <algorithm>
#include <cmath>

namespace mcla::metal {

// One opt-in frame only. End the render encoder before Record; readbacks stay
// ordered on the frame command buffer. Nothing is mapped before GPU completion.
// The two normalized points are image coordinates, excluding letterbox bars.
class PixelHistory {
  static constexpr NSUInteger kLimit = 16384; // Before/after up to 8192 draws.
  static constexpr NSUInteger kStride = 512; // Two separately aligned pixels.
  id<MTLBuffer> pixels_ = nil;
  NSMutableArray<NSDictionary *> *records_ = nil;
  double x_ = .315, y_ = .395;
  double referenceX_ = .70, referenceY_ = .30;
  bool truncated_ = false;

public:
  void Reset(NSDictionary *request) {
    pixels_ = nil;
    records_ = nil;
    truncated_ = false;
    auto coordinate = [&](NSString *key, double fallback) {
      id value = request[key];
      if (![value isKindOfClass:NSNumber.class]) return fallback;
      const double d = [value doubleValue];
      return std::isfinite(d) && d >= 0 && d <= 1 ? d : fallback;
    };
    x_ = coordinate(@"x", .315); y_ = coordinate(@"y", .395);
    referenceX_ = coordinate(@"reference_x", .70);
    referenceY_ = coordinate(@"reference_y", .30);
  }
  bool CanRecord(id<MTLTexture> texture) {
    if (records_.count >= kLimit) { truncated_ = true; return false; }
    return texture && texture.textureType == MTLTextureType2D &&
        texture.sampleCount == 1 &&
        (texture.pixelFormat == MTLPixelFormatRGBA8Unorm ||
         texture.pixelFormat == MTLPixelFormatRGBA16Float);
  }
  bool Record(id<MTLDevice> device, id<MTLCommandBuffer> commands,
              id<MTLTexture> texture, NSDictionary *metadata) {
    if (!CanRecord(texture) || !commands) return false;
    if (!pixels_) {
      pixels_ = [device newBufferWithLength:kLimit * kStride
                                   options:MTLResourceStorageModeShared];
      records_ = [NSMutableArray array];
    }
    if (!pixels_) return false;
    const NSUInteger offset = records_.count * kStride;
    auto encoder = [commands blitCommandEncoder];
    if (!encoder) return false;
    NSMutableArray *points = [NSMutableArray array];
    for (unsigned i = 0; i < 2; ++i) {
      const NSUInteger x = std::min(texture.width - 1,
          NSUInteger((i ? referenceX_ : x_) * texture.width));
      const NSUInteger y = std::min(texture.height - 1,
          NSUInteger((i ? referenceY_ : y_) * texture.height));
      [points addObject:@[@(x), @(y)]];
      [encoder copyFromTexture:texture sourceSlice:0 sourceLevel:0
          sourceOrigin:MTLOriginMake(x,y,0) sourceSize:MTLSizeMake(1,1,1)
          toBuffer:pixels_ destinationOffset:offset + i * 256
          destinationBytesPerRow:256 destinationBytesPerImage:256];
    }
    [encoder endEncoding];
    NSMutableDictionary *entry = [metadata mutableCopy];
    entry[@"offset"] = @(offset);
    entry[@"points"] = points;
    entry[@"width"] = @(texture.width); entry[@"height"] = @(texture.height);
    entry[@"format"] = texture.pixelFormat == MTLPixelFormatRGBA16Float
        ? @"rgba16f" : @"rgba8";
    [records_ addObject:entry];
    return true;
  }
  void Finish(id<MTLCommandBuffer> commands, NSString *path,
              uint64_t token, uint64_t frame) {
    if (!records_.count || !commands) return;
    // Capture these objects, not this: the next request may reset the probe
    // while this completion handler is still writing its immutable result.
    id<MTLBuffer> pixels = pixels_;
    NSArray *records = [records_ copy];
    const bool truncated = truncated_;
    [commands addCompletedHandler:^(id<MTLCommandBuffer> cb) {
      if (cb.status != MTLCommandBufferStatusCompleted) return;
      NSString *binary = [path stringByAppendingPathExtension:@"bin"];
      const BOOL wrote = [[NSData dataWithBytes:pixels.contents
          length:records.count * kStride] writeToFile:binary atomically:YES];
      if (!wrote) return;
      NSDictionary *result = @{@"version":@1, @"frame":@(frame),
          @"token":@(token), @"gpu_completed":@YES,
          @"truncated":@(truncated), @"records":records};
      [[NSJSONSerialization dataWithJSONObject:result options:0 error:nil]
          writeToFile:[path stringByAppendingPathExtension:@"json"] atomically:YES];
    }];
    pixels_ = nil; records_ = nil;
  }
};

} // namespace mcla::metal
