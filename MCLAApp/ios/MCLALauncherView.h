#import <UIKit/UIKit.h>

// The launcher owns its scene and can release all rendering resources once
// gameplay starts. No SceneKit work is scheduled over the game's Metal view.
@interface MCLALauncherView : UIView
@property(nonatomic, readonly) UIButton* launchButton;
@property(nonatomic, readonly) UIButton* graphicsButton;
@property(nonatomic, readonly) UIButton* controlsButton;
@property(nonatomic, readonly) UIButton* savesButton;
@property(nonatomic, readonly) UILabel* statusLabel;
@property(nonatomic, readonly) UILabel* detailLabel;
@property(nonatomic, assign) BOOL launchReady;
- (void)setSceneActive:(BOOL)active;
- (void)releaseScene;
- (void)moveSelection:(NSInteger)direction;
- (void)activateSelection;
- (void)adjustCameraWithX:(float)x y:(float)y;
- (void)setControllerConnected:(BOOL)connected;
- (void)setGraphicsSummary:(NSString*)summary;
- (void)setLaunching:(BOOL)launching;
@end
