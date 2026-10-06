#include "../MCLAApp/runtime/MCLAControlOverhaul.h"
#include <cassert>
#include <limits>
#include <cstdio>
int main() {
    using namespace mcla::metal;
    assert(RaisedHudMove({75,460,305,685}).scale == .90f);
    assert(RaisedHudMove({940,510,1190,670}).scale == 1.f);
    assert(RaisedHudMove({0,0,1280,720}).y == 0); // fade/menu backgrounds
    assert(RaisedHudMove({75,460,1190,685}).y == 0); // mixed HUD batch
    // Each independent quad in a mixed batch can retain its own transform.
    const HudBounds quads[]={{75,460,305,685},{940,510,1190,670},{500,100,700,250}};
    assert(RaisedHudMove(quads[0]).y!=0);
    assert(RaisedHudMove(quads[1]).right && RaisedHudMove(quads[1]).y!=0);
    assert(RaisedHudMove(quads[2]).y==0);
    assert(RaisedHudMove({500,500,600,650}).y == 0); // world/center overlays
    assert(RaisedHudMove({75,100,305,330}).y == 0); // already at destination
    assert(RaisedHudMove({75,430,305,685}).y == 0); // crosses capture boundary
    assert(RaisedHudMove({305,460,75,685}).y == 0);
    assert(RaisedHudMove({NAN,460,305,685}).y == 0);
    const auto map=RaisedHudMove({72,440,330,710});
    const auto ring=RaisedHudMove({23.3f,407.6f,359.8f,744.2f});
    assert(ring.scale==map.scale && ring.x==map.x && ring.y==map.y);
    assert(RaisedHudMove({16,400,368,752}).y==0); // unrelated larger panel
    const auto gauge=RaisedHudMove({900,480,1260,710});
    assert(std::fabs(440*map.scale+map.y-76)<.001f);
    assert(std::fabs(710*map.scale+map.y-319.f)<.001f);
    assert(std::fabs(1260*gauge.scale+gauge.x-1252)<.001f);
    assert(std::fabs(480*gauge.scale+gauge.y-76)<.001f);
    assert(std::fabs(72*map.scale+map.x-28)<.001f);
    const auto ipad=HudSafeFrame(1600,1100);
    const auto mapFrame=AnchoredHudFrame(ipad,1600,map);
    assert(mapFrame.left==0 && mapFrame.top==0 && mapFrame.height==900);
    assert(AnchoredHudFrame(ipad,1600,HudMove{}).top==100);
    const auto phone=HudSafeFrame(1600,720);
    assert(AnchoredHudFrame(phone,1600,gauge).left==320);
    assert(AnchoredHudFrame(phone,1600,map).left==0);
    assert(MovedHudEdge(0,1,-410,720) == 0);
    assert(MovedHudEdge(720,1,-410,720) == 310);
    assert(MovedHudEdge(720,1,100,720) == 720);
    assert(MovedHudEdge(550,1,-410*1.25,900) == 37);
    assert(MovedHudEdge(104,.78,35,1600) == 116);
    puts("Raised HUD: isolated panels, mixed/full-screen rejection, invalid bounds and translated scissor passed");
}
