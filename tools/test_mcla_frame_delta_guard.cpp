#include "../larecomp/src/mc_engine/frame_delta_guard.h"
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <limits>
#include <initializer_list>
int main() {
    using mc::ClampFrameDeltaTicks;
    for(uint64_t hz:{50000000ull,100000000ull,24960000ull}) {
        const auto cap=hz/8;
        // Preserve normal 30/60 Hz updates and short hitches exactly.
        for(uint64_t ticks=0;ticks<=cap;ticks+=97)
            assert(ClampFrameDeltaTicks(ticks,hz)==ticks);
        assert(ClampFrameDeltaTicks(cap,hz)==cap);
        assert(ClampFrameDeltaTicks(cap+1,hz)==cap);
        assert(ClampFrameDeltaTicks(hz*5,hz)==cap); // load/background gap
        assert(ClampFrameDeltaTicks(std::numeric_limits<uint64_t>::max(),hz)==cap);
    }
    assert(ClampFrameDeltaTicks(50000000,0)==6250000);
    puts("Normal frame deltas preserved; load/resume/overflow gaps bounded at 125 ms; fallback frequency passed");
}
