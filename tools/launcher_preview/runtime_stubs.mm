// UI-only simulator integration. Never linked into the shipping app.
#import <UIKit/UIKit.h>
#import "MCLAMetalView.h"
#include "MCLAHostBridge.h"
#include "MCLAGraphicsFoundation.h"
#include "MCLABootstrapSubsystems.h"
#include <cassert>
static bool started=false;
@implementation MCLAMetalView
- (BOOL)isMetalReady { return YES; }
@end
extern "C" {
uint32_t MCLAHostBridgeVersion(void) { return 2; }
bool MCLAHostInspectGameData(const char*,MCLADataReport* r) { *r={}; r->ready=true; return true; }
bool MCLAHostStartRuntime(const char*,char*,uint32_t) {
    UIWindowScene* scene=(UIWindowScene*)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIView* view=scene.windows.firstObject.rootViewController.view;
    assert(view.bounds.size.width>view.bounds.size.height && "Runtime must begin in landscape");
    started=true; return true;
}
void MCLAHostGetRuntimeReport(MCLARuntimeReport* r) { *r={}; r->available=true; r->running=started; r->entryReached=started; }
void MCLAGraphicsGetReport(MCLAGraphicsReport* r) { *r={}; r->metalPresenterReady=true; r->titleDrivenFrames=started?1:0; }
void MCLAGraphicsConfigureNativeAspect(uint32_t,uint32_t,bool) {}
void MCLAGraphicsConfigureOutput(uint32_t,bool) {}
uint32_t MCLAGraphicsCopyFrameTiming(MCLAFrameTimingSample*,uint32_t,float*,float*) { return 0; }
double MCLAGraphicsPerformanceCaptureRemainingSeconds(void) { return -1; }
bool MCLAGraphicsStartPerformanceCapture(void) { return true; }
void MCLAGraphicsFinishPerformanceCapture(void) {}
}
void MCLASetVirtualGamepadButton(uint16_t,bool) {}
void MCLASetVirtualGamepadTrigger(bool,bool) {}
void MCLASetVirtualGamepadLeftStick(float,float,bool) {}
void MCLASetVirtualGamepadRightStick(float,float,bool) {}
void MCLASetVirtualGamepadTilt(float,bool) {}
void MCLAResetVirtualGamepad() {}
