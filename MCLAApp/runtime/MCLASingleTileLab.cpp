#include <rex/logging.h>
#include <rex/ppc/context.h>

#include <atomic>
#include <cstdint>

namespace {
constexpr uint32_t kGuestTileCountAddress = 0x827D42A4;
constexpr uint32_t kVirtualEdramTiles = 4096;
std::atomic<uint64_t> gPrimaryScenes{0};
std::atomic<uint64_t> gOffscreenPasses{0};
std::atomic<uint64_t> gUnexpectedDimensions{0};
std::atomic<uint64_t> gEdramBypasses{0};
std::atomic<uint64_t> gEdramOverLimit{0};
}  // namespace

// The Lab uses its own generated AOT copies. No change is made to the
// working MCLA app's generated hook sites. r17 preserves the guest render
// target argument; the upstream fix allows only the r17 == 0 main scene.
void MCLASingleTileLabBegin(PPCRegister& r7, PPCRegister& r8, const PPCRegister& r17,
                            const PPCRegister& r25, const PPCRegister& r28, uint8_t* base) {
    const uint32_t width = r28.u32;
    const uint32_t height = r25.u32;
    const uint32_t tileWidth = r7.u32;
    const uint32_t tileHeight = r8.u32;
    if (r17.u32 != 0) {
        const auto skipped = gOffscreenPasses.fetch_add(1, std::memory_order_relaxed) + 1;
        if (skipped <= 4 || skipped % 120 == 0) {
            REXLOG_INFO("MCLA LAB single-tile skip target={:08X} tile={}x{} scene={}x{} skips={} primary={} edram_bypass={}",
                        r17.u32, tileWidth, tileHeight, width, height, skipped,
                        gPrimaryScenes.load(std::memory_order_relaxed),
                        gEdramBypasses.load(std::memory_order_relaxed));
        }
        return;
    }

    // The guest ABI remains 720p for all three Metal output resolutions.
    if (!base || width != 1280 || height != 720 || tileWidth == 0 ||
        tileHeight == 0 || tileWidth > width || tileHeight > height) {
        if (gUnexpectedDimensions.fetch_add(1, std::memory_order_relaxed) == 0) {
            REXLOG_WARN("MCLA LAB single-tile unexpected dimensions tile={}x{} scene={}x{}",
                        tileWidth, tileHeight, width, height);
        }
        return;
    }

    r7.u64 = r28.u64;
    r8.u64 = r25.u64;
    // The resolve/end path reads this already-computed big-endian tile count.
    base[kGuestTileCountAddress + 0] = 0;
    base[kGuestTileCountAddress + 1] = 0;
    base[kGuestTileCountAddress + 2] = 0;
    base[kGuestTileCountAddress + 3] = 1;
    if (gPrimaryScenes.fetch_add(1, std::memory_order_relaxed) == 0) {
        REXLOG_INFO("MCLA LAB single-tile ACTIVE tile={}x{} -> {}x{}; offscreen passes unchanged",
                    tileWidth, tileHeight, width, height);
    }
}

// Match the corrected upstream 4096-tile virtual EDRAM bound. Keep the
// existing console path for allocations that fit under 2048 tiles.
bool MCLASingleTileLabAllowEdram(const PPCRegister& r3, const PPCRegister& r30,
                                 const PPCRegister& r11) {
    const uint32_t base = r3.u32;
    const uint32_t size = r30.u32;
    const uint32_t end = r11.u32;
    if (end <= 2048) return false;
    if (base >= kVirtualEdramTiles || end > kVirtualEdramTiles ||
        uint64_t(base) + size != end) {
        if (gEdramOverLimit.fetch_add(1, std::memory_order_relaxed) == 0) {
            REXLOG_WARN("MCLA LAB EDRAM over limit base={} size={} end={}", base, size, end);
        }
        return false;
    }
    if (gEdramBypasses.fetch_add(1, std::memory_order_relaxed) == 0) {
        REXLOG_INFO("MCLA LAB EDRAM first accepted base={} size={} end={}", base, size, end);
    }
    return true;
}
