#pragma once

#include <cstdint>

// MCLA's title-native front end. The generated game calls these functions at
// the high-level D3D entry points, before the fallback command processor turns
// them into PM4 packets. The bridge owns a bounded, non-blocking command stream
// that the Apple renderer can consume without parsing an emulated ring buffer.

struct MCLANativeTitleBridgeReport {
    uint64_t submitted = 0;
    uint64_t processed = 0;
    uint64_t dropped = 0;
    uint64_t drawIndexed = 0;
    uint64_t draw = 0;
    uint64_t inlineDraw = 0;
    uint64_t clears = 0;
    uint64_t resolves = 0;
    uint64_t frameEnds = 0;
    uint64_t swaps = 0;
    uint64_t uniqueShaderPairs = 0;
    uint64_t captureRecords = 0;
    uint64_t capturedShaders = 0;
    uint64_t captureFailures = 0;
    uint64_t metadataHits = 0;
    uint64_t metadataMisses = 0;
    uint64_t shaderPackHits = 0;
    uint64_t shaderPackMisses = 0;
    uint64_t shaderMatchedDraws = 0;
    uint64_t shaderIncompleteDraws = 0;
    uint32_t metadataShaders = 0;
    uint32_t metadataElements = 0;
    uint32_t lastMetadataElements = 0;
    uint32_t shaderPackVertexShaders = 0;
    uint32_t shaderPackPixelShaders = 0;
    uint32_t shaderPackProvisionalShaders = 0;
    uint32_t shaderPackBytes = 0;
    uint32_t lastVertexSpirvBytes = 0;
    uint32_t lastPixelSpirvBytes = 0;
    uint64_t lastVertexShader = 0;
    uint64_t lastPixelShader = 0;
    uint32_t lastDevice = 0;
    uint32_t lastValidVertexFetches = 0;
    uint32_t queueDepth = 0;
    uint32_t queueHighWatermark = 0;
};

// Sets the app-container directory used for the title-native corpus. Draw
// hooks only copy deduplicated state; filesystem work stays on the bridge's
// consumer thread.
void MCLANativeTitleBridgeSetCaptureRoot(const char* path);

// Loads the compact host-built map captured from MCLA's own VertexShader
// descriptors. Values returned by CopyVertexElements use LARecomp's existing
// packed layout: instruction address[0:11], usage[12:15], usage index[16:19].
// This is the MCLA-specific geometry ABI presented to the future native draw
// consumer; the generic Xenos fallback does not use it.
bool MCLANativeTitleBridgeSetMetadataPath(const char* path);
uint32_t MCLANativeTitleBridgeCopyVertexElements(uint64_t shaderIdentity,
                                                 uint32_t* output,
                                                 uint32_t capacity);

// Loads the MCLA-only, offline-compiled SPIR-V corpus. CopyShaderSpirv returns
// the required byte count and copies up to capacityBytes when output is not
// null. The first corpus remains explicitly provisional until its integer
// definition constants are recovered, so loading it cannot enable takeover.
bool MCLANativeTitleBridgeSetShaderPackPath(const char* path);
uint32_t MCLANativeTitleBridgeCopyShaderSpirv(uint64_t shaderIdentity,
                                              bool pixelShader,
                                              void* output,
                                              uint32_t capacityBytes);

void MCLANativeTitleBridgeDraw(const uint8_t* base, uint32_t device,
                               uint32_t primitive, uint32_t count,
                               uint32_t start, int32_t baseVertex,
                               bool indexed);
void MCLANativeTitleBridgeInlineDraw(const uint8_t* base, uint32_t device,
                                     uint32_t primitive, uint32_t count,
                                     uint32_t stride, uint32_t buffer);
void MCLANativeTitleBridgeClear(const uint8_t* base, uint32_t device,
                                uint32_t flags, uint32_t color,
                                float depth, uint32_t stencil);
void MCLANativeTitleBridgeBeginTiling(uint32_t device, uint32_t flags,
                                      uint32_t tiles);
void MCLANativeTitleBridgeEndTiling(uint32_t device, uint32_t flags,
                                    uint32_t destinationTexture);
void MCLANativeTitleBridgeResolve(uint32_t device, uint32_t flags,
                                  uint32_t sourceRect,
                                  uint32_t destinationTexture,
                                  uint32_t destinationPoint,
                                  uint32_t clearColor);
void MCLANativeTitleBridgeFrameEnd(uint32_t device);
void MCLANativeTitleBridgeSwap(uint32_t device);
void MCLANativeTitleBridgeGetReport(MCLANativeTitleBridgeReport* report);
void MCLANativeTitleBridgeShutdown();
