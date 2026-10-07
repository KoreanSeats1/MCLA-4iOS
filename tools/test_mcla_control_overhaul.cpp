#include "../MCLAApp/runtime/MCLAControlOverhaul.h"
#include <cassert>
#include <limits>
#include <cstdio>
#include <vector>
#include <random>
int main() {
    using namespace mcla::metal;
    // Cached whole-draw projections preserve each independently classified
    // primitive, including a maximum-size quad batch and invalid coordinates.
    std::vector<std::array<float,2>> points(4096);
    std::mt19937 rng(713);
    std::uniform_real_distribution<float> xy(-500,1500);
    for (auto& p:points) p={xy(rng),xy(rng)};
    for (unsigned step:{3u,4u}) {
        for (unsigned first=0;first+step<=points.size();first+=step) {
            auto box=HudPointBounds(std::span<const std::array<float,2>>(points).subspan(first,step));
            assert(box);
            for (unsigned i=0;i<step;++i) {
                const auto& p=points[first+i];
                assert(box->left<=p[0] && box->right>=p[0] && box->top<=p[1] && box->bottom>=p[1]);
            }
        }
    }
    assert(HudPointBounds(points));
    assert(!HudPointBounds(std::span<const std::array<float,2>>(points).first(2)));
    points[4][0]=NAN; assert(!HudPointBounds(points));
    points[4][0]=INFINITY; assert(!HudPointBounds(points));
    points.resize(4097); assert(!HudPointBounds(points));
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
    assert(RaisedHudMove({75,430,305,685}).y == 0); // oversized off-center panel
    assert(RaisedHudMove({305,460,75,685}).y == 0);
    assert(RaisedHudMove({NAN,460,305,685}).y == 0);
    const auto map=RaisedHudMove({72,440,330,710});
    const auto ring=RaisedHudMove({23.3f,407.6f,359.8f,744.2f});
    assert(ring.scale==map.scale && ring.x==map.x && ring.y==map.y);
    // Every heading keeps the padded circular texture on the same map frame.
    for (int degrees=0;degrees<360;++degrees) {
        const float a=degrees*3.14159265358979323846f/180;
        const float half=168.3f*(std::fabs(std::sin(a))+std::fabs(std::cos(a)));
        const auto rotated=RaisedHudMove({191.5f-half,576.f-half,191.5f+half,576.f+half});
        assert(rotated.scale==map.scale && rotated.x==map.x && rotated.y==map.y);
        // A rotating GPS pointer outside the street-fill rectangle.
        const float cx=191.5f+145*std::cos(a), cy=576+145*std::sin(a);
        const float arrowHalf=28*(std::fabs(std::sin(a))+std::fabs(std::cos(a)));
        const auto arrow=RaisedHudMove({cx-arrowHalf,cy-arrowHalf,cx+arrowHalf,cy+arrowHalf});
        assert(arrow.scale==map.scale && arrow.x==map.x && arrow.y==map.y);
    }
    assert(RaisedHudMove({0,350,600,800}).y==0); // unrelated large lower-left panel
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
