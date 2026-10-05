#import "MCLAMetalView.h"

#import "MCLAGraphicsFoundation.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

@implementation MCLAMetalView

+ (Class)layerClass {
    return CAMetalLayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }

    self.backgroundColor = UIColor.blackColor;
    CAMetalLayer* metalLayer = (CAMetalLayer*)self.layer;
    MCLAGraphicsBindMetalLayer((__bridge void*)metalLayer);
    return self;
}

- (BOOL)isMetalReady {
    MCLAGraphicsReport report = {};
    MCLAGraphicsGetReport(&report);
    return report.metalPresenterReady;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CAMetalLayer* metalLayer = (CAMetalLayer*)self.layer;
    // The 16:9 game view is letterboxed inside the iPad's UIKit viewport.
    // Its point size (even multiplied by contentScaleFactor) can be just
    // 1920x1080 on a native-resolution iPad, making FSR a 1:1 pass at 1080p.
    // Size the presenter against physical screen pixels instead; the Metal
    // layer still displays inside this view and keeps its 16:9 aspect.
    UIScreen* screen = self.window.screen ?: UIScreen.mainScreen;
    CGSize nativePixels = screen.nativeBounds.size;
    const CGFloat nativeWidth = MAX(nativePixels.width, nativePixels.height);
    const CGFloat nativeHeight = MIN(nativePixels.width, nativePixels.height);
    MCLAGraphicsResizeMetalLayer((__bridge void*)metalLayer,
                                nativeWidth > 0 ? nativeWidth : self.bounds.size.width,
                                nativeHeight > 0 ? nativeHeight : self.bounds.size.height,
                                nativeWidth > 0 ? 1.0 : self.contentScaleFactor);
    MCLAGraphicsReport report={};
    MCLAGraphicsGetReport(&report);
    if(!report.titleDrivenFrames)
        MCLAGraphicsPresentBringupFrame(0.015, 0.025, 0.055, 1.0);
}

- (void)dealloc {
    MCLAGraphicsUnbindMetalLayer((__bridge void*)self.layer);
}

@end
