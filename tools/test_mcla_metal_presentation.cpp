#include "../MCLAApp/runtime/MCLAMetalPresentation.h"
#include <cassert>
#include <cmath>
#include <cstdio>
int main(){
  using namespace mcla::metal;
  for(unsigned height : {720u,900u,1080u}) {
    auto scene=RenderSize(height);
    assert(scene.height==height && scene.width*9==height*16);
    auto output=OutputForSettings(height,false,2816,1940);
    assert(output.width==scene.width && output.height==scene.height);
    assert(OutputForSettings(height,true,2816,1940).width==2816);
    assert(SceneExtent(1280,720,height).height==height);
    for(auto size : {OutputSize{1280,1280},OutputSize{640,640},
                    OutputSize{320,180},OutputSize{256,256}}) {
      assert(SceneExtent(size.width,size.height,height).height==size.height);
      assert(SceneTextureFlags(size.width,size.height,height)==0);
    }
    // Full-scene depth band resolves cover 512+208 rows without a gap.
    auto upper=ScaleResolveSpan(720,height,720,height,0,0,512);
    auto lower=ScaleResolveSpan(720,height,720,height,512,512,208);
    assert(upper.sourceSize+lower.sourceSize==height);
    assert(upper.destination+upper.destinationSize==lower.destination);
    assert(lower.source+lower.sourceSize==height);
    assert(ScaleResolveSpan(720,height,720,height,720,0,10).sourceSize==0);
    // Resolve scene to an unscaled postprocess texture: both coordinate spaces.
    auto down=ScaleResolveSpan(720,height,180,180,0,0,180);
    assert(down.sourceSize==height/4 && down.destinationSize==180);
    // Odd mip heights and one-pixel strips must meet at the same endpoint.
    for(unsigned mip=0;mip<10;++mip) {
      unsigned logical=std::max(1u,720u>>mip), physical=std::max(1u,height>>mip);
      unsigned total=0;
      for(unsigned y=0;y<logical;++y) {
        auto span=ScaleResolveSpan(logical,physical,logical,physical,y,y,1);
        assert(span.source==total && span.destination==total);
        total+=span.sourceSize;
      }
      assert(total==physical);
    }
    for(unsigned gamma : {0u,0x80000000u}) {
      unsigned flags=SceneTextureFlags(1280,720,height);
      for(unsigned slot=0;slot<26;++slot)assert(((slot|flags|gamma)&0x1fffffffu)==slot);
    }
  }
  assert(RenderHeight(0)==720 && RenderHeight(1081)==720);
  const auto full=OutputForSettings(720,true,2816,1940);
  assert(full.width==2816 && full.width*9==full.height*16);
  assert(OutputForSettings(1080,true,0,0).width==1920);
  // The physical iPad screen, rather than the letterboxed UIKit view, must
  // drive FSR's output extent even when the internal scene is 1080p.
  const auto ipadNative=OutputForSettings(1080,true,2752,2064);
  assert(ipadNative.width*9==ipadNative.height*16);
  assert(ipadNative.height>RenderSize(1080).height);
  assert(OutputForSettings(720,true,99999,99999).width<=3840);
  const auto tall=SceneSize(900,1280,960);
  assert(tall.width==1600 && tall.height==1200);
  assert(SceneExtent(1280,720,900,1280,960).height==1200);
  assert(SceneTextureFlags(1280,720,900,1280,960)==0x50000000u);
  assert(OutputForSettings(900,true,2816,1940,1280,880).height==1940);
  const auto ipadHud=HudSafeFrame(1600,1100);
  assert(ipadHud.left==0 && ipadHud.top==100 &&
         ipadHud.width==1600 && ipadHud.height==900);
  const auto phoneHud=HudSafeFrame(1950,900);
  assert(phoneHud.left==175 && phoneHud.top==0 &&
         phoneHud.width==1600 && phoneHud.height==900);
  const auto originalHud=HudSafeFrame(1600,900);
  assert(originalHud.left==0 && originalHud.top==0 &&
         originalHud.width==1600 && originalHud.height==900);
  PresentationClock sixty;
  double last=sixty.Plan(10,60);
  for(int i=1;i<120;++i) {
    double target=sixty.Plan(10+i/60.0+(i%2?.001:-.001),60);
    assert(std::abs(target-last-1.0/60)<1e-9); last=target;
  }
  double switched=sixty.Plan(20,30);
  assert(std::abs(switched-20-1.0/30)<1e-9);
  assert(sixty.Plan(30,60)>30); // late frames rebase, no catch-up burst
  PresentationClock clock;
  double previous=clock.Plan(10);
  for(unsigned i=1;i<300;++i){
    double target=clock.Plan(10+i*PresentationClock::period+(i%2?.002:-.002));
    assert(std::abs(target-previous-PresentationClock::period)<1e-9);
    previous=target;
  }
  assert(clock.resyncs==0);
  auto recovered=clock.Plan(30);
  assert(recovered>30 && recovered<30.1 && clock.resyncs==1);
  std::puts("PASS: 720/900/1080 scene + independent FSR, unchanged shadow targets, scaled resolve/mip boundaries, descriptor flags, fixed-phase 30fps.");
}
