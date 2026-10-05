#import <MetalKit/MetalKit.h>
#import <SceneKit/SceneKit.h>

// Launcher-only renderer. SceneKit supplies geometry/lighting; our floating-point
// Metal presentation preserves radiance above SDR white instead of flattening it.
@interface MCLALauncherSceneView : MTKView
@property(nonatomic,strong) SCNScene* scene;
@property(nonatomic,strong) SCNNode* pointOfView;
@property(nonatomic,copy) void (^updateScene)(CFTimeInterval time, CFTimeInterval delta);
- (instancetype)initWithFrame:(CGRect)frame;
- (void)setAnimating:(BOOL)animating;
@end
