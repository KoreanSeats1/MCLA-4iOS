// UI-only export test: production controller and exporter, synthetic runtime failure.
#import "MCLAViewController.h"
#import "MCLALauncherView.h"
#include <cassert>
void MCLAControlPreviewSetRuntimeFailed(bool failed);
@interface MCLAViewController (LogExportTest)
- (void)refreshBringupStatus;
@end
@interface LogExportTestController : MCLAViewController
@property(nonatomic, assign) BOOL startedTest;
@end
@implementation LogExportTestController
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.startedTest) return;
    self.startedTest = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MCLALauncherView* launcher = [self valueForKey:@"panel"];
        [self setValue:@YES forKey:@"launchRequested"];
        [launcher setLaunching:YES];
        assert(!launcher.logsButton.enabled);
        MCLAControlPreviewSetRuntimeFailed(true);
        [self refreshBringupStatus];
        assert(![[self valueForKey:@"launchRequested"] boolValue]);
        assert(launcher.logsButton.enabled);
        assert([launcher.statusLabel.text isEqual:@"LAUNCH STOPPED"]);
        [launcher.logsButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        [self checkExport:0];
    });
}
- (void)checkExport:(NSUInteger)attempt {
    if (!self.presentedViewController && attempt < 20) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self checkExport:attempt + 1];
        });
        return;
    }
    assert([self.presentedViewController isKindOfClass:UIActivityViewController.class]);
    BOOL zipFound = NO;
    for (NSString* name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:NSTemporaryDirectory() error:nil])
        if ([name hasPrefix:@"MCLA-Logs-"] && [name hasSuffix:@".zip"]) zipFound = YES;
    assert(zipFound);
    NSLog(@"MCLA_LOG_EXPORT_UI_TEST PASS: startup failure restores Export Logs and opens ZIP share sheet");
    exit(0);
}
@end
UIViewController* MCLACreateLauncherTestController(void) { return [[LogExportTestController alloc] init]; }
