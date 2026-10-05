#include <rex/ppc.h>
#include <rex/memory.h>

#include <atomic>
#include <algorithm>
#include <bit>
#include <cmath>
#include <vector>

#include "MCLAAppleGraphicsHooks.h"
#include "MCLAGraphicsFoundation.h"
#include "MCLANativeTitleBridge.h"
#include "MCLANativeRenderer.h"

namespace {

std::atomic<uint64_t> gDrawIndexed{0};
std::atomic<uint64_t> gDraw{0};
std::atomic<uint64_t> gBeginVertices{0};
std::atomic<uint64_t> gEndVertices{0};
std::atomic<uint64_t> gBeginTiling{0};
std::atomic<uint64_t> gEndTiling{0};
std::atomic<uint64_t> gResolves{0};
std::atomic<uint64_t> gFrameEnds{0};
std::atomic<uint64_t> gSwaps{0};
std::atomic<uint64_t> gClears{0};
std::atomic<uint64_t> gIdleBypasses{0};
std::atomic<uint64_t> gNativePresents{0};
std::atomic<uint32_t> gInlinePrimitive{0};
std::atomic<uint32_t> gInlineVertexCount{0};
std::atomic<uint32_t> gInlineStride{0};
std::atomic<uint32_t> gInlineBuffer{0};
std::atomic<uint32_t> gInlineWords[4]{};
std::atomic<uint32_t> gInlineChecksum{0};
std::atomic<const char*> gLastHook{"(none)"};

struct PendingInlineDraw {
    uint32_t device = 0;
    uint32_t primitive = 0;
    uint32_t count = 0;
    uint32_t stride = 0;
    uint32_t buffer = 0;
};
thread_local PendingInlineDraw gPendingInline;

uint32_t LoadGuestU32(uint8_t* base, uint32_t address) {
    const auto* value = rex::memory::GuestPtr<const uint32_t*>(base, address);
    return __builtin_bswap32(*value);
}

#define MCLA_OBSERVED_FORWARD(name, counter)                                  \
    extern "C" REX_FUNC(rex_generated_##name);                               \
    extern "C" REX_FUNC(name) {                                              \
        gLastHook.store(#name, std::memory_order_relaxed);                    \
        counter.fetch_add(1, std::memory_order_relaxed);                      \
        rex_generated_##name(ctx, base);                                      \
    }

}  // namespace

extern "C" REX_FUNC(rex_generated_D3DDevice_DrawIndexedVertices);
extern "C" REX_FUNC(D3DDevice_DrawIndexedVertices) {
    gLastHook.store("D3DDevice_DrawIndexedVertices", std::memory_order_relaxed);
    gDrawIndexed.fetch_add(1, std::memory_order_relaxed);
    // Capture before the generated D3D path flushes constant/fetch dirtiness.
    MCLANativeTitleBridgeDraw(base, ctx.r3.u32, ctx.r4.u32, ctx.r7.u32,
                              ctx.r6.u32, int32_t(ctx.r5.u32), true);
#if !MCLA_NATIVE_TITLE
    rex_generated_D3DDevice_DrawIndexedVertices(ctx, base);
#endif
}

extern "C" REX_FUNC(rex_generated_D3DDevice_DrawVertices);
extern "C" REX_FUNC(D3DDevice_DrawVertices) {
    gLastHook.store("D3DDevice_DrawVertices", std::memory_order_relaxed);
    gDraw.fetch_add(1, std::memory_order_relaxed);
    MCLANativeTitleBridgeDraw(base, ctx.r3.u32, ctx.r4.u32, ctx.r6.u32,
                              ctx.r5.u32, 0, false);
#if !MCLA_NATIVE_TITLE
    rex_generated_D3DDevice_DrawVertices(ctx, base);
#endif
}

extern "C" REX_FUNC(rex_generated_D3DDevice_BeginTiling);
extern "C" REX_FUNC(D3DDevice_BeginTiling) {
    gLastHook.store("D3DDevice_BeginTiling", std::memory_order_relaxed);
    gBeginTiling.fetch_add(1, std::memory_order_relaxed);
    MCLANativeTitleBridgeBeginTiling(ctx.r3.u32, ctx.r4.u32, ctx.r5.u32);
#if MCLA_NATIVE_TITLE
    MCLANativeBeginTiling(base, ctx.r3.u32, ctx.r5.u32, ctx.r6.u32);
#endif
    rex_generated_D3DDevice_BeginTiling(ctx, base);
}

extern "C" REX_FUNC(rex_generated_D3DDevice_EndTiling);
extern "C" REX_FUNC(D3DDevice_EndTiling) {
    gLastHook.store("D3DDevice_EndTiling", std::memory_order_relaxed);
    gEndTiling.fetch_add(1, std::memory_order_relaxed);
    const uint32_t device = ctx.r3.u32;
    const uint32_t flags = ctx.r4.u32;
    const uint32_t destinationTexture = ctx.r6.u32;
    rex_generated_D3DDevice_EndTiling(ctx, base);
    MCLANativeTitleBridgeEndTiling(device, flags, destinationTexture);
}

extern "C" REX_FUNC(rex_generated_D3DDevice_Resolve);
extern "C" REX_FUNC(D3DDevice_Resolve) {
    gLastHook.store("D3DDevice_Resolve", std::memory_order_relaxed);
    gResolves.fetch_add(1, std::memory_order_relaxed);
    const uint32_t device = ctx.r3.u32;
    const uint32_t flags = ctx.r4.u32;
    const uint32_t sourceRect = ctx.r5.u32;
    const uint32_t destinationTexture = ctx.r6.u32;
    const uint32_t destinationPoint = ctx.r7.u32;
    const uint32_t clearColor = ctx.r10.u32;
#if MCLA_NATIVE_TITLE
    uint32_t stencil = 0, parameters = 0;
    if (MCLANativeResolveStackArguments(base, ctx.r1.u32, &stencil, &parameters)) {
        const bool accepted = MCLANativeResolve(base, device, flags, sourceRect, destinationTexture,
            destinationPoint, ctx.r8.u32, ctx.r9.u32, clearColor, ctx.f1.f64,
            stencil, parameters);
        ctx.r3.u64 = accepted ? 0 : 0x80070057u;
    } else {
        ctx.r3.u64 = 0x80070057u;
    }
    return;
#endif
    rex_generated_D3DDevice_Resolve(ctx, base);
    MCLANativeTitleBridgeResolve(device, flags, sourceRect,
                                 destinationTexture, destinationPoint,
                                 clearColor);
}

extern "C" REX_FUNC(rex_generated_grcDevice_EndFrame);
extern "C" REX_FUNC(grcDevice_EndFrame) {
    gLastHook.store("grcDevice_EndFrame", std::memory_order_relaxed);
    gFrameEnds.fetch_add(1, std::memory_order_relaxed);
    const uint32_t device = ctx.r3.u32;
    rex_generated_grcDevice_EndFrame(ctx, base);
    MCLANativeTitleBridgeFrameEnd(device);
}

extern "C" REX_FUNC(rex_generated_rex_sub_824195E8);
extern "C" REX_FUNC(rex_sub_824195E8) {
    gLastHook.store("rex_sub_824195E8", std::memory_order_relaxed);
    gClears.fetch_add(1, std::memory_order_relaxed);
#if MCLA_NATIVE_TITLE
    MCLANativeClear(base, ctx.r3.u32, ctx.r4.u32, ctx.r5.u32,
                    ctx.r6.u32, ctx.r7.u32,
                    float(ctx.f1.f64), ctx.r9.u32);
    ctx.r3.u64 = 0;
    return;
#endif
    MCLANativeTitleBridgeClear(base, ctx.r3.u32, ctx.r6.u32, ctx.r7.u32,
                               float(ctx.f1.f64), ctx.r9.u32);
    rex_generated_rex_sub_824195E8(ctx, base);
}

extern "C" REX_FUNC(rex_generated_D3DDevice_BeginVertices);
extern "C" REX_FUNC(D3DDevice_BeginVertices) {
    gLastHook.store("D3DDevice_BeginVertices", std::memory_order_relaxed);
    gBeginVertices.fetch_add(1, std::memory_order_relaxed);
    const uint32_t device = ctx.r3.u32;
    const uint32_t primitive = ctx.r4.u32;
    const uint32_t count = ctx.r5.u32;
    const uint32_t stride = ctx.r6.u32;
    rex_generated_D3DDevice_BeginVertices(ctx, base);
    gPendingInline = {device, primitive, count, stride, ctx.r3.u32};
}

extern "C" REX_FUNC(rex_generated_D3DDevice_EndVertices);
extern "C" REX_FUNC(D3DDevice_EndVertices) {
    gLastHook.store("D3DDevice_EndVertices", std::memory_order_relaxed);
    gEndVertices.fetch_add(1, std::memory_order_relaxed);
    rex_generated_D3DDevice_EndVertices(ctx, base);

    const PendingInlineDraw draw = gPendingInline;
    if (!draw.buffer || !draw.count || !draw.stride) {
        return;
    }
    gInlinePrimitive.store(draw.primitive, std::memory_order_relaxed);
    gInlineVertexCount.store(draw.count, std::memory_order_relaxed);
    gInlineStride.store(draw.stride, std::memory_order_relaxed);
    gInlineBuffer.store(draw.buffer, std::memory_order_relaxed);
    uint32_t checksum = 2166136261u;
    const uint32_t bytes = std::min<uint32_t>(draw.count * draw.stride, 256u);
    const uint32_t words = bytes / 4u;
    for (uint32_t i = 0; i < words; ++i) {
        const uint32_t word = LoadGuestU32(base, draw.buffer + i * 4u);
        checksum = (checksum ^ word) * 16777619u;
        if (i < 4) {
            gInlineWords[i].store(word, std::memory_order_relaxed);
        }
    }
    gInlineChecksum.store(checksum, std::memory_order_release);
    MCLANativeTitleBridgeInlineDraw(base, draw.device, draw.primitive,
                                    draw.count, draw.stride, draw.buffer);
#if MCLA_NATIVE_TITLE
    gPendingInline = {};
    return;
#endif

    // Primitive 4 is the title's triangle-list path. Preserve MCLA's own
    // screen-space positions and batch them for the next real Swap. Color is
    // diagnostic until the bound declaration/shader state is translated.
    if (draw.primitive == 4 && draw.count >= 3 && draw.count <= 4096 &&
        draw.stride >= 12) {
        std::vector<MCLAInlineVertex> vertices;
        vertices.reserve(draw.count);
        const float red = 0.25f + float((checksum >> 16) & 0xFFu) / 510.0f;
        const float green = 0.25f + float((checksum >> 8) & 0xFFu) / 510.0f;
        const float blue = 0.25f + float(checksum & 0xFFu) / 510.0f;
        for (uint32_t i = 0; i < draw.count; ++i) {
            const uint32_t vertex = draw.buffer + i * draw.stride;
            const float x = std::bit_cast<float>(LoadGuestU32(base, vertex));
            const float y = std::bit_cast<float>(LoadGuestU32(base, vertex + 4));
            const float z = std::bit_cast<float>(LoadGuestU32(base, vertex + 8));
            if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z) ||
                std::abs(x) > 8192.0f || std::abs(y) > 8192.0f) {
                vertices.clear();
                break;
            }
            vertices.push_back({x, y, z, red, green, blue, 0.38f});
        }
        if (!vertices.empty()) {
            MCLAGraphicsSubmitInlineTriangles(vertices.data(),
                                               uint32_t(vertices.size()));
        }
    }
    gPendingInline = {};
}

extern "C" REX_FUNC(rex_generated_D3DDevice_Swap);
extern "C" REX_FUNC(D3DDevice_Swap) {
    gLastHook.store("D3DDevice_Swap", std::memory_order_relaxed);
    const uint64_t frame = gSwaps.fetch_add(1, std::memory_order_relaxed) + 1;
    const uint32_t device = ctx.r3.u32;
#if MCLA_NATIVE_TITLE
    if (MCLANativePresent(base, device, ctx.r4.u32)) ++gNativePresents;
    ctx.r3.u64 = 0;
    return;
#endif
    rex_generated_D3DDevice_Swap(ctx, base);
    MCLANativeTitleBridgeSwap(device);
#if !MCLA_XENOS_RUNTIME_LINKED
    // This call is intentionally attached to MCLA's real swap, not a UIKit
    // timer. It is the first proof that the title can drive the Metal path.
    if (MCLAGraphicsPresentTitleDiagnostic(
            frame, gEndVertices.load(std::memory_order_relaxed),
            gResolves.load(std::memory_order_relaxed))) {
        gNativePresents.fetch_add(1, std::memory_order_relaxed);
    }
#else
    (void)frame;
#endif
}

// With the Apple native path owning guest-visible completion, there is no
// emulated command processor to wait for. The original function spins first on
// a fence and then on D3DDevice+11008, a word only an Xbox GPU would clear.
// Returning immediately is the title-verified LARecomp no-CP behavior.
#if MCLA_XENOS_RUNTIME_LINKED && !MCLA_NATIVE_TITLE
MCLA_OBSERVED_FORWARD(D3DDevice_BlockUntilIdle, gIdleBypasses)
#else
extern "C" REX_FUNC(D3DDevice_BlockUntilIdle) {
    gLastHook.store("D3DDevice_BlockUntilIdle", std::memory_order_relaxed);
    gIdleBypasses.fetch_add(1, std::memory_order_relaxed);
}
#endif

void MCLAGetAppleGraphicsHookReport(MCLAAppleGraphicsHookReport* report) {
    if (!report) {
        return;
    }
    report->drawIndexed = gDrawIndexed.load(std::memory_order_relaxed);
    report->draw = gDraw.load(std::memory_order_relaxed);
    report->beginVertices = gBeginVertices.load(std::memory_order_relaxed);
    report->endVertices = gEndVertices.load(std::memory_order_relaxed);
    report->beginTiling = gBeginTiling.load(std::memory_order_relaxed);
    report->endTiling = gEndTiling.load(std::memory_order_relaxed);
    report->resolves = gResolves.load(std::memory_order_relaxed);
    report->frameEnds = gFrameEnds.load(std::memory_order_relaxed);
    report->swaps = gSwaps.load(std::memory_order_relaxed);
    report->clears = gClears.load(std::memory_order_relaxed);
    report->idleBypasses = gIdleBypasses.load(std::memory_order_relaxed);
    report->nativePresents = gNativePresents.load(std::memory_order_relaxed);
    report->inlinePrimitive = gInlinePrimitive.load(std::memory_order_relaxed);
    report->inlineVertexCount = gInlineVertexCount.load(std::memory_order_relaxed);
    report->inlineStride = gInlineStride.load(std::memory_order_relaxed);
    report->inlineBuffer = gInlineBuffer.load(std::memory_order_relaxed);
    for (uint32_t i = 0; i < 4; ++i) {
        report->inlineWords[i] = gInlineWords[i].load(std::memory_order_relaxed);
    }
    report->inlineChecksum = gInlineChecksum.load(std::memory_order_acquire);
    report->lastHook = gLastHook.load(std::memory_order_relaxed);
}

#undef MCLA_OBSERVED_FORWARD

#if MCLA_NATIVE_TITLE
extern "C" REX_FUNC(rex_generated_rex_sub_82421F38);
extern "C" REX_FUNC(rex_sub_82421F38) {
    MCLANativeResourceUnlock(base, ctx.r3.u32, ctx.r5.u32, ctx.lr);
    rex_generated_rex_sub_82421F38(ctx, base);
}

extern "C" REX_FUNC(rex_generated_D3DResource_Release);
extern "C" REX_FUNC(D3DResource_Release) {
    const uint32_t resource = ctx.r3.u32;
    rex_generated_D3DResource_Release(ctx, base);
    if (!ctx.r3.u32) MCLANativeResourceRelease(resource);
}
#endif
