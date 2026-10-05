// Standalone visual harness. Links the production launcher only, so screenshots
// don't need game data, run the emulated title, or affect a device's save files.
#import <UIKit/UIKit.h>
#import "MCLALauncherView.h"
#ifdef MCLA_LAUNCHER_INTEGRATION_TEST
UIViewController* MCLACreateLauncherTestController(void);
#endif
@interface PreviewController : UIViewController
@end
@implementation PreviewController
- (void)loadView {
    MCLALauncherView* launcher=[[MCLALauncherView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view=launcher;
    launcher.launchReady=YES;
    launcher.statusLabel.text=@"●  READY TO DRIVE";
    [launcher setGraphicsSummary:@"1080p SCENE   /   FSR ON   /   METAL"];
    [launcher setControllerConnected:YES];
    [launcher setSceneActive:YES];
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.view.window.windowScene requestGeometryUpdateWithPreferences:
        [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:self.supportedInterfaceOrientations]
        errorHandler:^(NSError* error) { NSLog(@"Preview orientation: %@",error); }];
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [NSProcessInfo.processInfo.environment[@"PREVIEW_LANDSCAPE"] boolValue]
        ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskPortrait;
}
@end
@interface PreviewScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow* window;
@end
@implementation PreviewScene
- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)options {
    (void)session; (void)options;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene*)scene];
#ifdef MCLA_LAUNCHER_INTEGRATION_TEST
    self.window.rootViewController=MCLACreateLauncherTestController();
#else
    self.window.rootViewController=[[PreviewController alloc] init];
#endif
    [self.window makeKeyAndVisible];
}
@end
@interface PreviewApp : UIResponder <UIApplicationDelegate>
@end
@implementation PreviewApp
@end
int main(int argc,char** argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(PreviewApp.class)); }
}
