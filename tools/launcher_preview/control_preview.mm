// Layout study only: shipping UIKit controls plus captured HUD crops.
// No game runtime is linked and this does not verify live HUD relocation.
#import "MCLAViewController.h"
#import "MCLALauncherView.h"
#include "../../MCLAApp/runtime/MCLAControlOverhaul.h"
#include <cassert>
#import "MCLAControlArtwork.h"
bool MCLAControlPreviewRightTrigger();
bool MCLAControlPreviewLeftTrigger();
uint16_t MCLAControlPreviewButtons();
@interface UIView (SlidingTest)
- (NSUInteger)inputsAtPoint:(CGPoint)point previous:(NSUInteger)previous;
- (void)moveFinger:(NSValue*)key toPoint:(CGPoint)point;
- (void)endFinger:(NSValue*)key;
- (void)reset;
@end
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
    // Exercise the shipping cached art states, not a duplicate test renderer.
    [self.view layoutIfNeeded];
    NSDictionary* artControls=[self valueForKey:@"layoutControls"];
    UIButton* nitro=artControls[@"nitro"];
    UIImageView* art=[nitro valueForKey:@"artworkView"];
    UIImage* normal=art.image;
    assert(normal && normal.size.width>0);
    nitro.highlighted=YES; UIImage* pressed=art.image;
    assert(pressed && pressed!=normal && nitro.highlighted);
    nitro.highlighted=NO; assert(art.image==normal);
    nitro.enabled=NO; assert(art.image!=normal && art.image!=pressed);
    nitro.enabled=YES; assert(art.image==normal);
    assert([[nitro titleColorForState:UIControlStateNormal] isEqual:UIColor.clearColor]);
    assert(!art.userInteractionEnabled);
    UIButton* camera=artControls[@"camera"];
    assert([camera.gestureRecognizers filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIGestureRecognizer* g, NSDictionary* bindings) {
        (void)bindings; return [g isKindOfClass:UIPanGestureRecognizer.class] || [g isKindOfClass:UIPinchGestureRecognizer.class];
    }]].count==2);
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
    assert([[defaults arrayForKey:@"MCLATouchActiveControlsOverhaul"] count]==12);
    [defaults setBool:NO forKey:@"MCLAControlOverhaulTestEnabled"];
    [self refreshTouchInputForGameVisible:YES];
    [self.view layoutIfNeeded];
    assert([[gas titleForState:UIControlStateNormal] isEqual:@"GAS\nRT"]);
    [defaults setBool:YES forKey:@"MCLAControlOverhaulTestEnabled"];
    [self refreshTouchInputForGameVisible:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self verifySlidingControls]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [self.view layoutIfNeeded];
        UIGraphicsImageRenderer* renderer=[[UIGraphicsImageRenderer alloc] initWithSize:self.view.bounds.size];
        UIImage* image=[renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
            (void)context; [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:YES];
        }];
        NSString* path=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/layout.png"];
        [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
        UIGraphicsImageRenderer* sheet=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1280,640)];
        UIImage* atlas=[sheet imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [[UIColor colorWithRed:.025 green:.06 blue:.08 alpha:1] setFill]; CGContextFillRect(context.CGContext,CGRectMake(0,0,1280,640));
            NSArray* keys=@[@"pause",@"camera",@"nitro",@"ability",@"brake",@"weight",@"headlights",@"track_left",@"track_right",@"gas_handbrake"];
            NSArray* labels=@[@"",@"CAMERA",@"NITRO",@"ABILITY",@"BRAKE / REV",@"WEIGHT",@"LIGHTS",@"TRACK BACK",@"TRACK NEXT",@"GAS +\nHANDBRAKE"];
            for(int state=0;state<3;++state) {
                for(NSUInteger i=0;i<keys.count;++i) {
                    UIImage* asset=MCLAControlArtwork(keys[i],labels[i],CGSizeMake(108,145),state==1,state!=2,0);
                    [asset drawInRect:CGRectMake(20+i*124,40+state*190,108,145)];
                }
                NSString* name=@[@"NORMAL",@"PRESSED",@"DISABLED"][state];
                [name drawAtPoint:CGPointMake(24,16+state*190) withAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor,NSFontAttributeName:[UIFont systemFontOfSize:12 weight:UIFontWeightBold]}];
            }
        }];
        [UIImagePNGRepresentation(atlas) writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/button-artwork.png"] atomically:YES];
        NSLog(@"MCLA_CONTROL_PREVIEW snapshot %@",path);
    });
}
- (void)verifySlidingControls {
    [self.view layoutIfNeeded];
    NSDictionary* controls=[self valueForKey:@"layoutControls"];
    UIButton* gas=controls[@"gas"],*hb=controls[@"handbrake"];
    [self refreshTouchInputForGameVisible:YES];
    UIView* router=[self valueForKey:@"slideControls"];
    UIButton* brake=controls[@"brake"], *weight=controls[@"weight"];
    CGPoint gp=[gas convertPoint:CGPointMake(gas.bounds.size.width/2,gas.bounds.size.height/2) toView:router];
    CGPoint hp=[hb convertPoint:CGPointMake(hb.bounds.size.width/2,hb.bounds.size.height/2) toView:router];
    CGPoint bp=[brake convertPoint:CGPointMake(brake.bounds.size.width/2,brake.bounds.size.height/2) toView:router];
    CGPoint wp=[weight convertPoint:CGPointMake(weight.bounds.size.width/2,weight.bounds.size.height/2) toView:router];
    CGPoint blend=CGPointMake((hp.x+bp.x)/2,(hp.y+bp.y)/2);
    NSValue* finger=[NSValue valueWithPointer:(void*)1],*second=[NSValue valueWithPointer:(void*)2];
    assert([router hitTest:gp withEvent:nil]==router);
    [router moveFinger:finger toPoint:gp]; assert(MCLAControlPreviewRightTrigger() && !MCLAControlPreviewLeftTrigger());
    [router moveFinger:finger toPoint:hp]; assert(MCLAControlPreviewRightTrigger() && (MCLAControlPreviewButtons() & 0x1000));
    [router moveFinger:finger toPoint:blend]; assert(MCLAControlPreviewRightTrigger() && MCLAControlPreviewLeftTrigger() && (MCLAControlPreviewButtons() & 0x1000));
    [router moveFinger:finger toPoint:bp]; assert(!MCLAControlPreviewRightTrigger() && MCLAControlPreviewLeftTrigger());
    [router moveFinger:finger toPoint:wp]; assert(MCLAControlPreviewLeftTrigger() && (MCLAControlPreviewButtons() & 0x2000));
    [router moveFinger:finger toPoint:gp]; assert(MCLAControlPreviewRightTrigger() && !(MCLAControlPreviewButtons() & 0x2000));
    [router moveFinger:finger toPoint:wp]; assert(MCLAControlPreviewRightTrigger() && (MCLAControlPreviewButtons() & 0x2000));
    [router moveFinger:second toPoint:bp]; assert(MCLAControlPreviewLeftTrigger());
    [router endFinger:finger]; assert(!MCLAControlPreviewRightTrigger() && MCLAControlPreviewLeftTrigger() && !(MCLAControlPreviewButtons() & 0x2000));
    [router reset]; assert(!MCLAControlPreviewRightTrigger() && !MCLAControlPreviewLeftTrigger() && !MCLAControlPreviewButtons());
    // Sliding off all zones releases the previous driving state as well.
    [router moveFinger:finger toPoint:gp]; [router moveFinger:finger toPoint:CGPointMake(600,50)];
    assert(!MCLAControlPreviewRightTrigger()); [router endFinger:finger];
    NSLog(@"MCLA_CONTROL_PREVIEW PASS: cached normal/pressed/disabled artwork, edit gestures, combined pedal overlap/release and isolated layout preferences, continuous slides, three-input blend, weight hold/release, independent fingers and cancellation");
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
