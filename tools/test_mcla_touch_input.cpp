#include "../MCLAApp/runtime/MCLATouchInputMath.h"
#include "../MCLAApp/runtime/MCLABootstrapSubsystems.h"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <limits>

int main() {
    using mcla::touch::Stick;
    assert(Stick(0.0f) == 0);
    assert(Stick(1.0f) == 32767);
    assert(Stick(-1.0f) == -32768);
    assert(Stick(4.0f) == 32767);
    assert(Stick(-4.0f) == -32768);
    assert(Stick(std::numeric_limits<float>::quiet_NaN()) == 0);
    assert(mcla::touch::Trigger(true) == 255);
    assert(mcla::touch::Trigger(false) == 0);
    assert(mcla::touch::MergeTrigger(150, 0) == 150);
    assert(mcla::touch::MergeTrigger(150, 255) == 255);
    constexpr uint16_t buttons[] = {
        MCLA_GAMEPAD_DPAD_UP, MCLA_GAMEPAD_DPAD_DOWN,
        MCLA_GAMEPAD_DPAD_LEFT, MCLA_GAMEPAD_DPAD_RIGHT,
        MCLA_GAMEPAD_START, MCLA_GAMEPAD_BACK,
        MCLA_GAMEPAD_LEFT_THUMB, MCLA_GAMEPAD_RIGHT_THUMB,
        MCLA_GAMEPAD_LEFT_SHOULDER, MCLA_GAMEPAD_RIGHT_SHOULDER,
        MCLA_GAMEPAD_GUIDE, MCLA_GAMEPAD_A, MCLA_GAMEPAD_B,
        MCLA_GAMEPAD_X, MCLA_GAMEPAD_Y,
    };
    uint16_t seen = 0;
    for (uint16_t button : buttons) {
        assert((seen & button) == 0);
        seen |= button;
    }
}
