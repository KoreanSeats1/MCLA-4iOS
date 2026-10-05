#pragma once
#import <UIKit/UIKit.h>

// One touch owner for the movable driving controls. Every finger keeps its
// own last driving combination while visiting Weight; fingers merge by OR.
@interface MCLASlidingControls : UIView
@property(nonatomic,strong) NSDictionary<NSString*,UIView*>* controls;
@property(nonatomic,copy) void (^changed)(NSUInteger);
@property(nonatomic,strong) NSMutableDictionary<NSValue*,NSNumber*>* held;
@property(nonatomic,strong) NSMutableDictionary<NSValue*,NSNumber*>* driving;
- (NSUInteger)inputsAtPoint:(CGPoint)point previous:(NSUInteger)previous;
- (void)reset;
- (void)moveFinger:(NSValue*)key toPoint:(CGPoint)point;
- (void)endFinger:(NSValue*)key;
@end
@implementation MCLASlidingControls
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor; self.multipleTouchEnabled=YES;
        self.held=[NSMutableDictionary dictionary]; self.driving=[NSMutableDictionary dictionary];
        self.accessibilityIdentifier=@"mcla.touch.slide-zones";
    } return self;
}
- (NSArray*)keys { return @[@"gas",@"handbrake",@"brake",@"weight"]; }
- (NSUInteger)maskForKey:(NSString*)key {
    return [key isEqual:@"gas"] ? 1 : [key isEqual:@"handbrake"] ? 3 : [key isEqual:@"brake"] ? 4 : 8;
}
- (BOOL)available:(NSString*)key {
    UIView* v=self.controls[key]; return v && !v.hidden && v.userInteractionEnabled;
}
- (CGRect)rect:(NSString*)key { return [self.controls[key] convertRect:self.controls[key].bounds toView:self]; }
- (CGPoint)center:(NSString*)key { CGRect r=[self rect:key]; return CGPointMake(CGRectGetMidX(r),CGRectGetMidY(r)); }
// A corridor follows the actual saved control frames. The central 40% blends
// the two end inputs; its width accommodates a thumb without stealing nearby buttons.
- (BOOL)corridor:(CGPoint)p from:(NSString*)a to:(NSString*)b fraction:(CGFloat*)fraction {
    CGPoint u=[self center:a], v=[self center:b];
    CGFloat dx=v.x-u.x,dy=v.y-u.y,length2=dx*dx+dy*dy;
    if (length2<1) return NO;
    CGFloat t=((p.x-u.x)*dx+(p.y-u.y)*dy)/length2;
    if (t<0 || t>1) return NO;
    CGFloat distance=hypot(p.x-u.x-t*dx,p.y-u.y-t*dy);
    CGFloat width=MIN(32,MIN(CGRectGetWidth([self rect:a]),CGRectGetWidth([self rect:b]))*.25);
    if (distance>width) return NO;
    if (fraction) *fraction=t;
    return YES;
}
- (NSArray*)pairs { return @[@[@"gas",@"handbrake"],@[@"gas",@"brake"],@[@"handbrake",@"brake"],@[@"gas",@"weight"],@[@"handbrake",@"weight"],@[@"brake",@"weight"]]; }
- (NSUInteger)inputsAtPoint:(CGPoint)p previous:(NSUInteger)previous {
    // Weight adds to the previous driving zone and releases immediately on exit.
    if ([self available:@"weight"] && CGRectContainsPoint([self rect:@"weight"],p)) return (previous & 7)|8;
    NSUInteger inside=0;
    for (NSString* key in @[@"gas",@"handbrake",@"brake"])
        if ([self available:key] && CGRectContainsPoint([self rect:key],p)) inside|=[self maskForKey:key];
    // The brake/drift blend also works across touching or overlapping frames.
    CGFloat t=0;
    if ([self available:@"handbrake"] && [self available:@"brake"] &&
        [self corridor:p from:@"handbrake" to:@"brake" fraction:&t] && t>=.3 && t<=.7) return 7;
    if (inside) return inside;
    for (NSArray* pair in [self pairs]) {
        NSString* a=pair[0],*b=pair[1];
        if (![self available:a] || ![self available:b] || ![self corridor:p from:a to:b fraction:&t]) continue;
        if ([b isEqual:@"weight"]) return previous & 7; // B only within its visible button.
        return t<.3 ? [self maskForKey:a] : t>.7 ? [self maskForKey:b] : [self maskForKey:a]|[self maskForKey:b];
    }
    return 0;
}
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)event {
    if (self.hidden || !self.userInteractionEnabled) return nil;
    // Let all other deployed buttons (lights, track, menus) keep their own touches.
    for (NSString* key in self.controls) {
        if ([[self keys] containsObject:key]) continue;
        UIView* v=self.controls[key];
        if (!v.hidden && CGRectContainsPoint([v convertRect:v.bounds toView:self],p)) return nil;
    }
    if ([self inputsAtPoint:p previous:0]) return self;
    for (NSArray* pair in [self pairs])
        if ([self available:pair[0]] && [self available:pair[1]] && [self corridor:p from:pair[0] to:pair[1] fraction:nil]) return self;
    return nil;
}
- (void)publish {
    NSUInteger inputs=0; for (NSNumber* mask in self.held.allValues) inputs|=mask.unsignedIntegerValue;
    for (NSString* key in [self keys]) {
        UIButton* button=(UIButton*)self.controls[key];
        button.highlighted=(inputs & ([key isEqual:@"handbrake"] ? 2 : [self maskForKey:key]))!=0;
    }
    if (self.changed) self.changed(inputs);
    [self setNeedsDisplay];
}
- (void)moveFinger:(NSValue*)key toPoint:(CGPoint)point {
    NSUInteger previous=[self.driving[key] unsignedIntegerValue];
    NSUInteger inputs=[self inputsAtPoint:point previous:previous];
    self.held[key]=@(inputs);
    if (!(inputs & 8)) self.driving[key]=@(inputs & 7);
    [self publish];
}
- (void)endFinger:(NSValue*)key {
    [self.held removeObjectForKey:key]; [self.driving removeObjectForKey:key]; [self publish];
}
- (void)track:(NSSet<UITouch*>*)touches {
    for (UITouch* touch in touches)
        [self moveFinger:[NSValue valueWithNonretainedObject:touch] toPoint:[touch locationInView:self]];
}
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event { [self track:touches]; }
- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event { [self track:touches]; }
- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event {
    for (UITouch* touch in touches) { NSValue* key=[NSValue valueWithNonretainedObject:touch]; [self.held removeObjectForKey:key]; [self.driving removeObjectForKey:key]; }
    [self publish];
}
- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event { [self touchesEnded:touches withEvent:event]; }
- (void)reset { [self.held removeAllObjects]; [self.driving removeAllObjects]; [self publish]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef c=UIGraphicsGetCurrentContext();
    // Clip the connector artwork to gaps, preserving the button icons.
    UIBezierPath* clip=[UIBezierPath bezierPathWithRect:self.bounds];
    for (NSString* key in self.controls) {
        UIView* v=self.controls[key]; if (!v.hidden) [clip appendPath:[UIBezierPath bezierPathWithRect:[v convertRect:v.bounds toView:self]]];
    }
    clip.usesEvenOddFillRule=YES; [clip addClip];
    for (NSArray* pair in [self pairs]) {
        if (![self available:pair[0]] || ![self available:pair[1]]) continue;
        CGPoint a=[self center:pair[0]], b=[self center:pair[1]];
        UIBezierPath* path=[UIBezierPath bezierPath]; [path moveToPoint:a]; [path addLineToPoint:b];
        BOOL weight=[pair[1] isEqual:@"weight"];
        [[UIColor colorWithRed:.1 green:.85 blue:1 alpha:.12] setStroke]; path.lineWidth=weight ? 20 : 32; [path stroke];
        [[UIColor colorWithRed:.5 green:.95 blue:1 alpha:.65] setStroke]; path.lineWidth=1.5;
        CGFloat dash[]={3,5}; if(weight) [path setLineDash:dash count:2 phase:0]; [path stroke];
        if ([pair[0] isEqual:@"handbrake"] && [pair[1] isEqual:@"brake"]) {
            CGPoint m=CGPointMake((a.x+b.x)/2,(a.y+b.y)/2);
            NSString* plus=@"+"; [plus drawAtPoint:CGPointMake(m.x-6,m.y-12) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:20],NSForegroundColorAttributeName:UIColor.cyanColor}];
        }
    }
    (void)c;
}
@end
