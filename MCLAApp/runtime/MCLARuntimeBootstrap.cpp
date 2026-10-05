#include "MCLADiagnostics.h"
#include "MCLARuntimeBootstrap.h"
#include "MCLAAppleGraphicsHooks.h"
#include "MCLABootstrapSubsystems.h"
#include "MCLANativeTitleBridge.h"
#include "MCLANativeRenderer.h"
#include "MCLAGraphicsFoundation.h"

#include <rex/image_info.h>
#include <rex/chrono/clock.h>
#include <rex/diagnostics/policy.h>
#include <rex/filesystem/vfs.h>
#include <rex/graphics/flags.h>
#include <rex/kernel/init.h>
#include <rex/kernel/crt/heap.h>
#include <rex/kernel/xboxkrnl/video.h>
#include <rex/logging.h>
#include <rex/memory/utils.h>
#include <rex/runtime.h>
#include <rex/system/function_dispatcher.h>
#include <rex/system/interfaces/graphics.h>
#include <rex/system/kernel_state.h>
#include <rex/system/user_module.h>
#include <rex/system/xmemory.h>
#include <rex/system/xthread.h>
#include <rex/thread.h>
#include <rex/ui/flags.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

extern const rex::PPCImageInfo PPCImageConfig;

namespace {

std::atomic_flag gAttempted = ATOMIC_FLAG_INIT;
std::atomic<bool> gRunning{false};
std::atomic<bool> gFinished{false};
std::atomic<bool> gEntryReached{false};
std::atomic<bool> gFailed{false};
std::mutex gStatusMutex;
std::string gStatus = "Runtime is ready for its first launch attempt.";
std::filesystem::path gStatusPath;
std::filesystem::path gGpuTelemetryPath;
PPCFunc* gOriginalEntry = nullptr;

void SetStatus(std::string status) {
    std::lock_guard lock(gStatusMutex);
    gStatus = std::move(status);
    if (mcla::DiagnosticsEnabled() && !gStatusPath.empty()) {
        std::ofstream output(gStatusPath, std::ios::trunc);
        output << gStatus << '\n';
    }
}

void WriteGpuTelemetry(const std::string& telemetry) {
    std::lock_guard lock(gStatusMutex);
    if (mcla::DiagnosticsEnabled() && !gGpuTelemetryPath.empty()) {
        std::ofstream output(gGpuTelemetryPath, std::ios::trunc);
        output << telemetry << '\n';
    }
}

void ConfigureMCLACompatibilityFlags() {
#if MCLA_DIRECT_METAL
    uint32_t guestWidth = 1280, guestHeight = 720;
    MCLAGraphicsGuestVideoSize(&guestWidth, &guestHeight);
    REXCVAR_SET(video_mode_width, static_cast<int32_t>(guestWidth));
    REXCVAR_SET(video_mode_height, static_cast<int32_t>(guestHeight));
    REXCVAR_SET(video_mode_refresh_rate, 60.0);
    REXLOG_INFO("MCLA handwritten Metal: guest_video={}x{} title hooks, offline Metal shaders, 3 frame slots; generic GPU settings disabled", guestWidth, guestHeight);
#else
    // Apply these before Runtime::Setup so the texture and pipeline caches see
    // their final policy when the generic command processor is created.
    REXCVAR_SET(gpu_allow_invalid_fetch_constants, true);
    REXCVAR_SET(readback_resolve, std::string("fast"));
    REXCVAR_SET(readback_memexport, true);
    REXCVAR_SET(readback_memexport_fast, true);
    REXCVAR_SET(occlusion_query_enable, false);
    REXCVAR_SET(async_shader_compilation, true);
    REXCVAR_SET(anisotropic_override, int32_t{5});

    // LARecomp's desktop profile uses 1536/2048 MB. Keep extra headroom over
    // ReXGlue defaults while respecting the tighter iPad process budget.
    REXCVAR_SET(texture_cache_memory_limit_render_to_texture, int32_t{64});
    REXCVAR_SET(texture_cache_memory_limit_soft, int32_t{768});
    REXCVAR_SET(texture_cache_memory_limit_hard, int32_t{1280});
    REXCVAR_SET(vsync, true);
    REXCVAR_SET(video_mode_refresh_rate, 60.0);

    REXLOG_INFO(
        "MCLA compatibility profile: resolve={} memexport_fast={} occlusion={} invalid_fetch={} async_shaders={} texture_cache={}/{} MB RTT={} MB anisotropic={} vsync={}",
        REXCVAR_GET(readback_resolve), REXCVAR_GET(readback_memexport_fast),
        REXCVAR_GET(occlusion_query_enable),
        REXCVAR_GET(gpu_allow_invalid_fetch_constants),
        REXCVAR_GET(async_shader_compilation),
        REXCVAR_GET(texture_cache_memory_limit_soft),
        REXCVAR_GET(texture_cache_memory_limit_hard),
        REXCVAR_GET(texture_cache_memory_limit_render_to_texture),
        REXCVAR_GET(anisotropic_override), REXCVAR_GET(vsync));
#endif
}

void CopyMessage(char* destination, std::size_t destinationSize,
                 const char* message) {
    if (!destination || destinationSize == 0) {
        return;
    }
    std::snprintf(destination, destinationSize, "%s", message ? message : "");
}

void ObservedEntry(PPCContext& context, uint8_t* base) {
    gEntryReached.store(true, std::memory_order_release);
    SetStatus("MCLA AOT entry reached; the Xbox main thread is executing.");
    REXLOG_INFO("MCLA AOT ENTRY REACHED");
    gOriginalEntry(context, base);
}

// This is the first native/no-command-processor GPU boundary. MCLA needs more
// than successful Vd* exports to boot: it directly reads the Xenos MMIO window,
// waits for vblank interrupts, and waits for GPU-owned ring/fence writebacks.
// The title-native renderer consumes immutable host snapshots. This wrapper
// supplies guest-visible progress for the bypassed Xenos ring while the native
// engine separately owns actual GPU submission and completion lifetimes.
class MCLALaunchProbeGraphics final : public rex::system::IGraphicsSystem {
 public:
    ~MCLALaunchProbeGraphics() override { Shutdown(); }

    rex::X_STATUS SetupPresentation(rex::ui::WindowedAppContext*) override {
#if MCLA_NATIVE_TITLE
        nativeRenderer_ = MCLACreateNativeRenderer();
        if (!nativeRenderer_) return static_cast<rex::X_STATUS>(0xC0000001u);
#endif
        return static_cast<rex::X_STATUS>(0x00000000u);
    }

    rex::X_STATUS SetupGuestGpu(
        rex::runtime::FunctionDispatcher* dispatcher,
        rex::system::KernelState* kernelState) override {
        if (!dispatcher || !kernelState || !dispatcher->memory()) {
            return static_cast<rex::X_STATUS>(0xC000000Du);
        }
        dispatcher_ = dispatcher;
        kernelState_ = kernelState;
        memory_ = dispatcher->memory();
#if MCLA_NATIVE_TITLE
        if (!nativeRenderer_) nativeRenderer_ = MCLACreateNativeRenderer();
        if (!nativeRenderer_) return static_cast<rex::X_STATUS>(0xC0000001u);
        auto nativeStatus = nativeRenderer_->SetupGuestGpu(dispatcher, kernelState);
        if (nativeStatus != 0) return nativeStatus;
#endif
        registers_.assign(kRegisterCount, 0);
        if (!memory_->AddVirtualMappedRange(
                kGpuWindowBase, kGpuWindowMask, kGpuWindowSize, this,
                &MCLALaunchProbeGraphics::ReadRegisterThunk,
                &MCLALaunchProbeGraphics::WriteRegisterThunk)) {
            REXLOG_ERROR("MCLA could not map the Xenos MMIO window");
            return static_cast<rex::X_STATUS>(0xC0000001u);
        }

        workerRunning_.store(true, std::memory_order_release);
        vblankWorker_ = rex::system::object_ref<rex::system::XHostThread>(
            new rex::system::XHostThread(kernelState_, 128 * 1024, 0,
                                         [this]() { return VblankWorker(); }));
        vblankWorker_->set_name("MCLA Native VSync");
        vblankWorker_->Create();
        ready_ = true;
        SetStatus("MCLA guest GPU services active; waiting for the title entry point.");
        REXLOG_INFO("MCLA native guest GPU services connected: MMIO + vblank + immediate retirement");
        return static_cast<rex::X_STATUS>(0x00000000u);
    }

    bool has_presentation() const override { return true; }

    void InitializeShaderStorage(const std::filesystem::path& root, uint32_t title,
                                  bool blocking) override {
        if (nativeRenderer_) nativeRenderer_->InitializeShaderStorage(root, title, blocking);
    }

    void SetInterruptCallback(uint32_t callback, uint32_t userData) override {
        interruptCallback_.store(callback, std::memory_order_release);
        interruptData_.store(userData, std::memory_order_release);
        REXLOG_INFO("MCLA GPU interrupt callback {:08X}, data {:08X}",
                    callback, userData);
    }

    void InitializeRingBuffer(uint32_t pointer, uint32_t sizeLog2) override {
        ringPointer_.store(pointer, std::memory_order_release);
        ringSizeLog2_.store(sizeLog2, std::memory_order_release);
        SetStatus("MCLA initialized its Xenos ring; native boot compatibility is consuming submissions.");
        REXLOG_INFO("MCLA Xenos ring initialized at {:08X}, size log2 {}", pointer,
                    sizeLog2);
    }

    void EnableReadPointerWriteBack(uint32_t pointer,
                                    uint32_t blockSizeLog2) override {
        readPointerWriteback_.store(pointer, std::memory_order_release);
        REXLOG_INFO("MCLA ring read-pointer writeback {:08X}, block log2 {}",
                    pointer, blockSizeLog2);
    }

    void Shutdown() override {
        ready_ = false;
        if (vblankWorker_) {
            workerRunning_.store(false, std::memory_order_release);
            vblankWorker_->Wait(0, 0, 0, nullptr);
            vblankWorker_.reset();
        }
        if (nativeRenderer_) { nativeRenderer_->Shutdown(); nativeRenderer_.reset(); }
    }

 private:
    std::unique_ptr<rex::system::IGraphicsSystem> nativeRenderer_;
    static constexpr uint32_t kGpuWindowBase = 0x7FC80000u;
    static constexpr uint32_t kGpuWindowMask = 0xFFFF0000u;
    static constexpr uint32_t kGpuWindowSize = 0x0000FFFFu;
    static constexpr uint32_t kRegisterCount = 0x5003u;
    static constexpr uint32_t kRegCpRbWptr = 0x01C5u;
    static constexpr uint32_t kRegPrimarySurfaceAddress = 0x1844u;
    static constexpr uint32_t kRegVCounter = 0x194Cu;
    static constexpr uint32_t kRegInterruptStatus = 0x1951u;
    static constexpr uint32_t kRegViewportSize = 0x1961u;

    static uint32_t ReadRegisterThunk(void*, void* context, uint32_t address) {
        return static_cast<MCLALaunchProbeGraphics*>(context)->ReadRegister(address);
    }

    static void WriteRegisterThunk(void*, void* context, uint32_t address,
                                   uint32_t value) {
        static_cast<MCLALaunchProbeGraphics*>(context)->WriteRegister(address,
                                                                       value);
    }

    uint32_t ReadRegister(uint32_t address) {
        const uint32_t index = (address & 0xFFFFu) / 4u;
        switch (index) {
            case 0x0F00u:
                return 0x08100748u;
            case 0x0F01u:
                return 0x0000200Eu;
            case kRegVCounter: {
                rex::system::X_VIDEO_MODE mode{};
                rex::kernel::xboxkrnl::VdQueryVideoMode(&mode);
                return std::min(uint32_t(mode.display_height), uint32_t(0x0FFF));
            }
            case kRegInterruptStatus:
                return 1u;
            case kRegViewportSize: {
                rex::system::X_VIDEO_MODE mode{};
                rex::kernel::xboxkrnl::VdQueryVideoMode(&mode);
                const uint32_t width =
                    std::min(uint32_t(mode.display_width), uint32_t(0x0FFF));
                const uint32_t height =
                    std::min(uint32_t(mode.display_height), uint32_t(0x0FFF));
                return (width << 16) | height;
            }
            default:
                return index < registers_.size() ? registers_[index] : 0u;
        }
    }

    void WriteRegister(uint32_t address, uint32_t value) {
        const uint32_t index = (address & 0xFFFFu) / 4u;
        if (index < registers_.size()) {
            registers_[index] = value;
        }
        if (index == kRegCpRbWptr) {
            writePointer_.store(value, std::memory_order_release);
            PublishReadPointer(value);
            ringKicks_.fetch_add(1, std::memory_order_relaxed);
        } else if (index == kRegPrimarySurfaceAddress) {
            frontBuffer_.store(value, std::memory_order_release);
            const uint64_t flip = flips_.fetch_add(1, std::memory_order_relaxed) + 1;
            if (flip == 1) {
                SetStatus("MCLA reached its first guest flip; Metal frame mapping is next.");
                REXLOG_INFO("MCLA first guest flip: front buffer {:08X}", value);
            }
        }
    }

    bool GuestRangeReadable(uint32_t address, uint32_t size) const {
        if (!memory_ || address < 0x1000u || size == 0 ||
            uint64_t(address) + size > 0x100000000ull) {
            return false;
        }
        auto* heap = memory_->LookupHeap(address);
        return heap &&
               heap->QueryRangeAccess(address, address + size - 1) !=
                   rex::memory::PageAccess::kNoAccess;
    }

    uint32_t LoadGuestBe32(uint32_t address) const {
        uint32_t value = 0;
        std::memcpy(&value, rex::memory::GuestPtr(memory_->virtual_membase(), address),
                    sizeof(value));
        return __builtin_bswap32(value);
    }

    void StoreGuestBe32(uint32_t address, uint32_t value) const {
        const uint32_t swapped = __builtin_bswap32(value);
        std::memcpy(rex::memory::GuestPtr(memory_->virtual_membase(), address),
                    &swapped, sizeof(swapped));
    }

    void PublishReadPointer(uint32_t value) {
        const uint32_t address =
            readPointerWriteback_.load(std::memory_order_acquire);
        if (memory_ && address) {
            rex::memory::store_and_swap<uint32_t>(
                memory_->TranslatePhysical(address), value);
        }
    }

    void RetireTitleWork(uint32_t device) {
        if (!device || !memory_) {
            return;
        }
        constexpr uint32_t kRetiredPointerOffset = 10896u;
        constexpr uint32_t kIssuedOffset = 10908u;
        constexpr uint32_t kBufferEndOffset = 14908u;
        constexpr uint32_t kWrapOffset = 14920u;
        if (!GuestRangeReadable(device + kRetiredPointerOffset, 16)) {
            return;
        }
        const uint32_t retiredAddress =
            LoadGuestBe32(device + kRetiredPointerOffset);
        if (!GuestRangeReadable(retiredAddress, 8)) {
            return;
        }
        const uint32_t issued = LoadGuestBe32(device + kIssuedOffset);
        if (LoadGuestBe32(retiredAddress) != issued) {
            StoreGuestBe32(retiredAddress, issued);
        }
        if (GuestRangeReadable(device + kBufferEndOffset, 16)) {
            const uint32_t end = LoadGuestBe32(device + kBufferEndOffset);
            const uint32_t wrap = LoadGuestBe32(device + kWrapOffset) & 3u;
            if (end) {
                StoreGuestBe32(retiredAddress + 4, (end & ~3u) | wrap);
            }
        }
    }

    void DispatchVblank() {
        const uint32_t callback =
            interruptCallback_.load(std::memory_order_acquire);
        const uint32_t data = interruptData_.load(std::memory_order_acquire);
        if (!callback || !dispatcher_) {
            return;
        }
        auto thread = rex::system::XThread::GetCurrentThread();
        if (!thread) {
            return;
        }
        thread->SetActiveCpu(2);
        uint64_t args[] = {0u, uint64_t(data)};
        dispatcher_->ExecuteInterrupt(thread->thread_state(), callback, args, 2);
    }

    int VblankWorker() {
        rex::system::X_VIDEO_MODE mode{};
        rex::kernel::xboxkrnl::VdQueryVideoMode(&mode);
        const double refresh =
            std::max(1.0, double(float(mode.refresh_rate)));
        const uint64_t frequency = rex::chrono::Clock::guest_tick_frequency();
        const uint64_t interval =
            std::max(uint64_t(1), uint64_t(double(frequency) / refresh));
        uint64_t last = rex::chrono::Clock::QueryGuestTickCount();
        uint32_t reportTicks = 0;
        while (workerRunning_.load(std::memory_order_acquire)) {
            uint64_t now = rex::chrono::Clock::QueryGuestTickCount();
            if (now < last) {
                last = now;
            }
            uint64_t pending = (now - last) / interval;
            if (pending > 4) {
                last += (pending - 4) * interval;
                pending = 4;
            }
            const uint32_t device =
                interruptData_.load(std::memory_order_acquire);
            RetireTitleWork(device);
            PublishReadPointer(writePointer_.load(std::memory_order_acquire));
            for (uint64_t i = 0; i < pending; ++i) {
                DispatchVblank();
                vblanks_.fetch_add(1, std::memory_order_relaxed);
                last += interval;
            }
            if (++reportTicks >= 1000) {
                reportTicks = 0;
                MCLAAppleGraphicsHookReport hooks{};
                MCLAGetAppleGraphicsHookReport(&hooks);
                char telemetry[896] = {};
                std::snprintf(
                    telemetry, sizeof(telemetry),
                    "backend=mcla-theft4-native native_title_takeover=1 generic_cp=0 "
                    "callback=%08X device=%08X vblanks=%llu ring=%08X size_log2=%u "
                    "write=%08X writeback=%08X kicks=%llu flips=%llu front=%08X | "
                    "draw_i=%llu draw=%llu begin_v=%llu end_v=%llu begin_t=%llu end_t=%llu "
                    "resolve=%llu frame_end=%llu swap=%llu clear=%llu idle_bypass=%llu native_present=%llu last=%s | "
                    "inline prim=%u count=%u stride=%u buffer=%08X words=%08X,%08X,%08X,%08X checksum=%08X",
                    interruptCallback_.load(std::memory_order_relaxed),
                    interruptData_.load(std::memory_order_relaxed),
                    (unsigned long long)vblanks_.load(std::memory_order_relaxed),
                    ringPointer_.load(std::memory_order_relaxed),
                    ringSizeLog2_.load(std::memory_order_relaxed),
                    writePointer_.load(std::memory_order_relaxed),
                    readPointerWriteback_.load(std::memory_order_relaxed),
                    (unsigned long long)ringKicks_.load(std::memory_order_relaxed),
                    (unsigned long long)flips_.load(std::memory_order_relaxed),
                    frontBuffer_.load(std::memory_order_relaxed),
                    (unsigned long long)hooks.drawIndexed,
                    (unsigned long long)hooks.draw,
                    (unsigned long long)hooks.beginVertices,
                    (unsigned long long)hooks.endVertices,
                    (unsigned long long)hooks.beginTiling,
                    (unsigned long long)hooks.endTiling,
                    (unsigned long long)hooks.resolves,
                    (unsigned long long)hooks.frameEnds,
                    (unsigned long long)hooks.swaps,
                    (unsigned long long)hooks.clears,
                    (unsigned long long)hooks.idleBypasses,
                    (unsigned long long)hooks.nativePresents,
                    hooks.lastHook ? hooks.lastHook : "(none)",
                    hooks.inlinePrimitive,
                    hooks.inlineVertexCount,
                    hooks.inlineStride,
                    hooks.inlineBuffer,
                    hooks.inlineWords[0], hooks.inlineWords[1],
                    hooks.inlineWords[2], hooks.inlineWords[3],
                    hooks.inlineChecksum);
                WriteGpuTelemetry(telemetry);
            }
            rex::thread::Sleep(std::chrono::milliseconds(1));
        }
        return 0;
    }

    bool ready_ = false;
    rex::runtime::FunctionDispatcher* dispatcher_ = nullptr;
    rex::system::KernelState* kernelState_ = nullptr;
    rex::memory::Memory* memory_ = nullptr;
    std::vector<uint32_t> registers_;
    std::atomic<bool> workerRunning_{false};
    rex::system::object_ref<rex::system::XHostThread> vblankWorker_;
    std::atomic<uint32_t> interruptCallback_{0};
    std::atomic<uint32_t> interruptData_{0};
    std::atomic<uint32_t> ringPointer_{0};
    std::atomic<uint32_t> ringSizeLog2_{0};
    std::atomic<uint32_t> readPointerWriteback_{0};
    std::atomic<uint32_t> writePointer_{0};
    std::atomic<uint32_t> frontBuffer_{0};
    std::atomic<uint64_t> vblanks_{0};
    std::atomic<uint64_t> ringKicks_{0};
    std::atomic<uint64_t> flips_{0};
};

void RunRuntime(std::filesystem::path gameRoot,
                std::filesystem::path supportRoot) {
    gRunning.store(true, std::memory_order_release);
    try {
        std::filesystem::create_directories(supportRoot);
        std::filesystem::create_directories(supportRoot / "user");
        std::filesystem::create_directories(supportRoot / "cache");
        std::filesystem::create_directories(supportRoot / "marketplace");
        std::filesystem::create_directories(supportRoot / "saves");
        const std::string nativeCaptureRoot =
            (supportRoot / "native-capture").string();
        if (mcla::DiagnosticsEnabled())
            MCLANativeTitleBridgeSetCaptureRoot(nativeCaptureRoot.c_str());

        // Opt-in, one-request-at-a-time GPU readback using Theft4's fenced
        // diagnostic path. Default launches do not allocate capture buffers.
        if (const char* capture = std::getenv("MCLA_NATIVE_FRAME_CAPTURE");
            mcla::DiagnosticsEnabled() && capture && std::strcmp(capture, "1") == 0) {
            const auto captureRoot = supportRoot / "native-frame-capture";
            std::filesystem::create_directories(captureRoot);
            const auto requestPath = captureRoot / "request.txt";
            std::ofstream(requestPath, std::ios::trunc) << "0\n";
            setenv("REX_GTA4_FIRE_TRACE", "1", 1);
            setenv("REX_GTA4_FIRE_INTERVAL", "1", 1);
            setenv("REX_GTA4_FIRE_FRAME_MIB", "128", 1);
            setenv("REX_GTA4_FIRE_DISK_MIB", "128", 1);
            setenv("REX_GTA4_FIRE_OUTPUT", captureRoot.c_str(), 1);
            setenv("REX_GTA4_RAIL_REQUEST_FILE", requestPath.c_str(), 1);
        }

        {
            std::lock_guard lock(gStatusMutex);
            gStatusPath = supportRoot / "runtime-status.txt";
            gGpuTelemetryPath = supportRoot / "runtime-gpu.txt";
        }
        WriteGpuTelemetry(
            "backend=mcla-theft4-native native_title_takeover=1 generic_cp=0 stage=starting");

        const std::string logPath = (supportRoot / "runtime.log").string();
        std::string diagnosticsError;
        if (!rex::diagnostics::Configure(
                mcla::DiagnosticsEnabled(), mcla::DiagnosticsEnabled()
                    ? "logging,vulkan,presenter,guest-hooks,watchdog" : "",
                &diagnosticsError)) {
            throw std::runtime_error("Unable to enable MCLA diagnostics: " +
                                     diagnosticsError);
        }
        rex::LogConfig logging;
        logging.log_file = logPath.c_str();
        logging.log_to_console = true;
        if (mcla::DiagnosticsEnabled()) rex::InitLogging(logging);
        ConfigureMCLACompatibilityFlags();

        SetStatus("Initializing the Xbox runtime and MCLA AOT table…");
        rex::Runtime runtime(gameRoot, supportRoot / "user",
                             gameRoot / "update", supportRoot / "cache", {},
                             supportRoot / "marketplace", supportRoot / "saves");
        rex::RuntimeConfig config;
        config.tool_mode = false;
        config.graphics = std::make_unique<MCLALaunchProbeGraphics>();
        config.input_factory = [](bool) {
            return MCLACreateBootstrapInput();
        };
        config.audio_factory =
            [](rex::runtime::FunctionDispatcher* dispatcher) {
                return MCLACreateBootstrapAudio(dispatcher);
            };
        config.kernel_init = rex::kernel::InitializeKernel;

        if (runtime.Setup(PPCImageConfig, std::move(config)) != 0) {
            throw std::runtime_error("Xbox/AOT runtime setup failed.");
        }

        SetStatus("Loading default.xex and resolving Xbox imports…");
        if (runtime.LoadXexImage("game:/default.xex") != 0) {
            throw std::runtime_error("default.xex or Xbox import resolution failed.");
        }

        if (PPCImageConfig.rexcrt_heap &&
            !rex::kernel::crt::InitHeap(REXCVAR_GET(rexcrt_heap_size_mb),
                                        runtime.memory())) {
            throw std::runtime_error("Unable to initialize the MCLA guest CRT heap.");
        }

        // MCLA loads city, art, and collision resources through t:. This is
        // the same title mapping installed by LARecomp after Runtime::Setup.
        if (auto* fileSystem = runtime.file_system()) {
            fileSystem->RegisterSymbolicLink("t:",
                                             "\\Device\\Harddisk0\\Partition1");
        }

        auto module = runtime.kernel_state()->GetExecutableModule();
        if (!module) {
            throw std::runtime_error("The loaded MCLA executable module is unavailable.");
        }
        if (auto* graphics = runtime.graphics_system()) {
            SetStatus("Preparing the Theft4 native renderer with MCLA shaders…");
            graphics->InitializeShaderStorage(supportRoot / "cache",
                                              module->title_id(), true);
        }
        const uint32_t entryAddress = module->entry_point();
        gOriginalEntry = runtime.function_dispatcher()->GetFunction(entryAddress);
        if (!gOriginalEntry) {
            throw std::runtime_error("No generated AOT function matches the MCLA entry point.");
        }
        if (!runtime.function_dispatcher()->SetFunction(entryAddress, ObservedEntry)) {
            throw std::runtime_error("Unable to install the MCLA entry-point observer.");
        }

        auto thread = runtime.PrepareModuleLaunch();
        if (!thread) {
            throw std::runtime_error("Unable to create the MCLA Xbox main thread.");
        }
        SetStatus("Starting the MCLA Xbox main thread…");
        if (thread->ResumeFromInitialSuspension() != 0) {
            throw std::runtime_error("Unable to resume the MCLA Xbox main thread.");
        }
        thread->Wait(0, 0, 0, nullptr);
        if (!gEntryReached.load(std::memory_order_acquire)) {
            throw std::runtime_error("The Xbox main thread exited before reaching the AOT entry.");
        }
        SetStatus("MCLA main thread exited after reaching the AOT entry.");
        rex::ShutdownLogging();
    } catch (const std::exception& error) {
        gFailed.store(true, std::memory_order_release);
        SetStatus(error.what());
        REXLOG_ERROR("MCLA launch failed: {}", error.what());
        rex::ShutdownLogging();
    }
    gRunning.store(false, std::memory_order_release);
    gFinished.store(true, std::memory_order_release);
}

}  // namespace

void MCLAPublishRuntimeGpuTelemetry(const char* telemetry) {
    WriteGpuTelemetry(telemetry ? telemetry : "");
}

bool MCLAStartRuntimeBackend(const char* gameRoot, const char* supportRoot,
                             char* errorMessage,
                             std::size_t errorMessageSize) {
    if (!gameRoot || !gameRoot[0] || !supportRoot || !supportRoot[0]) {
        CopyMessage(errorMessage, errorMessageSize,
                    "Game-data or support path is missing.");
        return false;
    }
    if (gAttempted.test_and_set()) {
        CopyMessage(errorMessage, errorMessageSize,
                    "This runtime launch is one-shot; restart the app to retry.");
        return false;
    }

    gFinished.store(false, std::memory_order_release);
    gFailed.store(false, std::memory_order_release);
    gEntryReached.store(false, std::memory_order_release);
    SetStatus("Launch queued…");
    std::thread(RunRuntime, std::filesystem::path(gameRoot),
                std::filesystem::path(supportRoot)).detach();
    CopyMessage(errorMessage, errorMessageSize, "Launch started.");
    return true;
}

void MCLAGetRuntimeBackendStatus(char* message, std::size_t messageSize,
                                 bool* running, bool* finished,
                                 bool* entryReached, bool* failed) {
    if (running) *running = gRunning.load(std::memory_order_acquire);
    if (finished) *finished = gFinished.load(std::memory_order_acquire);
    if (entryReached) *entryReached = gEntryReached.load(std::memory_order_acquire);
    if (failed) *failed = gFailed.load(std::memory_order_acquire);
    std::lock_guard lock(gStatusMutex);
    CopyMessage(message, messageSize, gStatus.c_str());
}
