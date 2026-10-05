// Layout study only: shipping UIKit controls plus captured HUD crops.
// No game runtime is linked and this does not verify live HUD relocation.
#import "MCLAViewController.h"
#import "MCLALauncherView.h"
#include "../../MCLAApp/runtime/MCLAControlOverhaul.h"
#include <cassert>
bool MCLAControlPreviewRightTrigger();
@interface MCLAViewController (ControlPreview)
- (void)refreshBringupStatus;
- (void)prepareGameDataFolderIfNeeded;
- (void)resetTouchLayout;
- (void)refreshTouchInputForGameVisible:(BOOL)visible;
- (void)applyTouchLayout;
- (void)gamepadButtonDown:(UIButton*)sender;
- (void)gamepadButtonUp:(UIButton*)sender;
- (void)pedalDown:(UIButton*)sender;
- (void)pedalUp:(UIButton*)sender;
@end
@interface ControlPreviewController : MCLAViewController
@property(nonatomic,strong) UIView* study;
@property(nonatomic,strong) UIImageView* scene;
@property(nonatomic,strong) NSArray<UIImageView*>* panels;
@property(nonatomic,strong) UILabel* studyCaption;
@end
@implementation ControlPreviewController
- (void)prepareGameDataFolderIfNeeded { [self setValue:NSHomeDirectory() forKey:@"gameRoot"]; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (void)viewDidLoad {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"MCLATouchEnabledControlOverhaulTest"];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"MCLAControlOverhaulTestEnabled"];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"MCLATiltEnabled"];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"MCLAFullPadVisible"];
    [super viewDidLoad];
    self.study=[[UIView alloc] init]; self.study.backgroundColor=[UIColor colorWithWhite:.045 alpha:1];
    [self.view insertSubview:self.study atIndex:1];
    UIImage* capture=[UIImage imageNamed:@"capture.png"];
    self.scene=[[UIImageView alloc] initWithImage:capture];
    // A center slice retains the driving scene without the original HUD panels.
    self.scene.layer.contentsRect=CGRectMake(.29,120.0/1312,.42,1072.0/1312);
    self.scene.contentMode=UIViewContentModeScaleToFill;
    [self.study addSubview:self.scene];
    NSMutableArray* panels=[NSMutableArray array];
    for (int i=0;i<2;++i) {
        UIImageView* panel=[[UIImageView alloc] initWithImage:capture];
        CGRect r=i==0 ? CGRectMake(72,440,258,270) : CGRectMake(900,480,360,230);
        panel.layer.contentsRect=CGRectMake(r.origin.x/1280,
            (120+r.origin.y*1072/720)/1312,r.size.width/1280,r.size.height*1072/720/1312);
        panel.contentMode=UIViewContentModeScaleToFill;
        [self.study addSubview:panel]; [panels addObject:panel];
    }
    self.panels=panels;
    self.studyCaption=[[UILabel alloc] init];
    self.studyCaption.text=@"LAYOUT STUDY · CAPTURED HUD / LIVE CONTROLS";
    self.studyCaption.textColor=[UIColor colorWithWhite:1 alpha:.65];
    self.studyCaption.font=[UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    self.studyCaption.textAlignment=NSTextAlignmentCenter;
    [self.study addSubview:self.studyCaption];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.view.window.windowScene requestGeometryUpdateWithPreferences:
        [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeRight]
        errorHandler:nil];
    MCLALauncherView* launcher=[self valueForKey:@"panel"];
    launcher.hidden=YES; [launcher setSceneActive:NO];
    [self refreshTouchInputForGameVisible:YES];
    [self.view setNeedsLayout];
    // Exercise overlap/release through the production event handlers.
    NSDictionary* controls=[self valueForKey:@"layoutControls"];
    UIButton* gas=controls[@"gas"]; UIButton* hb=controls[@"handbrake"];
    [self pedalDown:gas]; [self gamepadButtonDown:hb]; [self gamepadButtonUp:hb];
    assert([[self valueForKey:@"overhaulGasHeld"] boolValue]);
    assert(MCLAControlPreviewRightTrigger());
    assert(![[self valueForKey:@"overhaulHandbrakeHeld"] boolValue]);
    [self gamepadButtonDown:hb]; [self pedalUp:gas];
    assert([[self valueForKey:@"overhaulHandbrakeHeld"] boolValue]);
    assert(MCLAControlPreviewRightTrigger());
    [self gamepadButtonUp:hb];
    assert(!MCLAControlPreviewRightTrigger());
    NSUserDefaults* defaults=NSUserDefaults.standardUserDefaults;
    NSDictionary* baseline=@{@"gas":@[@.88,@.75]};
    [defaults setObject:baseline forKey:@"MCLATouchLayoutPositions"];
    [self resetTouchLayout];
    assert([[defaults dictionaryForKey:@"MCLATouchLayoutPositions"] isEqual:baseline]);
    assert([[defaults arrayForKey:@"MCLATouchActiveControlsOverhaul"] count]==4);
    [defaults setBool:NO forKey:@"MCLAControlOverhaulTestEnabled"];
    [self refreshTouchInputForGameVisible:YES];
    [self.view layoutIfNeeded];
    assert([[gas titleForState:UIControlStateNormal] isEqual:@"GAS\nRT"]);
    [defaults setBool:YES forKey:@"MCLAControlOverhaulTestEnabled"];
    [self refreshTouchInputForGameVisible:YES];
    NSLog(@"MCLA_CONTROL_PREVIEW PASS: production combined pedal overlap/release, isolated reset and original title restoration");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [self.view layoutIfNeeded];
        UIGraphicsImageRenderer* renderer=[[UIGraphicsImageRenderer alloc] initWithSize:self.view.bounds.size];
        UIImage* image=[renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
            (void)context; [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:YES];
        }];
        NSString* path=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/layout.png"];
        [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
        NSLog(@"MCLA_CONTROL_PREVIEW snapshot %@",path);
    });
}
- (void)refreshBringupStatus {
    if (!self.study) { [super refreshBringupStatus]; return; }
    ((UIView*)[self valueForKey:@"panel"]).hidden=YES;
    ((UIView*)[self valueForKey:@"touchControls"]).hidden=YES;
    ((UIView*)[self valueForKey:@"performanceGraph"]).hidden=YES;
    [self refreshTouchInputForGameVisible:YES];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
    self.study.frame=safe;
    CGFloat scale=MIN(safe.size.width/1280,safe.size.height/720);
    CGFloat left=(safe.size.width-1280*scale)/2, top=(safe.size.height-720*scale)/2;
    self.scene.frame=CGRectMake(left+330*scale,top,570*scale,720*scale);
    const mcla::metal::HudBounds bounds[]={{72,440,330,710},{900,480,1260,710}};
    for(int i=0;i<2;++i) {
        auto b=bounds[i]; auto move=mcla::metal::RaisedHudMove(b);
        self.panels[i].frame=CGRectMake((move.right ? safe.size.width-1280*scale : 0)+(b.left*move.scale+move.x)*scale,
            (b.top*move.scale+move.y)*scale,
            (b.right-b.left)*move.scale*scale,(b.bottom-b.top)*move.scale*scale);
    }
    self.studyCaption.frame=CGRectMake(left+300*scale,top+20*scale,680*scale,20*scale);
}
@end
UIViewController* MCLACreateLauncherTestController(void) { return [[ControlPreviewController alloc] init]; }
