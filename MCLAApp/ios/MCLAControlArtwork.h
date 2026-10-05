#pragma once
#import <UIKit/UIKit.h>

// Native vector reconstruction of the user's October 5 control-sheet JPG.
// The sheet is a design reference, not a transparent sprite atlas.
static UIColor* MCLAControlInk(CGFloat alpha) {
    return [UIColor colorWithRed:.76 green:.98 blue:1 alpha:alpha];
}
static void MCLAControlStroke(CGContextRef c, UIBezierPath* p, CGFloat width, CGFloat alpha) {
    CGContextSetStrokeColorWithColor(c,MCLAControlInk(alpha).CGColor);
    CGContextSetLineWidth(c,width); CGContextSetLineCap(c,kCGLineCapRound);
    CGContextSetLineJoin(c,kCGLineJoinRound); CGContextAddPath(c,p.CGPath); CGContextStrokePath(c);
}
static UIBezierPath* MCLAControlPolyline(const CGPoint* points, NSUInteger count, BOOL closed) {
    UIBezierPath* p=[UIBezierPath bezierPath];
    if(count) [p moveToPoint:points[0]];
    for(NSUInteger i=1;i<count;++i) [p addLineToPoint:points[i]];
    if(closed) [p closePath]; return p;
}
static void MCLAControlGradient(CGContextRef c, UIBezierPath* clip, CGRect r, BOOL lit) {
    CGContextSaveGState(c); CGContextAddPath(c,clip.CGPath); CGContextClip(c);
    NSArray* colors=lit ? @[(id)[UIColor colorWithRed:.19 green:.66 blue:.73 alpha:.88].CGColor,
                           (id)[UIColor colorWithRed:.015 green:.10 blue:.14 alpha:.80].CGColor] :
                         @[(id)[UIColor colorWithRed:.04 green:.12 blue:.16 alpha:.57].CGColor,
                           (id)[UIColor colorWithRed:.005 green:.025 blue:.04 alpha:.58].CGColor];
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient=CGGradientCreateWithColors(space,(__bridge CFArrayRef)colors,nullptr);
    CGContextDrawLinearGradient(c,gradient,CGPointMake(CGRectGetMidX(r),CGRectGetMinY(r)),
                                CGPointMake(CGRectGetMidX(r),CGRectGetMaxY(r)),0);
    CGGradientRelease(gradient); CGColorSpaceRelease(space); CGContextRestoreGState(c);
}
static void MCLAControlChevron(CGContextRef c, CGFloat y, BOOL up) {
    const CGPoint points[]={{-.20,y+(up ? .08 : -.08)},{0,y+(up ? -.09 : .09)},{.20,y+(up ? .08 : -.08)}};
    MCLAControlStroke(c,MCLAControlPolyline(points,3,NO),.065,1);
}
// Icon coordinates are normalized to a square centered at the origin.
static void MCLAControlIcon(CGContextRef c, NSString* key) {
    CGContextSetFillColorWithColor(c,MCLAControlInk(1).CGColor);
    if([key isEqual:@"pause"]) {
        CGContextFillRect(c,CGRectMake(-.37,-.30,.12,.60));
        CGContextFillRect(c,CGRectMake(-.16,-.30,.12,.60));
        const CGPoint play[]={{.10,-.30},{.43,0},{.10,.30}};
        CGContextAddPath(c,MCLAControlPolyline(play,3,YES).CGPath); CGContextFillPath(c);
    } else if([key isEqual:@"weight"]) {
        UIBezierPath* car=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(-.17,-.31,.34,.62) cornerRadius:.10];
        MCLAControlStroke(c,car,.045,1);
        MCLAControlStroke(c,[UIBezierPath bezierPathWithRoundedRect:CGRectMake(-.12,-.17,.24,.17) cornerRadius:.03],.035,1);
        for(int sign : {-1,1}) {
            const CGPoint arrow[]={{sign*.25,-.10},{sign*.40,0},{sign*.25,.10}};
            MCLAControlStroke(c,MCLAControlPolyline(arrow,3,NO),.045,1);
        }
    } else if([key isEqual:@"headlights"]) {
        UIBezierPath* lamp=[UIBezierPath bezierPath]; [lamp moveToPoint:CGPointMake(.08,-.26)];
        [lamp addCurveToPoint:CGPointMake(.08,.26) controlPoint1:CGPointMake(.55,-.26) controlPoint2:CGPointMake(.55,.26)];
        [lamp closePath]; MCLAControlStroke(c,lamp,.045,1);
        for(int i=0;i<4;++i) {
            CGFloat y=-.24+i*.16; const CGPoint ray[]={{-.38,y+.07},{-.05,y}};
            MCLAControlStroke(c,MCLAControlPolyline(ray,2,NO),.045,1);
        }
    } else if([key isEqual:@"track_left"] || [key isEqual:@"track_right"]) {
        CGContextSaveGState(c);
        if([key isEqual:@"track_right"]) CGContextScaleCTM(c,-1,1);
        CGContextFillRect(c,CGRectMake(-.38,-.26,.07,.52));
        const CGPoint triangle[]={{-.23,0},{.04,-.26},{.04,.26}};
        CGContextAddPath(c,MCLAControlPolyline(triangle,3,YES).CGPath); CGContextFillPath(c);
        const CGPoint second[]={{.04,0},{.31,-.26},{.31,.26}};
        CGContextAddPath(c,MCLAControlPolyline(second,3,YES).CGPath); CGContextFillPath(c);
        CGContextRestoreGState(c);
    } else if([key isEqual:@"camera"]) {
        UIBezierPath* body=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(-.42,-.25,.84,.56) cornerRadius:.06];
        CGContextAddPath(c,body.CGPath); CGContextFillPath(c);
        CGContextFillRect(c,CGRectMake(-.23,-.36,.25,.13));
        CGContextSetFillColorWithColor(c,[UIColor colorWithRed:.025 green:.15 blue:.18 alpha:1].CGColor);
        CGContextFillEllipseInRect(c,CGRectMake(-.17,-.17,.34,.34));
        MCLAControlStroke(c,[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-.105,-.105,.21,.21)],.04,1);
        CGContextSetFillColorWithColor(c,MCLAControlInk(1).CGColor);
        CGContextFillRect(c,CGRectMake(.23,-.16,.07,.06));
    } else if([key isEqual:@"nitro"]) {
        CGContextSaveGState(c); CGContextRotateCTM(c,.30);
        UIBezierPath* bottle=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(-.23,-.24,.46,.66) cornerRadius:.10];
        CGContextAddPath(c,bottle.CGPath); CGContextFillPath(c);
        CGContextFillRect(c,CGRectMake(-.12,-.47,.24,.26));
        CGContextFillRect(c,CGRectMake(-.17,-.48,.34,.09));
        const CGPoint bolt[]={{.06,-.20},{-.14,.10},{-.01,.08},{-.08,.30},{.16,-.02},{.025,0}};
        CGContextSetFillColorWithColor(c,[UIColor colorWithRed:.02 green:.12 blue:.17 alpha:1].CGColor);
        CGContextAddPath(c,MCLAControlPolyline(bolt,6,YES).CGPath); CGContextFillPath(c);
        CGContextRestoreGState(c);
    } else if([key isEqual:@"ability"]) {
        const CGPoint points[]={{-.44,.03},{-.27,.03},{-.18,-.26},{-.07,.28},{.035,-.36},{.16,.22},{.26,-.08},{.34,.03},{.44,.03}};
        MCLAControlStroke(c,MCLAControlPolyline(points,9,NO),.065,1);
    } else if([key isEqual:@"brake"]) {
        MCLAControlStroke(c,[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-.29,-.29,.58,.58)],.065,1);
        MCLAControlStroke(c,[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-.085,-.085,.17,.17)],.04,1);
        for(int i=0;i<8;++i) { CGFloat a=i*M_PI/4; CGContextFillEllipseInRect(c,CGRectMake(cos(a)*.195-.025,sin(a)*.195-.025,.05,.05)); }
        UIBezierPath* sector=[UIBezierPath bezierPath];
        [sector addArcWithCenter:CGPointZero radius:.41 startAngle:-M_PI*.5 endAngle:M_PI*.15 clockwise:YES];
        MCLAControlStroke(c,sector,.13,1);
    } else if([key isEqual:@"hud"]) {
        for(int i=0;i<4;++i) {
            CGContextSaveGState(c); CGContextRotateCTM(c,i*M_PI/2);
            const CGPoint pts[]={{.10,-.10},{.34,-.34},{.14,-.34},{.34,-.34},{.34,-.14}};
            MCLAControlStroke(c,MCLAControlPolyline(pts,5,NO),.045,1); CGContextRestoreGState(c);
        }
    } else if([key isEqual:@"gps"]) {
        const CGPoint outline[]={{-.39,-.27},{-.13,-.36},{.13,-.27},{.39,-.36},{.39,.27},{.13,.36},{-.13,.27},{-.39,.36}};
        MCLAControlStroke(c,MCLAControlPolyline(outline,8,YES),.045,1);
        const CGPoint a[]={{-.13,-.36},{-.13,.27}}, b[]={{.13,-.27},{.13,.36}};
        MCLAControlStroke(c,MCLAControlPolyline(a,2,NO),.04,1); MCLAControlStroke(c,MCLAControlPolyline(b,2,NO),.04,1);
    } else if([key isEqual:@"handbrake"]) {
        MCLAControlStroke(c,[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-.31,-.31,.62,.62)],.045,1);
        MCLAControlStroke(c,[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-.24,-.24,.48,.48)],.03,1);
        const CGPoint a[]={{-.10,-.15},{-.10,.15}}, b[]={{.10,-.15},{.10,.15}}, d[]={{-.10,0},{.10,0}};
        MCLAControlStroke(c,MCLAControlPolyline(a,2,NO),.045,1); MCLAControlStroke(c,MCLAControlPolyline(b,2,NO),.045,1); MCLAControlStroke(c,MCLAControlPolyline(d,2,NO),.045,1);
        UIBezierPath* arc=[UIBezierPath bezierPath]; [arc addArcWithCenter:CGPointZero radius:.39 startAngle:M_PI*.72 endAngle:M_PI*1.28 clockwise:YES]; MCLAControlStroke(c,arc,.04,1);
    } else if([key isEqual:@"gas"]) {
        MCLAControlChevron(c,-.13,YES); MCLAControlChevron(c,.10,YES);
    } else if([key isEqual:@"gas_handbrake"]) {
        // Front-view car and two curved tire tracks, matching the lower pedal.
        UIBezierPath* car=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(-.25,-.28,.50,.38) cornerRadius:.07];
        MCLAControlStroke(c,car,.045,1);
        const CGPoint roof[]={{-.23,-.20},{-.15,-.36},{.15,-.36},{.23,-.20}};
        MCLAControlStroke(c,MCLAControlPolyline(roof,4,NO),.045,1);
        CGContextFillEllipseInRect(c,CGRectMake(-.18,-.09,.07,.07)); CGContextFillEllipseInRect(c,CGRectMake(.11,-.09,.07,.07));
        for(int sign : {-1,1}) { UIBezierPath* p=[UIBezierPath bezierPath]; [p moveToPoint:CGPointMake(sign*.15,.14)]; [p addCurveToPoint:CGPointMake(sign*.12,.39) controlPoint1:CGPointMake(sign*.40,.23) controlPoint2:CGPointMake(-sign*.12,.29)]; MCLAControlStroke(c,p,.045,1); }
    } else {
        NSDictionary* symbols=@{@"headlights":@"headlight.low.beam",@"weight":@"arrow.up.and.down",@"horn":@"speaker.wave.2",@"hydraulics":@"arrow.up.arrow.down",@"track_left":@"backward.end.fill",@"track_right":@"forward.end.fill",@"info":@"info.circle",@"guide":@"gamecontroller",@"look_back":@"mirror.side.left",@"shift_up":@"chevron.up",@"shift_down":@"chevron.down"};
        UIImage* icon=[UIImage systemImageNamed:symbols[key] ?: @"circle"];
        icon=[icon imageWithTintColor:MCLAControlInk(1) renderingMode:UIImageRenderingModeAlwaysOriginal];
        [icon drawInRect:CGRectMake(-.36,-.36,.72,.72)];
    }
}
static UIImage* MCLAControlArtwork(NSString* key, NSString* label, CGSize size, BOOL pressed, BOOL enabled, NSInteger segment) {
    static NSCache<NSString*,UIImage*>* cache;
    static dispatch_once_t once; dispatch_once(&once,^{ cache=[[NSCache alloc] init]; cache.totalCostLimit=16*1024*1024; });
    if(size.width<=0 || size.height<=0) return nil;
    NSString* cacheKey=[NSString stringWithFormat:@"%@|%@|%.1f,%.1f|%d|%d|%ld|%.1f",key,label,size.width,size.height,pressed,enabled,(long)segment,UIScreen.mainScreen.scale];
    UIImage* image=[cache objectForKey:cacheKey]; if(image) return image;
    UIGraphicsImageRenderer* renderer=[[UIGraphicsImageRenderer alloc] initWithSize:size];
    image=[renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
        CGContextRef c=context.CGContext;
        if(!enabled) CGContextSetAlpha(c,.30);
        BOOL pedal=[key isEqual:@"gas"] || [key isEqual:@"gas_handbrake"];
        CGFloat d=MIN(size.width,size.height), padding=d*.045;
        CGRect r=pedal ? CGRectInset((CGRect){CGPointZero,size},padding,padding) : CGRectMake((size.width-d)/2+padding,(size.height-d)/2+padding,d-2*padding,d-2*padding);
        UIRectCorner corners=UIRectCornerAllCorners;
        if(pedal && segment==1) { corners=UIRectCornerTopLeft|UIRectCornerTopRight; r.size.height+=padding; }
        if(pedal && segment==2) { corners=UIRectCornerBottomLeft|UIRectCornerBottomRight; r.origin.y=0; r.size.height+=padding; }
        UIBezierPath* shell=pedal ? [UIBezierPath bezierPathWithRoundedRect:r byRoundingCorners:corners cornerRadii:CGSizeMake(d*.28,d*.28)] : [UIBezierPath bezierPathWithOvalInRect:r];
        MCLAControlGradient(c,shell,r,pressed);
        CGContextSaveGState(c); CGContextSetShadowWithColor(c,CGSizeZero,d*.025,[UIColor colorWithRed:.15 green:.85 blue:1 alpha:.6].CGColor);
        MCLAControlStroke(c,shell,MAX(1,d*.014),.88); CGContextRestoreGState(c);
        CGRect inner=CGRectInset(r,d*.038,d*.038);
        UIBezierPath* rim=pedal ? [UIBezierPath bezierPathWithRoundedRect:inner byRoundingCorners:corners cornerRadii:CGSizeMake(d*.24,d*.24)] : [UIBezierPath bezierPathWithOvalInRect:inner];
        MCLAControlStroke(c,rim,MAX(.5,d*.006),.60);
        if(pedal) {
            CGContextSaveGState(c); CGContextAddPath(c,shell.CGPath); CGContextClip(c);
            CGContextSetFillColorWithColor(c,MCLAControlInk(.045).CGColor);
            CGFloat step=MAX(5,d*.055);
            for(CGFloat y=r.origin.y+8;y<CGRectGetMaxY(r)-4;y+=step)
                for(CGFloat x=r.origin.x+8;x<CGRectGetMaxX(r)-4;x+=step) CGContextFillEllipseInRect(c,CGRectMake(x,y,1,1));
            CGContextRestoreGState(c);
        }
        BOOL drift=[key isEqual:@"gas_handbrake"];
        CGFloat iconSize=d*(pedal ? .60 : .51);
        CGFloat iconY=CGRectGetMidY(r)-(label.length ? d*.095 : 0);
        if(drift) {
            CGContextSaveGState(c);
            CGContextTranslateCTM(c,CGRectGetMidX(r),r.origin.y+r.size.height*.18);
            CGContextScaleCTM(c,d*.42,d*.42); MCLAControlChevron(c,0,YES);
            CGContextRestoreGState(c);
            iconY=r.origin.y+r.size.height*.82; iconSize=d*.40;
        }
        CGContextSaveGState(c); CGContextTranslateCTM(c,CGRectGetMidX(r),iconY); CGContextScaleCTM(c,iconSize,iconSize);
        MCLAControlIcon(c,key); CGContextRestoreGState(c);
        if(label.length) {
            CGFloat fontSize=MAX(8,d*(pedal ? .11 : .095));
            UIFont* font=[UIFont fontWithName:@"AvenirNextCondensed-DemiBold" size:fontSize] ?: [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
            NSMutableParagraphStyle* para=[[NSMutableParagraphStyle alloc] init]; para.alignment=NSTextAlignmentCenter;
            NSDictionary* attributes=@{NSFontAttributeName:font,NSForegroundColorAttributeName:MCLAControlInk(.98),NSParagraphStyleAttributeName:para};
            CGFloat labelY=drift ? r.origin.y+r.size.height*.30 : iconY+iconSize*.46;
            [label drawInRect:CGRectMake(r.origin.x+3,labelY,r.size.width-6,MAX(fontSize*2.5,CGRectGetMaxY(r)-labelY-3)) withAttributes:attributes];
        }
    }];
    [cache setObject:image forKey:cacheKey cost:NSUInteger(size.width*size.height*UIScreen.mainScreen.scale*UIScreen.mainScreen.scale*4)];
    return image;
}
static UIImage* MCLAStickArtwork(CGSize size, BOOL knob) {
    NSString* key=knob ? @"stick_knob" : @"stick_base";
    static NSCache<NSString*,UIImage*>* cache;
    static dispatch_once_t once; dispatch_once(&once,^{ cache=[[NSCache alloc] init]; cache.totalCostLimit=8*1024*1024; });
    NSString* idKey=[NSString stringWithFormat:@"%@|%.1f,%.1f|%.1f",key,size.width,size.height,UIScreen.mainScreen.scale];
    UIImage* cached=[cache objectForKey:idKey]; if(cached) return cached;
    if(size.width<=0 || size.height<=0) return nil;
    UIGraphicsImageRenderer* renderer=[[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage* image=[renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
        CGContextRef c=context.CGContext; CGFloat d=MIN(size.width,size.height);
        CGRect r=CGRectMake((size.width-d)/2+d*.035,(size.height-d)/2+d*.035,d*.93,d*.93);
        UIBezierPath* circle=[UIBezierPath bezierPathWithOvalInRect:r];
        MCLAControlGradient(c,circle,r,knob);
        CGContextSaveGState(c); CGContextSetShadowWithColor(c,CGSizeZero,d*.03,MCLAControlInk(knob ? .7 : .18).CGColor);
        MCLAControlStroke(c,circle,d*.014,knob ? 1 : .5); CGContextRestoreGState(c);
        MCLAControlStroke(c,[UIBezierPath bezierPathWithOvalInRect:CGRectInset(r,d*.05,d*.05)],d*.008,knob ? .9 : .10);
        if(!knob) {
            for(int i=0;i<4;++i) {
                CGContextSaveGState(c); CGContextTranslateCTM(c,size.width/2,size.height/2); CGContextRotateCTM(c,i*M_PI/2);
                const CGPoint pts[]={{0,-d*.405},{-d*.046,-d*.35},{d*.046,-d*.35}};
                CGContextSetFillColorWithColor(c,MCLAControlInk(.42).CGColor); CGContextAddPath(c,MCLAControlPolyline(pts,3,YES).CGPath); CGContextFillPath(c); CGContextRestoreGState(c);
            }
        }
    }];
    [cache setObject:image forKey:idKey cost:NSUInteger(size.width*size.height*UIScreen.mainScreen.scale*UIScreen.mainScreen.scale*4)];
    return image;
}
