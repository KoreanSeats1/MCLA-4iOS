#include "MCLAXenosGraphics.h"

#include "MCLAAppleGraphicsHooks.h"
#include "MCLAGraphicsFoundation.h"
#include "MCLANativeTitleBridge.h"
#include "MCLARuntimeBootstrap.h"
#include "MCLAVulkanGate.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <functional>
#include <memory>
#include <thread>

#include <rex/graphics/command_processor.h>
#include <rex/graphics/register_file.h>
#include <rex/graphics/vulkan/command_processor.h>
#include <rex/logging.h>
#include <rex/system/function_dispatcher.h>
#include <rex/system/interfaces/graphics.h>
#include <rex/system/kernel_state.h>
#include <rex/system/xthread.h>
#include <rex/thread.h>

namespace {

using rex::X_STATUS;

class MCLAXenosGraphics final : public rex::system::IGraphicsSystem {
 public:
    ~MCLAXenosGraphics() override { Shutdown(); }

    rex::X_STATUS SetupPresentation(rex::ui::WindowedAppContext*) override {
        return X_STATUS_SUCCESS;
    }

    rex::X_STATUS SetupGuestGpu(
        rex::runtime::FunctionDispatcher* dispatcher,
        rex::system::KernelState* kernelState) override {
        if (running_.load(std::memory_order_acquire)) {
            return X_STATUS_SUCCESS;
        }
        if (!dispatcher || !kernelState || !dispatcher->memory() ||
            !MCLAGraphicsHasMetalLayer()) {
            return X_STATUS_INVALID_PARAMETER;
        }
        if (!MCLAVulkanDeviceGate() || !MCLAVulkanDevice() ||
            !MCLAVulkanPresenter()) {
            REXLOG_ERROR("MCLA generic Xenos/Vulkan backend could not initialize MoltenVK");
            return X_STATUS_UNSUCCESSFUL;
        }

        dispatcher_ = dispatcher;
        kernelState_ = kernelState;
        memory_ = dispatcher->memory();
        auto interruptDispatcher = [this](uint32_t source, uint32_t cpu) {
            DispatchInterrupt(source, cpu);
        };
        commandProcessor_ =
            std::make_unique<rex::graphics::vulkan::VulkanCommandProcessor>(
                memory_, &registerFile_, kernelState_, interruptDispatcher,
                MCLAVulkanDevice(), nullptr, MCLAVulkanPresenter());

        if (!memory_->AddVirtualMappedRange(
                0x7FC80000, 0xFFFF0000, 0x0000FFFF, this,
                reinterpret_cast<rex::runtime::MMIOReadCallback>(&ReadRegisterThunk),
                reinterpret_cast<rex::runtime::MMIOWriteCallback>(&WriteRegisterThunk)) ||
            !commandProcessor_->Initialize()) {
            commandProcessor_.reset();
            MCLAVulkanDeviceShutdown();
            dispatcher_ = nullptr;
            kernelState_ = nullptr;
            memory_ = nullptr;
            return X_STATUS_UNSUCCESSFUL;
        }

        running_.store(true, std::memory_order_release);
        vblankWorker_ = rex::system::object_ref<rex::system::XHostThread>(
            new rex::system::XHostThread(kernelState_, 128 * 1024, 0,
                                         [this]() { return VblankWorkerMain(); }));
        vblankWorker_->set_name("MCLA GPU VSync");
        const X_STATUS status = vblankWorker_->Create();
        if (XFAILED(status)) {
            running_.store(false, std::memory_order_release);
            commandProcessor_->Shutdown();
            commandProcessor_.reset();
            vblankWorker_.reset();
            MCLAVulkanDeviceShutdown();
            dispatcher_ = nullptr;
            kernelState_ = nullptr;
            memory_ = nullptr;
            return status;
        }

        REXLOG_INFO(
            "MCLA generic emulation GPU active: PM4 command processor, runtime "
            "Xenos shader translation, EDRAM emulation, texture cache, and "
            "MoltenVK presentation (title-native renderer is NOT active)");
        MCLAPublishRuntimeGpuTelemetry(
            "backend=generic-xenos-vulkan native_title_bridge=1 "
            "native_title_takeover=0 stage=active");
        return X_STATUS_SUCCESS;
    }

    bool has_presentation() const override {
        return MCLAGraphicsHasMetalLayer();
    }

    void SetInterruptCallback(uint32_t callback, uint32_t userData) override {
        interruptData_.store(userData, std::memory_order_release);
        interruptCallback_.store(callback, std::memory_order_release);
        REXLOG_INFO("MCLA GPU interrupt callback {:08X} data {:08X}", callback,
                    userData);
    }

    void InitializeRingBuffer(uint32_t pointer, uint32_t sizeLog2) override {
        ringPointer_.store(pointer, std::memory_order_release);
        ringSizeLog2_.store(sizeLog2, std::memory_order_release);
        if (commandProcessor_) {
            commandProcessor_->InitializeRingBuffer(pointer, sizeLog2);
        }
        REXLOG_INFO("MCLA GPU ring buffer {:08X}, size log2 {}", pointer,
                    sizeLog2);
    }

    void EnableReadPointerWriteBack(uint32_t pointer,
                                    uint32_t blockSizeLog2) override {
        readPointerWriteback_.store(pointer, std::memory_order_release);
        if (commandProcessor_) {
            commandProcessor_->EnableReadPointerWriteBack(pointer,
                                                          blockSizeLog2);
        }
        REXLOG_INFO("MCLA GPU read-pointer writeback {:08X}, block log2 {}",
                    pointer, blockSizeLog2);
    }

    void InitializeShaderStorage(const std::filesystem::path& cacheRoot,
                                 uint32_t titleId, bool blocking) override {
        if (!commandProcessor_ || cacheRoot.empty() || !titleId) {
            return;
        }
        if (blocking) {
            rex::thread::Fence fence;
            commandProcessor_->CallInThread([this, cacheRoot, titleId, &fence]() {
                commandProcessor_->InitializeShaderStorage(cacheRoot, titleId,
                                                           true);
                fence.Signal();
            });
            fence.Wait();
        } else {
            commandProcessor_->CallInThread([this, cacheRoot, titleId]() {
                commandProcessor_->InitializeShaderStorage(cacheRoot, titleId,
                                                           false);
            });
        }
    }

    void Shutdown() override {
        if (!running_.exchange(false, std::memory_order_acq_rel)) {
            return;
        }
        if (vblankWorker_) {
            vblankWorker_->Wait(0, 0, 0, nullptr);
            vblankWorker_.reset();
        }
        if (commandProcessor_) {
            commandProcessor_->Shutdown();
            commandProcessor_.reset();
        }
        MCLAVulkanDeviceShutdown();
        dispatcher_ = nullptr;
        kernelState_ = nullptr;
        memory_ = nullptr;
    }

 private:
    static uint32_t ReadRegisterThunk(void*, MCLAXenosGraphics* graphics,
                                      uint32_t address) {
        return graphics->ReadRegister(address);
    }

    static void WriteRegisterThunk(void*, MCLAXenosGraphics* graphics,
                                   uint32_t address, uint32_t value) {
        graphics->WriteRegister(address, value);
    }

    uint32_t ReadRegister(uint32_t address) const {
        const uint32_t index = (address & 0xFFFFu) / sizeof(uint32_t);
        switch (index) {
            case 0x0F00:
                return 0x08100748;
            case 0x0F01:
                return 0x0000200E;
            case 0x194C:
                return 720;
            case 0x1951:
                return 1;
            case 0x1961:
                return (1280u << 16) | 720u;
            default:
                return index < rex::graphics::RegisterFile::kRegisterCount
                           ? registerFile_.values[index]
                           : 0;
        }
    }

    void WriteRegister(uint32_t address, uint32_t value) {
        const uint32_t index = (address & 0xFFFFu) / sizeof(uint32_t);
        if (index < rex::graphics::RegisterFile::kRegisterCount) {
            registerFile_.values[index] = value;
        }
        if (index == 0x01C5 && commandProcessor_) {
            writePointer_.store(value, std::memory_order_release);
            ringKicks_.fetch_add(1, std::memory_order_relaxed);
            commandProcessor_->UpdateWritePointer(value);
        }
    }

    void DispatchInterrupt(uint32_t source, uint32_t cpu) {
        const uint32_t callback =
            interruptCallback_.load(std::memory_order_acquire);
        if (!callback || !dispatcher_) {
            return;
        }
        auto* thread = rex::system::XThread::GetCurrentThread();
        if (!thread || !thread->thread_state()) {
            return;
        }
        if (cpu == 0xFFFFFFFF) {
            cpu = 2;
        }
        thread->SetActiveCpu(cpu);
        uint64_t args[] = {
            source, interruptData_.load(std::memory_order_acquire)};
        dispatcher_->ExecuteInterrupt(thread->thread_state(), callback, args,
                                      std::size(args));
        interrupts_.fetch_add(1, std::memory_order_relaxed);
    }

    int VblankWorkerMain() {
        auto nextVblank = std::chrono::steady_clock::now();
        auto nextReport = nextVblank + std::chrono::seconds(1);
        while (running_.load(std::memory_order_acquire)) {
            const auto now = std::chrono::steady_clock::now();
            if (now >= nextVblank) {
                if (commandProcessor_) {
                    commandProcessor_->increment_counter();
                }
                DispatchInterrupt(0, 2);
                vblanks_.fetch_add(1, std::memory_order_relaxed);
                nextVblank = now + std::chrono::microseconds(16667);
            }
            if (now >= nextReport) {
                MCLAAppleGraphicsHookReport hooks{};
                MCLAGetAppleGraphicsHookReport(&hooks);
                MCLANativeTitleBridgeReport nativeBridge{};
                MCLANativeTitleBridgeGetReport(&nativeBridge);
                MCLAGraphicsReport presentation{};
                MCLAGraphicsGetReport(&presentation);
                // Keep enough room for the renderer, title-bridge, metadata, and
                // native shader-pack counters. Truncating this line hides the
                // final per-stage SPIR-V sizes during device diagnostics.
                char telemetry[2048] = {};
                std::snprintf(
                    telemetry, sizeof(telemetry),
                    "backend=generic-xenos-vulkan native_title_bridge=1 "
                    "native_title_takeover=0 "
                    "stage=running callback=%08X device=%08X "
                    "vblanks=%llu interrupts=%llu ring=%08X size_log2=%u "
                    "write=%08X writeback=%08X kicks=%llu cp_counter=%u "
                    "published=%llu | draw_i=%llu draw=%llu begin_v=%llu "
                    "end_v=%llu begin_t=%llu end_t=%llu resolve=%llu "
                    "frame_end=%llu swap=%llu clear=%llu block_idle=%llu last=%s "
                    "| title_q=%u title_q_hi=%u title_submit=%llu "
                    "title_done=%llu title_drop=%llu title_draw_i=%llu "
                    "title_draw=%llu title_inline=%llu title_resolve=%llu "
                    "title_swap=%llu shader_pairs=%llu vs=%016llX ps=%016llX "
                    "vfetch=%u capture_records=%llu captured_shaders=%llu "
                    "capture_failures=%llu metadata_shaders=%u "
                    "metadata_elements=%u metadata_hits=%llu "
                    "metadata_misses=%llu metadata_last_elements=%u "
                    "native_spirv_vs=%u native_spirv_ps=%u "
                    "native_spirv_provisional=%u native_spirv_bytes=%u "
                    "native_spirv_hits=%llu native_spirv_misses=%llu "
                    "native_spirv_draws=%llu native_spirv_incomplete=%llu "
                    "native_spirv_last_vs=%u native_spirv_last_ps=%u",
                    interruptCallback_.load(std::memory_order_relaxed),
                    interruptData_.load(std::memory_order_relaxed),
                    static_cast<unsigned long long>(
                        vblanks_.load(std::memory_order_relaxed)),
                    static_cast<unsigned long long>(
                        interrupts_.load(std::memory_order_relaxed)),
                    ringPointer_.load(std::memory_order_relaxed),
                    ringSizeLog2_.load(std::memory_order_relaxed),
                    writePointer_.load(std::memory_order_relaxed),
                    readPointerWriteback_.load(std::memory_order_relaxed),
                    static_cast<unsigned long long>(
                        ringKicks_.load(std::memory_order_relaxed)),
                    commandProcessor_ ? commandProcessor_->counter() : 0,
                    static_cast<unsigned long long>(
                        presentation.titleDrivenFrames),
                    static_cast<unsigned long long>(hooks.drawIndexed),
                    static_cast<unsigned long long>(hooks.draw),
                    static_cast<unsigned long long>(hooks.beginVertices),
                    static_cast<unsigned long long>(hooks.endVertices),
                    static_cast<unsigned long long>(hooks.beginTiling),
                    static_cast<unsigned long long>(hooks.endTiling),
                    static_cast<unsigned long long>(hooks.resolves),
                    static_cast<unsigned long long>(hooks.frameEnds),
                    static_cast<unsigned long long>(hooks.swaps),
                    static_cast<unsigned long long>(hooks.clears),
                    static_cast<unsigned long long>(hooks.idleBypasses),
                    hooks.lastHook ? hooks.lastHook : "(none)",
                    nativeBridge.queueDepth,
                    nativeBridge.queueHighWatermark,
                    static_cast<unsigned long long>(nativeBridge.submitted),
                    static_cast<unsigned long long>(nativeBridge.processed),
                    static_cast<unsigned long long>(nativeBridge.dropped),
                    static_cast<unsigned long long>(nativeBridge.drawIndexed),
                    static_cast<unsigned long long>(nativeBridge.draw),
                    static_cast<unsigned long long>(nativeBridge.inlineDraw),
                    static_cast<unsigned long long>(nativeBridge.resolves),
                    static_cast<unsigned long long>(nativeBridge.swaps),
                    static_cast<unsigned long long>(
                        nativeBridge.uniqueShaderPairs),
                    static_cast<unsigned long long>(
                        nativeBridge.lastVertexShader),
                    static_cast<unsigned long long>(
                        nativeBridge.lastPixelShader),
                    nativeBridge.lastValidVertexFetches,
                    static_cast<unsigned long long>(
                        nativeBridge.captureRecords),
                    static_cast<unsigned long long>(
                        nativeBridge.capturedShaders),
                    static_cast<unsigned long long>(
                        nativeBridge.captureFailures),
                    nativeBridge.metadataShaders,
                    nativeBridge.metadataElements,
                    static_cast<unsigned long long>(nativeBridge.metadataHits),
                    static_cast<unsigned long long>(nativeBridge.metadataMisses),
                    nativeBridge.lastMetadataElements,
                    nativeBridge.shaderPackVertexShaders,
                    nativeBridge.shaderPackPixelShaders,
                    nativeBridge.shaderPackProvisionalShaders,
                    nativeBridge.shaderPackBytes,
                    static_cast<unsigned long long>(nativeBridge.shaderPackHits),
                    static_cast<unsigned long long>(nativeBridge.shaderPackMisses),
                    static_cast<unsigned long long>(nativeBridge.shaderMatchedDraws),
                    static_cast<unsigned long long>(nativeBridge.shaderIncompleteDraws),
                    nativeBridge.lastVertexSpirvBytes,
                    nativeBridge.lastPixelSpirvBytes);
                MCLAPublishRuntimeGpuTelemetry(telemetry);
                nextReport = now + std::chrono::seconds(1);
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        return 0;
    }

    rex::runtime::FunctionDispatcher* dispatcher_ = nullptr;
    rex::system::KernelState* kernelState_ = nullptr;
    rex::memory::Memory* memory_ = nullptr;
    rex::graphics::RegisterFile registerFile_;
    std::unique_ptr<rex::graphics::CommandProcessor> commandProcessor_;
    rex::system::object_ref<rex::system::XHostThread> vblankWorker_;
    std::atomic<bool> running_{false};
    std::atomic<uint32_t> interruptCallback_{0};
    std::atomic<uint32_t> interruptData_{0};
    std::atomic<uint32_t> ringPointer_{0};
    std::atomic<uint32_t> ringSizeLog2_{0};
    std::atomic<uint32_t> readPointerWriteback_{0};
    std::atomic<uint32_t> writePointer_{0};
    std::atomic<uint64_t> ringKicks_{0};
    std::atomic<uint64_t> vblanks_{0};
    std::atomic<uint64_t> interrupts_{0};
};

}  // namespace

std::unique_ptr<rex::system::IGraphicsSystem> MCLACreateXenosGraphics() {
    return std::make_unique<MCLAXenosGraphics>();
}
