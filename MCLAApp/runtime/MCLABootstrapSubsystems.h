#pragma once

#include <cstdint>
#include <memory>

namespace rex::runtime {
class FunctionDispatcher;
}

namespace rex::system {
class IAudioSystem;
class IInputSystem;
}

// MCLA-owned, title-neutral host services used during native bring-up. The
// audio implementation advances the Xbox mixer at its native 256-sample pace,
// includes the shared XMA decoder, and feeds the proven AudioUnit output ring.
// Input uses Apple's GameController framework and exposes a neutral user-0 pad
// when no physical controller is attached, so boot never depends on pairing.
std::unique_ptr<rex::system::IAudioSystem> MCLACreateBootstrapAudio(
    rex::runtime::FunctionDispatcher* dispatcher);
std::unique_ptr<rex::system::IInputSystem> MCLACreateBootstrapInput();

// UIKit touch controls merge into Xbox user 0 without replacing a connected
// physical controller. These values match the Xbox 360 XInput button mask.
constexpr uint16_t MCLA_GAMEPAD_DPAD_UP = 0x0001;
constexpr uint16_t MCLA_GAMEPAD_DPAD_DOWN = 0x0002;
constexpr uint16_t MCLA_GAMEPAD_DPAD_LEFT = 0x0004;
constexpr uint16_t MCLA_GAMEPAD_DPAD_RIGHT = 0x0008;
constexpr uint16_t MCLA_GAMEPAD_START = 0x0010;
constexpr uint16_t MCLA_GAMEPAD_BACK = 0x0020;
constexpr uint16_t MCLA_GAMEPAD_LEFT_THUMB = 0x0040;
constexpr uint16_t MCLA_GAMEPAD_RIGHT_THUMB = 0x0080;
constexpr uint16_t MCLA_GAMEPAD_LEFT_SHOULDER = 0x0100;
constexpr uint16_t MCLA_GAMEPAD_RIGHT_SHOULDER = 0x0200;
constexpr uint16_t MCLA_GAMEPAD_GUIDE = 0x0400;
constexpr uint16_t MCLA_GAMEPAD_A = 0x1000;
constexpr uint16_t MCLA_GAMEPAD_B = 0x2000;
constexpr uint16_t MCLA_GAMEPAD_X = 0x4000;
constexpr uint16_t MCLA_GAMEPAD_Y = 0x8000;
void MCLASetVirtualGamepadButton(uint16_t buttonMask, bool pressed);
void MCLASetVirtualGamepadTrigger(bool right, bool pressed);
void MCLASetVirtualGamepadLeftStick(float x, float y, bool active);
void MCLASetVirtualGamepadRightStick(float x, float y, bool active);
void MCLASetVirtualGamepadTilt(float x, bool active);
uint64_t MCLAVirtualGamepadButtonEdgeCount();
void MCLAResetVirtualGamepad();
