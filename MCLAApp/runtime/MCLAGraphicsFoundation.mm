#include "MCLADiagnostics.h"
#include "MCLAGraphicsFoundation.h"
#include "MCLAMetalPresentation.h"
#include "MCLAApplicationActivity.h"
#include <pthread.h>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <os/lock.h>

#include <atomic>
#include <array>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

#ifndef MCLA_REXGLUE_SOURCE_STAGED
#define MCLA_REXGLUE_SOURCE_STAGED 0
#endif

#ifndef MCLA_XENOS_RUNTIME_LINKED
#define MCLA_XENOS_RUNTIME_LINKED 0
#endif

#ifndef MCLA_NATIVE_RENDERER_CORE_LINKED
#define MCLA_NATIVE_RENDERER_CORE_LINKED 0
#endif

#ifndef MCLA_TITLE_AOT_LINKED
#define MCLA_TITLE_AOT_LINKED 0
#endif

#if MCLA_NATIVE_RENDERER_CORE_LINKED
#include "native_buffer_arena.h"
#include "draw_slicing.h"
#include "shader_identity.h"
#endif

namespace {
mcla::metal::ApplicationActivity gApplicationActivity;

// MCLA's Xbox 360 output is 720p. Keeping the guest surface stable avoids
// scaling the emulated workload to the physical Retina pixel count.
constexpr double kGuestDrawableWidth = 1280.0;
constexpr double kGuestDrawableHeight = 720.0;
constexpr uint32_t kMaximumFramesInFlight = 3;

void CopyDetail(char* destination, size_t destinationSize,
                const char* message);

os_unfair_lock gPresenterLock = OS_UNFAIR_LOCK_INIT;
CAMetalLayer* gBoundLayer = nil;
id<MTLDevice> gMetalDevice = nil;
id<MTLCommandQueue> gCommandQueue = nil;
id<MTLRenderPipelineState> gDiagnosticPipeline = nil;
id<MTLRenderPipelineState> gInlinePipeline = nil;
id<MTLDepthStencilState> gDiagnosticDepthState = nil;
id<MTLTexture> gDiagnosticDepth[kMaximumFramesInFlight] = {nil, nil, nil};
dispatch_semaphore_t gFrameSlots = nil;
std::atomic<uint64_t> gSubmittedFrames{0};
std::atomic<uint64_t> gCompletedFrames{0};
std::atomic<uint64_t> gTitleDrivenFrames{0};
std::atomic<uint64_t> gTitleInlineVertices{0};
std::atomic<uint32_t> gRenderHeight{720};
std::atomic<bool> gFSREnabled{false};
std::atomic<uint32_t> gGuestVideoWidth{1280};
std::atomic<uint32_t> gGuestVideoHeight{720};
std::vector<MCLAInlineVertex> gPendingInlineVertices;
char gPipelineError[256] = {};

constexpr uint32_t kFrameTimingCapacity = 240;
os_unfair_lock gFrameTimingLock = OS_UNFAIR_LOCK_INIT;
MCLAFrameTimingSample gFrameTiming[kFrameTimingCapacity] = {};
uint32_t gFrameTimingCount = 0;
uint32_t gFrameTimingWrite = 0;
double gLastPresentedSeconds = 0.0;
float gLatestGPUMilliseconds = 0.0f;

struct PerformanceCaptureRow {
    MCLAPerformanceFrame frame;
    double seconds;
    float latestDisplayMilliseconds;
    float latestCompletedGPUMilliseconds;
    int thermalState = 0;
    bool lowPower = false;
    float gpuMilliseconds = -1, commitToGPUMilliseconds = -1, driverMilliseconds = -1;
    double presentedSeconds = -1;
};
std::vector<PerformanceCaptureRow> gPerformanceRows;
std::vector<MCLAGPUPassTiming> gGPUPassRows;
uint64_t gGPUPassRowsDropped=0;
constexpr size_t kMaxGPUPassRows=16384;
bool gPerformanceActive = false;
std::atomic<bool> gPerformanceActiveFast{false};
uint64_t gPerformanceGeneration = 0;
double gPerformanceStart = 0.0;
double gPerformanceSavedUntil = 0.0;
constexpr double kPerformanceCaptureSeconds = 20.0;
constexpr size_t kPerformanceCaptureMaxRows = 1200;

static NSString* const kDiagnosticMetalSource = @R"METAL(
#include <metal_stdlib>
using namespace metal;

struct MCLAWireOut {
    float4 position [[position]];
    float4 color;
};

vertex MCLAWireOut mcla_diagnostic_vertex(
    uint vertexID [[vertex_id]], constant float4& parameters [[buffer(0)]]) {
    constexpr float3 vertices[36] = {
        // front
        {-1,-1,-1}, { 1,-1,-1}, { 1, 1,-1},
        {-1,-1,-1}, { 1, 1,-1}, {-1, 1,-1},
        // back
        { 1,-1, 1}, {-1,-1, 1}, {-1, 1, 1},
        { 1,-1, 1}, {-1, 1, 1}, { 1, 1, 1},
        // left
        {-1,-1, 1}, {-1,-1,-1}, {-1, 1,-1},
        {-1,-1, 1}, {-1, 1,-1}, {-1, 1, 1},
        // right
        { 1,-1,-1}, { 1,-1, 1}, { 1, 1, 1},
        { 1,-1,-1}, { 1, 1, 1}, { 1, 1,-1},
        // top
        {-1, 1,-1}, { 1, 1,-1}, { 1, 1, 1},
        {-1, 1,-1}, { 1, 1, 1}, {-1, 1, 1},
        // bottom
        {-1,-1, 1}, { 1,-1, 1}, { 1,-1,-1},
        {-1,-1, 1}, { 1,-1,-1}, {-1,-1,-1}
    };
    constexpr float3 faceColors[6] = {
        {0.05, 0.85, 1.00}, {1.00, 0.22, 0.42},
        {0.20, 1.00, 0.55}, {1.00, 0.62, 0.08},
        {0.72, 0.28, 1.00}, {0.08, 0.38, 1.00}
    };

    float3 p = vertices[vertexID];
    const float phase = parameters.x;
    const float cp = cos(phase);
    const float sp = sin(phase);
    const float ct = cos(phase * 0.63);
    const float st = sin(phase * 0.63);
    p = float3(cp * p.x + sp * p.z, p.y, -sp * p.x + cp * p.z);
    p = float3(p.x, ct * p.y - st * p.z, st * p.y + ct * p.z);
    p.z += 4.2;

    MCLAWireOut out;
    out.position = float4(p.x * 1.65 / parameters.z,
                          p.y * 1.65, p.z - 0.12, p.z);
    const float pulse = 0.72 + 0.28 * parameters.y;
    out.color = float4(faceColors[vertexID / 6] * pulse, 1.0);
    return out;
}

fragment float4 mcla_diagnostic_fragment(MCLAWireOut in [[stage_in]]) {
    return in.color;
}

struct MCLAInlineVertex {
    packed_float3 position;
    packed_float4 color;
};

vertex MCLAWireOut mcla_inline_vertex(
    uint vertexID [[vertex_id]],
    const device MCLAInlineVertex* vertices [[buffer(0)]]) {
    const MCLAInlineVertex v = vertices[vertexID];
    MCLAWireOut out;
    out.position = float4(v.position.x / 640.0 - 1.0,
                          1.0 - v.position.y / 360.0,
                          0.05, 1.0);
    out.color = float4(v.color);
    return out;
}
)METAL";

void EnsureDeviceLocked() {
    if (!gMetalDevice) {
        gMetalDevice = MTLCreateSystemDefaultDevice();
    }
    if (gMetalDevice && !gCommandQueue) {
        gCommandQueue = [gMetalDevice newCommandQueue];
        gCommandQueue.label = @"MCLA Xenos Queue";
    }
    if (!gFrameSlots) {
        gFrameSlots = dispatch_semaphore_create(kMaximumFramesInFlight);
    }
    if (gMetalDevice && !gDiagnosticPipeline && !gPipelineError[0]) {
        NSError* error = nil;
        id<MTLLibrary> library =
            [gMetalDevice newLibraryWithSource:kDiagnosticMetalSource
                                       options:nil error:&error];
        if (!library) {
            CopyDetail(gPipelineError, sizeof(gPipelineError),
                       error.localizedDescription.UTF8String);
            return;
        }
        MTLRenderPipelineDescriptor* descriptor =
            [[MTLRenderPipelineDescriptor alloc] init];
        descriptor.label = @"MCLA title-driven diagnostic 3D";
        descriptor.vertexFunction =
            [library newFunctionWithName:@"mcla_diagnostic_vertex"];
        descriptor.fragmentFunction =
            [library newFunctionWithName:@"mcla_diagnostic_fragment"];
        descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        gDiagnosticPipeline =
            [gMetalDevice newRenderPipelineStateWithDescriptor:descriptor
                                                          error:&error];
        if (!gDiagnosticPipeline) {
            CopyDetail(gPipelineError, sizeof(gPipelineError),
                       error.localizedDescription.UTF8String);
            return;
        }
        MTLRenderPipelineDescriptor* inlineDescriptor =
            [[MTLRenderPipelineDescriptor alloc] init];
        inlineDescriptor.label = @"MCLA guest inline triangles";
        inlineDescriptor.vertexFunction =
            [library newFunctionWithName:@"mcla_inline_vertex"];
        inlineDescriptor.fragmentFunction =
            [library newFunctionWithName:@"mcla_diagnostic_fragment"];
        inlineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        inlineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        inlineDescriptor.colorAttachments[0].blendingEnabled = YES;
        inlineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        inlineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        inlineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        inlineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        gInlinePipeline =
            [gMetalDevice newRenderPipelineStateWithDescriptor:inlineDescriptor
                                                          error:&error];
        if (!gInlinePipeline) {
            CopyDetail(gPipelineError, sizeof(gPipelineError),
                       error.localizedDescription.UTF8String);
            gDiagnosticPipeline = nil;
            return;
        }
        MTLDepthStencilDescriptor* depthDescriptor =
            [[MTLDepthStencilDescriptor alloc] init];
        depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
        depthDescriptor.depthWriteEnabled = YES;
        gDiagnosticDepthState =
            [gMetalDevice newDepthStencilStateWithDescriptor:depthDescriptor];
        for (uint32_t i = 0; i < kMaximumFramesInFlight; ++i) {
            MTLTextureDescriptor* depthTexture =
                [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                   width:(NSUInteger)kGuestDrawableWidth
                                                                  height:(NSUInteger)kGuestDrawableHeight
                                                               mipmapped:NO];
            depthTexture.usage = MTLTextureUsageRenderTarget;
            depthTexture.storageMode = MTLStorageModePrivate;
            gDiagnosticDepth[i] = [gMetalDevice newTextureWithDescriptor:depthTexture];
            gDiagnosticDepth[i].label = [NSString stringWithFormat:@"MCLA depth %u", i];
        }
    }
}

void CopyDetail(char* destination, size_t destinationSize,
                const char* message) {
    if (!destination || destinationSize == 0) {
        return;
    }
    std::snprintf(destination, destinationSize, "%s", message ? message : "");
}

}  // namespace

static std::atomic<bool> gExperimental60FPS{false};
void MCLAGraphicsSetExperimental60FPS(bool enabled) { gExperimental60FPS.store(enabled,std::memory_order_relaxed); }
bool MCLAGraphicsExperimental60FPS(void) { return gExperimental60FPS.load(std::memory_order_relaxed); }
uint32_t MCLAGraphicsFrameRate(void) { return MCLAGraphicsExperimental60FPS() ? 60u : 30u; }
static std::atomic<uint32_t> gVisualExperiments{7};
void MCLAGraphicsSetVisualExperiments(uint32_t experiments) { gVisualExperiments.store(experiments,std::memory_order_relaxed); }
uint32_t MCLAGraphicsVisualExperiments(void) { return gVisualExperiments.load(std::memory_order_relaxed); }
static std::atomic<bool> gDepthOfFieldDisabled{false};
void MCLAGraphicsSetDepthOfFieldDisabled(bool disabled) { gDepthOfFieldDisabled.store(disabled,std::memory_order_relaxed); }
bool MCLAGraphicsDepthOfFieldDisabled(void) { return gDepthOfFieldDisabled.load(std::memory_order_relaxed); }
static std::atomic<bool> gMotionBlurDisabled{false};
void MCLAGraphicsSetMotionBlurDisabled(bool disabled) { gMotionBlurDisabled.store(disabled,std::memory_order_relaxed); }
bool MCLAGraphicsMotionBlurDisabled(void) { return gMotionBlurDisabled.load(std::memory_order_relaxed); }

void MCLAGraphicsSetApplicationActive(bool active) {
    gApplicationActivity.Set(active);
}
bool MCLAGraphicsApplicationActive(void) { return gApplicationActivity.IsActive(); }
bool MCLAGraphicsWaitForApplicationActive(void) {
    return gApplicationActivity.Wait(!pthread_main_np());
}

void MCLAGraphicsBindMetalLayer(void* rawLayer) {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)rawLayer;
    if (!layer) {
        return;
    }

    os_unfair_lock_lock(&gPresenterLock);
    EnsureDeviceLocked();
    layer.device = gMetalDevice;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.opaque = YES;
    layer.contentsGravity = kCAGravityResizeAspect;
    layer.allowsNextDrawableTimeout = YES;
    layer.presentsWithTransaction = NO;
    layer.maximumDrawableCount = kMaximumFramesInFlight;
    layer.contentsScale = 1.0;
    layer.drawableSize = CGSizeMake(kGuestDrawableWidth, kGuestDrawableHeight);
    gBoundLayer = layer;
    os_unfair_lock_unlock(&gPresenterLock);
}

void MCLAGraphicsUnbindMetalLayer(void* rawLayer) {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)rawLayer;
    os_unfair_lock_lock(&gPresenterLock);
    if (!layer || gBoundLayer == layer) {
        gBoundLayer = nil;
    }
    os_unfair_lock_unlock(&gPresenterLock);
}

void MCLAGraphicsResizeMetalLayer(void* rawLayer, double width, double height,
                                  double scale) {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)rawLayer;
    if (!layer || width <= 0.0 || height <= 0.0 || scale <= 0.0) {
        return;
    }
    // Keep presentation at native size for live FSR A/B comparisons. Off
    // uses the normal bilinear copy, not a differently sized drawable pool.
    const auto output=mcla::metal::OutputForSettings(gRenderHeight.load(),true,
        uint32_t(width*scale),uint32_t(height*scale),
        gGuestVideoWidth.load(),gGuestVideoHeight.load());
    // UIKit may lay out the game view while tracking a button. Assigning
    // drawableSize repeatedly can invalidate Metal's drawable pool even when
    // the scene and screen dimensions have not changed.
    if (layer.contentsScale != 1.0) layer.contentsScale = 1.0;
    if (layer.drawableSize.width != output.width ||
        layer.drawableSize.height != output.height)
        layer.drawableSize = CGSizeMake(output.width,output.height);
}

void MCLAGraphicsConfigureOutput(uint32_t renderHeight, bool fsrEnabled) {
    gRenderHeight.store(mcla::metal::RenderHeight(renderHeight));
    gFSREnabled.store(fsrEnabled);
}
void MCLAGraphicsConfigureNativeAspect(uint32_t nativeWidth,
                                       uint32_t nativeHeight, bool enabled) {
    uint32_t guestWidth = 1280, guestHeight = 720;
    if (enabled && nativeWidth && nativeHeight) {
        const double aspect = double(nativeWidth) / nativeHeight;
        if (aspect > 16.0 / 9.0)
            guestWidth = uint32_t(std::clamp(
                std::lround(720.0 * aspect / 8.0) * 8L, 1280L, 2048L));
        else
            guestHeight = uint32_t(std::clamp(
                std::lround(1280.0 / aspect / 8.0) * 8L, 720L, 1280L));
    }
    gGuestVideoWidth.store(guestWidth);
    gGuestVideoHeight.store(guestHeight);
}
void MCLAGraphicsGuestVideoSize(uint32_t* width, uint32_t* height) {
    if (width) *width = gGuestVideoWidth.load();
    if (height) *height = gGuestVideoHeight.load();
}
uint32_t MCLAGraphicsRenderHeight(void) { return gRenderHeight.load(); }
bool MCLAGraphicsFSREnabled(void) { return gFSREnabled.load(); }
void MCLAGraphicsSetFSREnabled(bool enabled) { gFSREnabled.store(enabled); }

bool MCLAGraphicsHasMetalLayer(void) {
    os_unfair_lock_lock(&gPresenterLock);
    const bool available = gBoundLayer && gMetalDevice && gCommandQueue;
    os_unfair_lock_unlock(&gPresenterLock);
    return available;
}

void* MCLAGraphicsBoundMetalLayer(void) {
    os_unfair_lock_lock(&gPresenterLock);
    CAMetalLayer* layer = gBoundLayer;
    os_unfair_lock_unlock(&gPresenterLock);
    return (__bridge void*)layer;
}

bool MCLAGraphicsBoundLayerSize(uint32_t* width, uint32_t* height) {
    if (!width || !height) {
        return false;
    }
    os_unfair_lock_lock(&gPresenterLock);
    CAMetalLayer* layer = gBoundLayer;
    const CGSize size = layer ? layer.drawableSize : CGSizeZero;
    os_unfair_lock_unlock(&gPresenterLock);
    if (size.width < 1.0 || size.height < 1.0) {
        *width = 0;
        *height = 0;
        return false;
    }
    *width = (uint32_t)size.width;
    *height = (uint32_t)size.height;
    return true;
}

// The shared presenter currently exposes this title-neutral publication hook
// under its historical Theft4 symbol. Keep the compatibility spelling at the
// linkage boundary only; MCLA owns the counter and no GTA-specific behavior is
// involved.
extern "C" void theft4_frame_counter_note_published(void) {
    gTitleDrivenFrames.fetch_add(1, std::memory_order_relaxed);
}

void MCLAGraphicsNoteMetalSubmission(void) {
    gSubmittedFrames.fetch_add(1, std::memory_order_relaxed);
}
void MCLAGraphicsNoteMetalCompletion(bool presented) {
    gCompletedFrames.fetch_add(1, std::memory_order_relaxed);
    if (presented) gTitleDrivenFrames.fetch_add(1, std::memory_order_relaxed);
}

bool MCLAGraphicsPresentBringupFrame(double red, double green, double blue,
                                     double alpha) {
    @autoreleasepool {
        os_unfair_lock_lock(&gPresenterLock);
        CAMetalLayer* layer = gBoundLayer;
        id<MTLCommandQueue> queue = gCommandQueue;
        dispatch_semaphore_t slots = gFrameSlots;
        os_unfair_lock_unlock(&gPresenterLock);
        if (!layer || !queue || !slots) {
            return false;
        }

        dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) {
            dispatch_semaphore_signal(slots);
            return false;
        }

        MTLRenderPassDescriptor* pass =
            [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = drawable.texture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].clearColor =
            MTLClearColorMake(red, green, blue, alpha);

        id<MTLCommandBuffer> buffer = [queue commandBuffer];
        if (!buffer) {
            dispatch_semaphore_signal(slots);
            return false;
        }
        const uint64_t frame = gSubmittedFrames.fetch_add(1) + 1;
        buffer.label = [NSString stringWithFormat:@"MCLA Bring-up Frame %llu",
                                                  (unsigned long long)frame];
        id<MTLRenderCommandEncoder> encoder =
            [buffer renderCommandEncoderWithDescriptor:pass];
        [encoder endEncoding];
        [buffer presentDrawable:drawable];
        [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
            (void)completed;
            gCompletedFrames.fetch_add(1);
            dispatch_semaphore_signal(slots);
        }];
        [buffer commit];
        return true;
    }
}

bool MCLAGraphicsPresentTitleDiagnostic(uint64_t guestFrame,
                                        uint64_t immediateVertices,
                                        uint64_t resolves) {
    @autoreleasepool {
        os_unfair_lock_lock(&gPresenterLock);
        CAMetalLayer* layer = gBoundLayer;
        id<MTLCommandQueue> queue = gCommandQueue;
        id<MTLRenderPipelineState> pipeline = gDiagnosticPipeline;
        id<MTLRenderPipelineState> inlinePipeline = gInlinePipeline;
        id<MTLDepthStencilState> depthState = gDiagnosticDepthState;
        dispatch_semaphore_t slots = gFrameSlots;
        std::vector<MCLAInlineVertex> inlineVertices;
        inlineVertices.swap(gPendingInlineVertices);
        os_unfair_lock_unlock(&gPresenterLock);
        if (!layer || !queue || !pipeline || !inlinePipeline || !depthState || !slots) {
            return false;
        }

        dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) {
            dispatch_semaphore_signal(slots);
            return false;
        }
        const uint64_t submitted = gSubmittedFrames.fetch_add(1) + 1;
        id<MTLTexture> depth = gDiagnosticDepth[submitted % kMaximumFramesInFlight];
        if (!depth) {
            dispatch_semaphore_signal(slots);
            return false;
        }

        MTLRenderPassDescriptor* pass =
            [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = drawable.texture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        const double activity = double((immediateVertices / 64 + resolves) % 256) / 255.0;
        pass.colorAttachments[0].clearColor =
            MTLClearColorMake(0.008 + activity * 0.018, 0.012,
                              0.035 + activity * 0.035, 1.0);
        pass.depthAttachment.texture = depth;
        pass.depthAttachment.loadAction = MTLLoadActionClear;
        pass.depthAttachment.storeAction = MTLStoreActionDontCare;
        pass.depthAttachment.clearDepth = 1.0;

        id<MTLCommandBuffer> buffer = [queue commandBuffer];
        if (!buffer) {
            dispatch_semaphore_signal(slots);
            return false;
        }
        buffer.label = [NSString stringWithFormat:@"MCLA title frame %llu",
                                                   (unsigned long long)guestFrame];
        id<MTLRenderCommandEncoder> encoder =
            [buffer renderCommandEncoderWithDescriptor:pass];
        const float parameters[4] = {
            float(double(guestFrame) * (1.0 / 90.0)),
            float(0.5 + 0.5 * std::sin(double(immediateVertices) * 0.0002)),
            float(kGuestDrawableWidth / kGuestDrawableHeight), 0.0f};
        [encoder setRenderPipelineState:pipeline];
        [encoder setDepthStencilState:depthState];
        [encoder setCullMode:MTLCullModeNone];
        [encoder setVertexBytes:parameters length:sizeof(parameters) atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:36];
        if (!inlineVertices.empty()) {
            id<MTLBuffer> inlineBuffer =
                [gMetalDevice newBufferWithBytes:inlineVertices.data()
                                           length:inlineVertices.size() * sizeof(MCLAInlineVertex)
                                          options:MTLResourceStorageModeShared];
            if (inlineBuffer) {
                inlineBuffer.label = @"MCLA guest-authored inline geometry";
                [encoder setRenderPipelineState:inlinePipeline];
                [encoder setDepthStencilState:nil];
                [encoder setVertexBuffer:inlineBuffer offset:0 atIndex:0];
                [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                             vertexStart:0
                             vertexCount:inlineVertices.size()];
                gTitleInlineVertices.fetch_add(inlineVertices.size());
            }
        }
        [encoder endEncoding];
        [buffer presentDrawable:drawable];
        [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
            (void)completed;
            gCompletedFrames.fetch_add(1);
            dispatch_semaphore_signal(slots);
        }];
        [buffer commit];
        gTitleDrivenFrames.fetch_add(1);
        return true;
    }
}

void MCLAGraphicsSubmitInlineTriangles(const MCLAInlineVertex* vertices,
                                       uint32_t vertexCount) {
    if (!vertices || vertexCount < 3 || vertexCount > 4096) {
        return;
    }
    os_unfair_lock_lock(&gPresenterLock);
    constexpr size_t kMaximumPendingVertices = 8192;
    const size_t available =
        gPendingInlineVertices.size() < kMaximumPendingVertices
            ? kMaximumPendingVertices - gPendingInlineVertices.size()
            : 0;
    const size_t accepted = std::min<size_t>(vertexCount, available);
    gPendingInlineVertices.insert(gPendingInlineVertices.end(), vertices,
                                  vertices + accepted);
    os_unfair_lock_unlock(&gPresenterLock);
}

void MCLAGraphicsGetReport(MCLAGraphicsReport* report) {
    if (!report) {
        return;
    }
    std::memset(report, 0, sizeof(*report));

    os_unfair_lock_lock(&gPresenterLock);
    CAMetalLayer* layer = gBoundLayer;
    report->metalPresenterReady = layer && gMetalDevice && gCommandQueue;
    const CGSize drawableSize = layer ? layer.drawableSize : CGSizeZero;
    os_unfair_lock_unlock(&gPresenterLock);

    report->drawableWidth = (uint32_t)drawableSize.width;
    report->drawableHeight = (uint32_t)drawableSize.height;
    report->maximumFramesInFlight = kMaximumFramesInFlight;
    report->submittedFrames = gSubmittedFrames.load();
    report->completedFrames = gCompletedFrames.load();
    report->titleDrivenFrames = gTitleDrivenFrames.load();
    report->titleInlineVertices = gTitleInlineVertices.load();
    report->rexglueSourceStaged = MCLA_REXGLUE_SOURCE_STAGED;
#if MCLA_NATIVE_RENDERER_CORE_LINKED
    // Exercise promoted title-neutral ownership components. This proves only
    // that the portable utilities are linked; it does not mean MCLA draws are
    // being submitted by the title-native renderer.
    rex::graphics::gta4_native::NativeBufferArena arena({4096, 256});
    const auto reservation = arena.Reserve(512);
    mcla::native_gfx::DrawSlicer slicer(4, 6);
    mcla::native_gfx::DrawSlice slice{};
    const uint8_t identityProbe[] = {0x4d, 0x43, 0x4c, 0x41};
    const bool mclaTitleMappingReady =
        slicer.valid() && slicer.Next(slice) && slice.count == 6 &&
        mcla::native_gfx::Fnv1a64(identityProbe, sizeof(identityProbe)) != 0;
    report->nativeRendererCoreReady =
        arena.valid() && reservation &&
        arena.Commit(reservation.allocation.id) ==
            rex::graphics::gta4_native::NativeBufferArenaStatus::kSuccess &&
        mclaTitleMappingReady;
#else
    report->nativeRendererCoreReady = false;
#endif
    report->xenosRuntimeLinked = MCLA_XENOS_RUNTIME_LINKED;
    report->titleAOTLinked = MCLA_TITLE_AOT_LINKED;

    if (gPipelineError[0]) {
        CopyDetail(report->detail, sizeof(report->detail), gPipelineError);
    } else if (!report->metalPresenterReady) {
        CopyDetail(report->detail, sizeof(report->detail),
                   "UIKit has not bound a usable CAMetalLayer.");
    } else if (!report->nativeRendererCoreReady) {
        CopyDetail(report->detail, sizeof(report->detail),
                   "Metal active; portable renderer utilities are not linked.");
    } else if (!report->titleAOTLinked) {
        CopyDetail(report->detail, sizeof(report->detail),
                   "Portable Theft4 ownership utilities and MCLA title decoding are linked; full MCLA-native draw submission is still pending.");
    } else {
        CopyDetail(report->detail, sizeof(report->detail),
#if MCLA_DIRECT_METAL
                   "Hand-written MCLA Metal renderer: three completion-owned frame slots; no Vulkan, MoltenVK, generic command processor or fallback.");
#else
                   "Theft4 title-native renderer selected with MCLA shaders; generic Xenos command processing is disabled. Visual validation is in progress.");
#endif
    }
}

void MCLAGraphicsNoteDisplayPresentation(double presentedSeconds) {
    if (!mcla::DiagnosticsEnabled()) return;
    if (!(presentedSeconds > 0.0)) return;
    os_unfair_lock_lock(&gFrameTimingLock);
    if (gLastPresentedSeconds > 0.0) {
        const double milliseconds =
            (presentedSeconds - gLastPresentedSeconds) * 1000.0;
        // Ignore clock resets and lifecycle gaps, but preserve real missed
        // frames (66.7 ms, 100 ms, and so on) in the graph.
        if (milliseconds > 0.1 && milliseconds < 500.0) {
            gFrameTiming[gFrameTimingWrite] = {
                (float)milliseconds, gLatestGPUMilliseconds};
            gFrameTimingWrite = (gFrameTimingWrite + 1) % kFrameTimingCapacity;
            gFrameTimingCount =
                std::min(gFrameTimingCount + 1, kFrameTimingCapacity);
        }
    }
    gLastPresentedSeconds = presentedSeconds;
    os_unfair_lock_unlock(&gFrameTimingLock);
}

void MCLAGraphicsNoteGPUTime(double gpuMilliseconds) {
    if (!mcla::DiagnosticsEnabled()) return;
    if (!(gpuMilliseconds >= 0.0) || !std::isfinite(gpuMilliseconds)) return;
    os_unfair_lock_lock(&gFrameTimingLock);
    gLatestGPUMilliseconds = (float)gpuMilliseconds;
    os_unfair_lock_unlock(&gFrameTimingLock);
}

uint32_t MCLAGraphicsCopyFrameTiming(MCLAFrameTimingSample* samples,
                                     uint32_t capacity,
                                     float* framesPerSecond,
                                     float* latestGPUMilliseconds) {
    os_unfair_lock_lock(&gFrameTimingLock);
    const uint32_t copied = std::min(capacity, gFrameTimingCount);
    const uint32_t first =
        (gFrameTimingWrite + kFrameTimingCapacity - copied) %
        kFrameTimingCapacity;
    double recentMilliseconds = 0.0;
    const uint32_t recentCount = std::min(gFrameTimingCount, 60u);
    for (uint32_t i = 0; i < recentCount; ++i) {
        const uint32_t index =
            (gFrameTimingWrite + kFrameTimingCapacity - recentCount + i) %
            kFrameTimingCapacity;
        recentMilliseconds += gFrameTiming[index].frameMilliseconds;
    }
    if (samples) {
        for (uint32_t i = 0; i < copied; ++i)
            samples[i] = gFrameTiming[(first + i) % kFrameTimingCapacity];
    }
    if (framesPerSecond) {
        *framesPerSecond = recentMilliseconds > 0.0
            ? (float)(1000.0 * recentCount / recentMilliseconds) : 0.0f;
    }
    if (latestGPUMilliseconds)
        *latestGPUMilliseconds = gLatestGPUMilliseconds;
    os_unfair_lock_unlock(&gFrameTimingLock);
    return copied;
}

bool MCLAGraphicsStartPerformanceCapture(void) {
    if (!mcla::DiagnosticsEnabled()) return false;
    os_unfair_lock_lock(&gFrameTimingLock);
    if (gPerformanceActive) {
        os_unfair_lock_unlock(&gFrameTimingLock);
        return false;
    }
    gPerformanceRows.clear();
    gPerformanceRows.reserve(kPerformanceCaptureMaxRows);
    gGPUPassRows.clear();gGPUPassRows.reserve(kMaxGPUPassRows);gGPUPassRowsDropped=0;
    gPerformanceStart = CACurrentMediaTime();
    gPerformanceActive = true;
    gPerformanceActiveFast.store(true, std::memory_order_relaxed);
    gPerformanceSavedUntil = 0.0;
    const uint64_t generation = ++gPerformanceGeneration;
    os_unfair_lock_unlock(&gFrameTimingLock);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(kPerformanceCaptureSeconds * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            os_unfair_lock_lock(&gFrameTimingLock);
            const bool sameCapture = gPerformanceActive &&
                                     gPerformanceGeneration == generation;
            os_unfair_lock_unlock(&gFrameTimingLock);
            if (sameCapture) MCLAGraphicsFinishPerformanceCapture();
        });
    return true;
}

void MCLAGraphicsNotePerformanceFrame(const MCLAPerformanceFrame* frame) {
    if (!frame) return;
    const int thermal = int(NSProcessInfo.processInfo.thermalState);
    const bool lowPower = NSProcessInfo.processInfo.lowPowerModeEnabled;
    os_unfair_lock_lock(&gFrameTimingLock);
    if (gPerformanceActive && gPerformanceRows.size() < kPerformanceCaptureMaxRows) {
        const float displayMilliseconds = gFrameTimingCount
            ? gFrameTiming[(gFrameTimingWrite + kFrameTimingCapacity - 1) %
                           kFrameTimingCapacity].frameMilliseconds : 0.0f;
        gPerformanceRows.push_back({*frame,
            CACurrentMediaTime() - gPerformanceStart,
            displayMilliseconds, gLatestGPUMilliseconds, thermal, lowPower});
    }
    os_unfair_lock_unlock(&gFrameTimingLock);
}

bool MCLAGraphicsPerformanceCaptureActive(void) {
    return gPerformanceActiveFast.load(std::memory_order_relaxed);
}

// Rows are monotonic. Completion/presentation can arrive later or out of order;
// update the exact frame and leave -1 for genuinely unobserved callbacks.
void MCLAGraphicsNotePerformanceGPU(uint64_t frame, double gpuMilliseconds,
    double commitToGPUMilliseconds, double driverMilliseconds) {
    os_unfair_lock_lock(&gFrameTimingLock);
    auto row = std::lower_bound(gPerformanceRows.begin(), gPerformanceRows.end(), frame,
        [](const auto& r, uint64_t f) { return r.frame.frame < f; });
    if (gPerformanceActive && row != gPerformanceRows.end() && row->frame.frame == frame) {
        row->gpuMilliseconds = gpuMilliseconds;
        row->commitToGPUMilliseconds = commitToGPUMilliseconds;
        row->driverMilliseconds = driverMilliseconds;
    }
    os_unfair_lock_unlock(&gFrameTimingLock);
}

void MCLAGraphicsNoteGPUPasses(const MCLAGPUPassTiming* passes,uint32_t count) {
    if(!passes || !count)return;
    os_unfair_lock_lock(&gFrameTimingLock);
    auto row=std::lower_bound(gPerformanceRows.begin(),gPerformanceRows.end(),passes[0].frame,
        [](const auto& row,uint64_t id){return row.frame.frame<id;});
    if(gPerformanceActive && row!=gPerformanceRows.end() && row->frame.frame==passes[0].frame) {
        for(uint32_t i=0;i<count;++i) {
            if(passes[i].frame!=row->frame.frame)continue;
            if(gGPUPassRows.size()<kMaxGPUPassRows)gGPUPassRows.push_back(passes[i]);
            else ++gGPUPassRowsDropped;
        }
    }
    os_unfair_lock_unlock(&gFrameTimingLock);
}
void MCLAGraphicsNotePerformancePresented(uint64_t frame, double seconds) {
    os_unfair_lock_lock(&gFrameTimingLock);
    auto row = std::lower_bound(gPerformanceRows.begin(), gPerformanceRows.end(), frame,
        [](const auto& r, uint64_t f) { return r.frame.frame < f; });
    if (gPerformanceActive && row != gPerformanceRows.end() && row->frame.frame == frame)
        row->presentedSeconds = seconds;
    os_unfair_lock_unlock(&gFrameTimingLock);
}

double MCLAGraphicsPerformanceCaptureRemainingSeconds(void) {
    os_unfair_lock_lock(&gFrameTimingLock);
    const double now = CACurrentMediaTime();
    const double result = gPerformanceActive
        ? std::max(0.01, kPerformanceCaptureSeconds - (now - gPerformanceStart))
        : (now < gPerformanceSavedUntil ? 0.0 : -1.0);
    os_unfair_lock_unlock(&gFrameTimingLock);
    return result;
}

void MCLAGraphicsFinishPerformanceCapture(void) {
    std::vector<PerformanceCaptureRow> rows;
    std::vector<MCLAGPUPassTiming> passes;
    uint64_t droppedPassRows=0;
    double duration = 0.0;
    os_unfair_lock_lock(&gFrameTimingLock);
    if (!gPerformanceActive) {
        os_unfair_lock_unlock(&gFrameTimingLock);
        return;
    }
    duration = CACurrentMediaTime() - gPerformanceStart;
    rows.swap(gPerformanceRows);
    passes.swap(gGPUPassRows);droppedPassRows=gGPUPassRowsDropped;
    gPerformanceActive = false;
    gPerformanceActiveFast.store(false, std::memory_order_relaxed);
    gPerformanceSavedUntil = CACurrentMediaTime() + 8.0;
    os_unfair_lock_unlock(&gFrameTimingLock);

    // Formatting and filesystem I/O must not stall UIKit/input on the main
    // thread at the end of a capture. Freeze the output options with the rows.
    const bool fsrEnabled = MCLAGraphicsFSREnabled();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
    @autoreleasepool {
    NSString* documents = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString* directory = [documents stringByAppendingPathComponent:@"Diagnostics"];
    NSError* error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory
        withIntermediateDirectories:YES attributes:nil error:&error]) {
        if (mcla::DiagnosticsEnabled()) NSLog(@"MCLA performance capture directory failed: %@", error);
        return;
    }
    const long long timestamp = (long long)NSDate.date.timeIntervalSince1970;
    NSString* base = [directory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"mcla-performance-%lld", timestamp]];
    NSMutableString* csv = [NSMutableString stringWithString:
        @"seconds,frame,submit_ms,latest_display_ms,latest_completed_gpu_ms,"
        @"draws,resolves,failed_total,texture_checks_total,stale_textures_total,"
        @"decoded_textures_total,surfaces,textures,buffers,gpu_errors_total,"
        @"in_flight,scene_width,scene_height,output_width,output_height,touch_button_edges_total,"
        @"thermal_state,low_power,renderer_commands_cpu_ms,native_draw_cpu_ms,present_cpu_ms,"
        @"drawable_wait_ms,slot_wait_ms,previous_pacing_ms,constant_uploads_total,constant_reuses_total,upload_bytes,"
        @"paired_gpu_ms,commit_to_gpu_ms,driver_schedule_ms,paired_presented_seconds,"
        @"cache_maintenance_ms,resource_invalidation_ms,cache_evictions,invalidation_calls,"
        @"invalidated_keys,alias_removals,oldest_cache_age_frames,"
        @"attachment_reuses_total,pipeline_reuses_total,vertex_reuses_total,index_reuses_total,"
        @"texture_group_reuses_total,vertex_bind_skips_total,gpu_pass_trace_status,fsr_enabled,"
        @"submission_thread_wall_ms,submission_thread_cpu_ms,draw_profile_samples"];
    static const char* const drawStageNames[] = {
        "state", "pipeline", "dynamic", "vertices", "bindings", "indices",
        "constants", "textures", "encode"};
    for(const char* name:drawStageNames)
        [csv appendFormat:@",draw_%s_wall_us,draw_%s_cpu_us",name,name];
    [csv appendString:@"\n"];
    std::vector<double> submitTimes, displayTimes, gpuTimes;
    submitTimes.reserve(rows.size());
    displayTimes.reserve(rows.size());
    gpuTimes.reserve(rows.size());
    uint32_t maxInFlight = 0;
    unsigned slow40 = 0, slow60 = 0;
    std::array<unsigned,4> thermalCounts{};
    unsigned lowPowerFrames = 0, pairedGPUFrames = 0;
    std::vector<double> pairedGPU, commandCPU, drawCPU, drawableWait, slotWait;
    std::vector<double> maintenanceCPU, invalidationCPU;
    std::vector<double> submissionThreadCPU, submissionThreadWall,
                        submissionThreadNonCPU;
    uint64_t profiledDraws=0;
    uint64_t evictions=0,invalidations=0,invalidatedKeys=0,maxCacheAge=0;
    for (const auto& row : rows) {
        const auto& f = row.frame;
        [csv appendFormat:@"%.3f,%llu,%.3f,%.3f,%.3f,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%u,%u,%u,%u,%u,%llu",
            row.seconds, (unsigned long long)f.frame,
            f.submitMilliseconds, row.latestDisplayMilliseconds,
            row.latestCompletedGPUMilliseconds,
            (unsigned long long)f.draws, (unsigned long long)f.resolves,
            (unsigned long long)f.failedTotal,
            (unsigned long long)f.textureChecks,
            (unsigned long long)f.staleTextures,
            (unsigned long long)f.decodedTextures,
            (unsigned long long)f.surfaces,
            (unsigned long long)f.textures,
            (unsigned long long)f.buffers,
            (unsigned long long)f.gpuErrors,
            f.inFlight, f.sceneWidth, f.sceneHeight,
            f.outputWidth, f.outputHeight,
            (unsigned long long)f.touchButtonEdges];
        [csv appendFormat:@",%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%llu,%llu,%llu,%.3f,%.3f,%.3f,%.6f",
            row.thermalState,int(row.lowPower),f.rendererMilliseconds,f.nativeDrawMilliseconds,
            f.presentMilliseconds,f.drawableWaitMilliseconds,f.slotWaitMilliseconds,
            f.previousPacingMilliseconds,(unsigned long long)f.constantBankUploads,
            (unsigned long long)f.constantBankReuses,(unsigned long long)f.uploadBytes,
            row.gpuMilliseconds,row.commitToGPUMilliseconds,row.driverMilliseconds,row.presentedSeconds];
        [csv appendFormat:@",%.3f,%.3f,%llu,%llu,%llu,%llu,%llu",
            f.cacheMaintenanceMilliseconds,f.resourceInvalidationMilliseconds,
            (unsigned long long)f.cacheEvictions,(unsigned long long)f.invalidationCalls,
            (unsigned long long)f.invalidatedKeys,(unsigned long long)f.aliasRemovals,
            (unsigned long long)f.oldestCacheAgeFrames];
        [csv appendFormat:@",%llu,%llu,%llu,%llu,%llu,%llu,%d,%u,%.3f,%.3f,%u",
            (unsigned long long)f.attachmentReuses,(unsigned long long)f.pipelineReuses,
            (unsigned long long)f.vertexReuses,(unsigned long long)f.indexReuses,
            (unsigned long long)f.textureGroupReuses,(unsigned long long)f.vertexBindSkips,
            f.gpuPassTraceStatus,f.fsrEnabled,
            f.submissionThreadWallMilliseconds,f.submissionThreadCPUMilliseconds,
            f.drawProfileSamples];
        for(unsigned section=0;section<9;++section)
            [csv appendFormat:@",%.3f,%.3f",
                f.drawStageWallMicroseconds[section],
                f.drawStageCPUMicroseconds[section]];
        [csv appendString:@"\n"];
        maintenanceCPU.push_back(f.cacheMaintenanceMilliseconds);
        invalidationCPU.push_back(f.resourceInvalidationMilliseconds);
        if(f.submissionThreadCPUMilliseconds>=0 &&
           f.submissionThreadWallMilliseconds>=0) {
            submissionThreadCPU.push_back(f.submissionThreadCPUMilliseconds);
            submissionThreadWall.push_back(f.submissionThreadWallMilliseconds);
            submissionThreadNonCPU.push_back(std::max(0.0,
                double(f.submissionThreadWallMilliseconds-
                       f.submissionThreadCPUMilliseconds)));
        }
        profiledDraws+=f.drawProfileSamples;
        evictions+=f.cacheEvictions;invalidations+=f.invalidationCalls;
        invalidatedKeys+=f.invalidatedKeys;maxCacheAge=std::max(maxCacheAge,f.oldestCacheAgeFrames);
        if (row.thermalState >= 0 && row.thermalState < 4) ++thermalCounts[row.thermalState];
        lowPowerFrames += row.lowPower;
        if (row.gpuMilliseconds >= 0) { pairedGPU.push_back(row.gpuMilliseconds); ++pairedGPUFrames; }
        commandCPU.push_back(f.rendererMilliseconds); drawCPU.push_back(f.nativeDrawMilliseconds);
        drawableWait.push_back(f.drawableWaitMilliseconds); slotWait.push_back(f.slotWaitMilliseconds);
        if (f.submitMilliseconds > 0) submitTimes.push_back(f.submitMilliseconds);
        if (row.latestDisplayMilliseconds > 0) {
            displayTimes.push_back(row.latestDisplayMilliseconds);
            slow40 += row.latestDisplayMilliseconds > 40.0f;
            slow60 += row.latestDisplayMilliseconds > 60.0f;
        }
        if (row.latestCompletedGPUMilliseconds > 0)
            gpuTimes.push_back(row.latestCompletedGPUMilliseconds);
        maxInFlight = std::max(maxInFlight, f.inFlight);
    }
    auto percentile = [](std::vector<double>& values, double q) {
        if (values.empty()) return 0.0;
        std::sort(values.begin(), values.end());
        return values[std::min(values.size() - 1,
            size_t((values.size() - 1) * q))];
    };
    const uint64_t rejectedDelta = rows.size() > 1
        ? rows.back().frame.failedTotal - rows.front().frame.failedTotal : 0;
    const uint64_t staleDelta = rows.size() > 1
        ? rows.back().frame.staleTextures - rows.front().frame.staleTextures : 0;
    const uint64_t touchEdgeDelta = rows.size() > 1
        ? rows.back().frame.touchButtonEdges - rows.front().frame.touchButtonEdges : 0;
    NSMutableString* summary = [NSMutableString stringWithFormat:
        @"MCLA bounded gameplay diagnostics\nDuration: %.2f s; frames: %zu\n"
        @"Scene: %ux%u; output: %ux%u; FSR at save: %@ (per-frame fsr_enabled column is authoritative)\n"
        @"Submission interval p50/p95/max: %.2f / %.2f / %.2f ms\n"
        @"Latest displayed interval p50/p95/max: %.2f / %.2f / %.2f ms\n"
        @"Latest completed GPU p50/p95/max: %.2f / %.2f / %.2f ms\n"
        @"Displayed intervals >40 ms: %u; >60 ms: %u; max in flight: %u\n"
        @"Rejected draw delta: %llu; stale texture refresh delta: %llu; touch button edges: %llu\n"
        @"GPU timings/display intervals are latest completed samples, not exact-row pairs.\n"
        @"Correlate by time with Application Support/MCLA/runtime.log for shader/error detail.\n",
        duration, rows.size(), rows.empty() ? 0 : rows.back().frame.sceneWidth,
        rows.empty() ? 0 : rows.back().frame.sceneHeight,
        rows.empty() ? 0 : rows.back().frame.outputWidth,
        rows.empty() ? 0 : rows.back().frame.outputHeight,
        fsrEnabled ? @"on" : @"off",
        percentile(submitTimes, .5), percentile(submitTimes, .95),
        percentile(submitTimes, 1), percentile(displayTimes, .5),
        percentile(displayTimes, .95), percentile(displayTimes, 1),
        percentile(gpuTimes, .5), percentile(gpuTimes, .95),
        percentile(gpuTimes, 1), slow40, slow60, maxInFlight,
        (unsigned long long)rejectedDelta, (unsigned long long)staleDelta,
        (unsigned long long)touchEdgeDelta];
    [summary appendFormat:
        @"\nCapture schema: 5\nThermal frames: nominal=%u fair=%u serious=%u critical=%u; Low Power Mode=%u\n"
        @"Paired GPU p50/p95/max: %.2f / %.2f / %.2f ms (%u completed rows)\n"
        @"Renderer command CPU p50/p95: %.2f / %.2f ms\nNative draw CPU p50/p95: %.2f / %.2f ms\n"
        @"Drawable wait p50/p95: %.2f / %.2f ms; frame-slot wait p50/p95: %.2f / %.2f ms\n"
        @"thermal_state: 0=nominal, 1=fair, 2=serious, 3=critical (OS pressure, not temperature).\n"
        @"native_draw_cpu_ms includes renderer draws; renderer_commands_cpu_ms also includes clears/resolves. Do not add them.\n"
        @"CPU wall times include waits; first capture row may cover a partial CPU frame.\n"
        @"previous_pacing_ms belongs to the preceding Swap's sleep, contributing to this submission interval.\n"
        @"paired_* columns refer to this frame; -1 means callback not observed before capture ended.\n"
        @"commit_to_gpu_ms includes submission overhead/driver scheduling/queue delay, not pure GPU work.\n",
        thermalCounts[0],thermalCounts[1],thermalCounts[2],thermalCounts[3],lowPowerFrames,
        percentile(pairedGPU,.5),percentile(pairedGPU,.95),percentile(pairedGPU,1),pairedGPUFrames,
        percentile(commandCPU,.5),percentile(commandCPU,.95),percentile(drawCPU,.5),percentile(drawCPU,.95),
        percentile(drawableWait,.5),percentile(drawableWait,.95),percentile(slotWait,.5),percentile(slotWait,.95)];
    [summary appendFormat:
        @"Submission-thread wall p50/p95: %.2f / %.2f ms; execution CPU p50/p95: %.2f / %.2f ms (%zu valid frames).\n"
        @"Non-CPU wall p50/p95: %.2f / %.2f ms, includes previous frame pacing, waits and descheduling.\n"
        @"Draw preparation profiled every 64th successful draw: %llu samples. Stage wall/CPU microseconds in CSV are per-frame sample means.\n"
        @"Binding stage includes constants, textures and encode; do not add those sub-stages to binding.\n"
        @"Submission-thread interval spans prior Present return to current Present entry; it includes game/adapter work and prior pacing but excludes current presentation. First row may be invalid.\n",
        percentile(submissionThreadWall,.5),percentile(submissionThreadWall,.95),
        percentile(submissionThreadCPU,.5),percentile(submissionThreadCPU,.95),
        submissionThreadCPU.size(),percentile(submissionThreadNonCPU,.5),
        percentile(submissionThreadNonCPU,.95),
        (unsigned long long)profiledDraws];
    [summary appendFormat:
        @"Cache maintenance CPU p50/p95/max: %.3f / %.3f / %.3f ms; evicted keys: %llu\n"
        @"Resource invalidation CPU p50/p95/max: %.3f / %.3f / %.3f ms; calls: %llu; invalidated keys: %llu\n"
        @"Oldest retained cache age max: %llu frames (retention 1800, soft cleanup budget 0.5 ms/frame, cap 128 keys).\n"
        @"Maintenance is included in present_cpu_ms; invalidation is included in renderer_commands_cpu_ms. Do not add twice.\n"
        @"Invalidation time covers resource write/release commands; invalidated_keys also counts source textures replaced by resolves.\n"
        @"A single resource destruction can exceed the soft budget; watch cache age/counts for a cleanup backlog.\n",
        percentile(maintenanceCPU,.5),percentile(maintenanceCPU,.95),percentile(maintenanceCPU,1),
        (unsigned long long)evictions,percentile(invalidationCPU,.5),percentile(invalidationCPU,.95),
        percentile(invalidationCPU,1),(unsigned long long)invalidations,(unsigned long long)invalidatedKeys,
        (unsigned long long)maxCacheAge];
    NSMutableString* passCSV=[NSMutableString stringWithString:
        @"frame,pass,kind,width,height,format,draws,first_vs,first_ps,mixed_shaders,"
        @"vertex_start_tick,vertex_end_tick,fragment_start_tick,fragment_end_tick,ms_per_tick,vertex_ms,fragment_ms,span_ms\n"];
    for(const auto& p:passes) {
        [passCSV appendFormat:@"%llu,%u,%s,%u,%u,%u,%u,%016llX,%016llX,%u,%llu,%llu,%llu,%llu,%.12g,%.6f,%.6f,%.6f\n",
            (unsigned long long)p.frame,p.pass,p.kind,p.width,p.height,p.format,p.draws,
            (unsigned long long)p.vertexShader,(unsigned long long)p.pixelShader,p.mixedShaders,
            (unsigned long long)p.ticks[0],(unsigned long long)p.ticks[1],
            (unsigned long long)p.ticks[2],(unsigned long long)p.ticks[3],p.millisecondsPerTick,
            p.vertexMilliseconds,p.fragmentMilliseconds,p.spanMilliseconds];
    }
    [summary appendFormat:@"GPU pass rows: %lu; dropped by capture cap: %llu. Sparse (one in 30 frames), max 512 passes/sample.\n"
        @"Trace status: 0 unsampled, 1 sampled, 2 pass cap reached, -1 unsupported, -2 allocation failed. Missing/invalid timing = -1.\n"
        @"Stages/passes may overlap: DO NOT sum as frame GPU time. Use paired_gpu_ms for total GPU time.\n"
        @"Guest pass labels do not assert scene/shadow/reflection identity; correlate target dimensions and first shader IDs. mixed_shaders=2 means blit.\n",
        (unsigned long)passes.size(),(unsigned long long)droppedPassRows];
    BOOL wrotePasses=[passCSV writeToFile:[base stringByAppendingString:@"-gpu-passes.csv"]
        atomically:YES encoding:NSUTF8StringEncoding error:&error];
    BOOL wroteCSV = [csv writeToFile:[base stringByAppendingPathExtension:@"csv"]
        atomically:YES encoding:NSUTF8StringEncoding error:&error];
    BOOL wroteSummary = [summary writeToFile:[base stringByAppendingPathExtension:@"txt"]
        atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (mcla::DiagnosticsEnabled()) NSLog(@"MCLA performance capture %@: %@", wroteCSV && wroteSummary && wrotePasses
        ? @"saved" : @"failed", base);
    }
    });
}
