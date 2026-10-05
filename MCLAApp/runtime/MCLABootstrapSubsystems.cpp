#include "MCLABootstrapSubsystems.h"
#include "MCLAAudioOutput.h"
#include "MCLATouchInputMath.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <pthread/qos.h>
#include <thread>
#include <vector>

#include <rex/audio/xma/decoder.h>
#include <rex/input/input.h>
#include <ios/ios_input_driver.h>
#include <rex/logging.h>
#include <rex/memory/utils.h>
#include <rex/system/function_dispatcher.h>
#include <rex/system/interfaces/audio.h>
#include <rex/system/interfaces/input.h>
#include <rex/system/kernel_state.h>
#include <rex/system/xmemory.h>
#include <rex/system/xthread.h>
#include <rex/ui/virtual_key.h>

namespace {

using rex::X_RESULT;
using rex::X_STATUS;

std::atomic<uint16_t> gVirtualGamepadButtons{0};
std::atomic<uint32_t> gVirtualGamepadPacket{1};
std::atomic<uint64_t> gVirtualButtonEdges{0};
std::atomic<uint8_t> gVirtualLeftTrigger{0};
std::atomic<uint8_t> gVirtualRightTrigger{0};
std::atomic<int16_t> gVirtualLeftX{0}, gVirtualLeftY{0};
std::atomic<int16_t> gVirtualRightX{0}, gVirtualRightY{0};
std::atomic<int16_t> gVirtualTiltX{0};
std::atomic<bool> gVirtualLeftActive{false}, gVirtualRightActive{false};
std::atomic<bool> gVirtualTiltActive{false};
std::mutex gVirtualKeystrokeMutex;
std::deque<rex::input::X_INPUT_KEYSTROKE> gVirtualKeystrokes;

uint16_t VirtualKeyForButton(uint16_t buttonMask) {
    switch (buttonMask) {
        case MCLA_GAMEPAD_DPAD_UP: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadDpadUp);
        case MCLA_GAMEPAD_DPAD_DOWN: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadDpadDown);
        case MCLA_GAMEPAD_DPAD_LEFT: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadDpadLeft);
        case MCLA_GAMEPAD_DPAD_RIGHT: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadDpadRight);
        case MCLA_GAMEPAD_START:
            return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadStart);
        case MCLA_GAMEPAD_BACK: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadBack);
        case MCLA_GAMEPAD_LEFT_THUMB: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadLThumbPress);
        case MCLA_GAMEPAD_RIGHT_THUMB: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadRThumbPress);
        case MCLA_GAMEPAD_LEFT_SHOULDER: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadLShoulder);
        case MCLA_GAMEPAD_RIGHT_SHOULDER: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadRShoulder);
        case MCLA_GAMEPAD_A:
            return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadA);
        case MCLA_GAMEPAD_B: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadB);
        case MCLA_GAMEPAD_X: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadX);
        case MCLA_GAMEPAD_Y: return static_cast<uint16_t>(rex::ui::VirtualKey::kXInputPadY);
        default:
            return 0;
    }
}

void QueueVirtualKeystroke(uint16_t virtualKey, bool pressed) {
    if (!virtualKey) return;
    rex::input::X_INPUT_KEYSTROKE keystroke = {};
    keystroke.virtual_key = virtualKey;
    keystroke.flags = pressed ? rex::input::X_INPUT_KEYSTROKE_KEYDOWN
                              : rex::input::X_INPUT_KEYSTROKE_KEYUP;
    keystroke.user_index = 0;
    std::lock_guard lock(gVirtualKeystrokeMutex);
    // Most gameplay polls GetState rather than GetKeystroke. Bound pending
    // edges so long touch sessions cannot grow an unconsumed queue forever.
    if (gVirtualKeystrokes.size() >= 64) gVirtualKeystrokes.pop_front();
    gVirtualKeystrokes.push_back(keystroke);
}

class MCLABootstrapAudio final : public rex::system::IAudioSystem {
 public:
    explicit MCLABootstrapAudio(
        rex::runtime::FunctionDispatcher* dispatcher)
        : dispatcher_(dispatcher),
          xmaDecoder_(dispatcher
                          ? std::make_unique<rex::audio::XmaDecoder>(dispatcher)
                          : nullptr) {}

    ~MCLABootstrapAudio() override { Shutdown(); }

    X_STATUS Setup(rex::system::KernelState* kernelState) override {
        if (!dispatcher_ || !dispatcher_->memory() || !kernelState) {
            return X_STATUS_INVALID_PARAMETER;
        }
        kernelState_ = kernelState;
        if (!xmaDecoder_ || XFAILED(xmaDecoder_->Setup(kernelState))) {
            kernelState_ = nullptr;
            return X_STATUS_UNSUCCESSFUL;
        }
        output_ = mcla_ios_audio_output_create();
        if (output_) {
            REXLOG_INFO(
                "MCLA iOS audio active: speaker-driven 32-block guest queue");
        } else {
            REXLOG_WARN(
                "MCLA native audio output unavailable; retaining paced-silence fallback");
        }
        running_.store(true, std::memory_order_release);
        worker_ = rex::system::object_ref<rex::system::XHostThread>(
            new rex::system::XHostThread(
                kernelState_, 128 * 1024, 0,
                [this]() { return WorkerMain(); }));
        worker_->set_name("MCLA audio clock");
        const X_STATUS status = worker_->Create();
        if (XFAILED(status)) {
            running_.store(false, std::memory_order_release);
            worker_.reset();
            mcla_ios_audio_output_destroy(output_);
            output_ = nullptr;
            xmaDecoder_->Shutdown();
            kernelState_ = nullptr;
            return status;
        }
        REXLOG_INFO("MCLA audio services active: XMA decoder plus Xbox mixer");
        return X_STATUS_SUCCESS;
    }

    X_STATUS RegisterClient(uint32_t callback, uint32_t callbackArg,
                            size_t* outIndex) override {
        if (!callback || !dispatcher_ || !dispatcher_->memory()) {
            return X_STATUS_INVALID_PARAMETER;
        }
        std::lock_guard lock(mutex_);
        for (size_t index = 0; index < clients_.size(); ++index) {
            if (clients_[index].active) {
                continue;
            }
            const uint32_t wrappedArg =
                dispatcher_->memory()->SystemHeapAlloc(sizeof(uint32_t));
            if (!wrappedArg) {
                return X_STATUS_NO_MEMORY;
            }
            rex::memory::store_and_swap<uint32_t>(
                dispatcher_->memory()->TranslateVirtual(wrappedArg),
                callbackArg);
            clients_[index] = {callback, wrappedArg, true};
            allocations_.push_back(wrappedArg);
            const uint64_t requested =
                mcla_ios_audio_output_requested_blocks(output_);
            pumpedBlocks_[index].store(requested > 32 ? requested - 32 : 0,
                                       std::memory_order_relaxed);
            if (outIndex) {
                *outIndex = index;
            }
            REXLOG_INFO(
                "MCLA audio registered mixer client {} callback {:08X}",
                index, callback);
            return X_STATUS_SUCCESS;
        }
        return X_STATUS_NO_MEMORY;
    }

    void UnregisterClient(size_t index) override {
        std::lock_guard lock(mutex_);
        if (index < clients_.size()) {
            clients_[index].active = false;
        }
    }

    void SubmitFrame(size_t index, uint32_t samplesPtr) override {
        if (index < submittedFrames_.size()) {
            submittedFrames_[index].fetch_add(1, std::memory_order_relaxed);
        }
        if (output_ && samplesPtr && dispatcher_ && dispatcher_->memory()) {
            const float* samples =
                dispatcher_->memory()->TranslateVirtual<const float*>(samplesPtr);
            mcla_ios_audio_output_submit(output_, samples, 256);
        }
    }

    rex::audio::XmaDecoder* xma_decoder() override {
        return xmaDecoder_.get();
    }

    void Shutdown() override {
        if (!running_.exchange(false, std::memory_order_acq_rel)) {
            return;
        }
        if (worker_) {
            worker_->Wait(0, 0, 0, nullptr);
            worker_.reset();
        }
        if (dispatcher_ && dispatcher_->memory()) {
            for (uint32_t allocation : allocations_) {
                dispatcher_->memory()->SystemHeapFree(allocation);
            }
        }
        allocations_.clear();
        mcla_ios_audio_output_destroy(output_);
        output_ = nullptr;
        if (xmaDecoder_) {
            xmaDecoder_->Shutdown();
        }
        kernelState_ = nullptr;
    }

 private:
    struct Client {
        uint32_t callback = 0;
        uint32_t wrappedArg = 0;
        bool active = false;
    };

    int WorkerMain() {
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);

        // The real AudioUnit callback advances the requested block count. If
        // audio setup is unavailable, retain a 256-sample / 48 kHz clock so
        // guest state still advances deterministically.
        constexpr auto kIdlePoll = std::chrono::microseconds(250);
        constexpr auto kFallbackBlockDuration =
            std::chrono::microseconds(5333);
        auto fallbackDeadline = std::chrono::steady_clock::now();
        uint64_t fallbackRequested = 1;
        while (running_.load(std::memory_order_acquire)) {
            uint64_t requested = 0;
            if (output_) {
                requested = mcla_ios_audio_output_requested_blocks(output_);
            } else {
                const auto now = std::chrono::steady_clock::now();
                if (now >= fallbackDeadline) {
                    ++fallbackRequested;
                    fallbackDeadline = now + kFallbackBlockDuration;
                }
                requested = fallbackRequested;
            }

            std::array<Client, 8> clients;
            {
                std::lock_guard lock(mutex_);
                clients = clients_;
            }
            bool pumped = false;
            for (size_t index = 0; index < clients.size(); ++index) {
                const Client& client = clients[index];
                if (!client.active || !client.callback ||
                    pumpedBlocks_[index].load(std::memory_order_relaxed) >=
                        requested) {
                    continue;
                }
                uint64_t args[] = {client.wrappedArg};
                dispatcher_->Execute(worker_->thread_state(), client.callback,
                                     args, std::size(args));
                pumpedBlocks_[index].fetch_add(1, std::memory_order_relaxed);
                pumped = true;
            }
            if (!pumped) {
                std::this_thread::sleep_for(kIdlePoll);
            }
        }
        return 0;
    }

    rex::runtime::FunctionDispatcher* dispatcher_ = nullptr;
    rex::system::KernelState* kernelState_ = nullptr;
    rex::system::object_ref<rex::system::XHostThread> worker_;
    std::atomic<bool> running_{false};
    std::mutex mutex_;
    std::array<Client, 8> clients_{};
    std::array<std::atomic<uint64_t>, 8> submittedFrames_{};
    std::array<std::atomic<uint64_t>, 8> pumpedBlocks_{};
    std::vector<uint32_t> allocations_;
    mcla_ios_audio_output* output_ = nullptr;
    std::unique_ptr<rex::audio::XmaDecoder> xmaDecoder_;
};

class MCLABootstrapInput final : public rex::system::IInputSystem {
 public:
    X_STATUS Setup() override {
        driver_ =
            std::make_unique<rex::input::ios::IOSInputDriver>(nullptr, 0);
        const X_STATUS status = driver_->Setup();
        if (status != X_STATUS_SUCCESS) {
            driver_.reset();
            REXLOG_WARN(
                "MCLA GameController initialization failed; retaining neutral user-0 pad");
            return X_STATUS_SUCCESS;
        }
        REXLOG_INFO(
            "MCLA iOS input active: Xbox, PlayStation and MFi controllers map to Xbox 360 input");
        return status;
    }

    void Shutdown() override { driver_.reset(); }

    X_RESULT GetCapabilities(
        uint32_t userIndex, uint32_t flags,
        rex::input::X_INPUT_CAPABILITIES* outCapabilities) override {
        if (driver_) {
            const X_RESULT result =
                driver_->GetCapabilities(userIndex, flags, outCapabilities);
            if (result != X_ERROR_DEVICE_NOT_CONNECTED) {
                return result;
            }
        }
        if (userIndex != 0) {
            return X_ERROR_DEVICE_NOT_CONNECTED;
        }
        if (outCapabilities) {
            std::memset(outCapabilities, 0, sizeof(*outCapabilities));
            outCapabilities->type = rex::input::XINPUT_DEVTYPE_GAMEPAD;
            outCapabilities->sub_type = 0x01;
            outCapabilities->gamepad.buttons = 0xFFFF;
            outCapabilities->gamepad.left_trigger = 0xFF;
            outCapabilities->gamepad.right_trigger = 0xFF;
            outCapabilities->gamepad.thumb_lx = 0x7FFF;
            outCapabilities->gamepad.thumb_ly = 0x7FFF;
            outCapabilities->gamepad.thumb_rx = 0x7FFF;
            outCapabilities->gamepad.thumb_ry = 0x7FFF;
        }
        return X_ERROR_SUCCESS;
    }

    X_RESULT GetState(uint32_t userIndex,
                      rex::input::X_INPUT_STATE* outState) override {
        X_RESULT physicalResult = X_ERROR_DEVICE_NOT_CONNECTED;
        if (driver_) {
            physicalResult = driver_->GetState(userIndex, outState);
            if (physicalResult != X_ERROR_SUCCESS &&
                physicalResult != X_ERROR_DEVICE_NOT_CONNECTED) {
                return physicalResult;
            }
        }
        if (physicalResult == X_ERROR_DEVICE_NOT_CONNECTED && userIndex != 0) {
            return X_ERROR_DEVICE_NOT_CONNECTED;
        }
        if (outState && physicalResult == X_ERROR_DEVICE_NOT_CONNECTED) {
            std::memset(outState, 0, sizeof(*outState));
        }

        // Digital inputs OR with the physical pad. A touched analog stick (or
        // enabled tilt X) owns only its active axes; idle touch never zeros a
        // paired controller. Pedals take the greater physical/touch pressure.
        if (outState && userIndex == 0) {
            const uint16_t virtualButtons =
                gVirtualGamepadButtons.load(std::memory_order_acquire);
            const uint16_t physicalButtons =
                static_cast<uint16_t>(outState->gamepad.buttons);
            outState->gamepad.buttons = physicalButtons | virtualButtons;
            outState->gamepad.left_trigger = mcla::touch::MergeTrigger(
                outState->gamepad.left_trigger,
                gVirtualLeftTrigger.load(std::memory_order_acquire));
            outState->gamepad.right_trigger = mcla::touch::MergeTrigger(
                outState->gamepad.right_trigger,
                gVirtualRightTrigger.load(std::memory_order_acquire));
            if (gVirtualTiltActive.load(std::memory_order_acquire))
                outState->gamepad.thumb_lx = gVirtualTiltX.load(std::memory_order_relaxed);
            else if (gVirtualLeftActive.load(std::memory_order_acquire))
                outState->gamepad.thumb_lx = gVirtualLeftX.load(std::memory_order_relaxed);
            if (gVirtualLeftActive.load(std::memory_order_acquire))
                outState->gamepad.thumb_ly = gVirtualLeftY.load(std::memory_order_relaxed);
            if (gVirtualRightActive.load(std::memory_order_acquire)) {
                outState->gamepad.thumb_rx = gVirtualRightX.load(std::memory_order_relaxed);
                outState->gamepad.thumb_ry = gVirtualRightY.load(std::memory_order_relaxed);
            }
            const uint32_t physicalPacket =
                static_cast<uint32_t>(outState->packet_number);
            outState->packet_number =
                physicalPacket +
                gVirtualGamepadPacket.load(std::memory_order_relaxed);
        }
        return X_ERROR_SUCCESS;
    }

    X_RESULT SetState(uint32_t userIndex,
                      rex::input::X_INPUT_VIBRATION* vibration) override {
        if (driver_) {
            const X_RESULT result = driver_->SetState(userIndex, vibration);
            if (result != X_ERROR_DEVICE_NOT_CONNECTED) {
                return result;
            }
        }
        if (userIndex != 0) {
            return X_ERROR_DEVICE_NOT_CONNECTED;
        }
        return vibration ? X_ERROR_SUCCESS : X_ERROR_BAD_ARGUMENTS;
    }

    X_RESULT GetKeystroke(
        uint32_t userIndex, uint32_t flags,
        rex::input::X_INPUT_KEYSTROKE* outKeystroke) override {
        if (driver_) {
            const X_RESULT result =
                driver_->GetKeystroke(userIndex, flags, outKeystroke);
            if (result != X_ERROR_DEVICE_NOT_CONNECTED &&
                result != X_ERROR_EMPTY) {
                return result;
            }
        }
        if (userIndex != 0) {
            return X_ERROR_DEVICE_NOT_CONNECTED;
        }
        if (!outKeystroke) {
            return X_ERROR_BAD_ARGUMENTS;
        }
        {
            std::lock_guard lock(gVirtualKeystrokeMutex);
            if (!gVirtualKeystrokes.empty()) {
                *outKeystroke = gVirtualKeystrokes.front();
                gVirtualKeystrokes.pop_front();
                return X_ERROR_SUCCESS;
            }
        }
        std::memset(outKeystroke, 0, sizeof(*outKeystroke));
        return X_ERROR_EMPTY;
    }

 private:
    std::unique_ptr<rex::input::ios::IOSInputDriver> driver_;
};

}  // namespace

std::unique_ptr<rex::system::IAudioSystem> MCLACreateBootstrapAudio(
    rex::runtime::FunctionDispatcher* dispatcher) {
    return std::make_unique<MCLABootstrapAudio>(dispatcher);
}

std::unique_ptr<rex::system::IInputSystem> MCLACreateBootstrapInput() {
    return std::make_unique<MCLABootstrapInput>();
}

void MCLASetVirtualGamepadButton(uint16_t buttonMask, bool pressed) {
    uint16_t previous = gVirtualGamepadButtons.load(std::memory_order_relaxed);
    uint16_t desired = previous;
    do {
        desired = pressed ? static_cast<uint16_t>(previous | buttonMask)
                          : static_cast<uint16_t>(previous & ~buttonMask);
        if (desired == previous) {
            return;
        }
    } while (!gVirtualGamepadButtons.compare_exchange_weak(
        previous, desired, std::memory_order_release,
        std::memory_order_relaxed));
    gVirtualGamepadPacket.fetch_add(1, std::memory_order_relaxed);
    gVirtualButtonEdges.fetch_add(1, std::memory_order_relaxed);
    QueueVirtualKeystroke(VirtualKeyForButton(buttonMask), pressed);
}

void MCLASetVirtualGamepadTrigger(bool right, bool pressed) {
    auto& trigger = right ? gVirtualRightTrigger : gVirtualLeftTrigger;
    const uint8_t value = mcla::touch::Trigger(pressed);
    if (trigger.exchange(value, std::memory_order_acq_rel) == value) return;
    gVirtualGamepadPacket.fetch_add(1, std::memory_order_relaxed);
    gVirtualButtonEdges.fetch_add(1, std::memory_order_relaxed);
    QueueVirtualKeystroke(static_cast<uint16_t>(right
        ? rex::ui::VirtualKey::kXInputPadRTrigger
        : rex::ui::VirtualKey::kXInputPadLTrigger), pressed);
}

void MCLASetVirtualGamepadLeftStick(float x, float y, bool active) {
    const int16_t nextX = active ? mcla::touch::Stick(x) : 0;
    const int16_t nextY = active ? mcla::touch::Stick(y) : 0;
    const bool changed = (gVirtualLeftX.exchange(nextX) != nextX) |
        (gVirtualLeftY.exchange(nextY) != nextY) |
        (gVirtualLeftActive.exchange(active) != active);
    if (changed) gVirtualGamepadPacket.fetch_add(1, std::memory_order_relaxed);
}

void MCLASetVirtualGamepadRightStick(float x, float y, bool active) {
    const int16_t nextX = active ? mcla::touch::Stick(x) : 0;
    const int16_t nextY = active ? mcla::touch::Stick(y) : 0;
    const bool changed = (gVirtualRightX.exchange(nextX) != nextX) |
        (gVirtualRightY.exchange(nextY) != nextY) |
        (gVirtualRightActive.exchange(active) != active);
    if (changed) gVirtualGamepadPacket.fetch_add(1, std::memory_order_relaxed);
}

void MCLASetVirtualGamepadTilt(float x, bool active) {
    const int16_t next = active ? mcla::touch::Stick(x) : 0;
    const bool changed = (gVirtualTiltX.exchange(next) != next) |
        (gVirtualTiltActive.exchange(active) != active);
    if (changed) gVirtualGamepadPacket.fetch_add(1, std::memory_order_relaxed);
}

uint64_t MCLAVirtualGamepadButtonEdgeCount() {
    return gVirtualButtonEdges.load(std::memory_order_relaxed);
}

void MCLAResetVirtualGamepad() {
    constexpr uint16_t buttons[] = {
        MCLA_GAMEPAD_DPAD_UP, MCLA_GAMEPAD_DPAD_DOWN,
        MCLA_GAMEPAD_DPAD_LEFT, MCLA_GAMEPAD_DPAD_RIGHT,
        MCLA_GAMEPAD_START, MCLA_GAMEPAD_BACK,
        MCLA_GAMEPAD_LEFT_THUMB, MCLA_GAMEPAD_RIGHT_THUMB,
        MCLA_GAMEPAD_LEFT_SHOULDER, MCLA_GAMEPAD_RIGHT_SHOULDER,
        MCLA_GAMEPAD_GUIDE, MCLA_GAMEPAD_A, MCLA_GAMEPAD_B,
        MCLA_GAMEPAD_X, MCLA_GAMEPAD_Y,
    };
    for (uint16_t button : buttons) MCLASetVirtualGamepadButton(button, false);
    MCLASetVirtualGamepadTrigger(false, false);
    MCLASetVirtualGamepadTrigger(true, false);
    MCLASetVirtualGamepadLeftStick(0, 0, false);
    MCLASetVirtualGamepadRightStick(0, 0, false);
    MCLASetVirtualGamepadTilt(0, false);
}
