#pragma once
#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>

// Attach to the screen, so the resizing finger need not land on the control.
@interface MCLAControlResizeGesture : UIGestureRecognizer
@property(nonatomic, copy) UIView* (^selectControl)(CGPoint point);
@property(nonatomic, weak, readonly) UIView* control;
@property(nonatomic, readonly) CGFloat scale;
@end

@implementation MCLAControlResizeGesture {
    UITouch* _anchor;
    UITouch* _resizer;
    __weak UIView* _control;
    CGFloat _distance;
    CGFloat _scale;
}
- (UIView*)control { return _control; }
- (CGFloat)scale { return _scale; }
- (void)reset {
    [super reset];
    _anchor=nil; _resizer=nil; _control=nil; _distance=0; _scale=1;
}
- (CGFloat)distance {
    CGPoint a=[_anchor locationInView:self.view];
    CGPoint b=[_resizer locationInView:self.view];
    return hypot(b.x-a.x,b.y-a.y);
}
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    // Timestamp ordering preserves the intended first finger for simultaneous
    // delivery. A gesture starting on scenery never selects a later control.
    NSArray* ordered=[touches.allObjects sortedArrayUsingComparator:^NSComparisonResult(UITouch* a,UITouch* b) {
        return a.timestamp<b.timestamp ? NSOrderedAscending : a.timestamp>b.timestamp ? NSOrderedDescending : NSOrderedSame;
    }];
    for (UITouch* touch in ordered) {
        if (!_anchor) {
            _anchor=touch;
            _control=self.selectControl ? self.selectControl([touch locationInView:self.view]) : nil;
            if (!_control) { self.state=UIGestureRecognizerStateFailed; return; }
        } else if (!_resizer) _resizer=touch;
    }
    if (_resizer) {
        _distance=MAX(24,[self distance]); _scale=1;
        self.state=self.state==UIGestureRecognizerStatePossible ? UIGestureRecognizerStateBegan : UIGestureRecognizerStateChanged;
    }
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if (!_anchor || !_resizer) return;
    CGFloat distance=MAX(24,[self distance]);
    _scale=distance/_distance; _distance=distance;
    self.state=UIGestureRecognizerStateChanged;
}
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    _scale=1;
    if ([touches containsObject:_anchor]) {
        self.state=self.state==UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateEnded;
    } else if (_resizer && [touches containsObject:_resizer]) {
        // Keep the anchor held: the second finger may lift and resize again.
        _resizer=nil; _distance=0;
    }
}
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    _scale=1;
    self.state=self.state==UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateCancelled;
}
@end
