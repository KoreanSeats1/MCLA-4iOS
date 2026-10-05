#include "../larecomp/src/mc_engine/frame_rate_scaling.h"
#include <cassert>
#include <initializer_list>
#include <cmath>
#include <limits>
#include <cstdio>
int main() {
    for(double fps : {30.,45.,59.,60.,61.,120.}) {
        double dt=1/fps;
        double raw=std::round(fps)<60 ? .2 : .4;
        auto camera=mc::CameraSmoothing(raw,dt,fps);
        assert(std::abs(std::pow(1-camera,fps)-std::pow(.8,30))<1e-12);
        auto chassis=mc::ChassisSmoothing(.1,dt);
        assert(std::abs(std::pow(1-chassis,fps)-std::pow(.9,30))<1e-12);
    }
    for(double fps : {59.49,59.5,60.49}) {
        double raw=std::round(fps)<60 ? .2 : .4;
        assert(std::abs(mc::CameraSmoothing(raw,1/60.,fps)-(1-std::sqrt(.8)))<1e-12);
    }
    auto nan=std::numeric_limits<double>::quiet_NaN();
    assert(mc::CameraSmoothing(.4,nan,60)==.4);
    assert(mc::CameraSmoothing(.4,.02,nan)==.4);
    assert(mc::CameraSmoothing(.4,0,60)==.4);
    assert(mc::CameraSmoothing(1,.02,60)==1);
    assert(mc::ChassisSmoothing(.1,nan)==.1);
    assert(mc::ChassisSmoothing(.1,-1)==.1);
    puts("Frame-rate invariant camera/chassis scaling passed");
}
