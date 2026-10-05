#import "MCLALauncherView.h"
#import "MCLALauncherSceneView.h"
#import <SceneKit/SceneKit.h>
#include <cmath>
#include <vector>

static UIColor* Ink(void) { return [UIColor colorWithRed:.025 green:.037 blue:.055 alpha:1]; }
static UIColor* Amber(void) { return [UIColor colorWithRed:1 green:.67 blue:.31 alpha:1]; }
static UIColor* Cream(void) { return [UIColor colorWithRed:.96 green:.93 blue:.86 alpha:1]; }
static SCNMaterial* Surface(UIColor* color, CGFloat metal, CGFloat rough) {
    SCNMaterial* m = [SCNMaterial material];
    m.lightingModelName = SCNLightingModelPhysicallyBased;
    m.diffuse.contents = color;
    m.metalness.contents = @(metal);
    m.roughness.contents = @(rough);
    return m;
}
static SCNMaterial* Glow(UIColor* color) {
    SCNMaterial* m = [SCNMaterial material];
    m.lightingModelName = SCNLightingModelConstant;
    m.diffuse.contents = UIColor.blackColor;
    m.emission.contents = color;
    m.emission.intensity = 3.0;
    return m;
}
static SCNNode* Box(SCNNode* parent, float x, float y, float z,
                    float w, float h, float d, CGFloat radius, SCNMaterial* m) {
    SCNBox* box = [SCNBox boxWithWidth:w height:h length:d chamferRadius:radius];
    box.chamferSegmentCount = 3;
    box.materials = @[m];
    SCNNode* node = [SCNNode nodeWithGeometry:box];
    node.position = SCNVector3Make(x,y,z);
    [parent addChildNode:node];
    return node;
}
static SCNNode* Cylinder(SCNNode* parent, float radius, float height,
                         SCNVector3 position, SCNMaterial* material) {
    SCNCylinder* shape = [SCNCylinder cylinderWithRadius:radius height:height];
    shape.radialSegmentCount = 64;
    shape.materials = @[material];
    SCNNode* node = [SCNNode nodeWithGeometry:shape];
    node.position = position;
    [parent addChildNode:node];
    return node;
}
static SCNNode* Ring(SCNNode* parent, float radius, float tube, float y, SCNMaterial* m) {
    SCNTorus* torus = [SCNTorus torusWithRingRadius:radius pipeRadius:tube];
    torus.ringSegmentCount = 128;
    torus.pipeSegmentCount = 6;
    torus.materials = @[m];
    SCNNode* n = [SCNNode nodeWithGeometry:torus];
    n.position = SCNVector3Make(0,y,0);
    [parent addChildNode:n];
    return n;
}
static UIImage* Windows(void) {
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(128,256) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [[UIColor colorWithRed:.09 green:.13 blue:.17 alpha:1] setFill];
            UIRectFill(CGRectMake(0,0,128,256));
            for (int y=0;y<32;++y) for (int x=0;x<12;++x) {
                unsigned seed = (x*37+y*91+17) % 19;
                UIColor* c = seed<6 ? [UIColor colorWithRed:.9 green:.64 blue:.34 alpha:1]
                    : seed<10 ? [UIColor colorWithRed:.27 green:.45 blue:.55 alpha:1]
                    : [UIColor colorWithRed:.035 green:.055 blue:.085 alpha:1];
                [c setFill];
                UIRectFill(CGRectMake(3+x*10,3+y*8,6,4));
            }
            (void)context;
        }];
}

static SCNNode* BuildCar(void) {
    SCNNode* car = [SCNNode node];
    SCNMaterial* paint = Surface([UIColor colorWithRed:.68 green:.20 blue:.09 alpha:1],.72,.24);
    SCNMaterial* glass = Surface([UIColor colorWithRed:.035 green:.09 blue:.12 alpha:1],.85,.14);
    SCNMaterial* black = Surface([UIColor colorWithWhite:.025 alpha:1],.2,.6);
    SCNMaterial* chrome = Surface([UIColor colorWithWhite:.52 alpha:1],.95,.2);
    SCNMaterial* white = Glow([UIColor colorWithRed:1 green:.89 blue:.65 alpha:1]);
    SCNMaterial* red = Glow([UIColor colorWithRed:1 green:.075 blue:.025 alpha:1]);
    white.emission.intensity=7.0;
    red.emission.intensity=4.5;
    // A sculpted coupe profile. Extrusion gives a continuous shoulder and
    // angled nose; the glasshouse is a separate tapered silhouette.
    UIBezierPath* profile = [UIBezierPath bezierPath];
    [profile moveToPoint:CGPointMake(-2.65,.42)];
    [profile addLineToPoint:CGPointMake(-2.5,1.04)];
    [profile addLineToPoint:CGPointMake(-1.28,1.20)];
    [profile addLineToPoint:CGPointMake(.98,1.18)];
    [profile addLineToPoint:CGPointMake(2.50,.86)];
    [profile addLineToPoint:CGPointMake(2.7,.53)];
    [profile addLineToPoint:CGPointMake(2.45,.33)];
    [profile addLineToPoint:CGPointMake(-2.4,.33)];
    [profile closePath];
    SCNShape* body = [SCNShape shapeWithPath:profile extrusionDepth:1.94];
    body.chamferRadius = .075;
    body.materials = @[paint];
    [car addChildNode:[SCNNode nodeWithGeometry:body]];
    UIBezierPath* cabinPath = [UIBezierPath bezierPath];
    [cabinPath moveToPoint:CGPointMake(-1.65,1.12)];
    [cabinPath addLineToPoint:CGPointMake(-.87,1.62)];
    [cabinPath addLineToPoint:CGPointMake(.30,1.60)];
    [cabinPath addLineToPoint:CGPointMake(1.55,1.13)];
    [cabinPath closePath];
    SCNShape* cabin = [SCNShape shapeWithPath:cabinPath extrusionDepth:1.63];
    cabin.chamferRadius = .025;
    cabin.materials = @[glass];
    [car addChildNode:[SCNNode nodeWithGeometry:cabin]];
    Box(car,-.27,1.63,0,1.24,.065,1.68,.03,paint);
    for (float z : {-0.84f,0.84f}) {
        Box(car,-.38,1.36,z,.055,.5,.065,.015,paint);
        Box(car,-.40,1.12,z,2.4,.065,.12,.02,chrome);
        Box(car,.10,1.00,z*1.18,.33,.055,.045,.02,chrome);
        Box(car,.96,1.30,z*1.17,.32,.15,.25,.05,paint);
    }
    Box(car,2.63,.57,0,.12,.23,1.85,.025,black);
    Box(car,-2.58,.55,0,.12,.18,1.85,.025,black);
    Box(car,2.61,.86,-.65,.10,.11,.44,.018,white);
    Box(car,2.61,.86,.65,.10,.11,.44,.018,white);
    Box(car,-2.58,.85,0,.10,.10,1.67,.012,red);
    Box(car,-2.16,1.20,0,.42,.08,2.10,.025,black);
    for(int i=0;i<6;++i) Box(car,-1.18-i*.16,1.22,0,.06,.028,1.48,.008,black);
    for(float z : {-.68f,.68f}) Box(car,1.9,1.02,z,.45,.025,.24,.01,black);
    for (float x : {-1.67f,1.67f}) for (float z : {-1.0f,1.0f}) {
        SCNNode* tire = Cylinder(car,.48,.28,SCNVector3Make(x,.48,z),black);
        tire.eulerAngles = SCNVector3Make(M_PI_2,0,0);
        SCNNode* rim = Cylinder(car,.33,.29,SCNVector3Make(x,.48,z),chrome);
        rim.eulerAngles = SCNVector3Make(M_PI_2,0,0);
        SCNNode* hub = Cylinder(car,.22,.305,SCNVector3Make(x,.48,z),black);
        hub.eulerAngles = SCNVector3Make(M_PI_2,0,0);
        for (int i=0;i<5;++i) {
            float a=i*2*M_PI/5;
            SCNNode* spoke=Box(car,x+sin(a)*.15,.48+cos(a)*.15,z*1.155,
                              .06,.30,.035,.01,chrome);
            spoke.eulerAngles=SCNVector3Make(0,0,-a);
        }
    }
    return car;
}

static void AddPalm(SCNNode* parent, float x, float z, float height) {
    SCNMaterial* bark=Surface([UIColor colorWithRed:.20 green:.13 blue:.10 alpha:1],0,.9);
    SCNMaterial* leaf=Surface([UIColor colorWithRed:.10 green:.25 blue:.22 alpha:1],.1,.65);
    leaf.doubleSided=YES;
    SCNNode* palm=[SCNNode node];
    palm.position=SCNVector3Make(x,0,z);
    SCNCone* trunk=[SCNCone coneWithTopRadius:.045 bottomRadius:.115 height:height];
    trunk.radialSegmentCount=8; trunk.materials=@[bark];
    SCNNode* t=[SCNNode nodeWithGeometry:trunk];
    t.position=SCNVector3Make(0,height/2,0);
    [palm addChildNode:t];
    for(int i=0;i<9;++i) {
        UIBezierPath* p=[UIBezierPath bezierPath];
        [p moveToPoint:CGPointZero];
        [p addQuadCurveToPoint:CGPointMake(1.65,-.48) controlPoint:CGPointMake(.95,.66)];
        [p addQuadCurveToPoint:CGPointZero controlPoint:CGPointMake(.65,.12)];
        SCNShape* s=[SCNShape shapeWithPath:p extrusionDepth:.015]; s.materials=@[leaf];
        SCNNode* frond=[SCNNode nodeWithGeometry:s];
        frond.position=SCNVector3Make(0,height,0);
        frond.eulerAngles=SCNVector3Make(.22,i*2*M_PI/9,0);
        [palm addChildNode:frond];
    }
    [parent addChildNode:palm];
}

@interface MCLALauncherView () <UIGestureRecognizerDelegate>
@property(nonatomic,strong) MCLALauncherSceneView* sceneView;
@property(nonatomic,strong) SCNNode* cameraRig;
@property(nonatomic,strong) SCNNode* cameraNode;
@property(nonatomic,strong) UIView* shade;
@property(nonatomic,strong) CAGradientLayer* gradient;
@property(nonatomic,strong) UILabel* masthead;
@property(nonatomic,strong) UILabel* edition;
@property(nonatomic,strong) UILabel* eyebrow;
@property(nonatomic,strong) UILabel* title;
@property(nonatomic,strong) UILabel* subtitle;
@property(nonatomic,strong) UILabel* sceneCaption;
@property(nonatomic,strong) UILabel* footer;
@property(nonatomic,strong) UILabel* graphicsSummaryLabel;
@property(nonatomic,strong) UILabel* shortcutHint;
@property(nonatomic,strong) UIView* rule;
@property(nonatomic,strong) UIButton* launchButton;
@property(nonatomic,strong) UIButton* graphicsButton;
@property(nonatomic,strong) UIButton* controlsButton;
@property(nonatomic,strong) UIButton* savesButton;
@property(nonatomic,strong) UILabel* statusLabel;
@property(nonatomic,strong) UILabel* detailLabel;
@property(nonatomic,assign) NSInteger selection;
@property(nonatomic,assign) BOOL launching;
@property(nonatomic,assign) BOOL sceneActive;
@property(nonatomic,assign) CGFloat cameraYaw;
@property(nonatomic,assign) CGFloat cameraPitch;
@property(nonatomic,assign) CGFloat smoothedYaw;
@property(nonatomic,assign) CGFloat smoothedPitch;
@property(nonatomic,strong) SCNNode* heroCar;
@property(nonatomic,strong) SCNNode* heroPool;
@end

@implementation MCLALauncherView

- (UILabel*)label:(NSString*)text size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel* label=[[UILabel alloc] init];
    label.text=text; label.textColor=Cream();
    label.font=[UIFont systemFontOfSize:size weight:weight];
    [self addSubview:label]; return label;
}
- (UIButton*)command:(NSString*)title symbol:(NSString*)symbol tag:(NSInteger)tag {
    UIButton* button=[UIButton buttonWithType:UIButtonTypeSystem];
    button.tag=tag;
    UIButtonConfiguration* config=[UIButtonConfiguration plainButtonConfiguration];
    config.title=title;
    config.image=[UIImage systemImageNamed:symbol];
    config.imagePadding=12;
    config.contentInsets=NSDirectionalEdgeInsetsMake(16,20,16,20);
    config.baseForegroundColor=Cream();
    config.titleTextAttributesTransformer=^NSDictionary*(NSDictionary* incoming) {
        NSMutableDictionary* attributes=[incoming mutableCopy];
        attributes[NSFontAttributeName]=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        return attributes;
    };
    button.configuration=config;
    button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    button.layer.cornerRadius=13;
    button.layer.borderWidth=1;
    [button addTarget:self action:@selector(commandFocused:) forControlEvents:UIControlEventTouchDown];
    [self addSubview:button]; return button;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:frame];
    if(!self) return nil;
    self.backgroundColor=Ink();
    self.accessibilityIdentifier=@"mcla.launcher";
    _sceneView=[[MCLALauncherSceneView alloc] initWithFrame:self.bounds];
    _sceneView.backgroundColor=Ink();
    _sceneView.preferredFramesPerSecond=60;
    _sceneView.userInteractionEnabled=NO;
    _sceneView.accessibilityElementsHidden=YES;
    [self addSubview:_sceneView];
    [self buildScene];
    __weak MCLALauncherView* weakSelf=self;
    _sceneView.updateScene=^(CFTimeInterval time,CFTimeInterval delta) {
        [weakSelf animateCameraAtTime:time delta:delta];
    };
    UIPanGestureRecognizer* orbit=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(orbitScene:)];
    orbit.maximumNumberOfTouches=1; orbit.delegate=self;
    [self addGestureRecognizer:orbit];
    _shade=[[UIView alloc] init]; _shade.userInteractionEnabled=NO;
    _gradient=[CAGradientLayer layer];
    [_shade.layer addSublayer:_gradient]; [self addSubview:_shade];
    _masthead=[self label:@"M C L A  /  LOS ANGELES" size:12 weight:UIFontWeightBold];
    _masthead.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _edition=[self label:@"COMPLETE EDITION" size:10 weight:UIFontWeightSemibold];
    _edition.textColor=[Cream() colorWithAlphaComponent:.48];
    _edition.textAlignment=NSTextAlignmentRight;
    _eyebrow=[self label:@"AFTER HOURS  /  LOS ANGELES" size:10 weight:UIFontWeightSemibold];
    _eyebrow.textColor=Amber();
    _eyebrow.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
    _title=[self label:@"THE CITY\nIS YOURS." size:66 weight:UIFontWeightBlack];
    _title.numberOfLines=2;
    _title.lineBreakMode=NSLineBreakByClipping;
    _title.font=[UIFont fontWithName:@"AvenirNextCondensed-HeavyItalic" size:76] ?: _title.font;
    _subtitle=[self label:@"Midnight Club: Los Angeles" size:15 weight:UIFontWeightMedium];
    _subtitle.textColor=[Cream() colorWithAlphaComponent:.65];
    _sceneCaption=[self label:@"ENDLESS SUMMER\nDRAG TO EXPLORE" size:9 weight:UIFontWeightMedium];
    _sceneCaption.numberOfLines=2;
    _sceneCaption.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    _sceneCaption.textColor=[Cream() colorWithAlphaComponent:.40];
    _rule=[[UIView alloc] init]; _rule.backgroundColor=[Cream() colorWithAlphaComponent:.16];
    [self addSubview:_rule];
    _launchButton=[self command:@"Enter Los Angeles" symbol:@"arrow.up.right" tag:0];
    _launchButton.accessibilityIdentifier=@"mcla.launch";
    _graphicsButton=[self command:@"Graphics" symbol:@"slider.horizontal.3" tag:1];
    _graphicsButton.accessibilityIdentifier=@"mcla.graphics";
    _controlsButton=[self command:@"Controls" symbol:@"gamecontroller" tag:2];
    _controlsButton.accessibilityIdentifier=@"mcla.controls";
    _savesButton=[self command:@"Save Management" symbol:@"externaldrive" tag:3];
    _savesButton.accessibilityIdentifier=@"mcla.saves";
    _statusLabel=[self label:@"CHECKING GARAGE" size:10 weight:UIFontWeightSemibold];
    _statusLabel.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightSemibold];
    _detailLabel=[self label:@"" size:12 weight:UIFontWeightRegular];
    _detailLabel.numberOfLines=2;
    _detailLabel.textColor=[Cream() colorWithAlphaComponent:.54];
    _graphicsSummaryLabel=[self label:@"" size:10 weight:UIFontWeightMedium];
    _graphicsSummaryLabel.textColor=[Cream() colorWithAlphaComponent:.42];
    _footer=[self label:@"TOUCH TO SELECT  ·  CONTROLLER READY" size:9 weight:UIFontWeightMedium];
    _footer.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightMedium];
    _footer.textColor=[Cream() colorWithAlphaComponent:.45];
    _shortcutHint=[self label:@"IN GAME  ·  3-FINGER TAP FOR TOOLS" size:9 weight:UIFontWeightMedium];
    _shortcutHint.textColor=[Cream() colorWithAlphaComponent:.40];
    _shortcutHint.textAlignment=NSTextAlignmentRight;
    self.selection=0;
    [self updateSelection];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(motionPreferenceChanged:)
        name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    return self;
}

- (void)buildScene {
    SCNScene* scene=[SCNScene scene];
    UIColor* horizon=[UIColor colorWithRed:.19 green:.035 blue:.16 alpha:1];
    UIGraphicsImageRendererFormat* format=[UIGraphicsImageRendererFormat defaultFormat]; format.scale=1;
    UIImage* sky=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8,512) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext* renderer) {
            CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
            NSArray* colors=@[(id)[UIColor colorWithRed:.018 green:.014 blue:.065 alpha:1].CGColor,
                (id)[UIColor colorWithRed:.10 green:.024 blue:.15 alpha:1].CGColor,
                (id)horizon.CGColor,(id)[UIColor colorWithRed:.25 green:.045 blue:.12 alpha:1].CGColor];
            CGFloat locations[]={0,.45,.75,1};
            CGGradientRef gradient=CGGradientCreateWithColors(space,(__bridge CFArrayRef)colors,locations);
            CGContextDrawLinearGradient(renderer.CGContext,gradient,CGPointZero,CGPointMake(0,512),0);
            CGGradientRelease(gradient); CGColorSpaceRelease(space);
        }];
    scene.background.contents=sky;
    scene.fogColor=horizon; scene.fogStartDistance=75; scene.fogEndDistance=170;
    _sceneView.scene=scene;
    SCNNode* root=scene.rootNode;
    SCNMaterial* amber=Glow(Amber());
    SCNMaterial* cold=Glow([UIColor colorWithRed:.12 green:.72 blue:.94 alpha:1]);
    SCNMaterial* pink=Glow([UIColor colorWithRed:1 green:.11 blue:.48 alpha:1]);
    UIImage* grid=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(128,128) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext* renderer) {
            [[UIColor colorWithRed:.024 green:.015 blue:.055 alpha:1] setFill]; UIRectFill(CGRectMake(0,0,128,128));
            [[UIColor colorWithRed:.50 green:.035 blue:.30 alpha:1] setFill];
            UIRectFill(CGRectMake(0,0,128,1.2)); UIRectFill(CGRectMake(0,0,1.2,128));
            (void)renderer;
        }];
    SCNMaterial* floor=[SCNMaterial material]; floor.lightingModelName=SCNLightingModelConstant;
    floor.diffuse.contents=grid;
    floor.diffuse.wrapS=floor.diffuse.wrapT=SCNWrapModeRepeat;
    SCNPlane* ground=[SCNPlane planeWithWidth:240 height:240]; ground.materials=@[floor];
    SCNNode* groundNode=[SCNNode nodeWithGeometry:ground];
    groundNode.position=SCNVector3Make(0,-.08,-65); groundNode.eulerAngles=SCNVector3Make(-M_PI_2,0,0);
    [root addChildNode:groundNode];
    [groundNode runAction:[SCNAction repeatActionForever:[SCNAction customActionWithDuration:60
        actionBlock:^(SCNNode* n, CGFloat time) {
            SCNMatrix4 transform=SCNMatrix4MakeScale(40,40,1);
            transform.m42=-time*1.6; floor.diffuse.contentsTransform=transform; (void)n;
        }]]];
    SCNMaterial* asphalt=Surface([UIColor colorWithRed:.028 green:.028 blue:.065 alpha:1],.35,.35);
    Box(root,0,-.06,-60,12,.04,230,0,asphalt);
    Box(root,-6,.0,-60,.045,.02,230,0,pink); Box(root,6,.0,-60,.045,.02,230,0,pink);
    Box(root,-5.8,.0,-60,.035,.02,230,0,cold); Box(root,5.8,.0,-60,.035,.02,230,0,cold);
    for(int j=0;j<28;++j) for(float x : {-2.0f,2.0f}) {
        SCNNode* stripe=Box(root,x,.01,-j*6,.055,.012,2.1,0,amber);
        [stripe runAction:[SCNAction repeatActionForever:[SCNAction customActionWithDuration:14
            actionBlock:^(SCNNode* n,CGFloat time) {
                n.position=SCNVector3Make(x,.01,18-fmod(j*6+time*12,168));
            }]]];
    }
    // The horizon is a real scene plane: towers and palms occlude its stripes.
    UIImage* sun=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(512,512) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext* renderer) {
            CGContextRef c=renderer.CGContext;
            CGContextAddEllipseInRect(c,CGRectMake(2,2,508,508)); CGContextClip(c);
            CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
            NSArray* colors=@[(id)[UIColor colorWithRed:1 green:.82 blue:.35 alpha:1].CGColor,
                (id)[UIColor colorWithRed:1 green:.27 blue:.22 alpha:1].CGColor,
                (id)[UIColor colorWithRed:.94 green:.06 blue:.42 alpha:1].CGColor];
            CGFloat locations[]={0,.5,1};
            CGGradientRef g=CGGradientCreateWithColors(space,(__bridge CFArrayRef)colors,locations);
            CGContextDrawLinearGradient(c,g,CGPointZero,CGPointMake(0,512),0);
            CGGradientRelease(g); CGColorSpaceRelease(space);
            CGContextSetBlendMode(c,kCGBlendModeClear);
            for(int y=240,step=7;y<512;step+=3,y+=step+13) CGContextFillRect(c,CGRectMake(0,y,512,step));
        }];
    SCNMaterial* sunMaterial=Glow(UIColor.whiteColor);
    sunMaterial.diffuse.contents=sun;
    sunMaterial.emission.contents=sun; sunMaterial.emission.intensity=2.4;
    sunMaterial.writesToDepthBuffer=NO;
    SCNPlane* disc=[SCNPlane planeWithWidth:46 height:46]; disc.materials=@[sunMaterial];
    SCNNode* sunNode=[SCNNode nodeWithGeometry:disc]; sunNode.position=SCNVector3Make(0,20,-110);
    [root addChildNode:sunNode];
    SCNNode* buildings=[SCNNode node]; [root addChildNode:buildings];
    UIImage* windows=Windows();
    SCNMaterial* facade=Surface([UIColor colorWithWhite:.42 alpha:1],.35,.4);
    facade.diffuse.contents=windows; facade.emission.contents=windows;
    facade.emission.intensity=.27;
    SCNMaterial* roof=Surface([UIColor colorWithRed:.045 green:.035 blue:.10 alpha:1],.5,.4);
    for(int i=0;i<38;++i) {
        float x=(i-19)*3.0, z=-65-(i*13%7)*3.0;
        float h=4+(i*11%13)*1.45;
        SCNNode* tower=Box(buildings,x,h/2,z,1.3+(i%3)*.55,h,2.4,.06,facade);
        tower.geometry.materials=@[facade,facade,facade,facade,roof,roof];
        Box(buildings,x,h,z,1.3+(i%3)*.55,.055,2.4,0,i%3?cold:pink);
    }
    SCNNode* merged=[buildings flattenedClone]; [buildings removeFromParentNode];
    [root addChildNode:merged];
    SCNNode* palmPrototype=[SCNNode node]; AddPalm(palmPrototype,0,0,6.5);
    SCNNode* palmMesh=[palmPrototype flattenedClone];
    for(int j=0;j<16;++j) {
        SCNNode* palm=[palmMesh clone];
        palm.position=SCNVector3Make(j%2?-8:8,0,12-(j/2)*18);
        [root addChildNode:palm];
        [palm runAction:[SCNAction repeatActionForever:[SCNAction customActionWithDuration:24
            actionBlock:^(SCNNode* n,CGFloat time) {
                n.position=SCNVector3Make(j%2?-8:8,0,22-fmod((j/2)*18+time*6,144));
            }]]];
    }
    // Model forward is +X; the highway runs along Z. Keep the car between
    // the +/-2 lane markers and change composition with the camera, not its lane.
    _heroCar=BuildCar(); _heroCar.position=SCNVector3Make(0,.04,4.5);
    _heroCar.eulerAngles=SCNVector3Make(0,-M_PI_2,0);
    _heroCar.scale=SCNVector3Make(1.55,1.55,1.55); [root addChildNode:_heroCar];
    // A smooth emissive pool grounds the car without a reflection pass.
    UIImage* poolTexture=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(128,128) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext* renderer) {
            for(int i=0;i<28;++i) {
                [[UIColor colorWithRed:1 green:.05 blue:.28 alpha:.025] setFill];
                CGContextFillEllipseInRect(renderer.CGContext,CGRectInset(CGRectMake(0,0,128,128),i*1.7,i*1.7));
            }
        }];
    SCNPlane* pool=[SCNPlane planeWithWidth:5 height:10];
    SCNMaterial* glow=Glow(UIColor.whiteColor); glow.diffuse.contents=poolTexture; glow.emission.contents=poolTexture;
    glow.emission.intensity=.75;
    glow.blendMode=SCNBlendModeAdd; glow.writesToDepthBuffer=NO; pool.materials=@[glow];
    SCNNode* poolNode=[SCNNode nodeWithGeometry:pool]; poolNode.position=SCNVector3Make(0,.02,4.5);
    poolNode.eulerAngles=SCNVector3Make(-M_PI_2,0,0); [root addChildNode:poolNode];
    self.heroPool=poolNode;
    SCNLight* ambient=[SCNLight light]; ambient.type=SCNLightTypeAmbient;
    ambient.color=[UIColor colorWithRed:.45 green:.27 blue:.62 alpha:1]; ambient.intensity=180;
    SCNNode* ambientNode=[SCNNode node]; ambientNode.light=ambient; [root addChildNode:ambientNode];
    for(int i=0;i<3;++i) {
        SCNNode* light=[SCNNode node]; light.light=[SCNLight light];
        light.light.type=SCNLightTypeOmni;
        light.light.intensity=i==0?1200:i==1?1500:500;
        light.light.color=i==1?[UIColor colorWithRed:.13 green:.65 blue:1 alpha:1]
            : i==2?[UIColor colorWithRed:1 green:.08 blue:.38 alpha:1]:Amber();
        light.position=i==0?SCNVector3Make(-4,8,10):i==1?SCNVector3Make(6,5,-2):SCNVector3Make(-4,3,2);
        light.light.attenuationStartDistance=7; light.light.attenuationEndDistance=24;
        [root addChildNode:light];
    }
    _cameraRig=[SCNNode node]; [root addChildNode:_cameraRig];
    _cameraNode=[SCNNode node]; _cameraNode.camera=[SCNCamera camera];
    _cameraNode.camera.fieldOfView=48;
    _cameraNode.camera.zNear=.1; _cameraNode.camera.zFar=260;
    // SCN's wantsHDR applies an SDR tone map. Leave radiance unclamped in the
    // RGBA16Float target; MCLALauncherSceneView owns bloom + adaptive EDR mapping.
    _cameraNode.camera.wantsHDR=NO;
    _cameraNode.camera.wantsExposureAdaptation=NO;
    [_cameraRig addChildNode:_cameraNode];
    _sceneView.pointOfView=_cameraNode;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds=self.bounds; UIEdgeInsets insets=self.safeAreaInsets;
    CGFloat w=bounds.size.width, h=bounds.size.height;
    BOOL portrait=h>w;
    CGFloat margin=portrait?28:MAX(32,MIN(w*.055,74));
    CGFloat left=MAX(insets.left+18,margin), right=MAX(insets.right+18,margin);
    CGFloat top=insets.top+22, bottom=h-insets.bottom-20;
    self.shade.frame=bounds; self.gradient.frame=bounds;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.gradient.colors=portrait
        ? @[(id)[Ink() colorWithAlphaComponent:.15].CGColor,(id)[Ink() colorWithAlphaComponent:.05].CGColor,(id)[Ink() colorWithAlphaComponent:.97].CGColor,(id)Ink().CGColor]
        : @[(id)[Ink() colorWithAlphaComponent:.98].CGColor,(id)[Ink() colorWithAlphaComponent:.92].CGColor,(id)[Ink() colorWithAlphaComponent:.05].CGColor,(id)[Ink() colorWithAlphaComponent:.12].CGColor];
    self.gradient.locations=portrait?@[@0,@.26,@.56,@1]:@[@0,@.38,@.73,@1];
    self.gradient.startPoint=CGPointMake(0,0);
    self.gradient.endPoint=portrait?CGPointMake(0,1):CGPointMake(1,.28);
    [CATransaction commit];
    self.sceneView.frame=portrait?CGRectMake(0,0,w,h*.56):bounds;
    [self updateCamera];
    self.masthead.frame=CGRectMake(left,top,w-left-right,20);
    self.edition.hidden=w<600;
    self.edition.frame=CGRectMake(w-right-180,top,180,20);
    CGFloat menuWidth=portrait?w-left-right:MIN(390,w*.38);
    CGFloat rowHeight=portrait?56:(h<500?47:56);
    CGFloat titleSize=portrait?64:(h<500?36:MIN(94,h*.115));
    CGFloat menuBottom=bottom-54;
    CGFloat launchY=menuBottom-rowHeight*3-20;
    self.launchButton.frame=CGRectMake(left,launchY,menuWidth,rowHeight);
    CGFloat secondaryWidth=(menuWidth-10)/2;
    self.graphicsButton.frame=CGRectMake(left,launchY+rowHeight+10,secondaryWidth,rowHeight);
    self.controlsButton.frame=CGRectMake(left+secondaryWidth+10,launchY+rowHeight+10,secondaryWidth,rowHeight);
    self.savesButton.frame=CGRectMake(left,launchY+rowHeight*2+20,menuWidth,rowHeight);
    for(UIButton* b in @[self.graphicsButton,self.controlsButton]) {
        UIButtonConfiguration* c=b.configuration;
        c.contentInsets=NSDirectionalEdgeInsetsMake(12,12,12,12);
        c.imagePadding=8;
        c.titleTextAttributesTransformer=^NSDictionary*(NSDictionary* input) {
            NSMutableDictionary* a=[input mutableCopy];
            a[NSFontAttributeName]=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]; return a;
        };
        b.configuration=c;
    }
    UIFont* face=[UIFont fontWithName:@"AvenirNextCondensed-HeavyItalic" size:titleSize]
        ?: [UIFont systemFontOfSize:titleSize weight:UIFontWeightBlack];
    CGFloat longest=MAX([@"THE CITY" sizeWithAttributes:@{NSFontAttributeName:face}].width,
                        [@"IS YOURS." sizeWithAttributes:@{NSFontAttributeName:face}].width);
    if(longest>menuWidth) face=[face fontWithSize:titleSize*menuWidth/longest];
    self.title.font=face;
    CGFloat titleHeight=ceil(face.lineHeight*2)+4;
    CGFloat titleY=portrait?MAX(top+h*.29,launchY-titleHeight-106)
        : MAX(top+(h<500?28:52),launchY-titleHeight-94);
    self.eyebrow.frame=CGRectMake(left,titleY-22,menuWidth,16);
    self.eyebrow.hidden=!portrait && h<500;
    self.title.frame=CGRectMake(left-3,titleY,menuWidth+15,titleHeight);
    self.subtitle.frame=CGRectMake(left,titleY+titleHeight+2,menuWidth,21);
    self.statusLabel.frame=CGRectMake(left,launchY-36,menuWidth,16);
    self.detailLabel.frame=CGRectMake(left,launchY-65,menuWidth,29);
    self.detailLabel.hidden=self.launchReady && !self.launching;
    self.rule.frame=CGRectMake(left,launchY-12,menuWidth,1);
    self.graphicsSummaryLabel.frame=CGRectMake(left,menuBottom+10,menuWidth,16);
    self.footer.frame=CGRectMake(left,bottom-12,w-left-right,14);
    self.shortcutHint.frame=CGRectMake(w-right-245,bottom-12,245,14);
    self.shortcutHint.hidden=w<820;
    self.sceneCaption.hidden=portrait || h<440;
    self.sceneCaption.frame=CGRectMake(w-right-200,top+40,200,38);
    self.sceneCaption.textAlignment=NSTextAlignmentRight;
}
- (void)commandFocused:(UIButton*)button {
    self.selection=button.tag; [self updateSelection];
}
- (void)updateCamera {
    BOOL portrait=self.bounds.size.height>self.bounds.size.width;
    [SCNTransaction begin]; [SCNTransaction setAnimationDuration:0];
    [SCNTransaction setDisableActions:YES];
    float baseX=portrait?3.7:1.8;
    self.cameraNode.position=SCNVector3Make(baseX+self.smoothedYaw*3.5,
        (portrait?5.0:4.4)+self.smoothedPitch*2,portrait?22:20);
    [self.cameraNode lookAt:portrait?SCNVector3Make(-1,2,-10):SCNVector3Make(-12,2.8,-24)];
    self.cameraNode.camera.fieldOfView=portrait?58:48;
    [SCNTransaction commit];
}
- (void)animateCameraAtTime:(CFTimeInterval)time delta:(CFTimeInterval)delta {
    BOOL motion=!UIAccessibilityIsReduceMotionEnabled();
    // Exponential input smoothing is independent of touch/controller event rate.
    // Analytic sine has continuous position AND velocity at both turnarounds;
    // the old pair of eased SCNActions had a speed break at its middle join.
    double blend=1-exp(-MAX(0,delta)*10);
    self.smoothedYaw+=(self.cameraYaw-self.smoothedYaw)*blend;
    self.smoothedPitch+=(self.cameraPitch-self.smoothedPitch)*blend;
    [self updateCamera];
    [SCNTransaction begin]; [SCNTransaction setAnimationDuration:0];
    [SCNTransaction setDisableActions:YES];
    self.cameraRig.eulerAngles=SCNVector3Make(0,motion?.008*sin(time*2*M_PI/16):0,0);
    self.heroCar.position=SCNVector3Make(0,.04+(motion?.008*sin(time*2*M_PI/1.8):0),4.5);
    [SCNTransaction commit];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gesture shouldReceiveTouch:(UITouch*)touch {
    (void)gesture;
    for(UIView* view=touch.view;view && view!=self;view=view.superview)
        if([view isKindOfClass:UIControl.class]) return NO;
    return !self.launching;
}
- (void)orbitScene:(UIPanGestureRecognizer*)pan {
    if(UIAccessibilityIsReduceMotionEnabled()) return;
    CGPoint delta=[pan translationInView:self]; [pan setTranslation:CGPointZero inView:self];
    self.cameraYaw=MAX(-1,MIN(1,self.cameraYaw+delta.x/MAX(1,self.bounds.size.width)*2));
    self.cameraPitch=MAX(-.6,MIN(.6,self.cameraPitch+delta.y/MAX(1,self.bounds.size.height)*2));
}
- (void)adjustCameraWithX:(float)x y:(float)y {
    if(UIAccessibilityIsReduceMotionEnabled() || self.launching) return;
    if(fabsf(x)<.12 && fabsf(y)<.12) return;
    self.cameraYaw=MAX(-1,MIN(1,self.cameraYaw+x*.025));
    self.cameraPitch=MAX(-.6,MIN(.6,self.cameraPitch-y*.02));
}
- (void)updateSelection {
    NSArray<UIButton*>* commands=@[self.launchButton,self.graphicsButton,self.controlsButton,self.savesButton];
    for(UIButton* b in commands) {
        BOOL focused=b.tag==self.selection;
        BOOL primary=b.tag==0;
        b.backgroundColor=focused?Amber():primary?[Amber() colorWithAlphaComponent:.13]:[Cream() colorWithAlphaComponent:.045];
        b.layer.borderColor=(focused?Amber():[Cream() colorWithAlphaComponent:.17]).CGColor;
        UIButtonConfiguration* c=b.configuration;
        c.baseForegroundColor=focused?Ink():Cream(); b.configuration=c;
        b.accessibilityTraits=UIAccessibilityTraitButton | (focused?UIAccessibilityTraitSelected:0);
    }
}
- (void)moveSelection:(NSInteger)direction {
    if(self.launching) return;
    self.selection=(self.selection+direction+4)%4;
    [self updateSelection];
}
- (void)activateSelection {
    UIButton* button=@[self.launchButton,self.graphicsButton,self.controlsButton,self.savesButton][self.selection];
    if(button.enabled) [button sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)setControllerConnected:(BOOL)connected {
    self.footer.text=connected?@"D-PAD / STICK  SELECT     A  CONFIRM     B  BACK":@"TOUCH TO SELECT  ·  CONTROLLER READY";
}
- (void)setGraphicsSummary:(NSString*)summary { self.graphicsSummaryLabel.text=summary; }
- (void)setLaunchReady:(BOOL)ready {
    if(_launchReady==ready && self.launchButton.enabled==(ready && !self.launching)) return;
    _launchReady=ready;
    self.launchButton.enabled=ready && !self.launching;
    self.launchButton.alpha=ready || self.launching?1:.5;
    [self setNeedsLayout];
}
- (void)setLaunching:(BOOL)launching {
    if(_launching==launching) return;
    _launching=launching;
    self.graphicsButton.enabled=!launching; self.controlsButton.enabled=!launching;
    self.savesButton.enabled=!launching;
    self.launchButton.enabled=self.launchReady && !launching;
    UIButtonConfiguration* c=self.launchButton.configuration;
    c.title=launching?@"Opening the city…":@"Enter Los Angeles";
    c.showsActivityIndicator=launching; self.launchButton.configuration=c;
    [self setNeedsLayout];
}
- (void)setSceneActive:(BOOL)active {
    BOOL animate=active && !UIAccessibilityIsReduceMotionEnabled();
    if(_sceneActive==active && self.sceneView.scene.paused==!animate) return;
    _sceneActive=active;
    self.sceneView.scene.paused=!animate;
    [self.sceneView setAnimating:animate];
    if(active) [self.sceneView setNeedsDisplay];
}
- (void)motionPreferenceChanged:(NSNotification*)notification {
    (void)notification; [self setSceneActive:self.sceneActive];
}
- (void)releaseScene {
    [self setSceneActive:NO];
    self.sceneView.updateScene=nil;
    self.sceneView.scene=nil; self.sceneView.pointOfView=nil;
    [self.sceneView removeFromSuperview]; self.sceneView=nil;
    self.cameraNode=nil; self.cameraRig=nil;
    self.heroCar=nil; self.heroPool=nil;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
