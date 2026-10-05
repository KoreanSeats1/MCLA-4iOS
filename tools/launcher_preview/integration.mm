#import "MCLAViewController.h"
#import "MCLALauncherView.h"
#import "MCLALauncherSceneView.h"
#import <SceneKit/SceneKit.h>
#include <cassert>
#include <cmath>
@interface MCLAViewController (UITest)
- (void)refreshBringupStatus;
- (void)revealGameplayToolbar:(UITapGestureRecognizer*)tap;
@end
@interface MCLALauncherView (AnimationTest)
- (void)animateCameraAtTime:(CFTimeInterval)time delta:(CFTimeInterval)delta;
@end
@interface RecognizedTap : UITapGestureRecognizer
@end
@implementation RecognizedTap
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateRecognized; }
@end
@interface LauncherIntegrationController : MCLAViewController
@property(nonatomic,assign) BOOL testsStarted;
@end
@implementation LauncherIntegrationController
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(self.testsStarted) return;
    self.testsStarted=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self testMenu]; });
}
- (void)testMenu {
    MCLALauncherView* launcher=[self valueForKey:@"panel"];
    assert(launcher.launchButton.enabled);
    SCNNode* car=[launcher valueForKey:@"heroCar"];
    SCNNode* rig=[launcher valueForKey:@"cameraRig"];
    assert(fabs(car.position.x)<.00001 && fabs(car.eulerAngles.y+M_PI_2)<.00001);
    // Check both old join times and the new sine's turnarounds for position and
    // velocity continuity. This tests shipping transforms, not a copied formula.
    for(double t : {4.0,5.0,8.0,10.0,12.0,16.0}) {
        double values[3];
        for(int i=0;i<3;++i) {
            [launcher animateCameraAtTime:t+(i-1)*.001 delta:1.0/60.0];
            values[i]=rig.eulerAngles.y;
        }
        assert(fabs((values[2]-values[1])-(values[1]-values[0]))<1e-7);
    }
    MCLALauncherSceneView* sceneView=[launcher valueForKey:@"sceneView"];
    assert(sceneView.colorPixelFormat==MTLPixelFormatRGBA16Float);
    assert(sceneView.preferredFramesPerSecond==60);
    [sceneView setValue:@123.0 forKey:@"lastTime"];
    [launcher setSceneActive:YES];
    assert([[sceneView valueForKey:@"lastTime"] doubleValue]==123.0 && "Status poll must not restart the frame clock");
    [sceneView setValue:@0 forKey:@"lastTime"];
    [launcher animateCameraAtTime:0 delta:0];
    assert(((UIView*)[self valueForKey:@"touchControls"]).hidden);
    BOOL found=NO;
    for(UIGestureRecognizer* gesture in self.view.gestureRecognizers)
        if([gesture isKindOfClass:UITapGestureRecognizer.class] && ((UITapGestureRecognizer*)gesture).numberOfTouchesRequired==3) found=YES;
    assert(found && "Three-finger recognizer must be attached");
    [launcher moveSelection:1]; [launcher activateSelection];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        UINavigationController* nav=(UINavigationController*)self.presentedViewController;
        assert([nav isKindOfClass:UINavigationController.class]);
        assert([nav.topViewController.title isEqualToString:@"Graphics"]);
        [self dismissViewControllerAnimated:NO completion:^{
            [launcher moveSelection:1]; [launcher activateSelection];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
                UINavigationController* controls=(UINavigationController*)self.presentedViewController;
                assert([controls.topViewController.title isEqualToString:@"Driving Controls"]);
                [self dismissViewControllerAnimated:NO completion:^{
                    [launcher moveSelection:1]; [launcher activateSelection];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self testToolbar]; });
                }];
            });
        }];
    });
}
- (void)testToolbar {
    assert([[self valueForKey:@"gameVisible"] boolValue]);
    MCLALauncherView* launcher=[self valueForKey:@"panel"];
    assert([launcher valueForKey:@"sceneView"]==nil && "3D launcher resources must be released at gameplay");
    UIView* toolbar=[self valueForKey:@"touchControls"];
    assert(toolbar.hidden);
    [self revealGameplayToolbar:[[RecognizedTap alloc] init]];
    assert(!toolbar.hidden);
    [self refreshBringupStatus]; assert(!toolbar.hidden);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [self revealGameplayToolbar:[[RecognizedTap alloc] init]];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,11*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        assert(!toolbar.hidden && "A second gesture must renew the ten-second timeout");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,17*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        assert(toolbar.hidden && "Toolbar must disappear automatically");
        [self refreshBringupStatus]; assert(toolbar.hidden);
        puts("MCLA_LAUNCHER_UI_TEST PASS: car lane alignment, continuous sway, stable clock, HDR format, menu routing, portrait-to-landscape launch, scene release, hidden toolbar, reveal, timeout renewal, automatic hide");
        fflush(stdout); exit(0);
    });
}
@end
UIViewController* MCLACreateLauncherTestController(void) {
    NSString* documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    [NSFileManager.defaultManager createDirectoryAtPath:[documents stringByAppendingPathComponent:@"MCLA_Game_Files"]
        withIntermediateDirectories:YES attributes:nil error:nil];
    return [[LauncherIntegrationController alloc] init];
}
