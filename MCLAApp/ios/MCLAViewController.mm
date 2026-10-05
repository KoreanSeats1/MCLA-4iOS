#include "MCLADiagnostics.h"
#import "MCLAViewController.h"

#import "MCLAMetalView.h"
#import "MCLALauncherView.h"
#import "MCLASaveArchive.h"
#import "MCLAGraphicsFoundation.h"
#import "MCLAHostBridge.h"
#import "MCLABootstrapSubsystems.h"
#import <CoreMotion/CoreMotion.h>
#import <GameController/GameController.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "MCLAMetalPresentation.h"

// This test branch enables the in-game experiment by default. Dedicated
// switches leave the original branch’s control preferences untouched.
static BOOL MCLAControlOverhaulEnabled(void) {
    NSString* override = NSProcessInfo.processInfo.environment[@"MCLA_CONTROL_OVERHAUL"];
    return override ? override.boolValue :
        [NSUserDefaults.standardUserDefaults boolForKey:@"MCLAControlOverhaulTestEnabled"];
}
static NSString* MCLATouchPreference(NSString* key) {
    return MCLAControlOverhaulEnabled() ? [key stringByAppendingString:@"Overhaul"] : key;
}
static NSDictionary* MCLAOverhaulPositions(void) {
    return @{@"steer": @[@0.14,@0.80], @"nitro": @[@0.065,@0.53],
        @"gas": @[@0.925,@0.66], @"handbrake": @[@0.925,@0.875],
        @"brake": @[@0.80,@0.84], @"camera": @[@0.955,@0.065],
        @"pause": @[@0.045,@0.065]};
}
static NSDictionary* MCLAOverhaulSizes(void) {
    return @{@"steer": @[@230,@230], @"nitro": @[@114,@114],
        @"gas": @[@132,@170], @"handbrake": @[@132,@130],
        @"brake": @[@136,@140], @"pause": @[@56,@56], @"camera": @[@56,@56]};
}

static NSArray* MCLAOverhaulControls(void) {
    return @[@"nitro", @"handbrake", @"camera", @"pause"];
}

static NSArray<NSString*>* MCLAOutputOptionNames(void) {
    return @[@"720p · 1280 × 720", @"900p · 1600 × 900", @"1080p · 1920 × 1080"];
}

static NSArray<NSString*>* MCLAOutputOptionDetails(void) {
    return @[@"Native scene size. Recommended starting point for 30 FPS.",
             @"Renders 56% more scene pixels. Higher GPU and memory cost; needs gameplay testing.",
             @"Renders 125% more scene pixels. Highest detail and GPU cost; needs gameplay testing."];
}

static NSArray<NSString*>* MCLAFilterOptionNames(void) {
    return @[@"Game Default", @"Bilinear · 1×", @"Trilinear · 4×",
             @"Trilinear · 8×", @"Trilinear · 16×"];
}

static NSArray<NSString*>* MCLABloomOptionNames(void) {
    return @[@"Balanced", @"Original Intensity", @"Low"];
}

static NSArray<NSString*>* MCLADefaultTouchControls(void) {
    return @[@"handbrake", @"nitro", @"headlights", @"ability", @"camera",
             @"weight", @"gps", @"hud"];
}

// Captured from the user's approved live layouts on 2026-09-22. These are
// normalized safe-area coordinates, so they remain useful across similar
// phone/tablet sizes and orientations. Existing saved layouts still win.
static NSDictionary<NSString*, NSArray<NSNumber*>*>* MCLADeviceLayoutPositions(void) {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone)
        return @{
            @"ability": @[@0.08762886597938144, @0.6091666666666666],
            @"brake": @[@0.6993127147766323, @0.7975],
            @"camera": @[@0.7697594501718213, @0.2433333333333333],
            @"gas": @[@0.8947594501718213, @0.7616666666666666],
            @"gps": @[@0.08505154639175258, @0.3058333333333333],
            @"handbrake": @[@0.1967353951890034, @0.8575],
            @"headlights": @[@0.086, @0.46],
            @"hud": @[@0.2027491408934708, @0.3025],
            @"nitro": @[@0.8969072164948454, @0.4441666666666667],
            @"steer": @[@0.06829896907216494, @0.8625],
            @"weight": @[@0.904209621993127, @0.2175],
        };
    return @{
        @"ability": @[@0.0859375, @0.5931578947368421],
        @"brake": @[@0.7436079545454546, @0.8242105263157895],
        @"camera": @[@0.8295454545454546, @0.4947368421052631],
        @"gas": @[@0.8959517045454546, @0.7642105263157895],
        @"gps": @[@0.06924715909090909, @0.4978947368421053],
        @"handbrake": @[@0.9161931818181818, @0.4742105263157895],
        @"headlights": @[@0.83, @0.40],
        @"hud": @[@0.06498579545454546, @0.4347368421052631],
        @"nitro": @[@0.9151278409090909, @0.5715789473684211],
        @"steer": @[@0.1100852272727273, @0.8105263157894737],
        @"weight": @[@0.8299005681818182, @0.5694736842105264],
    };
}

static NSDictionary<NSString*, NSArray<NSNumber*>*>* MCLADeviceLayoutSizes(void) {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone)
        return @{@"steer": @[@97.86537511926713, @97.86537511926713]};
    return @{
        @"ability": @[@142.6, @89.9],
        @"gas": @[@205.8634962669981, @253.804310466162],
        @"handbrake": @[@111.9487151444354, @70.67014514723073],
        @"nitro": @[@118.6702449231349, @80.03342099467235],
        @"steer": @[@228.9985613059062, @228.9985613059062],
    };
}

static void MCLARegisterGraphicsDefaults(void) {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"MCLAOutputMode": @1,
        @"MCLARenderHeight": UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone ? @720 : @1080,
        @"MCLAFSREnabled": @NO,
        @"MCLAFilterMode": @2,
        @"MCLABloomMode": @0,
        @"MCLAPerformanceOverlay": @YES,
        @"MCLARetailMode": UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone ? @YES : @NO,
        @"MCLADisableMotionBlur": @NO,
        @"MCLADisableDepthOfField": @NO,
        @"MCLAExperimental60FPS": @NO,
        @"MCLATouchEnabledControlOverhaulTest": @YES,
        @"MCLATiltEnabled": @NO,
        @"MCLATiltInvert": @NO,
        @"MCLATouchActiveControls": MCLADefaultTouchControls(),
        @"MCLAControlOverhaulTestEnabled": @YES,
        @"MCLATouchActiveControlsOverhaul": MCLAOverhaulControls(),
    }];
    mcla::SetDiagnosticsEnabled(![NSUserDefaults.standardUserDefaults boolForKey:@"MCLARetailMode"]);
#if MCLA_SMAA_LAB
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"MCLASMAAEnabled": @YES}];
#endif
    // Preserve the old FSR on/off preference without resetting filtering,
    // bloom or diagnostics. The old modes all rendered the scene at 720p.
    if ([NSUserDefaults.standardUserDefaults integerForKey:
             @"MCLAGraphicsSettingsSchema"] < 2) {
        NSDictionary* persisted = [NSUserDefaults.standardUserDefaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
        if (persisted[@"MCLAOutputMode"]) {
        [NSUserDefaults.standardUserDefaults setInteger:720 forKey:@"MCLARenderHeight"];
        [NSUserDefaults.standardUserDefaults setBool:
            [NSUserDefaults.standardUserDefaults integerForKey:@"MCLAOutputMode"] != 0
                                             forKey:@"MCLAFSREnabled"];
        }
        [NSUserDefaults.standardUserDefaults setInteger:2
                                                 forKey:@"MCLAGraphicsSettingsSchema"];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults dictionaryForKey:@"MCLAGraphicsBaseline"]) {
        NSMutableDictionary* baseline = [NSMutableDictionary dictionary];
        for (NSString* key in @[@"MCLARenderHeight", @"MCLAFSREnabled", @"MCLAFilterMode", @"MCLABloomMode", @"MCLADisableMotionBlur", @"MCLARetailMode", @"MCLAPerformanceOverlay"])
            baseline[key] = [defaults objectForKey:key];
        // User requested enabled DoF as the default for this build.
        baseline[@"MCLADisableDepthOfField"] = @NO;
        [defaults setBool:NO forKey:@"MCLADisableDepthOfField"];
        [defaults setObject:baseline forKey:@"MCLAGraphicsBaseline"];
    }

}

@interface MCLAFrameTimeGraphView : UIView
@end

@implementation MCLAFrameTimeGraphView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = YES;
        self.opaque = NO;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    MCLAFrameTimingSample samples[180] = {};
    float fps = 0.0f;
    float gpuMilliseconds = 0.0f;
    const uint32_t count = MCLAGraphicsCopyFrameTiming(
        samples, 180, &fps, &gpuMilliseconds);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;

    UIBezierPath* background = [UIBezierPath bezierPathWithRoundedRect:rect
                                                          cornerRadius:12.0];
    [[UIColor colorWithWhite:0.025 alpha:0.82] setFill];
    [background fill];
    [[UIColor colorWithWhite:1.0 alpha:0.13] setStroke];
    background.lineWidth = 1.0;
    [background stroke];

    const BOOL compact = rect.size.height <= 85.0;
    const CGFloat header = compact ? 22.0 : 27.0;
    const CGFloat footer = compact ? 7.0 : 9.0;
    const CGRect graph = CGRectInset(CGRectMake(8.0, header,
        rect.size.width - 16.0, rect.size.height - header - footer), 0.0, 1.0);
    const CGFloat maximumMilliseconds = 70.0;
    const CGFloat guideValues[] = {16.67, 33.33, 50.0, 66.67};
    CGContextSetLineWidth(context, 0.75);
    for (NSUInteger i = 0; i < 4; ++i) {
        const CGFloat y = CGRectGetMaxY(graph) -
            MIN((CGFloat)guideValues[i], maximumMilliseconds) /
                maximumMilliseconds * graph.size.height;
        CGContextSetStrokeColorWithColor(context,
            (i == 1 ? [UIColor colorWithRed:0.25 green:0.9 blue:0.45 alpha:0.38]
                    : [UIColor colorWithWhite:1.0 alpha:0.12]).CGColor);
        CGContextMoveToPoint(context, CGRectGetMinX(graph), y);
        CGContextAddLineToPoint(context, CGRectGetMaxX(graph), y);
        CGContextStrokePath(context);
    }

    if (count > 1) {
        UIBezierPath* line = [UIBezierPath bezierPath];
        for (uint32_t i = 0; i < count; ++i) {
            const CGFloat x = CGRectGetMinX(graph) +
                (CGFloat)i / (CGFloat)(count - 1) * graph.size.width;
            const CGFloat clamped = MIN((CGFloat)samples[i].frameMilliseconds,
                                        maximumMilliseconds);
            const CGFloat y = CGRectGetMaxY(graph) -
                clamped / maximumMilliseconds * graph.size.height;
            if (i == 0) [line moveToPoint:CGPointMake(x, y)];
            else [line addLineToPoint:CGPointMake(x, y)];
        }
        [[UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:0.95] setStroke];
        line.lineWidth = 1.5;
        line.lineJoinStyle = kCGLineJoinRound;
        [line stroke];
    }

    const double captureRemaining = MCLAGraphicsPerformanceCaptureRemainingSeconds();
    NSString* summary = captureRemaining > 0.0
        ? [NSString stringWithFormat:@"REC %.0fs   %.1f FPS   %.1f ms GPU",
            ceil(captureRemaining), fps, gpuMilliseconds]
        : (captureRemaining == 0.0 ? @"SAVED · Documents/Diagnostics"
            : [NSString stringWithFormat:
                @"%.1f FPS   %.1f ms frame   %.1f ms GPU", fps,
                fps > 0.0f ? 1000.0f / fps : 0.0f, gpuMilliseconds]);
    [summary drawAtPoint:CGPointMake(9.0, compact ? 5.0 : 7.0)
          withAttributes:@{
              NSFontAttributeName: [UIFont monospacedSystemFontOfSize:compact ? 9.5 : 11.0
                                                               weight:UIFontWeightSemibold],
              NSForegroundColorAttributeName: UIColor.whiteColor,
          }];
}

@end

// UIKit normally changes a UIButton's appearance for each touch. That
// schedules Core Animation work over the full-screen Metal drawable and can
// miss the 30 Hz presentation slot on a busy device. These controls are
// deliberately static while held; their input state still changes instantly.
@interface MCLAStaticTouchButton : UIButton
@end

@implementation MCLAStaticTouchButton
- (void)setHighlighted:(BOOL)highlighted {
    (void)highlighted;
}
@end

@interface MCLAVirtualStickView : UIControl
@property(nonatomic, copy) void (^onStick)(float x, float y, BOOL active);
@property(nonatomic, strong) UIView* thumb;
@property(nonatomic, strong) UILabel* caption;
@property(nonatomic, weak) UITouch* trackedTouch;
@end

@implementation MCLAVirtualStickView

- (instancetype)initWithTitle:(NSString*)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0.03 alpha:0.20];
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.40].CGColor;
    self.layer.borderWidth = 1.2;
    self.layer.cornerRadius = 72;
    self.clipsToBounds = YES;
    self.multipleTouchEnabled = NO;
    _thumb = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 58, 58)];
    _thumb.backgroundColor = [UIColor colorWithWhite:0.9 alpha:0.32];
    _thumb.layer.cornerRadius = 29;
    _thumb.userInteractionEnabled = NO;
    [self addSubview:_thumb];
    _caption = [[UILabel alloc] initWithFrame:CGRectZero];
    _caption.text = title;
    _caption.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    _caption.textColor = UIColor.whiteColor;
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.userInteractionEnabled = NO;
    [self addSubview:_caption];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.caption.frame = CGRectMake(6, 8, self.bounds.size.width - 12, 16);
    if (!self.trackedTouch) self.thumb.center = CGPointMake(CGRectGetMidX(self.bounds),
                                                            CGRectGetMidY(self.bounds));
}

- (void)updateFromTouch:(UITouch*)touch {
    const CGPoint point = [touch locationInView:self];
    const CGFloat radius = MAX(1.0, MIN(self.bounds.size.width, self.bounds.size.height) * 0.36);
    CGFloat x = (point.x - CGRectGetMidX(self.bounds)) / radius;
    CGFloat y = (CGRectGetMidY(self.bounds) - point.y) / radius;
    const CGFloat length = hypot(x, y);
    if (length > 1.0) { x /= length; y /= length; }
    self.thumb.center = CGPointMake(CGRectGetMidX(self.bounds) + x * radius,
                                    CGRectGetMidY(self.bounds) - y * radius);
    if (self.onStick) self.onStick((float)x, (float)y, YES);
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    if (self.trackedTouch) return;
    self.trackedTouch = touches.anyObject;
    if (self.trackedTouch) [self updateFromTouch:self.trackedTouch];
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    if (self.trackedTouch && [touches containsObject:self.trackedTouch])
        [self updateFromTouch:self.trackedTouch];
}
- (void)releaseTouches:(NSSet<UITouch*>*)touches {
    if (!self.trackedTouch || ![touches containsObject:self.trackedTouch]) return;
    self.trackedTouch = nil;
    self.thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    if (self.onStick) self.onStick(0, 0, NO);
}
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event; [self releaseTouches:touches];
}
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event; [self releaseTouches:touches];
}
@end

@interface MCLAControlsOptionsController : UITableViewController
@property(nonatomic, copy) void (^onChange)(void);
@property(nonatomic, copy) void (^onCalibrate)(void);
@property(nonatomic, copy) void (^onResetLayout)(void);
@end

@implementation MCLAControlsOptionsController
- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) self.title = @"Driving Controls";
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self
        action:@selector(done:)];
}
- (void)done:(id)sender { (void)sender; [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? 5 : 2;
}
- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? @"On-Screen Pad" : @"Steering Setup";
}
- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return section == 0
        ? @"The translucent driving controls can be dragged into place with EDIT during gameplay. Positions are saved automatically. Tilt replaces left-stick steering; hold the iPad upright and turn it like a wheel. PAD has every Xbox 360 control."
        : @"Recenter with the iPad in your comfortable straight-ahead driving position. Use Invert if left and right feel reversed.";
}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)path {
    (void)tableView;
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                   reuseIdentifier:nil];
    if (path.section == 1) {
        cell.textLabel.text = path.row == 0 ? @"Recenter tilt steering" : @"Reset touch layout";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    NSArray<NSString*>* names = @[@"Touch driving controls", @"Tilt steering",
                                  @"Invert tilt direction", @"Show full pad at launch", @"Experimental control overhaul"];
    NSArray<NSString*>* keys = @[@"MCLATouchEnabledControlOverhaulTest", @"MCLATiltEnabled",
                                 @"MCLATiltInvert", @"MCLAFullPadVisible", @"MCLAControlOverhaulTestEnabled"];
    cell.textLabel.text = names[path.row];
    UISwitch* toggle = [[UISwitch alloc] init];
    toggle.tag = path.row;
    toggle.on = [NSUserDefaults.standardUserDefaults boolForKey:keys[path.row]];
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)toggleChanged:(UISwitch*)sender {
    NSArray<NSString*>* keys = @[@"MCLATouchEnabledControlOverhaulTest", @"MCLATiltEnabled",
                                 @"MCLATiltInvert", @"MCLAFullPadVisible", @"MCLAControlOverhaulTestEnabled"];
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:keys[sender.tag]];
    if (sender.tag == 4) MCLAResetVirtualGamepad();
    [NSUserDefaults.standardUserDefaults synchronize];
    if (self.onChange) self.onChange();
}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 1 && path.row == 0 && self.onCalibrate) self.onCalibrate();
    if (path.section == 1 && path.row == 1) {
        UIAlertController* confirmation = [UIAlertController
            alertControllerWithTitle:@"Reset touch layout?"
            message:@"This returns the steering, pedals, and driving buttons to their default positions."
            preferredStyle:UIAlertControllerStyleAlert];
        [confirmation addAction:[UIAlertAction actionWithTitle:@"Cancel"
            style:UIAlertActionStyleCancel handler:nil]];
        [confirmation addAction:[UIAlertAction actionWithTitle:@"Reset"
            style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
                (void)action;
                if (self.onResetLayout) self.onResetLayout();
            }]];
        confirmation.preferredAction = confirmation.actions.firstObject;
        [self presentViewController:confirmation animated:YES completion:nil];
    }
}
@end

@interface MCLAGraphicsChoiceController : UITableViewController
@property(nonatomic, copy) NSArray<NSString*>* names;
@property(nonatomic, copy) NSArray<NSString*>* details;
@property(nonatomic, assign) NSInteger selected;
@property(nonatomic, assign) NSInteger defaultChoice;
@property(nonatomic, copy) void (^onSelect)(NSInteger);
@end
@implementation MCLAGraphicsChoiceController
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return self.names.count;
}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)path {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"choice"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"choice"];
    cell.textLabel.text = path.row == self.defaultChoice ? [self.names[path.row] stringByAppendingString:@" · Default"] : self.names[path.row];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = path.row < self.details.count ? self.details[path.row] : nil;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.accessoryType = path.row == self.selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)path {
    if (self.onSelect) self.onSelect(path.row);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface MCLAGraphicsOptionsController : UITableViewController
@property(nonatomic, assign) BOOL settingsLocked;
@end
@implementation MCLAGraphicsOptionsController
- (instancetype)initWithSettingsLocked:(BOOL)locked {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { _settingsLocked = locked; self.title = @"Graphics"; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Defaults" style:UIBarButtonItemStylePlain target:self action:@selector(restoreGraphicsDefaults:)];
    self.navigationItem.leftBarButtonItem.enabled = !self.settingsLocked;
    self.tableView.estimatedRowHeight = 76;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.backgroundColor = [UIColor colorWithWhite:.055 alpha:1];
    UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0,0,320,100)];
    UIStackView* text = [[UIStackView alloc] init];
    text.axis = UILayoutConstraintAxisVertical; text.spacing = 7;
    UILabel* title = [[UILabel alloc] init];
    title.text = @"MAKE IT YOUR DRIVE";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.adjustsFontForContentSizeCategory = YES;
    title.textColor = [UIColor colorWithRed:1 green:.67 blue:.31 alpha:1];
    UILabel* subtitle = [[UILabel alloc] init];
    NSUInteger targetFPS = (self.settingsLocked ? MCLAGraphicsExperimental60FPS() : [NSUserDefaults.standardUserDefaults boolForKey:@"MCLAExperimental60FPS"]) ? 60 : 30;
    subtitle.tag = 600;
    subtitle.text = [NSString stringWithFormat:@"%lu FPS target · %@", (unsigned long)targetFPS, self.settingsLocked ? @"Session settings are locked" : @"Choose your look before launching"];
    subtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    subtitle.adjustsFontForContentSizeCategory = YES;
    subtitle.textColor = UIColor.secondaryLabelColor; subtitle.numberOfLines = 0;
    [text addArrangedSubview:title]; [text addArrangedSubview:subtitle];
    text.translatesAutoresizingMaskIntoConstraints = NO; [header addSubview:text];
    [NSLayoutConstraint activateConstraints:@[
        [text.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:22],
        [text.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-22],
        [text.topAnchor constraintEqualToAnchor:header.topAnchor constant:16],
        [text.bottomAnchor constraintLessThanOrEqualToAnchor:header.bottomAnchor constant:-12]]];
    self.tableView.tableHeaderView = header;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView* header = self.tableView.tableHeaderView;
    CGFloat width = self.tableView.bounds.size.width;
    CGFloat height = ceil([header systemLayoutSizeFittingSize:CGSizeMake(width,0)
        withHorizontalFittingPriority:UILayoutPriorityRequired
        verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height);
    if (fabs(header.frame.size.height-height) > .5) {
        header.frame = CGRectMake(0,0,width,height);
        self.tableView.tableHeaderView = header;
    }
}
- (void)updateFrameRateHeader {
    UILabel* subtitle = (UILabel*)[self.tableView.tableHeaderView viewWithTag:600];
    NSUInteger fps = (self.settingsLocked ? MCLAGraphicsExperimental60FPS() : [NSUserDefaults.standardUserDefaults boolForKey:@"MCLAExperimental60FPS"]) ? 60 : 30;
    subtitle.text = [NSString stringWithFormat:@"%lu FPS target · %@", (unsigned long)fps, self.settingsLocked ? @"Session settings are locked" : @"Choose your look before launching"];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self updateFrameRateHeader]; [self.tableView reloadData]; }
- (void)done:(id)sender { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView { return 5; }
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 4) return 1;
    if (section == 0) return 2;
    if (section == 1) {
#if MCLA_SMAA_LAB
        return 5;
#else
        return 4;
#endif
    }
    return 1;
}
- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Display", @"Image & Effects", @"Play Mode", @"Performance", @"Experimental"][section];
}
- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 4) return @"60 FPS is under evaluation and needs more performance headroom. Off by default; apply on the next launch. 30 FPS is the standard target.";
    if (section == 0) return self.settingsLocked ? @"Close and relaunch to change scene resolution. Upscaling can change during play." : @"720p gives the most room for a steady 30 FPS. Upscaling sharpens the image to fit your screen.";
    if (section == 1) return @"Filtering, bloom, motion blur and depth of field apply on the next launch.";
    if (section == 2) return @"Retail Mode keeps logs, captures and profiling off. Change before launching.";
    return mcla::DiagnosticsEnabled() ? @"Double-tap the graph during play to record 20 seconds of frame timings." : @"Turn Retail Mode off before launching to enable the frame graph.";
}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)path {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"graphics-row"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"graphics-row"];
    cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0;
    NSString* title; NSString* detail; NSString* icon; NSString* key = nil;
    SEL action = NULL; BOOL enabled = !self.settingsLocked; BOOL on = NO;
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    if (path.section == 0 && path.row == 0) {
        title = @"Scene Resolution"; icon = @"rectangle.expand.vertical";
        NSInteger height = [defaults integerForKey:@"MCLARenderHeight"];
        detail = height == 1080 ? @"1080p · Highest detail" : height == 900 ? @"900p · More detail" : @"720p · Recommended for 30 FPS";
    } else if (path.section == 0) {
        title = @"FSR Upscaling"; detail = @"Sharper image at your screen size"; icon = @"sparkles";
        key = @"MCLAFSREnabled"; action = @selector(fsrChanged:); enabled = YES;
        on = self.settingsLocked ? MCLAGraphicsFSREnabled() : [defaults boolForKey:key];
    } else if (path.section == 1 && path.row == 0) {
        title = @"Texture Filtering"; icon = @"square.stack.3d.up";
        detail = MCLAFilterOptionNames()[MIN(MAX([defaults integerForKey:@"MCLAFilterMode"],0),4)];
    } else if (path.section == 1 && path.row == 1) {
        title = @"Glow & Bloom"; icon = @"sun.max";
        detail = MCLABloomOptionNames()[MIN(MAX([defaults integerForKey:@"MCLABloomMode"],0),2)];
    } else if (path.section == 1 && path.row == 2) {
        title = @"Disable Motion Blur"; detail = @"Keep the road and car crisp in motion"; icon = @"camera.aperture";
        key = @"MCLADisableMotionBlur"; action = @selector(motionBlurChanged:); on = [defaults boolForKey:key];
    } else if (path.section == 1 && path.row == 3) {
        title = @"Disable Depth of Field"; detail = @"Keep near and distant scenery in focus"; icon = @"viewfinder";
        key = @"MCLADisableDepthOfField"; action = @selector(depthOfFieldChanged:); on = [defaults boolForKey:key];
    } else if (path.section == 1) {
        title = @"SMAA · High"; detail = @"Smooth edges before upscaling"; icon = @"triangle";
        key = @"MCLASMAAEnabled"; action = @selector(smaaChanged:); on = [defaults boolForKey:key];
    } else if (path.section == 2) {
        title = @"Retail Mode"; detail = @"Play without diagnostic logging or captures"; icon = @"steeringwheel";
        key = @"MCLARetailMode"; action = @selector(retailModeChanged:); on = [defaults boolForKey:key];
    } else if (path.section == 4) {
        title = @"Native 60 FPS";
        detail = @"Experimental · Real frame timing with camera and suspension corrections; may increase heat";
        icon = @"flask"; key = @"MCLAExperimental60FPS"; action = @selector(experimentalChanged:); on = [defaults boolForKey:key];
    } else {
        title = @"FPS & Frame-Time Graph"; detail = @"See frame pacing while driving"; icon = @"chart.xyaxis.line";
        key = @"MCLAPerformanceOverlay"; action = @selector(performanceOverlayChanged:);
        enabled = mcla::DiagnosticsEnabled(); on = enabled && [defaults boolForKey:key];
    }
    if (path.section < 4) {
        NSString* baselineKey = key ?: (path.section == 0 ? @"MCLARenderHeight" : path.row == 0 ? @"MCLAFilterMode" : @"MCLABloomMode");
        id baseline = [defaults dictionaryForKey:@"MCLAGraphicsBaseline"][baselineKey];
        BOOL isDefault = baseline && [baseline isEqual:[defaults objectForKey:baselineKey]];
        if (isDefault) detail = [@"Default · " stringByAppendingString:detail];
    }
    cell.textLabel.text = title; cell.detailTextLabel.text = detail;
    cell.textLabel.enabled = enabled; cell.detailTextLabel.enabled = enabled;
    cell.imageView.image = [UIImage systemImageNamed:icon];
    cell.imageView.tintColor = enabled ? self.view.tintColor : UIColor.tertiaryLabelColor;
    cell.selectionStyle = enabled && !key ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    if (key) {
        UISwitch* toggle = [[UISwitch alloc] init]; toggle.on = on; toggle.enabled = enabled;
        toggle.onTintColor = self.view.tintColor;
        toggle.accessibilityLabel = title;
        toggle.accessibilityIdentifier = key;
        [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)saveSwitch:(UISwitch*)sender key:(NSString*)key {
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:key];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self.tableView reloadData];
}
- (void)restoreGraphicsDefaults:(id)sender {
    if (self.settingsLocked) return;
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary* baseline = [defaults dictionaryForKey:@"MCLAGraphicsBaseline"];
    for (NSString* key in baseline) [defaults setObject:baseline[key] forKey:key];
    for (NSString* key in @[@"MCLAExperimental60FPS"])
        [defaults setBool:NO forKey:key];
    MCLAGraphicsSetFSREnabled([defaults boolForKey:@"MCLAFSREnabled"]);
    MCLAGraphicsSetMotionBlurDisabled([defaults boolForKey:@"MCLADisableMotionBlur"]);
    MCLAGraphicsSetDepthOfFieldDisabled([defaults boolForKey:@"MCLADisableDepthOfField"]);
    mcla::SetDiagnosticsEnabled(![defaults boolForKey:@"MCLARetailMode"]);
    [defaults synchronize]; [self updateFrameRateHeader]; [self.tableView reloadData];
}
- (void)experimentalChanged:(UISwitch*)sender {
    if (self.settingsLocked) return;
    [self saveSwitch:sender key:sender.accessibilityIdentifier];
    [self updateFrameRateHeader];
}
- (void)depthOfFieldChanged:(UISwitch*)sender {
    if (self.settingsLocked) return;
    [self saveSwitch:sender key:@"MCLADisableDepthOfField"];
    MCLAGraphicsSetDepthOfFieldDisabled(sender.on);
}
- (void)motionBlurChanged:(UISwitch*)sender {
    if (self.settingsLocked) return;
    [self saveSwitch:sender key:@"MCLADisableMotionBlur"];
    MCLAGraphicsSetMotionBlurDisabled(sender.on);
}
- (void)retailModeChanged:(UISwitch*)sender {
    if (self.settingsLocked) return;
    [self saveSwitch:sender key:@"MCLARetailMode"];
    mcla::SetDiagnosticsEnabled(!sender.on); [self.tableView reloadData];
}
- (void)performanceOverlayChanged:(UISwitch*)sender { [self saveSwitch:sender key:@"MCLAPerformanceOverlay"]; }
- (void)fsrChanged:(UISwitch*)sender {
    [self saveSwitch:sender key:@"MCLAFSREnabled"]; MCLAGraphicsSetFSREnabled(sender.on);
}
- (void)smaaChanged:(UISwitch*)sender { if (!self.settingsLocked) [self saveSwitch:sender key:@"MCLASMAAEnabled"]; }
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (self.settingsLocked) return;
    BOOL resolution = path.section == 0 && path.row == 0;
    BOOL filtering = path.section == 1 && path.row == 0;
    BOOL bloom = path.section == 1 && path.row == 1;
    if (!resolution && !filtering && !bloom) return;
    NSString* key = resolution ? @"MCLARenderHeight" : filtering ? @"MCLAFilterMode" : @"MCLABloomMode";
    MCLAGraphicsChoiceController* choices = [[MCLAGraphicsChoiceController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    choices.title = resolution ? @"Scene Resolution" : filtering ? @"Texture Filtering" : @"Glow & Bloom";
    choices.names = resolution ? MCLAOutputOptionNames() : filtering ? MCLAFilterOptionNames() : MCLABloomOptionNames();
    choices.details = resolution ? @[@"Most headroom for a steady 30 FPS.", @"56% more scene pixels than 720p.", @"125% more scene pixels than 720p."] : filtering ? @[@"Use the game's original filtering.", @"Lowest filtering cost.", @"Recommended balance of clarity and cost.", @"Sharper textures at a higher cost.", @"Maximum filtering quality."] : @[@"Reduce broad haze while keeping local highlights.", @"Keep the original glow strength.", @"Reduce glow for a cleaner image."];
    NSInteger defaultValue = [[NSUserDefaults.standardUserDefaults dictionaryForKey:@"MCLAGraphicsBaseline"][key] integerValue];
    choices.defaultChoice = resolution ? (defaultValue == 1080 ? 2 : defaultValue == 900 ? 1 : 0) : defaultValue;
    NSInteger selected = [NSUserDefaults.standardUserDefaults integerForKey:key];
    choices.selected = resolution ? (selected == 1080 ? 2 : selected == 900 ? 1 : 0) : selected;
    choices.onSelect = ^(NSInteger row) {
        NSInteger value = resolution ? (row == 2 ? 1080 : row == 1 ? 900 : 720) : row;
        [NSUserDefaults.standardUserDefaults setInteger:value forKey:key];
        [NSUserDefaults.standardUserDefaults synchronize];
    };
    [self.navigationController pushViewController:choices animated:YES];
}
@end

@interface MCLASavesOptionsController : UITableViewController
@property(nonatomic, assign) NSUInteger saveFileCount;
@property(nonatomic, copy) void (^onExport)(void);
@property(nonatomic, copy) void (^onImport)(void);
@property(nonatomic, copy) void (^onDelete)(void);
@end

@implementation MCLASavesOptionsController
- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) self.title = @"Save Management";
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
}
- (void)done:(id)sender { (void)sender; [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? 2 : 1;
}
- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? [NSString stringWithFormat:@"MCLA saves · %lu files",
        (unsigned long)self.saveFileCount] : @"Remove";
}
- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"Export and import the complete save set, including nested profiles and autosaves. The .mclasave file can be moved through Files or AirDrop. Only available before starting the game."
        : @"Deleting saves cannot be undone. Export a backup first.";
}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)path {
    (void)tableView;
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    if (path.section == 0 && path.row == 0) {
        cell.textLabel.text = @"Export saves";
        cell.detailTextLabel.text = @"Save a portable .mclasave backup to Files";
    } else if (path.section == 0) {
        cell.textLabel.text = @"Import saves";
        cell.detailTextLabel.text = @"Choose a backup; confirm before replacing current saves";
    } else {
        cell.textLabel.text = @"Delete all saves";
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.detailTextLabel.text = @"Requires confirmation";
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if ((path.section == 1 || (path.section == 0 && path.row == 0)) &&
        !self.saveFileCount) {
        cell.textLabel.enabled = NO; cell.detailTextLabel.enabled = NO;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0 && path.row == 0 && self.saveFileCount && self.onExport) self.onExport();
    else if (path.section == 0 && path.row == 1 && self.onImport) self.onImport();
    else if (path.section == 1 && self.saveFileCount && self.onDelete) self.onDelete();
}
@end

@interface MCLAViewController () <UIGestureRecognizerDelegate, UIDocumentPickerDelegate>
@property(nonatomic, strong) MCLAMetalView* metalView;
@property(nonatomic, strong) UILabel* statusLabel;
@property(nonatomic, strong) UILabel* detailLabel;
@property(nonatomic, strong) UIButton* launchButton;
@property(nonatomic, strong) UIButton* graphicsButton;
@property(nonatomic, strong) UIButton* launchControlsButton;
@property(nonatomic, strong) UIButton* savesButton;
@property(nonatomic, strong) UIButton* padButton;
@property(nonatomic, strong) UIButton* controlsButton;
@property(nonatomic, strong) UIButton* editButton;
@property(nonatomic, strong) UILabel* layoutHint;
@property(nonatomic, copy) NSString* gameRoot;
@property(nonatomic, strong) NSTimer* statusTimer;
@property(nonatomic, strong) MCLALauncherView* panel;
@property(nonatomic, strong) NSTimer* launcherInputTimer;
@property(nonatomic, strong) NSTimer* toolbarTimer;
@property(nonatomic, assign) BOOL toolbarVisible;
@property(nonatomic, assign) BOOL gameVisible;
@property(nonatomic, assign) BOOL launchRequested;
@property(nonatomic, assign) BOOL runtimeStartPending;
@property(nonatomic, assign) BOOL sceneReleased;
@property(nonatomic, assign) BOOL controllerConfirmDown;
@property(nonatomic, assign) BOOL controllerBackDown;
@property(nonatomic, assign) BOOL controllerSampled;
@property(nonatomic, copy) NSString* launchError;
@property(nonatomic, assign) NSInteger controllerDirection;
@property(nonatomic, assign) CFTimeInterval nextControllerRepeat;
@property(nonatomic, strong) NSIndexPath* controllerSettingsRow;
@property(nonatomic, weak) UITableViewController* controllerSettingsPage;
@property(nonatomic, weak) MCLASavesOptionsController* savesOptionsPage;
@property(nonatomic, strong) NSURL* saveExportURL;
@property(nonatomic, assign) BOOL importingSaveArchive;
@property(nonatomic, strong) UIAlertController* pendingSaveAlert;
@property(nonatomic, copy) void (^pendingSaveConfirm)(void);
@property(nonatomic, copy) void (^pendingSaveCancel)(void);
@property(nonatomic, strong) UIStackView* touchControls;
@property(nonatomic, assign) BOOL overhaulGasHeld;
@property(nonatomic, assign) BOOL overhaulHandbrakeHeld;
@property(nonatomic, assign) BOOL overhaulWasEnabled;
@property(nonatomic, strong) MCLAVirtualStickView* steeringStick;
@property(nonatomic, strong) MCLAVirtualStickView* cameraStick;
@property(nonatomic, strong) NSArray<UIButton*>* pedals;
@property(nonatomic, strong) NSArray<UIButton*>* drivingActions;
@property(nonatomic, strong) NSArray<NSString*>* drivingActionKeys;
@property(nonatomic, strong) UIVisualEffectView* fullPadPanel;
@property(nonatomic, strong) NSMutableDictionary<NSString*, UIButton*>* paletteButtons;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSDictionary*>* originalTouchAppearance;
@property(nonatomic, strong) NSMutableDictionary<NSString*, UIView*>* layoutControls;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSArray<NSNumber*>*>* layoutDefaults;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSLayoutConstraint*>* layoutX;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSLayoutConstraint*>* layoutY;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSLayoutConstraint*>* layoutWidth;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSLayoutConstraint*>* layoutHeight;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSArray<NSNumber*>*>* layoutDefaultSizes;
@property(nonatomic, assign) BOOL editingTouchLayout;
@property(nonatomic, strong) CMMotionManager* motionManager;
@property(nonatomic, assign) double tiltNeutral;
@property(nonatomic, assign) BOOL tiltNeutralValid;
@property(nonatomic, assign) float tiltFiltered;
@property(nonatomic, assign) BOOL touchInputActive;
@property(nonatomic, strong) MCLAFrameTimeGraphView* performanceGraph;
@property(nonatomic, assign) BOOL autoContinueSent;
@property(nonatomic, assign) BOOL autoContinueFallbackSent;
@property(nonatomic, assign) BOOL autoSaveConfirmSent;
@property(nonatomic, assign) BOOL autoSaveWarningConfirmSent;
@end

@implementation MCLAViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    MCLARegisterGraphicsDefaults();
    NSString* aspectOverride = NSProcessInfo.processInfo.environment[@"MCLA_NATIVE_ASPECT"];
    const BOOL nativeAspect = aspectOverride ? aspectOverride.boolValue : YES;
    CGSize nativePixels = UIScreen.mainScreen.nativeBounds.size;
    MCLAGraphicsConfigureNativeAspect(
        (uint32_t)MAX(nativePixels.width, nativePixels.height),
        (uint32_t)MIN(nativePixels.width, nativePixels.height), nativeAspect);
    [self prepareGameDataFolderIfNeeded];

    self.metalView = [[MCLAMetalView alloc] initWithFrame:CGRectZero];
    self.metalView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.metalView];
    if (nativeAspect) {
      [NSLayoutConstraint activateConstraints:@[
        [self.metalView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.metalView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.metalView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.metalView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
      ]];
    } else {
    [NSLayoutConstraint activateConstraints:@[
        [self.metalView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.metalView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.metalView.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor],
        [self.metalView.heightAnchor constraintLessThanOrEqualToAnchor:self.view.heightAnchor],
        [self.metalView.widthAnchor constraintEqualToAnchor:self.metalView.heightAnchor multiplier:16.0/9.0],
    ]];
    // Fill whichever dimension constrains the 16:9 image; never distort the
    // guest frame merely to fill the iPad/phone panel.
    NSLayoutConstraint* fillWidth = [self.metalView.widthAnchor
        constraintEqualToAnchor:self.view.widthAnchor];
    fillWidth.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint* fillHeight = [self.metalView.heightAnchor
        constraintEqualToAnchor:self.view.heightAnchor];
    fillHeight.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[fillWidth, fillHeight]];
    }

    MCLALauncherView* panel = [[MCLALauncherView alloc] initWithFrame:self.view.bounds];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:panel];
    self.panel = panel;

    UIButton* startButton = [self makeTouchButton:@"START"
                                              tag:MCLA_GAMEPAD_START];
    UIButton* aButton = [self makeTouchButton:@"A" tag:MCLA_GAMEPAD_A];
    self.padButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.padButton setTitle:@"CONTROLS" forState:UIControlStateNormal];
    [self.padButton addTarget:self action:@selector(toggleFullPad:)
             forControlEvents:UIControlEventTouchUpInside];
    self.controlsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.controlsButton setTitle:@"SETTINGS" forState:UIControlStateNormal];
    [self.controlsButton addTarget:self action:@selector(showControlsOptions:)
               forControlEvents:UIControlEventTouchUpInside];
    self.editButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.editButton setTitle:@"EDIT" forState:UIControlStateNormal];
    [self.editButton addTarget:self action:@selector(toggleTouchLayoutEditing:)
              forControlEvents:UIControlEventTouchUpInside];
    UIButton* performanceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    performanceButton.translatesAutoresizingMaskIntoConstraints = NO;
    [performanceButton setTitle:@"FPS" forState:UIControlStateNormal];
    performanceButton.titleLabel.font =
        [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightBold];
    UIButtonConfiguration* performanceConfiguration =
        [UIButtonConfiguration tintedButtonConfiguration];
    performanceConfiguration.baseForegroundColor = UIColor.systemCyanColor;
    performanceConfiguration.baseBackgroundColor =
        [UIColor colorWithWhite:0.12 alpha:0.82];
    performanceConfiguration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    performanceButton.configuration = performanceConfiguration;
    [performanceButton addTarget:self action:@selector(togglePerformanceOverlay:)
                forControlEvents:UIControlEventTouchUpInside];
    UIStackView* touchControls =
        [[UIStackView alloc] initWithArrangedSubviews:
            @[performanceButton, startButton, aButton, self.padButton,
              self.controlsButton, self.editButton]];
    touchControls.translatesAutoresizingMaskIntoConstraints = NO;
    touchControls.axis = UILayoutConstraintAxisHorizontal;
    touchControls.alignment = UIStackViewAlignmentCenter;
    touchControls.spacing = 14.0;
    touchControls.hidden = YES;
    [self.view addSubview:touchControls];
    self.touchControls = touchControls;
    touchControls.accessibilityIdentifier = @"mcla.gameplayToolbar";
    UITapGestureRecognizer* toolbarTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(revealGameplayToolbar:)];
    toolbarTap.numberOfTouchesRequired = 3;
    toolbarTap.cancelsTouchesInView = NO;
    toolbarTap.delegate = self;
    [self.view addGestureRecognizer:toolbarTap];

    self.performanceGraph = [[MCLAFrameTimeGraphView alloc] initWithFrame:CGRectZero];
    self.performanceGraph.translatesAutoresizingMaskIntoConstraints = NO;
    self.performanceGraph.hidden = YES;
    UITapGestureRecognizer* captureTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(startPerformanceCapture:)];
    captureTap.numberOfTapsRequired = 2;
    [self.performanceGraph addGestureRecognizer:captureTap];
    [self.view addSubview:self.performanceGraph];
    self.layoutHint = [[UILabel alloc] init];
    self.layoutHint.translatesAutoresizingMaskIntoConstraints = NO;
    self.layoutHint.text = @"DRAG · PINCH · 3-FINGER TAP FOR DONE";
    self.layoutHint.textAlignment = NSTextAlignmentCenter;
    self.layoutHint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightHeavy];
    self.layoutHint.textColor = UIColor.whiteColor;
    self.layoutHint.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.72];
    self.layoutHint.layer.cornerRadius = 12;
    self.layoutHint.clipsToBounds = YES;
    self.layoutHint.hidden = YES;
    [self.view addSubview:self.layoutHint];

    self.statusLabel = panel.statusLabel;
    self.detailLabel = panel.detailLabel;
    self.launchButton = panel.launchButton;
    [self.launchButton addTarget:self action:@selector(launchMCLA:)
                forControlEvents:UIControlEventTouchUpInside];

    self.graphicsButton=panel.graphicsButton;
    [self.graphicsButton addTarget:self action:@selector(showGraphicsOptions:)
                   forControlEvents:UIControlEventTouchUpInside];
    self.launchControlsButton = panel.controlsButton;
    [self.launchControlsButton addTarget:self action:@selector(showControlsOptions:)
                       forControlEvents:UIControlEventTouchUpInside];
    self.savesButton = panel.savesButton;
    [self.savesButton addTarget:self action:@selector(showSaveOptions:)
              forControlEvents:UIControlEventTouchUpInside];

    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [panel.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [panel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [touchControls.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor
                                                     constant:-18.0],
        [touchControls.topAnchor constraintEqualToAnchor:safe.topAnchor
                                                 constant:10.0],
        [startButton.widthAnchor constraintEqualToConstant:94.0],
        [startButton.heightAnchor constraintEqualToConstant:48.0],
        [performanceButton.widthAnchor constraintEqualToConstant:58.0],
        [performanceButton.heightAnchor constraintEqualToConstant:42.0],
        [aButton.widthAnchor constraintEqualToConstant:54.0],
        [aButton.heightAnchor constraintEqualToConstant:54.0],
        [self.padButton.widthAnchor constraintEqualToConstant:88.0],
        [self.controlsButton.widthAnchor constraintEqualToConstant:76.0],
        [self.editButton.widthAnchor constraintEqualToConstant:56.0],
        [self.layoutHint.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [self.layoutHint.topAnchor constraintEqualToAnchor:safe.topAnchor constant:72],
        [self.layoutHint.widthAnchor constraintEqualToConstant:390],
        [self.layoutHint.heightAnchor constraintEqualToConstant:30],
        [self.performanceGraph.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor
                                                             constant:14.0],
        [self.performanceGraph.topAnchor constraintEqualToAnchor:safe.topAnchor
                                                         constant:12.0],
        [self.performanceGraph.widthAnchor constraintEqualToConstant:
            UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone ? 230.0 : 300.0],
        [self.performanceGraph.heightAnchor constraintEqualToConstant:
            UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone ? 80.0 : 105.0],
    ]];

    [self buildDrivingControlsWithSafe:safe];
    self.motionManager = [[CMMotionManager alloc] init];
    self.motionManager.deviceMotionUpdateInterval = 1.0 / 60.0;
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(appWillResignActive:)
        name:UIApplicationWillResignActiveNotification object:nil];
    MCLAGraphicsSetApplicationActive(
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive);
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification
        object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification
        object:nil];

    [self refreshBringupStatus];
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
        target:self selector:@selector(refreshBringupStatus)
        userInfo:nil repeats:YES];
    __weak MCLAViewController* weakSelf = self;
    self.launcherInputTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 repeats:YES
        block:^(NSTimer* timer) { (void)timer; [weakSelf pollLauncherController]; }];

    // Device bring-up can request a repeatable, console-captured boot without
    // relying on UI automation. Normal launches retain the explicit button.
    if ([NSProcessInfo.processInfo.environment[@"MCLA_AUTOLAUNCH"] boolValue]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self launchMCLA:nil];
        });
    }
}

// Files.app exposes the app Documents container only after the app has run.
// Create the expected import folder once, but never alter an existing folder:
// the M5 iPad's verified game extraction must stay exactly as supplied.
- (void)prepareGameDataFolderIfNeeded {
    NSString* documents = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    self.gameRoot = [documents stringByAppendingPathComponent:@"MCLA_Game_Files"];
    BOOL directory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:self.gameRoot
                                            isDirectory:&directory]) {
        return;
    }
    NSError* error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:self.gameRoot
                                  withIntermediateDirectories:YES
                                                   attributes:nil error:&error]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Filesystem not created"
                message:[NSString stringWithFormat:@"MCLA could not create its game-data folder: %@", error.localizedDescription]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Filesystem created"
            message:@"MCLA_Game_Files is ready in this app’s Files folder. Close MCLA, copy your extracted game files into that folder, then reopen MCLA."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (UIButton*)makePedal:(NSString*)title right:(BOOL)right {
    UIButton* button = [self makeTouchButton:title tag:0];
    button.tag = right ? 2 : 1;
    [button removeTarget:self action:@selector(gamepadButtonDown:)
       forControlEvents:UIControlEventTouchDown];
    [button removeTarget:self action:@selector(gamepadButtonUp:)
       forControlEvents:(UIControlEventTouchUpInside |
                         UIControlEventTouchUpOutside | UIControlEventTouchCancel)];
    [button addTarget:self action:@selector(pedalDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(pedalUp:)
       forControlEvents:(UIControlEventTouchUpInside |
                         UIControlEventTouchUpOutside | UIControlEventTouchCancel)];
    UIColor* accent = right ? UIColor.systemTealColor : UIColor.systemOrangeColor;
    button.backgroundColor = [accent colorWithAlphaComponent:0.23];
    button.layer.borderColor = [accent colorWithAlphaComponent:0.60].CGColor;
    button.layer.borderWidth = 1.5;
    button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightHeavy];
    return button;
}

- (UIStackView*)controlRow:(NSArray<UIButton*>*)buttons {
    UIStackView* row = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 5.0;
    for (UIButton* button in buttons) {
        button.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.7;
        [button.heightAnchor constraintEqualToConstant:42.0].active = YES;
    }
    return row;
}

- (BOOL)isTouchControlDeployed:(NSString*)key {
    NSArray<NSString*>* active = [NSUserDefaults.standardUserDefaults
        arrayForKey:MCLATouchPreference(@"MCLATouchActiveControls")];
    return [active containsObject:key];
}

- (void)setTouchControl:(NSString*)key deployed:(BOOL)deployed {
    NSMutableOrderedSet<NSString*>* active = [NSMutableOrderedSet orderedSetWithArray:
        [NSUserDefaults.standardUserDefaults arrayForKey:MCLATouchPreference(@"MCLATouchActiveControls")] ?: @[]];
    if (deployed) [active addObject:key]; else [active removeObject:key];
    [NSUserDefaults.standardUserDefaults setObject:active.array
                                            forKey:MCLATouchPreference(@"MCLATouchActiveControls")];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self refreshTouchInputForGameVisible:!self.panel.hidden];
}

- (void)addPaletteControl:(UITapGestureRecognizer*)tap {
    if (tap.state != UIGestureRecognizerStateRecognized) return;
    NSString* identifier = tap.view.accessibilityIdentifier;
    NSString* key = [identifier stringByReplacingOccurrencesOfString:
        @"mcla.palette." withString:@""];
    if (!self.layoutControls[key]) return;
    [self setTouchControl:key deployed:YES];
    UIButton* button = self.paletteButtons[key];
    button.alpha = 0.42;
}

- (void)returnControlToPalette:(UITapGestureRecognizer*)tap {
    if (tap.state != UIGestureRecognizerStateRecognized ||
        !self.editingTouchLayout) return;
    NSString* key = [tap.view.accessibilityIdentifier
        stringByReplacingOccurrencesOfString:@"mcla.touch." withString:@""];
    if (![self.drivingActionKeys containsObject:key]) return;
    [self setTouchControl:key deployed:NO];
}

- (UIButton*)paletteButton:(NSString*)title key:(NSString*)key
                       mask:(uint16_t)mask {
    UIButton* button = [self makeTouchButton:title tag:mask];
    button.accessibilityIdentifier = [@"mcla.palette." stringByAppendingString:key];
    UITapGestureRecognizer* add = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(addPaletteControl:)];
    add.numberOfTapsRequired = 2;
    add.cancelsTouchesInView = YES;
    [button addGestureRecognizer:add];
    if (!self.paletteButtons) self.paletteButtons = [NSMutableDictionary dictionary];
    self.paletteButtons[key] = button;
    return button;
}

- (void)registerMovableControl:(UIView*)control key:(NSString*)key
                           x:(CGFloat)x y:(CGFloat)y
                       width:(CGFloat)width height:(CGFloat)height {
    if (!self.layoutControls) {
        self.layoutControls = [NSMutableDictionary dictionary];
        self.layoutDefaults = [NSMutableDictionary dictionary];
        self.layoutX = [NSMutableDictionary dictionary];
        self.layoutY = [NSMutableDictionary dictionary];
        self.layoutWidth = [NSMutableDictionary dictionary];
        self.layoutHeight = [NSMutableDictionary dictionary];
        self.layoutDefaultSizes = [NSMutableDictionary dictionary];
    }
    control.translatesAutoresizingMaskIntoConstraints = NO;
    control.accessibilityIdentifier = [@"mcla.touch." stringByAppendingString:key];
    [self.view addSubview:control];
    NSLayoutConstraint* centerX = [control.centerXAnchor
        constraintEqualToAnchor:self.view.leadingAnchor];
    NSLayoutConstraint* centerY = [control.centerYAnchor
        constraintEqualToAnchor:self.view.topAnchor];
    NSLayoutConstraint* controlWidth = [control.widthAnchor constraintEqualToConstant:width];
    NSLayoutConstraint* controlHeight = [control.heightAnchor constraintEqualToConstant:height];
    [NSLayoutConstraint activateConstraints:@[
        centerX, centerY,
        controlWidth, controlHeight,
    ]];
    self.layoutControls[key] = control;
    if ([control isKindOfClass:UIButton.class]) {
        if (!self.originalTouchAppearance) self.originalTouchAppearance=[NSMutableDictionary dictionary];
        UIButton* button=(UIButton*)control;
        self.originalTouchAppearance[key]=@{@"title":[button titleForState:UIControlStateNormal] ?: @"",
            @"background":button.backgroundColor ?: UIColor.clearColor,
            @"border":control.layer.borderColor ? [UIColor colorWithCGColor:control.layer.borderColor] : UIColor.clearColor,
            @"borderWidth":@(control.layer.borderWidth), @"font":button.titleLabel.font,
            @"lines":@(button.titleLabel.numberOfLines)};
    }
    self.layoutDefaults[key] = @[@(x), @(y)];
    self.layoutX[key] = centerX;
    self.layoutY[key] = centerY;
    self.layoutWidth[key] = controlWidth;
    self.layoutHeight[key] = controlHeight;
    self.layoutDefaultSizes[key] = @[@(width), @(height)];
    NSArray<NSNumber*>* devicePosition = MCLADeviceLayoutPositions()[key];
    if (devicePosition) self.layoutDefaults[key] = devicePosition;
    NSArray<NSNumber*>* deviceSize = MCLADeviceLayoutSizes()[key];
    if (deviceSize) self.layoutDefaultSizes[key] = deviceSize;
    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(dragTouchControl:)];
    pan.maximumNumberOfTouches = 1;
    pan.enabled = NO;
    [control addGestureRecognizer:pan];
    UIPinchGestureRecognizer* pinch = [[UIPinchGestureRecognizer alloc]
        initWithTarget:self action:@selector(pinchTouchControl:)];
    pinch.enabled = NO;
    [control addGestureRecognizer:pinch];
    UITapGestureRecognizer* remove = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(returnControlToPalette:)];
    remove.numberOfTapsRequired = 2;
    remove.cancelsTouchesInView = YES;
    [control addGestureRecognizer:remove];
}

- (UIButton*)addDrivingAction:(NSString*)title mask:(uint16_t)mask
                            key:(NSString*)key x:(CGFloat)x y:(CGFloat)y
                          width:(CGFloat)width {
    UIButton* button = [self makeTouchButton:title tag:mask];
    button.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.8;
    [self registerMovableControl:button key:key x:x y:y width:width height:58];
    return button;
}

- (void)buildDrivingControlsWithSafe:(UILayoutGuide*)safe {
    self.steeringStick = [[MCLAVirtualStickView alloc] initWithTitle:@"STEER · LEFT STICK"];
    __weak MCLAViewController* weakSelf = self;
    self.steeringStick.onStick = ^(float x, float y, BOOL active) {
        if (weakSelf.editingTouchLayout) return;
        MCLASetVirtualGamepadLeftStick(x, y, active);
    };
    self.steeringStick.layer.cornerRadius = 86;
    [self registerMovableControl:self.steeringStick key:@"steer"
                              x:0.15 y:0.72 width:172 height:172];

    UIButton* gas = [self makePedal:@"GAS\nRT" right:YES];
    UIButton* brake = [self makePedal:@"BRAKE\nLT" right:NO];
    for (UIButton* pedal in @[gas, brake]) {
        pedal.titleLabel.numberOfLines = 2;
        pedal.titleLabel.textAlignment = NSTextAlignmentCenter;
        pedal.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
        pedal.layer.cornerRadius = 25;
    }
    [self registerMovableControl:gas key:@"gas"
                              x:0.90 y:0.73 width:146 height:180];
    [self registerMovableControl:brake key:@"brake"
                              x:0.73 y:0.77 width:132 height:154];
    self.pedals = @[gas, brake];

    self.drivingActions = @[
        [self addDrivingAction:@"A · DRIFT" mask:MCLA_GAMEPAD_A
                          key:@"handbrake" x:0.72 y:0.50 width:92],
        [self addDrivingAction:@"X · NITRO" mask:MCLA_GAMEPAD_X
                          key:@"nitro" x:0.87 y:0.46 width:86],
        [self addDrivingAction:@"Y · HEADLIGHTS" mask:MCLA_GAMEPAD_Y
                          key:@"headlights" x:0.78 y:0.40 width:104],
        [self addDrivingAction:@"LB · ABILITY" mask:MCLA_GAMEPAD_LEFT_SHOULDER
                          key:@"ability" x:0.70 y:0.34 width:92],
        [self addDrivingAction:@"RB · CAMERA" mask:MCLA_GAMEPAD_RIGHT_SHOULDER
                          key:@"camera" x:0.86 y:0.31 width:92],
        [self addDrivingAction:@"B · WEIGHT" mask:MCLA_GAMEPAD_B
                          key:@"weight" x:0.57 y:0.61 width:86],
        [self addDrivingAction:@"BACK · GPS" mask:MCLA_GAMEPAD_BACK
                          key:@"gps" x:0.48 y:0.16 width:86],
        [self addDrivingAction:@"↑ · HUD" mask:MCLA_GAMEPAD_DPAD_UP
                          key:@"hud" x:0.61 y:0.16 width:80],
        [self addDrivingAction:@"↓ · HYD" mask:MCLA_GAMEPAD_DPAD_DOWN
                          key:@"hydraulics" x:0.55 y:0.24 width:80],
        [self addDrivingAction:@"← · TRACK" mask:MCLA_GAMEPAD_DPAD_LEFT
                          key:@"track_left" x:0.45 y:0.24 width:84],
        [self addDrivingAction:@"→ · TRACK" mask:MCLA_GAMEPAD_DPAD_RIGHT
                          key:@"track_right" x:0.65 y:0.24 width:84],
        [self addDrivingAction:@"LS · INFO" mask:MCLA_GAMEPAD_LEFT_THUMB
                          key:@"info" x:0.42 y:0.34 width:80],
        [self addDrivingAction:@"RS · HORN" mask:MCLA_GAMEPAD_RIGHT_THUMB
                          key:@"horn" x:0.58 y:0.34 width:80],
        [self addDrivingAction:@"START · PAUSE" mask:MCLA_GAMEPAD_START
                          key:@"pause" x:0.50 y:0.10 width:102],
        [self addDrivingAction:@"GUIDE" mask:MCLA_GAMEPAD_GUIDE
                          key:@"guide" x:0.50 y:0.42 width:76],
    ];
    self.drivingActionKeys = @[@"handbrake", @"nitro", @"headlights",
        @"ability", @"camera", @"weight", @"gps", @"hud", @"hydraulics",
        @"track_left", @"track_right", @"info", @"horn", @"pause", @"guide"];

    id glassClass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect* paletteEffect = glassClass ? [[glassClass alloc] init] :
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView* panel = [[UIVisualEffectView alloc]
        initWithEffect:paletteEffect];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.layer.cornerRadius = 22;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.28;
    panel.layer.shadowRadius = 22;
    panel.layer.shadowOffset = CGSizeMake(0, 10);
    panel.clipsToBounds = YES;
    [self.view addSubview:panel];
    self.fullPadPanel = panel;
    UIScrollView* scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [panel.contentView addSubview:scroll];
    UIStackView* content = [[UIStackView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 6;
    [scroll addSubview:content];
    UILabel* heading = [[UILabel alloc] init];
    heading.text = @"CONTROLS · DOUBLE TAP TO ADD";
    heading.textColor = UIColor.whiteColor;
    heading.font = [UIFont systemFontOfSize:12 weight:UIFontWeightHeavy];
    [content addArrangedSubview:heading];
    [content addArrangedSubview:[self controlRow:@[
        [self paletteButton:@"A · HANDBRAKE" key:@"handbrake" mask:MCLA_GAMEPAD_A],
        [self paletteButton:@"B · WEIGHT" key:@"weight" mask:MCLA_GAMEPAD_B],
        [self paletteButton:@"X · NITRO" key:@"nitro" mask:MCLA_GAMEPAD_X],
        [self paletteButton:@"Y · LIGHTS" key:@"headlights" mask:MCLA_GAMEPAD_Y]]]];
    [content addArrangedSubview:[self controlRow:@[
        [self paletteButton:@"LB · ABILITY" key:@"ability" mask:MCLA_GAMEPAD_LEFT_SHOULDER],
        [self paletteButton:@"RB · CAMERA" key:@"camera" mask:MCLA_GAMEPAD_RIGHT_SHOULDER],
        [self makePedal:@"LT · BRAKE" right:NO],
        [self makePedal:@"RT · GAS" right:YES]]]];
    [content addArrangedSubview:[self controlRow:@[
        [self paletteButton:@"BACK · GPS" key:@"gps" mask:MCLA_GAMEPAD_BACK],
        [self paletteButton:@"START · PAUSE" key:@"pause" mask:MCLA_GAMEPAD_START],
        [self paletteButton:@"GUIDE" key:@"guide" mask:MCLA_GAMEPAD_GUIDE]]]];
    [content addArrangedSubview:[self controlRow:@[
        [self paletteButton:@"↑ · HUD" key:@"hud" mask:MCLA_GAMEPAD_DPAD_UP],
        [self paletteButton:@"↓ · HYD" key:@"hydraulics" mask:MCLA_GAMEPAD_DPAD_DOWN],
        [self paletteButton:@"← · TRACK" key:@"track_left" mask:MCLA_GAMEPAD_DPAD_LEFT],
        [self paletteButton:@"→ · TRACK" key:@"track_right" mask:MCLA_GAMEPAD_DPAD_RIGHT]]]];
    [content addArrangedSubview:[self controlRow:@[
        [self paletteButton:@"LS · INFO" key:@"info" mask:MCLA_GAMEPAD_LEFT_THUMB],
        [self paletteButton:@"RS · HORN" key:@"horn" mask:MCLA_GAMEPAD_RIGHT_THUMB]]]];
    self.cameraStick = [[MCLAVirtualStickView alloc] initWithTitle:@"RIGHT STICK · LOOK"];
    self.cameraStick.translatesAutoresizingMaskIntoConstraints = NO;
    self.cameraStick.onStick = ^(float x, float y, BOOL active) {
        MCLASetVirtualGamepadRightStick(x, y, active);
    };
    UIView* cameraRow = [[UIView alloc] init];
    [cameraRow addSubview:self.cameraStick];
    [content addArrangedSubview:cameraRow];
    UILabel* guideNote = [[UILabel alloc] init];
    guideNote.text = @"GUIDE is the Xbox system key; it has no MCLA driving action.";
    guideNote.font = [UIFont systemFontOfSize:10];
    guideNote.textColor = UIColor.systemGray2Color;
    guideNote.numberOfLines = 0;
    [content addArrangedSubview:guideNote];

    [NSLayoutConstraint activateConstraints:@[
        [panel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [panel.topAnchor constraintEqualToAnchor:self.touchControls.bottomAnchor constant:9],
        [panel.widthAnchor constraintEqualToConstant:390],
        [panel.heightAnchor constraintEqualToConstant:420],
        [panel.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-8],
        [scroll.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:10],
        [scroll.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-10],
        [scroll.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor constant:10],
        [scroll.bottomAnchor constraintEqualToAnchor:panel.contentView.bottomAnchor constant:-10],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [cameraRow.heightAnchor constraintEqualToConstant:112],
        [self.cameraStick.leadingAnchor constraintEqualToAnchor:cameraRow.leadingAnchor],
        [self.cameraStick.topAnchor constraintEqualToAnchor:cameraRow.topAnchor],
        [self.cameraStick.widthAnchor constraintEqualToConstant:112],
        [self.cameraStick.heightAnchor constraintEqualToConstant:112],
    ]];
    self.steeringStick.hidden = YES;
    for (UIButton* pedal in self.pedals) pedal.hidden = YES;
    for (UIButton* action in self.drivingActions) action.hidden = YES;
    self.fullPadPanel.hidden = YES;
}

- (CGRect)touchSafeRect {
    return UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
}

- (NSArray<NSNumber*>*)touchPositionForKey:(NSString*)key {
    NSDictionary* saved = [NSUserDefaults.standardUserDefaults
        dictionaryForKey:MCLATouchPreference(@"MCLATouchLayoutPositions")];
    NSArray* position = saved[key];
    if ([position isKindOfClass:NSArray.class] && position.count == 2 &&
        [position[0] isKindOfClass:NSNumber.class] &&
        [position[1] isKindOfClass:NSNumber.class]) return position;
    return MCLAControlOverhaulEnabled() ?
        (MCLAOverhaulPositions()[key] ?: self.layoutDefaults[key]) : self.layoutDefaults[key];
}

- (NSArray<NSNumber*>*)touchSizeForKey:(NSString*)key {
    NSDictionary* saved = [NSUserDefaults.standardUserDefaults
        dictionaryForKey:MCLATouchPreference(@"MCLATouchLayoutSizes")];
    NSArray* size = saved[key];
    if ([size isKindOfClass:NSArray.class] && size.count == 2 &&
        [size[0] isKindOfClass:NSNumber.class] &&
        [size[1] isKindOfClass:NSNumber.class]) return size;
    if (MCLAControlOverhaulEnabled()) {
        NSArray<NSNumber*>* authored=MCLAOverhaulSizes()[key];
        if (authored) {
            CGRect safe=[self touchSafeRect];
            CGFloat scale=MIN(safe.size.width/1280.0,safe.size.height/720.0);
            return @[@(authored[0].doubleValue*scale),@(authored[1].doubleValue*scale)];
        }
    }
    return self.layoutDefaultSizes[key];
}

- (void)applyTouchControlAppearance:(UIView*)control {
    const CGFloat radius = MIN(control.bounds.size.width, control.bounds.size.height) * 0.18;
    if ([control isKindOfClass:MCLAVirtualStickView.class])
        control.layer.cornerRadius = MIN(control.bounds.size.width, control.bounds.size.height) * 0.5;
    else if ([control isKindOfClass:UIButton.class])
        control.layer.cornerRadius = radius;
    BOOL overhaul=MCLAControlOverhaulEnabled();
    NSString* key=[control.accessibilityIdentifier stringByReplacingOccurrencesOfString:@"mcla.touch." withString:@""];
    if ([control isKindOfClass:MCLAVirtualStickView.class]) {
        MCLAVirtualStickView* stick=(MCLAVirtualStickView*)control;
        stick.caption.hidden=overhaul;
        stick.layer.borderColor=(overhaul ? [UIColor colorWithRed:0.2 green:0.95 blue:1 alpha:0.8] : [UIColor colorWithWhite:1 alpha:0.4]).CGColor;
        stick.layer.borderWidth=overhaul ? 2 : 1.2;
    } else if ([control isKindOfClass:UIButton.class]) {
        UIButton* button=(UIButton*)control;
        NSDictionary* titles=@{@"gas":@"❯❯\nGAS", @"brake":@"❮❮\nBRAKE",
            @"handbrake":@"↝\nGAS + HB", @"nitro":@"ϟ\nNITRO", @"pause":@"Ⅱ", @"camera":@"▣"};
        NSDictionary* original=self.originalTouchAppearance[key];
        [button setTitle:overhaul && titles[key] ? titles[key] : original[@"title"] forState:UIControlStateNormal];
        button.titleLabel.numberOfLines=overhaul ? 2 : [original[@"lines"] integerValue];
        button.titleLabel.textAlignment=NSTextAlignmentCenter;
        button.titleLabel.font=overhaul ? [UIFont systemFontOfSize:MAX(12,MIN(26,control.bounds.size.height*.20)) weight:UIFontWeightHeavy] : original[@"font"];
        button.layer.borderColor=(overhaul ? [UIColor colorWithRed:0.2 green:0.95 blue:1 alpha:0.8] : (UIColor*)original[@"border"]).CGColor;
        button.backgroundColor=overhaul ? [UIColor colorWithWhite:0.015 alpha:0.35] : original[@"background"];
        button.layer.borderWidth=overhaul ? 1.8 : [original[@"borderWidth"] doubleValue];
        if (overhaul && [key isEqual:@"nitro"]) button.layer.cornerRadius=MIN(control.bounds.size.width,control.bounds.size.height)*.5;
    }
}

- (void)applyTouchLayout {
    CGRect safe = [self touchSafeRect];
    if (safe.size.width <= 0 || safe.size.height <= 0) return;
    for (NSString* key in self.layoutControls) {
        UIView* control = self.layoutControls[key];
        NSArray<NSNumber*>* defaultSize = self.layoutDefaultSizes[key];
        if (MCLAControlOverhaulEnabled()) {
            NSArray<NSNumber*>* authored=MCLAOverhaulSizes()[key];
            CGFloat scale=MIN(safe.size.width/1280.0,safe.size.height/720.0);
            if (authored) defaultSize=@[@(authored[0].doubleValue*scale),@(authored[1].doubleValue*scale)];
        }
        NSArray<NSNumber*>* savedSize = [self touchSizeForKey:key];
        // Keep edit controls usable: roughly 55%–155% of their authored size.
        const CGFloat minScale = 0.55;
        const CGFloat maxScale = 1.55;
        const CGFloat width = fmax(defaultSize[0].doubleValue * minScale,
            fmin(defaultSize[0].doubleValue * maxScale, savedSize[0].doubleValue));
        const CGFloat height = fmax(defaultSize[1].doubleValue * minScale,
            fmin(defaultSize[1].doubleValue * maxScale, savedSize[1].doubleValue));
        NSLayoutConstraint* widthConstraint = self.layoutWidth[key];
        NSLayoutConstraint* heightConstraint = self.layoutHeight[key];
        if (fabs(widthConstraint.constant - width) > 0.1) widthConstraint.constant = width;
        if (fabs(heightConstraint.constant - height) > 0.1) heightConstraint.constant = height;
        [self applyTouchControlAppearance:control];
        NSArray<NSNumber*>* position = [self touchPositionForKey:key];
        const CGFloat normalizedX = fmax(0, fmin(1, position[0].doubleValue));
        const CGFloat normalizedY = fmax(0, fmin(1, position[1].doubleValue));
        const CGFloat insetX = control.bounds.size.width * 0.5 + 4;
        const CGFloat insetY = control.bounds.size.height * 0.5 + 4;
        const CGFloat minX = CGRectGetMinX(safe) + insetX;
        const CGFloat maxX = CGRectGetMaxX(safe) - insetX;
        const CGFloat minY = CGRectGetMinY(safe) + insetY;
        const CGFloat maxY = CGRectGetMaxY(safe) - insetY;
        const CGFloat x = fmax(minX, fmin(maxX, CGRectGetMinX(safe) +
                                                normalizedX * safe.size.width));
        const CGFloat y = fmax(minY, fmin(maxY, CGRectGetMinY(safe) +
                                                normalizedY * safe.size.height));
        NSLayoutConstraint* centerX = self.layoutX[key];
        NSLayoutConstraint* centerY = self.layoutY[key];
        if (fabs(centerX.constant - x) > 0.1) centerX.constant = x;
        if (fabs(centerY.constant - y) > 0.1) centerY.constant = y;
    }
}

- (void)pinchTouchControl:(UIPinchGestureRecognizer*)pinch {
    if (!self.editingTouchLayout) return;
    UIView* control = pinch.view;
    NSString* key = [control.accessibilityIdentifier
        stringByReplacingOccurrencesOfString:@"mcla.touch." withString:@""];
    NSArray<NSNumber*>* defaultSize = self.layoutDefaultSizes[key];
    if (!defaultSize) return;
    if (pinch.state == UIGestureRecognizerStateBegan)
        pinch.scale = 1.0;
    const CGFloat currentWidth = self.layoutWidth[key].constant;
    const CGFloat currentHeight = self.layoutHeight[key].constant;
    const CGFloat nextWidth = currentWidth * pinch.scale;
    const CGFloat nextHeight = currentHeight * pinch.scale;
    pinch.scale = 1.0;
    NSMutableDictionary* sizes = [[NSUserDefaults.standardUserDefaults
        dictionaryForKey:MCLATouchPreference(@"MCLATouchLayoutSizes")] mutableCopy] ?: [NSMutableDictionary dictionary];
    sizes[key] = @[@(nextWidth), @(nextHeight)];
    [NSUserDefaults.standardUserDefaults setObject:sizes forKey:MCLATouchPreference(@"MCLATouchLayoutSizes")];
    [self applyTouchLayout];
    [self.view layoutIfNeeded];
    if (pinch.state == UIGestureRecognizerStateEnded ||
        pinch.state == UIGestureRecognizerStateCancelled)
        [NSUserDefaults.standardUserDefaults synchronize];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self applyTouchLayout];
    if (self.runtimeStartPending && self.view.bounds.size.width > self.view.bounds.size.height) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self startRuntimeAfterOrientation]; });
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
#if TARGET_OS_SIMULATOR
    static BOOL graphicsPreviewPresented = NO;
    if (!graphicsPreviewPresented &&
        [NSProcessInfo.processInfo.environment[@"MCLA_GRAPHICS_MENU_PREVIEW"] boolValue]) {
        graphicsPreviewPresented = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ [self showGraphicsOptions:nil]; });
    }
#endif
    if ([NSProcessInfo.processInfo.environment[@"MCLA_LAUNCHER_PORTRAIT"] boolValue] && !self.launchRequested) {
        [self.view.window.windowScene requestGeometryUpdateWithPreferences:
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait]
            errorHandler:^(NSError* error) { if (mcla::DiagnosticsEnabled()) NSLog(@"Launcher portrait capture: %@", error); }];
    }
}

- (void)dragTouchControl:(UIPanGestureRecognizer*)pan {
    if (!self.editingTouchLayout) return;
    UIView* control = pan.view;
    NSString* key = [control.accessibilityIdentifier
        stringByReplacingOccurrencesOfString:@"mcla.touch." withString:@""];
    if (!self.layoutControls[key]) return;
    CGPoint delta = [pan translationInView:self.view];
    [pan setTranslation:CGPointZero inView:self.view];
    CGRect safe = [self touchSafeRect];
    if (safe.size.width <= 0 || safe.size.height <= 0) return;
    CGPoint center = control.center;
    const CGFloat insetX = control.bounds.size.width * 0.5 + 4;
    const CGFloat insetY = control.bounds.size.height * 0.5 + 4;
    center.x = fmax(CGRectGetMinX(safe) + insetX,
                    fmin(CGRectGetMaxX(safe) - insetX, center.x + delta.x));
    center.y = fmax(CGRectGetMinY(safe) + insetY,
                    fmin(CGRectGetMaxY(safe) - insetY, center.y + delta.y));
    NSMutableDictionary* positions = [[NSUserDefaults.standardUserDefaults
        dictionaryForKey:MCLATouchPreference(@"MCLATouchLayoutPositions")] mutableCopy] ?: [NSMutableDictionary dictionary];
    positions[key] = @[@((center.x - CGRectGetMinX(safe)) / safe.size.width),
                       @((center.y - CGRectGetMinY(safe)) / safe.size.height)];
    [NSUserDefaults.standardUserDefaults setObject:positions forKey:MCLATouchPreference(@"MCLATouchLayoutPositions")];
    [self applyTouchLayout];
    [self.view layoutIfNeeded];
    if (pan.state == UIGestureRecognizerStateEnded ||
        pan.state == UIGestureRecognizerStateCancelled)
        [NSUserDefaults.standardUserDefaults synchronize];
}

- (void)toggleTouchLayoutEditing:(id)sender {
    (void)sender;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"MCLATouchEnabledControlOverhaulTest"]) {
        [self showControlsOptions:nil];
        return;
    }
    self.editingTouchLayout = !self.editingTouchLayout;
    if (self.editingTouchLayout) { MCLAResetVirtualGamepad();
        self.overhaulGasHeld=NO; self.overhaulHandbrakeHeld=NO; }
    for (UIView* control in self.layoutControls.allValues) {
        for (UIGestureRecognizer* recognizer in control.gestureRecognizers)
            if ([recognizer isKindOfClass:UIPanGestureRecognizer.class] ||
                [recognizer isKindOfClass:UIPinchGestureRecognizer.class])
                recognizer.enabled = self.editingTouchLayout;
        control.layer.borderColor = self.editingTouchLayout
            ? UIColor.systemCyanColor.CGColor
            : [UIColor colorWithWhite:1 alpha:0.40].CGColor;
    }
    [self.editButton setTitle:self.editingTouchLayout ? @"DONE" : @"EDIT"
                     forState:UIControlStateNormal];
    self.layoutHint.hidden = !self.editingTouchLayout;
    [self refreshBringupStatus];
}

- (void)resetTouchLayout {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:MCLATouchPreference(@"MCLATouchLayoutPositions")];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:MCLATouchPreference(@"MCLATouchLayoutSizes")];
    [NSUserDefaults.standardUserDefaults setObject:(MCLAControlOverhaulEnabled() ? MCLAOverhaulControls() : MCLADefaultTouchControls())
                                            forKey:MCLATouchPreference(@"MCLATouchActiveControls")];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self applyTouchLayout];
}

- (void)togglePerformanceOverlay:(UIButton*)sender {
    (void)sender;
    const BOOL visible = ![NSUserDefaults.standardUserDefaults
        boolForKey:@"MCLAPerformanceOverlay"];
    [NSUserDefaults.standardUserDefaults setBool:visible
                                          forKey:@"MCLAPerformanceOverlay"];
    [NSUserDefaults.standardUserDefaults synchronize];
    self.performanceGraph.hidden = !visible;
    if (visible) [self.performanceGraph setNeedsDisplay];
}

- (void)startPerformanceCapture:(UITapGestureRecognizer*)recognizer {
    if (recognizer.state != UIGestureRecognizerStateRecognized) return;
    MCLAGraphicsStartPerformanceCapture();
    [self.performanceGraph setNeedsDisplay];
}

- (UIButton*)makeTouchButton:(NSString*)title tag:(uint16_t)buttonMask {
    UIButton* button = [MCLAStaticTouchButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = buttonMask;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font =
        [UIFont systemFontOfSize:17.0 weight:UIFontWeightBlack];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.25];
    button.layer.cornerRadius = 18;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.40].CGColor;
    [button addTarget:self action:@selector(gamepadButtonDown:)
       forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(gamepadButtonUp:)
       forControlEvents:(UIControlEventTouchUpInside |
                         UIControlEventTouchUpOutside |
                         UIControlEventTouchCancel)];
    return button;
}

- (void)gamepadButtonDown:(UIButton*)sender {
    if (self.editingTouchLayout) return;
    MCLASetVirtualGamepadButton((uint16_t)sender.tag, true);
    if (MCLAControlOverhaulEnabled() && [sender.accessibilityIdentifier isEqual:@"mcla.touch.handbrake"]) {
        self.overhaulHandbrakeHeld=YES;
        MCLASetVirtualGamepadTrigger(true, true);
    }
}

- (void)gamepadButtonUp:(UIButton*)sender {
    MCLASetVirtualGamepadButton((uint16_t)sender.tag, false);
    if (MCLAControlOverhaulEnabled() && [sender.accessibilityIdentifier isEqual:@"mcla.touch.handbrake"]) {
        self.overhaulHandbrakeHeld=NO;
        MCLASetVirtualGamepadTrigger(true, self.overhaulGasHeld);
    }
}

- (void)pedalDown:(UIButton*)sender {
    if (self.editingTouchLayout) return;
    if (sender.tag == 2) self.overhaulGasHeld=YES;
    MCLASetVirtualGamepadTrigger(sender.tag == 2, true);
}

- (void)pedalUp:(UIButton*)sender {
    if (sender.tag == 2) self.overhaulGasHeld=NO;
    BOOL combinedHeld=MCLAControlOverhaulEnabled() && self.overhaulHandbrakeHeld;
    MCLASetVirtualGamepadTrigger(sender.tag == 2, sender.tag == 2 && combinedHeld);
}

- (void)toggleFullPad:(id)sender {
    (void)sender;
    if (self.editingTouchLayout) return;
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults boolForKey:@"MCLATouchEnabledControlOverhaulTest"]) {
        [self showControlsOptions:nil];
        return;
    }
    const BOOL show = ![defaults boolForKey:@"MCLAFullPadVisible"];
    if (show) {
        [defaults setBool:YES forKey:@"MCLAFullPadVisible"];
        [self refreshBringupStatus];
        self.fullPadPanel.alpha = 0;
        self.fullPadPanel.transform = CGAffineTransformConcat(
            CGAffineTransformMakeTranslation(0, -12),
            CGAffineTransformMakeScale(0.96, 0.96));
        [UIView animateWithDuration:0.24 delay:0
            usingSpringWithDamping:0.86 initialSpringVelocity:0.2 options:0
            animations:^{
                self.fullPadPanel.alpha = 1;
                self.fullPadPanel.transform = CGAffineTransformIdentity;
            } completion:nil];
    } else {
        [UIView animateWithDuration:0.18 animations:^{
            self.fullPadPanel.alpha = 0;
            self.fullPadPanel.transform = CGAffineTransformMakeTranslation(0, -8);
        } completion:^(BOOL finished) {
            (void)finished;
            self.fullPadPanel.transform = CGAffineTransformIdentity;
            self.fullPadPanel.alpha = 1;
            [defaults setBool:NO forKey:@"MCLAFullPadVisible"];
            [self refreshBringupStatus];
        }];
    }
}

- (void)showControlsOptions:(id)sender {
    (void)sender;
    MCLAControlsOptionsController* options = [[MCLAControlsOptionsController alloc] init];
    __weak MCLAViewController* weakSelf = self;
    options.onChange = ^{ [weakSelf refreshBringupStatus]; };
    options.onCalibrate = ^{ [weakSelf calibrateTilt]; };
    options.onResetLayout = ^{ [weakSelf resetTouchLayout]; };
    UINavigationController* navigation = [[UINavigationController alloc]
        initWithRootViewController:options];
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    navigation.view.tintColor = [UIColor colorWithRed:1 green:.67 blue:.31 alpha:1];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)calibrateTilt {
    CMDeviceMotion* motion = self.motionManager.deviceMotion;
    self.tiltNeutral = motion ? motion.gravity.y : 0.0;
    self.tiltNeutralValid = (motion != nil);
    self.tiltFiltered = 0.0f;
    MCLASetVirtualGamepadTilt(0.0f, self.motionManager.deviceMotionActive);
}

- (void)refreshTouchInputForGameVisible:(BOOL)gameVisible {
    if (self.overhaulWasEnabled != MCLAControlOverhaulEnabled()) {
        MCLAResetVirtualGamepad();
        self.overhaulGasHeld=NO; self.overhaulHandbrakeHeld=NO;
        self.overhaulWasEnabled=MCLAControlOverhaulEnabled();
    }

    MCLAGraphicsSetVisualExperiments(7u | (MCLAControlOverhaulEnabled() ? 8u : 0u));
    [self applyTouchLayout];
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    const BOOL active = gameVisible &&
        [defaults boolForKey:@"MCLATouchEnabledControlOverhaulTest"] &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    if (!active && self.touchInputActive) {
        MCLAResetVirtualGamepad();
        self.overhaulGasHeld=NO; self.overhaulHandbrakeHeld=NO;
    }
    if (!active && self.editingTouchLayout) {
        self.editingTouchLayout = NO;
        [self.editButton setTitle:@"EDIT" forState:UIControlStateNormal];
        self.layoutHint.hidden = YES;
        for (UIView* control in self.layoutControls.allValues) {
            for (UIGestureRecognizer* recognizer in control.gestureRecognizers)
                if ([recognizer isKindOfClass:UIPanGestureRecognizer.class] ||
                    [recognizer isKindOfClass:UIPinchGestureRecognizer.class])
                    recognizer.enabled = NO;
            control.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.40].CGColor;
        }
    }
    self.touchInputActive = active;
    const BOOL full = active && !self.editingTouchLayout &&
        [defaults boolForKey:@"MCLAFullPadVisible"];
    // Tilt is a complete replacement for driving-stick steering. Keep the
    // redundant stick out of gameplay and layout editing whenever the option
    // is enabled, while leaving pedals, actions and the optional full pad.
    const BOOL tiltConfigured = active &&
        [defaults boolForKey:@"MCLATiltEnabled"];
    self.steeringStick.hidden = !active || tiltConfigured;
    self.steeringStick.userInteractionEnabled = active && !tiltConfigured;
    if (tiltConfigured) MCLASetVirtualGamepadLeftStick(0.0f, 0.0f, false);
    for (UIButton* pedal in self.pedals) pedal.hidden = !active;
    [self.drivingActions enumerateObjectsUsingBlock:
        ^(UIButton* action, NSUInteger index, BOOL* stop) {
            (void)stop;
            action.hidden = !active ||
                ![self isTouchControlDeployed:self.drivingActionKeys[index]];
        }];
    [self.paletteButtons enumerateKeysAndObjectsUsingBlock:
        ^(NSString* key, UIButton* button, BOOL* stop) {
            (void)stop;
            button.alpha = [self isTouchControlDeployed:key] ? 0.42 : 1.0;
        }];
    self.fullPadPanel.hidden = !full;
    self.cameraStick.userInteractionEnabled = full;

    const BOOL useTilt = tiltConfigured && !self.editingTouchLayout &&
                         self.motionManager.isDeviceMotionAvailable;
    self.steeringStick.caption.text = @"STEER · LEFT STICK";
    if (useTilt && !self.motionManager.deviceMotionActive) {
        self.tiltNeutralValid = NO;
        __weak MCLAViewController* weakSelf = self;
        [self.motionManager startDeviceMotionUpdatesToQueue:NSOperationQueue.mainQueue
            withHandler:^(CMDeviceMotion* motion, NSError* error) {
                MCLAViewController* strongSelf = weakSelf;
                if (!strongSelf || error || !motion || !strongSelf.touchInputActive) return;
                if (!strongSelf.tiltNeutralValid) {
                    strongSelf.tiltNeutral = motion.gravity.y;
                    strongSelf.tiltNeutralValid = YES;
                }
                float direction = (float)((motion.gravity.y - strongSelf.tiltNeutral) * 2.6);
                if (strongSelf.view.window.windowScene.interfaceOrientation ==
                    UIInterfaceOrientationLandscapeRight) direction = -direction;
                if ([NSUserDefaults.standardUserDefaults boolForKey:@"MCLATiltInvert"])
                    direction = -direction;
                direction = fmaxf(-1.0f, fminf(1.0f, direction));
                if (fabsf(direction) < 0.05f) direction = 0.0f;
                strongSelf.tiltFiltered = 0.72f * strongSelf.tiltFiltered + 0.28f * direction;
                MCLASetVirtualGamepadTilt(strongSelf.tiltFiltered, true);
            }];
    } else if (!useTilt && self.motionManager.deviceMotionActive) {
        [self.motionManager stopDeviceMotionUpdates];
        self.tiltNeutralValid = NO;
        self.tiltFiltered = 0.0f;
        MCLASetVirtualGamepadTilt(0.0f, false);
    }
}

- (void)appWillResignActive:(NSNotification*)notification {
    (void)notification;
    MCLAGraphicsSetApplicationActive(false);
}

- (void)appDidEnterBackground:(NSNotification*)notification {
    (void)notification;
    MCLAGraphicsSetApplicationActive(false);
    MCLAGraphicsFinishPerformanceCapture();
    [self.motionManager stopDeviceMotionUpdates];
    self.touchInputActive = NO;
    MCLAResetVirtualGamepad();
    [self hideGameplayToolbar];
    [self.panel setSceneActive:NO];
}

- (void)appDidBecomeActive:(NSNotification*)notification {
    (void)notification;
    MCLAGraphicsSetApplicationActive(true);
    [self refreshBringupStatus];
}

- (void)pulseVirtualButton:(uint16_t)buttonMask duration:(NSTimeInterval)duration {
    MCLASetVirtualGamepadButton(buttonMask, true);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        MCLASetVirtualGamepadButton(buttonMask, false);
    });
}

- (void)dealloc {
    [self.statusTimer invalidate];
    [self.launcherInputTimer invalidate];
    [self.toolbarTimer invalidate];
    [self.motionManager stopDeviceMotionUpdates];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    MCLAResetVirtualGamepad();
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}

- (void)refreshBringupStatus {
    if (!self.gameRoot) [self prepareGameDataFolderIfNeeded];

    MCLADataReport report = {};
    MCLAHostInspectGameData(self.gameRoot.fileSystemRepresentation, &report);
    MCLAGraphicsReport graphics = {};
    MCLAGraphicsGetReport(&graphics);
    MCLARuntimeReport runtime = {};
    MCLAHostGetRuntimeReport(&runtime);
    const uint32_t selectedHeight = mcla::metal::RenderHeight((uint32_t)
        [NSUserDefaults.standardUserDefaults integerForKey:@"MCLARenderHeight"]);
    [self.panel setGraphicsSummary:[NSString stringWithFormat:@"%up SCENE   /   FSR %@   /   METAL",
        selectedHeight, [NSUserDefaults.standardUserDefaults boolForKey:@"MCLAFSREnabled"] ? @"On" : @"Off"]
    ];

    // A controller-driven title still looks idle to UIKit. Keep only an
    // actively running foreground game awake; never change the user's global
    // Auto-Lock setting or prevent an explicit lock/background transition.
    UIApplication.sharedApplication.idleTimerDisabled =
        runtime.running && !runtime.failed && !runtime.finished &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive;

    if (runtime.failed) {
        self.statusLabel.text = @"LAUNCH STOPPED";
        self.statusLabel.textColor = UIColor.systemRedColor;
    } else if (runtime.entryReached) {
        self.statusLabel.text = @"ENTERING LOS ANGELES";
        self.statusLabel.textColor = UIColor.systemGreenColor;
    } else if (runtime.running) {
        self.statusLabel.text = @"LAUNCHING MCLA…";
        self.statusLabel.textColor = UIColor.systemYellowColor;
    } else if (!self.metalView.isMetalReady) {
        self.statusLabel.text = @"METAL UNAVAILABLE";
        self.statusLabel.textColor = UIColor.systemRedColor;
    } else if (report.ready) {
        self.statusLabel.text = @"●  READY TO DRIVE";
        self.statusLabel.textColor = UIColor.systemGreenColor;
    } else {
        self.statusLabel.text = @"WAITING FOR GAME DATA";
        self.statusLabel.textColor = UIColor.systemOrangeColor;
    }

    self.panel.launchReady = report.ready && runtime.available &&
                                !runtime.running && !runtime.finished && !self.launchRequested;
    [self.panel setLaunching:runtime.running || self.launchRequested];
    // Once the title itself is driving Metal frames, reveal the full render
    // surface. The telemetry remains available in the persistent runtime log.
    const BOOL gameVisible = runtime.entryReached && graphics.titleDrivenFrames > 0 &&
                             !runtime.failed && !runtime.finished;
    self.gameVisible = gameVisible;
    self.panel.hidden = gameVisible;
    self.touchControls.hidden = !gameVisible || !self.toolbarVisible;
    [self.panel setSceneActive:!gameVisible && !self.launchRequested && !runtime.running &&
        !self.presentedViewController &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive];
    if (gameVisible && !self.sceneReleased) {
        [self.panel releaseScene];
        self.sceneReleased = YES;
        [self.launcherInputTimer invalidate];
        self.launcherInputTimer = nil;
    }
    [self refreshTouchInputForGameVisible:gameVisible];
    self.performanceGraph.hidden = !(mcla::DiagnosticsEnabled() && gameVisible &&
        [NSUserDefaults.standardUserDefaults boolForKey:@"MCLAPerformanceOverlay"]);
    if (!self.performanceGraph.hidden)
        [self.performanceGraph setNeedsDisplay];

    // The controlled device test can activate the title screen without UI
    // automation. Frame 680 is after the loading/logo sequence on the verified
    // Complete Edition build; normal launches always wait for an explicit
    // touch or physical-controller press.
    const BOOL autoContinue =
        [NSProcessInfo.processInfo.environment[@"MCLA_AUTOCONTINUE"] boolValue];
    const BOOL autoCreateSave =
        [NSProcessInfo.processInfo.environment[@"MCLA_AUTOCREATE_SAVE"] boolValue];
    if (autoContinue && !self.autoContinueSent &&
        graphics.titleDrivenFrames >= 680) {
        self.autoContinueSent = YES;
        [self pulseVirtualButton:MCLA_GAMEPAD_START duration:1.0];
        // Some Rockstar shells consume the title action as an XInput
        // keystroke rather than as a held gamepad bit. If Start alone doesn't
        // advance the shell, follow it with A after the complete down/up pair
        // has been available to both APIs. This also selects the default item
        // if Start already opened the first menu.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!self.autoContinueFallbackSent) {
                self.autoContinueFallbackSent = YES;
                [self pulseVirtualButton:MCLA_GAMEPAD_A duration:0.5];
                // Diagnostic launches may also select the highlighted
                // "Create a new save game" action. Keep this behind its own
                // environment switch so normal launches never manufacture
                // gameplay input or overwrite a user's menu choice.
                if (autoCreateSave) {
                    dispatch_after(
                        dispatch_time(DISPATCH_TIME_NOW,
                                      (int64_t)(15.0 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
                            if (!self.autoSaveConfirmSent) {
                                self.autoSaveConfirmSent = YES;
                                [self pulseVirtualButton:MCLA_GAMEPAD_A
                                               duration:0.5];
                                // MCLA follows the new-save choice with its
                                // autosave warning. Confirm that separately so
                                // the diagnostic reaches the storage-device
                                // selector and actual package operation.
                                dispatch_after(
                                    dispatch_time(
                                        DISPATCH_TIME_NOW,
                                        (int64_t)(10.0 * NSEC_PER_SEC)),
                                    dispatch_get_main_queue(), ^{
                                        if (!self.autoSaveWarningConfirmSent) {
                                            self.autoSaveWarningConfirmSent = YES;
                                            [self pulseVirtualButton:
                                                      MCLA_GAMEPAD_A
                                                           duration:0.5];
                                        }
                                    });
                            }
                        });
                }
            }
        });
    }
    self.detailLabel.text = self.launchError ?: (runtime.failed
        ? [NSString stringWithFormat:@"Please reopen MCLA. %s", runtime.detail]
        : runtime.finished ? @"This session has ended. Reopen MCLA to drive again."
        : !report.ready ? @"Copy your extracted game into Files → MCLA → MCLA_Game_Files."
        : self.launchRequested || runtime.running ? @"Your garage is warming up." : @"");
}

- (void)launchMCLA:(id)sender {
    (void)sender;
    if (self.launchRequested) return;
    MCLARuntimeReport runtime = {}; MCLAHostGetRuntimeReport(&runtime);
    if (runtime.running || runtime.finished) return;
    self.launchError = nil;
    self.launchRequested = YES;
    self.runtimeStartPending = YES;
    [self.panel setLaunching:YES];
    [self.panel setSceneActive:NO];
    [self setNeedsUpdateOfSupportedInterfaceOrientations];
    UIWindowScene* scene = self.view.window.windowScene;
    if (self.view.bounds.size.width > self.view.bounds.size.height) {
        [self startRuntimeAfterOrientation];
    } else {
        [scene requestGeometryUpdateWithPreferences:
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape]
            errorHandler:^(NSError* error) {
                if (mcla::DiagnosticsEnabled()) NSLog(@"MCLA launcher landscape request: %@", error.localizedDescription);
            }];
        __weak MCLAViewController* weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            MCLAViewController* owner = weakSelf;
            if (!owner.runtimeStartPending) return;
            if (owner.view.bounds.size.width > owner.view.bounds.size.height) {
                [owner startRuntimeAfterOrientation];
            } else {
                owner.runtimeStartPending = NO; owner.launchRequested = NO;
                owner.launchError = @"Rotate to landscape, then tap Enter Los Angeles.";
                [owner setNeedsUpdateOfSupportedInterfaceOrientations];
                [owner refreshBringupStatus];
            }
        });
    }
}

- (void)startRuntimeAfterOrientation {
    if (!self.runtimeStartPending) return;
    self.runtimeStartPending = NO;
    if (!self.gameRoot) {
        self.launchRequested = NO;
        return;
    }
    char message[256] = {};
    // Settings are immutable for a title session. Never resize guest targets
    // or replace sampling policy in the middle of an in-flight frame.
    NSDictionary* environment = NSProcessInfo.processInfo.environment;
    NSString* heightOverride = environment[@"MCLA_RENDER_HEIGHT"];
    NSString* fsrOverride = environment[@"MCLA_FSR_ENABLED"];
    const NSInteger height = heightOverride ? heightOverride.integerValue :
        [NSUserDefaults.standardUserDefaults integerForKey:@"MCLARenderHeight"];
    BOOL fsr = [NSUserDefaults.standardUserDefaults boolForKey:@"MCLAFSREnabled"];
    if (environment[@"MCLA_OUTPUT_MODE"]) fsr = [environment[@"MCLA_OUTPUT_MODE"] integerValue] != 0;
    if (fsrOverride) fsr = fsrOverride.boolValue;
    CGSize nativePixels = UIScreen.mainScreen.nativeBounds.size;
    BOOL nativeAspect = YES;
    if (NSString* aspectOverride = environment[@"MCLA_NATIVE_ASPECT"])
        nativeAspect = aspectOverride.boolValue;
    MCLAGraphicsConfigureNativeAspect(
        (uint32_t)MAX(nativePixels.width, nativePixels.height),
        (uint32_t)MIN(nativePixels.width, nativePixels.height), nativeAspect);
    MCLAGraphicsConfigureOutput((uint32_t)height, fsr);
    MCLAGraphicsSetMotionBlurDisabled([NSUserDefaults.standardUserDefaults boolForKey:@"MCLADisableMotionBlur"]);
    MCLAGraphicsSetDepthOfFieldDisabled([NSUserDefaults.standardUserDefaults boolForKey:@"MCLADisableDepthOfField"]);
    MCLAGraphicsSetExperimental60FPS([NSUserDefaults.standardUserDefaults boolForKey:@"MCLAExperimental60FPS"]);
    // Rendering correctness fixes are automatic, independent of saved legacy switches.
    MCLAGraphicsSetVisualExperiments(7u | (MCLAControlOverhaulEnabled() ? 8u : 0u));
    [self.metalView setNeedsLayout];
    [self.metalView layoutIfNeeded];
    if (!MCLAHostStartRuntime(self.gameRoot.fileSystemRepresentation,
                              message, sizeof(message))) {
        self.launchRequested = NO;
        self.launchError = [NSString stringWithUTF8String:message];
        [self setNeedsUpdateOfSupportedInterfaceOrientations];
        self.statusLabel.text = @"LAUNCH NOT STARTED";
        self.statusLabel.textColor = UIColor.systemRedColor;
        self.detailLabel.text = [NSString stringWithUTF8String:message];
    }
    [self refreshBringupStatus];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.launchRequested || self.gameVisible ? UIInterfaceOrientationMaskLandscape
        : UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)recognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)other {
    (void)recognizer; (void)other; return YES;
}

- (void)revealGameplayToolbar:(UITapGestureRecognizer*)recognizer {
    if (recognizer.state != UIGestureRecognizerStateRecognized || !self.gameVisible) return;
    self.toolbarVisible = YES;
    self.touchControls.hidden = NO;
    [self.toolbarTimer invalidate];
    __weak MCLAViewController* weakSelf = self;
    self.toolbarTimer = [NSTimer scheduledTimerWithTimeInterval:10 repeats:NO
        block:^(NSTimer* timer) { (void)timer; [weakSelf hideGameplayToolbar]; }];
    // Run in common modes so dragging a control cannot keep the toolbar alive.
    [NSRunLoop.mainRunLoop addTimer:self.toolbarTimer forMode:NSRunLoopCommonModes];
}

- (void)hideGameplayToolbar {
    [self.toolbarTimer invalidate]; self.toolbarTimer = nil;
    self.toolbarVisible = NO; self.touchControls.hidden = YES;
    MCLASetVirtualGamepadButton(MCLA_GAMEPAD_START, false);
    MCLASetVirtualGamepadButton(MCLA_GAMEPAD_A, false);
}

// Read the same controller snapshots as the game, without replacing the
// runtime's handlers. This timer exists only while the launcher is visible.
- (void)pollLauncherController {
    if (self.gameVisible || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    GCController* controller = GCController.current ?: GCController.controllers.firstObject;
    [self.panel setControllerConnected:controller != nil];
    GCExtendedGamepad* pad = controller.extendedGamepad;
    GCMicroGamepad* micro = controller.microGamepad;
    float x = pad ? pad.dpad.xAxis.value : micro.dpad.xAxis.value;
    float y = pad ? pad.dpad.yAxis.value : micro.dpad.yAxis.value;
    if (pad && fabsf(x)<.5 && fabsf(y)<.5) {
        x = pad.leftThumbstick.xAxis.value; y = pad.leftThumbstick.yAxis.value;
    }
    NSInteger direction = fabsf(y)>.55 ? (y>0 ? -1 : 1) : fabsf(x)>.55 ? (x>0 ? 1 : -1) : 0;
    BOOL confirm = pad ? pad.buttonA.pressed : micro.buttonA.pressed;
    BOOL back = pad ? pad.buttonB.pressed : micro.buttonX.pressed;
    if (!self.controllerSampled) {
        self.controllerSampled = YES;
        self.controllerConfirmDown = confirm; self.controllerBackDown = back;
    }
    BOOL pressedA = confirm && !self.controllerConfirmDown;
    BOOL pressedB = back && !self.controllerBackDown;
    self.controllerConfirmDown = confirm; self.controllerBackDown = back;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL move = direction && (direction != self.controllerDirection || now >= self.nextControllerRepeat);
    if (move) self.nextControllerRepeat = now + (direction != self.controllerDirection ? .38 : .16);
    self.controllerDirection = direction;
    if (!controller || self.launchRequested) return;
    UIViewController* modal = self.presentedViewController;
    if (!modal) {
        self.controllerSettingsRow = nil; self.controllerSettingsPage = nil;
        [self.panel adjustCameraWithX:pad.rightThumbstick.xAxis.value y:pad.rightThumbstick.yAxis.value];
        if (move) [self.panel moveSelection:direction];
        if (pressedA) [self.panel activateSelection];
        return;
    }
    if ([modal isKindOfClass:UINavigationController.class]) {
        UIViewController* visible = ((UINavigationController*)modal).topViewController;
        if (visible.presentedViewController) {
            UIAlertController* alert = [visible.presentedViewController isKindOfClass:UIAlertController.class]
                ? (UIAlertController*)visible.presentedViewController : nil;
            if ([visible isKindOfClass:MCLAControlsOptionsController.class] &&
                [alert.title isEqualToString:@"Reset touch layout?"] && alert.actions.count == 2) {
                if (move) alert.preferredAction = alert.preferredAction == alert.actions.firstObject
                    ? alert.actions.lastObject : alert.actions.firstObject;
                if (pressedA || pressedB) {
                    BOOL reset = pressedA && alert.preferredAction == alert.actions.lastObject;
                    [visible dismissViewControllerAnimated:YES completion:^{
                        MCLAControlsOptionsController* options = (MCLAControlsOptionsController*)visible;
                        if (reset && options.onResetLayout) options.onResetLayout();
                    }];
                }
            } else if (alert == self.pendingSaveAlert && alert.actions.count == 2) {
                if (move) alert.preferredAction = alert.preferredAction == alert.actions.firstObject
                    ? alert.actions.lastObject : alert.actions.firstObject;
                if (pressedA || pressedB) {
                    BOOL accepted = pressedA && alert.preferredAction == alert.actions.lastObject;
                    [visible dismissViewControllerAnimated:YES completion:^{
                        [self finishSaveConfirmation:accepted];
                    }];
                }
            } else if (pressedB) [visible dismissViewControllerAnimated:YES completion:nil];
            return;
        }
        if (pressedB) {
            if (visible.navigationController.viewControllers.count > 1)
                [visible.navigationController popViewControllerAnimated:YES];
            else [self dismissViewControllerAnimated:YES completion:nil];
            return;
        }
        if (![visible isKindOfClass:UITableViewController.class]) return;
        UITableViewController* page = (UITableViewController*)visible;
        UITableView* table = page.tableView;
        NSMutableArray<NSIndexPath*>* rows = [NSMutableArray array];
        for (NSInteger s=0;s<table.numberOfSections;++s)
            for (NSInteger r=0;r<[table numberOfRowsInSection:s];++r)
                [rows addObject:[NSIndexPath indexPathForRow:r inSection:s]];
        if (!rows.count) return;
        if (page != self.controllerSettingsPage) {
            self.controllerSettingsPage = page; self.controllerSettingsRow = rows.firstObject;
        }
        NSUInteger index = [rows indexOfObject:self.controllerSettingsRow];
        if (index == NSNotFound) index = 0;
        if (move) index = (index + rows.count + direction) % rows.count;
        self.controllerSettingsRow = rows[index];
        if (move || !table.indexPathForSelectedRow) {
            [table scrollToRowAtIndexPath:self.controllerSettingsRow atScrollPosition:UITableViewScrollPositionNone animated:NO];
            [table layoutIfNeeded];
            UITableViewCell* cell = [table cellForRowAtIndexPath:self.controllerSettingsRow];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            UIView* focus = [[UIView alloc] init];
            focus.backgroundColor = [UIColor colorWithRed:1 green:.67 blue:.31 alpha:.24];
            cell.selectedBackgroundView = focus;
            [table selectRowAtIndexPath:self.controllerSettingsRow animated:NO scrollPosition:UITableViewScrollPositionNone];
        }
        if (pressedA) {
            UITableViewCell* cell = [table cellForRowAtIndexPath:self.controllerSettingsRow];
            if ([cell.accessoryView isKindOfClass:UISwitch.class]) {
                UISwitch* toggle = (UISwitch*)cell.accessoryView;
                if (toggle.enabled) {
                    [toggle setOn:!toggle.on animated:YES];
                    [toggle sendActionsForControlEvents:UIControlEventValueChanged];
                }
            } else if ([table.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
                [table.delegate tableView:table didSelectRowAtIndexPath:self.controllerSettingsRow];
            }
        }
    } else if (pressedB) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (NSURL*)saveDirectoryURL {
    NSString* support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
        NSUserDomainMask, YES).firstObject;
    return [[[NSURL fileURLWithPath:support isDirectory:YES]
        URLByAppendingPathComponent:@"MCLA" isDirectory:YES]
        URLByAppendingPathComponent:@"saves" isDirectory:YES];
}

- (UIViewController*)savePresenter {
    return self.presentedViewController ?: self;
}

- (void)refreshSaveCount {
    self.savesOptionsPage.saveFileCount =
        [MCLASaveArchive fileCountAtDirectory:[self saveDirectoryURL]];
    [self.savesOptionsPage.tableView reloadData];
}

- (void)showSaveMessage:(NSString*)title detail:(NSString*)detail {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
        message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault handler:nil]];
    [[self savePresenter] presentViewController:alert animated:YES completion:nil];
}

- (void)finishSaveConfirmation:(BOOL)confirmed {
    dispatch_block_t action = confirmed ? self.pendingSaveConfirm : self.pendingSaveCancel;
    self.pendingSaveAlert = nil;
    self.pendingSaveConfirm = nil;
    self.pendingSaveCancel = nil;
    if (action) action();
}

- (void)confirmSaveAction:(NSString*)title detail:(NSString*)detail
              actionTitle:(NSString*)actionTitle destructive:(BOOL)destructive
                confirm:(dispatch_block_t)confirm cancel:(dispatch_block_t)cancel {
    if (self.pendingSaveAlert) return;
    self.pendingSaveConfirm = confirm;
    self.pendingSaveCancel = cancel;
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
        message:detail preferredStyle:UIAlertControllerStyleAlert];
    __weak MCLAViewController* weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:^(UIAlertAction* action) {
            (void)action; [weakSelf finishSaveConfirmation:NO];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle
        style:destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
        handler:^(UIAlertAction* action) {
            (void)action; [weakSelf finishSaveConfirmation:YES];
        }]];
    alert.preferredAction = alert.actions.firstObject;
    self.pendingSaveAlert = alert;
    [[self savePresenter] presentViewController:alert animated:YES completion:nil];
}

- (void)showSaveOptions:(UIButton*)sender {
    (void)sender;
    if (self.launchRequested || self.gameVisible || self.presentedViewController) return;
    MCLASavesOptionsController* options = [[MCLASavesOptionsController alloc] init];
    self.savesOptionsPage = options;
    options.saveFileCount = [MCLASaveArchive fileCountAtDirectory:[self saveDirectoryURL]];
    __weak MCLAViewController* weakSelf = self;
    options.onExport = ^{ [weakSelf exportSaves]; };
    options.onImport = ^{ [weakSelf importSaves]; };
    options.onDelete = ^{ [weakSelf deleteSaves]; };
    UINavigationController* navigation = [[UINavigationController alloc]
        initWithRootViewController:options];
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    navigation.view.tintColor = [UIColor colorWithRed:1 green:.67 blue:.31 alpha:1];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    navigation.preferredContentSize = CGSizeMake(570, 550);
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)exportSaves {
    if (self.launchRequested || self.gameVisible) return;
    NSURL* saves = [self saveDirectoryURL];
    NSURL* archive = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"MCLA-Saves-%@.mclasave",
                                     NSUUID.UUID.UUIDString]];
    __weak MCLAViewController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError* error = nil;
        BOOL succeeded = [MCLASaveArchive exportDirectory:saves toURL:archive error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            MCLAViewController* owner = weakSelf;
            if (!owner || owner.launchRequested || owner.gameVisible) {
                [NSFileManager.defaultManager removeItemAtURL:archive error:nil]; return;
            }
            if (!succeeded) {
                [owner showSaveMessage:@"Export failed" detail:error.localizedDescription];
                return;
            }
            owner.saveExportURL = archive;
            owner.importingSaveArchive = NO;
            UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
                initForExportingURLs:@[archive] asCopy:YES];
            picker.delegate = owner;
            [[owner savePresenter] presentViewController:picker animated:YES completion:nil];
        });
    });
}

- (void)importSaves {
    if (self.launchRequested || self.gameVisible) return;
    self.importingSaveArchive = YES;
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    [[self savePresenter] presentViewController:picker animated:YES completion:nil];
}

- (void)deleteSaves {
    if (self.launchRequested || self.gameVisible) return;
    __weak MCLAViewController* weakSelf = self;
    [self confirmSaveAction:@"Delete all MCLA saves?"
        detail:@"This removes every profile and autosave from this device. Export a backup first if you may need them."
        actionTitle:@"Delete saves" destructive:YES confirm:^{
            MCLAViewController* owner = weakSelf;
            if (!owner) return;
            NSError* error = nil;
            BOOL succeeded = [MCLASaveArchive deleteDirectory:[owner saveDirectoryURL] error:&error];
            [owner refreshSaveCount];
            [owner showSaveMessage:succeeded ? @"Saves deleted" : @"Delete failed"
                              detail:succeeded ? @"MCLA will create new saves when you play."
                                               : error.localizedDescription];
        } cancel:nil];
}

- (void)cleanupSaveExport {
    if (self.saveExportURL)
        [NSFileManager.defaultManager removeItemAtURL:self.saveExportURL error:nil];
    self.saveExportURL = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller {
    (void)controller;
    self.importingSaveArchive = NO;
    [self cleanupSaveExport];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    if (!self.importingSaveArchive) {
        [self cleanupSaveExport];
        return;
    }
    self.importingSaveArchive = NO;
    NSURL* archive = urls.firstObject;
    if (!archive) return;
    if (![[archive.pathExtension lowercaseString] isEqualToString:@"mclasave"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showSaveMessage:@"Unsupported file"
                           detail:@"Choose an MCLA .mclasave backup."];
        });
        return;
    }
    NSURL* saves = [self saveDirectoryURL];
    NSURL* stage = [[saves URLByDeletingLastPathComponent]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"saves-import-%@",
                                     NSUUID.UUID.UUIDString] isDirectory:YES];
    __weak MCLAViewController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        BOOL scoped = [archive startAccessingSecurityScopedResource];
        NSError* error = nil;
        BOOL valid = [MCLASaveArchive stageArchive:archive atDirectory:stage error:&error];
        if (scoped) [archive stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            MCLAViewController* owner = weakSelf;
            if (!owner || owner.launchRequested || owner.gameVisible) {
                [NSFileManager.defaultManager removeItemAtURL:stage error:nil]; return;
            }
            if (!valid) {
                [owner showSaveMessage:@"Import failed" detail:error.localizedDescription];
                return;
            }
            NSUInteger current = [MCLASaveArchive fileCountAtDirectory:saves];
            NSString* detail = current
                ? [NSString stringWithFormat:@"Replace %lu existing save files with this backup? This cannot be undone.",
                     (unsigned long)current]
                : @"Import this backup as the current MCLA saves?";
            [owner confirmSaveAction:current ? @"Replace current saves?" : @"Import saves?"
                detail:detail actionTitle:@"Import saves" destructive:current > 0
                confirm:^{
                    NSError* replaceError = nil;
                    BOOL installed = [MCLASaveArchive replaceDirectory:saves
                        withStagedDirectory:stage error:&replaceError];
                    if (!installed) [NSFileManager.defaultManager removeItemAtURL:stage error:nil];
                    [owner refreshSaveCount];
                    [owner showSaveMessage:installed ? @"Saves imported" : @"Import failed"
                                      detail:installed ? @"Your backup is ready for MCLA."
                                                       : replaceError.localizedDescription];
                }
                cancel:^{ [NSFileManager.defaultManager removeItemAtURL:stage error:nil]; }];
        });
    });
    (void)controller;
}

- (void)showGraphicsOptions:(UIButton*)sender {
    (void)sender;
    MCLARuntimeReport runtime={};MCLAHostGetRuntimeReport(&runtime);
    MCLAGraphicsOptionsController* options = [[MCLAGraphicsOptionsController alloc]
        initWithSettingsLocked:runtime.running];
    UINavigationController* navigation = [[UINavigationController alloc]
        initWithRootViewController:options];
    navigation.navigationBar.prefersLargeTitles = YES;
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    navigation.view.tintColor = [UIColor colorWithRed:1 green:.67 blue:.31 alpha:1];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    navigation.preferredContentSize = CGSizeMake(620.0, 820.0);
    if (@available(iOS 15.0, *)) {
        navigation.sheetPresentationController.detents = @[
            UISheetPresentationControllerDetent.mediumDetent,
            UISheetPresentationControllerDetent.largeDetent,
        ];
        navigation.sheetPresentationController.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
        navigation.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [self presentViewController:navigation animated:YES completion:^{
#if TARGET_OS_SIMULATOR
        if ([NSProcessInfo.processInfo.environment[@"MCLA_GRAPHICS_MENU_PREVIEW_EXPERIMENTAL"] boolValue])
            [options.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:4]
                                    atScrollPosition:UITableViewScrollPositionTop animated:NO];
#endif
    }];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

@end
