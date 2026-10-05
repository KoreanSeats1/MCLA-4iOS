#include "../MCLAApp/runtime/MCLAVisualExperiments.h"
#include <cassert>
#include <limits>
#include <cstdio>
int main() {
    using namespace mcla::metal;
    std::array<std::array<float,4>,4> quad{{{-1,-1,0,1},{1,-1,0,1},{-1,1,0,1},{1,1,0,1}}};
    assert(FullScreenOverlay(quad,false));
    assert(FullScreenOverlay({quad.data(),3},true));
    assert(!FullScreenOverlay({quad.data(),3},false));
    auto bad=quad; bad[0][0]=0; assert(!FullScreenOverlay(bad,false));
    bad=quad; bad[0][3]=0; assert(!FullScreenOverlay(bad,true));
    bad=quad; bad[0][0]=std::numeric_limits<float>::quiet_NaN(); assert(!FullScreenOverlay(bad,false));
    bad=quad; bad[0]=bad[1]; assert(!FullScreenOverlay(bad,false));
    auto hud=quad; for(auto& p:hud){p[0]*=.3f;p[1]*=.2f;} assert(!FullScreenOverlay(hud,false));
    for(auto& p:quad){p[0]*=2;p[1]*=2;p[3]=2;} assert(FullScreenOverlay(quad,false));
    puts("Full-screen overlay classification passed: HUD bounds, corners, homogeneous coordinates, invalid data");
}
