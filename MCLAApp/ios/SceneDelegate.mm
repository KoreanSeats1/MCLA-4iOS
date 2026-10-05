#import "SceneDelegate.h"
#import "MCLAViewController.h"

@implementation SceneDelegate

- (void)sceneWillResignActive:(UIScene*)scene {
    (void)scene;
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}

- (void)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
    options:(UISceneConnectionOptions*)connectionOptions {
    (void)session;
    (void)connectionOptions;

    if (![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }

    UIWindowScene* windowScene = (UIWindowScene*)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = [[MCLAViewController alloc] init];
    [self.window makeKeyAndVisible];
}

@end
