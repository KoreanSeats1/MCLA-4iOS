#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// UIKit owns the CAMetalLayer. The graphics foundation retains it only while
// bound, keeping Objective-C and view ownership out of the future Xenos
// command processor.
void MCLAGraphicsBindMetalLayer(void* layer);
void MCLAGraphicsUnbindMetalLayer(void* layer);
void MCLAGraphicsResizeMetalLayer(void* layer, double width, double height,
                                  double scale);
bool MCLAGraphicsHasMetalLayer(void);
void MCLAGraphicsSetApplicationActive(bool active);
bool MCLAGraphicsApplicationActive(void);
// Guest submission threads sleep while inactive. UIKit callers never block.
bool MCLAGraphicsWaitForApplicationActive(void);
// Borrowed UIKit-owned CAMetalLayer and its stable 720p drawable size. These
// are the only presentation details exposed to the generic Xenos/Vulkan
// backend; the command processor never owns a UIView.
void* MCLAGraphicsBoundMetalLayer(void);
bool MCLAGraphicsBoundLayerSize(uint32_t* width, uint32_t* height);
// Configure at title startup. Height stays fixed during play; FSR may be switched
// separately through MCLAGraphicsSetFSREnabled without changing scene/output size.
void MCLAGraphicsConfigureOutput(uint32_t renderHeight, bool fsrEnabled);
void MCLAGraphicsConfigureNativeAspect(uint32_t nativeWidth,
                                       uint32_t nativeHeight, bool enabled);
void MCLAGraphicsGuestVideoSize(uint32_t* width, uint32_t* height);
uint32_t MCLAGraphicsRenderHeight(void);
bool MCLAGraphicsFSREnabled(void);
// Launch-time post-effect preference, read by both guest motion-blur hooks.
void MCLAGraphicsSetMotionBlurDisabled(bool disabled);
bool MCLAGraphicsMotionBlurDisabled(void);
void MCLAGraphicsSetDepthOfFieldDisabled(bool disabled);
bool MCLAGraphicsDepthOfFieldDisabled(void);
// Launch-only: skip startup movies while retaining gameplay cinematics.
void MCLAGraphicsSetSkipIntro(bool enabled);
bool MCLAGraphicsSkipIntro(void);
// Launch-only: one rate controls guest timing and both host pacers.
void MCLAGraphicsSetExperimental60FPS(bool enabled);
bool MCLAGraphicsExperimental60FPS(void);
uint32_t MCLAGraphicsFrameRate(void);
void MCLAGraphicsSetVisualExperiments(uint32_t experiments);
uint32_t MCLAGraphicsVisualExperiments(void);
// Live presentation-only switch; scene resolution/aspect remain unchanged.
void MCLAGraphicsSetFSREnabled(bool enabled);

typedef struct MCLAGraphicsReport {
    bool metalPresenterReady;
    bool rexglueSourceStaged;
    bool nativeRendererCoreReady;
    bool xenosRuntimeLinked;
    bool titleAOTLinked;
    uint32_t drawableWidth;
    uint32_t drawableHeight;
    uint32_t maximumFramesInFlight;
    uint64_t submittedFrames;
    uint64_t completedFrames;
    uint64_t titleDrivenFrames;
    uint64_t titleInlineVertices;
    char detail[256];
} MCLAGraphicsReport;

typedef struct MCLAInlineVertex {
    float x;
    float y;
    float z;
    float red;
    float green;
    float blue;
    float alpha;
} MCLAInlineVertex;

bool MCLAGraphicsPresentBringupFrame(double red, double green, double blue,
                                     double alpha);
// Presents a native Metal frame at MCLA's real D3DDevice_Swap boundary. The
// first implementation is deliberately a 3D diagnostic scene: it proves the
// title's frame loop can drive the reused native presenter before guest shader
// and vertex translation are connected.
bool MCLAGraphicsPresentTitleDiagnostic(uint64_t guestFrame,
                                        uint64_t immediateVertices,
                                        uint64_t resolves);
void MCLAGraphicsSubmitInlineTriangles(const MCLAInlineVertex* vertices,
                                       uint32_t vertexCount);
void MCLAGraphicsGetReport(MCLAGraphicsReport* report);
// Actual drawable presentation cadence from CAMetalDrawable.presentedTime.
// The UI copies this bounded history for its optional performance overlay;
// it never estimates game FPS from UIKit refresh callbacks.
typedef struct MCLAFrameTimingSample {
    float frameMilliseconds;
    float gpuMilliseconds;
} MCLAFrameTimingSample;
void MCLAGraphicsNoteDisplayPresentation(double presentedSeconds);
void MCLAGraphicsNoteGPUTime(double gpuMilliseconds);
uint32_t MCLAGraphicsCopyFrameTiming(MCLAFrameTimingSample* samples,
                                     uint32_t capacity,
                                     float* framesPerSecond,
                                     float* latestGPUMilliseconds);
// Direct renderer publication; completion must be called from the GPU fence.
void MCLAGraphicsNoteMetalSubmission(void);
void MCLAGraphicsNoteMetalCompletion(bool presented);

// Bounded, low-overhead gameplay diagnostic triggered by double-tapping the
// frame-time graph. No GPU readback; normal play does not record these rows.
typedef struct MCLAPerformanceFrame {
    uint64_t frame, draws, failedTotal, resolves, textureChecks, staleTextures;
    uint64_t decodedTextures, surfaces, textures, buffers, gpuErrors;
    uint64_t touchButtonEdges;
    uint32_t inFlight, sceneWidth, sceneHeight, outputWidth, outputHeight;
    float submitMilliseconds;
    float rendererMilliseconds, nativeDrawMilliseconds;
    float presentMilliseconds, drawableWaitMilliseconds, slotWaitMilliseconds;
    float previousPacingMilliseconds;
    uint64_t constantBankUploads, constantBankReuses, uploadBytes;
    float cacheMaintenanceMilliseconds, resourceInvalidationMilliseconds;
    uint64_t cacheEvictions, invalidationCalls, invalidatedKeys, aliasRemovals;
    uint64_t oldestCacheAgeFrames;
    uint64_t attachmentReuses, pipelineReuses, vertexReuses, indexReuses;
    uint64_t textureGroupReuses, vertexBindSkips;
    int32_t gpuPassTraceStatus; // 0 unsampled, 1 sampled, 2 capped, -1 unsupported, -2 allocation failed
    uint32_t fsrEnabled; // Actual presentation mode for this frame, supports live A/B.
    // One submission thread, from the previous Present return through the
    // current Present entry. Includes previous frame pacing; -1 if unavailable.
    float submissionThreadWallMilliseconds, submissionThreadCPUMilliseconds;
    uint32_t drawProfileSamples; // Every 64th successful draw, capture only.
    // Per sampled draw in microseconds. Stage 4 (bindings) contains stages 6–8.
    float drawStageWallMicroseconds[9], drawStageCPUMicroseconds[9];
} MCLAPerformanceFrame;
typedef struct MCLAGPUPassTiming {
    uint64_t frame, vertexShader, pixelShader;
    uint32_t pass, width, height, format, draws, mixedShaders;
    char kind[32];
    uint64_t ticks[4];
    double millisecondsPerTick, vertexMilliseconds, fragmentMilliseconds, spanMilliseconds;
} MCLAGPUPassTiming;
void MCLAGraphicsNoteGPUPasses(const MCLAGPUPassTiming* passes, uint32_t count);
bool MCLAGraphicsStartPerformanceCapture(void);
bool MCLAGraphicsPerformanceCaptureActive(void);
void MCLAGraphicsNotePerformanceFrame(const MCLAPerformanceFrame* frame);
// Completion data is joined by frame ID, never assigned to a later CPU row.
void MCLAGraphicsNotePerformanceGPU(uint64_t frame, double gpuMilliseconds,
    double commitToGPUMilliseconds, double driverMilliseconds);
void MCLAGraphicsNotePerformancePresented(uint64_t frame, double seconds);
void MCLAGraphicsFinishPerformanceCapture(void);
// -1 = idle, 0 = recently saved, positive = seconds remaining.
double MCLAGraphicsPerformanceCaptureRemainingSeconds(void);

#ifdef __cplusplus
}
#endif
