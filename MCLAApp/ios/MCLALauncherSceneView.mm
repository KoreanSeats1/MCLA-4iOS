#include "MCLADiagnostics.h"
#import "MCLALauncherSceneView.h"
#import <QuartzCore/CAMetalLayer.h>
#include <cmath>
#include <cassert>

// Keep scene colors linear all the way to the compositor. The soft shoulder
// preserves saturated neon hues and adapts to available EDR headroom; it never
// raises UI white or changes the user's screen brightness.
static NSString* const PresentShaders = @R"metal(
#include <metal_stdlib>
using namespace metal;
struct Varying { float4 p [[position]]; float2 uv; };
vertex Varying fullscreen(uint i [[vertex_id]]) {
    float2 p=float2((i << 1) & 2, i & 2);
    return {float4(p*float2(2,-2)+float2(-1,1),0,1),p};
}
constexpr sampler linearClamp(coord::normalized, address::clamp_to_edge, filter::linear);
fragment half4 extractGlow(Varying in [[stage_in]], texture2d<half> scene [[texture(0)]]) {
    float2 d=1.0/float2(scene.get_width(),scene.get_height());
    float3 c=0;
    for(int y=-1;y<=1;y+=2) for(int x=-1;x<=1;x+=2)
        c+=float3(scene.sample(linearClamp,in.uv+float2(x,y)*d).rgb)*.25;
    float peak=max(c.r,max(c.g,c.b));
    return half4(half3(c*(max(peak-1.0,0.0)/max(peak,.0001))),1);
}
fragment half4 blurGlow(Varying in [[stage_in]], texture2d<half> src [[texture(0)]],
                        constant float2& direction [[buffer(0)]]) {
    float3 c=float3(src.sample(linearClamp,in.uv).rgb)*.227027;
    for(int s=-1;s<=1;s+=2) {
        c+=float3(src.sample(linearClamp,in.uv+direction*float(s)*1.384615).rgb)*.316216;
        c+=float3(src.sample(linearClamp,in.uv+direction*float(s)*3.230769).rgb)*.070270;
    }
    return half4(half3(c),1);
}
fragment half4 presentScene(Varying in [[stage_in]], texture2d<half> scene [[texture(0)]],
                            texture2d<half> glow [[texture(1)]], constant float& headroom [[buffer(0)]]) {
    float3 c=max(float3(scene.sample(linearClamp,in.uv).rgb),0.0);
    c+=float3(glow.sample(linearClamp,in.uv).rgb)*.10;
    // Exposure is scene-referred and fixed, so the moving sun does not pump it.
    c*=.90;
    float peak=max(c.r,max(c.g,c.b));
    const float knee=.72;
    float range=max(headroom-knee,.001);
    float mapped=peak<=knee?peak:knee+range*(1-exp(-(peak-knee)/range));
    c*=mapped/max(peak,.00001);
    return half4(half3(c),1);
}
)metal";

@interface MCLALauncherSceneView () <MTKViewDelegate>
@property(nonatomic,strong) SCNRenderer* renderer;
@property(nonatomic,strong) id<MTLCommandQueue> queue;
@property(nonatomic,strong) id<MTLRenderPipelineState> extractPipeline;
@property(nonatomic,strong) id<MTLRenderPipelineState> blurPipeline;
@property(nonatomic,strong) id<MTLRenderPipelineState> presentPipeline;
@property(nonatomic,strong) id<MTLTexture> sceneColor;
@property(nonatomic,strong) id<MTLTexture> sceneMSAA;
@property(nonatomic,strong) id<MTLTexture> sceneDepth;
@property(nonatomic,strong) id<MTLTexture> glowA;
@property(nonatomic,strong) id<MTLTexture> glowB;
@property(nonatomic,strong) dispatch_semaphore_t inFlight;
@property(nonatomic,assign) CFTimeInterval lastTime;
@property(nonatomic,assign) CFTimeInterval animationTime;
@property(nonatomic,assign) BOOL animating;
#if defined(MCLA_LAUNCHER_HDR_TEST)
@property(nonatomic,assign) BOOL capturedHDR;
#endif
@end

@implementation MCLALauncherSceneView
- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:frame device:MTLCreateSystemDefaultDevice()];
    if(!self) return nil;
    self.colorPixelFormat=MTLPixelFormatRGBA16Float;
    self.depthStencilPixelFormat=MTLPixelFormatInvalid;
    self.sampleCount=1; // Scene gets 2x MSAA; the fullscreen presentation needs none.
#if defined(MCLA_LAUNCHER_HDR_TEST)
    self.framebufferOnly=NO;
#endif
    self.preferredFramesPerSecond=60;
    self.opaque=YES;
    self.paused=YES; self.enableSetNeedsDisplay=YES;
    self.delegate=self;
    _renderer=[SCNRenderer rendererWithDevice:self.device options:nil];
    _renderer.playing=YES;
    _queue=[self.device newCommandQueue]; _queue.label=@"MCLA launcher HDR";
    _inFlight=dispatch_semaphore_create(2);
    CAMetalLayer* layer=(CAMetalLayer*)self.layer;
    layer.maximumDrawableCount=3;
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
    layer.colorspace=space; CGColorSpaceRelease(space);
    NSError* error=nil;
    id<MTLLibrary> library=[self.device newLibraryWithSource:PresentShaders options:nil error:&error];
    if(!library) if (mcla::DiagnosticsEnabled()) NSLog(@"[launcher] HDR shader compile failed: %@",error);
    _extractPipeline=[self pipeline:@"extractGlow" library:library];
    _blurPipeline=[self pipeline:@"blurGlow" library:library];
    _presentPipeline=[self pipeline:@"presentScene" library:library];
    return self;
}
- (id<MTLRenderPipelineState>)pipeline:(NSString*)fragment library:(id<MTLLibrary>)library {
    if(!library) return nil;
    MTLRenderPipelineDescriptor* d=[MTLRenderPipelineDescriptor new];
    d.label=fragment; d.vertexFunction=[library newFunctionWithName:@"fullscreen"];
    d.fragmentFunction=[library newFunctionWithName:fragment];
    d.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA16Float;
    NSError* error=nil;
    id<MTLRenderPipelineState> p=[self.device newRenderPipelineStateWithDescriptor:d error:&error];
    if(!p) if (mcla::DiagnosticsEnabled()) NSLog(@"[launcher] HDR pipeline %@ failed: %@",fragment,error);
    return p;
}
- (void)setScene:(SCNScene*)scene { self.renderer.scene=scene; }
- (SCNScene*)scene { return self.renderer.scene; }
- (void)setPointOfView:(SCNNode*)pointOfView { self.renderer.pointOfView=pointOfView; }
- (SCNNode*)pointOfView { return self.renderer.pointOfView; }
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateDisplayRange];
    self.lastTime=0;
    self.paused=!self.animating || !self.window;
}
- (void)updateDisplayRange {
    if(@available(iOS 16.0,*)) {
        ((CAMetalLayer*)self.layer).wantsExtendedDynamicRangeContent=
            self.window.screen.potentialEDRHeadroom>1.01;
    }
}
- (void)setAnimating:(BOOL)animating {
    if(_animating==animating) return; // Status polling must not reset frame time.
    _animating=animating; self.lastTime=0;
    self.paused=!animating || !self.window;
    self.enableSetNeedsDisplay=!animating;
    if(!animating) [self setNeedsDisplay];
}
- (id<MTLTexture>)texture:(NSString*)name width:(NSUInteger)w height:(NSUInteger)h
                   format:(MTLPixelFormat)format samples:(NSUInteger)samples {
    MTLTextureDescriptor* d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
        width:w height:h mipmapped:NO];
    d.sampleCount=samples;
    d.textureType=samples>1?MTLTextureType2DMultisample:MTLTextureType2D;
    d.storageMode=MTLStorageModePrivate;
    d.usage=samples>1?MTLTextureUsageRenderTarget:(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    id<MTLTexture> t=[self.device newTextureWithDescriptor:d]; t.label=name; return t;
}
- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
    (void)view; (void)size; self.sceneColor=nil;
}
- (void)allocateTargets:(CGSize)size {
    NSUInteger w=MAX(1,(NSUInteger)size.width),h=MAX(1,(NSUInteger)size.height);
    NSUInteger samples=[self.device supportsTextureSampleCount:2]?2:1;
    self.sceneColor=[self texture:@"Launcher linear HDR" width:w height:h format:MTLPixelFormatRGBA16Float samples:1];
    self.sceneMSAA=samples>1?[self texture:@"Launcher MSAA" width:w height:h format:MTLPixelFormatRGBA16Float samples:samples]:nil;
    self.sceneDepth=[self texture:@"Launcher depth" width:w height:h format:MTLPixelFormatDepth32Float_Stencil8 samples:samples];
    self.glowA=[self texture:@"Launcher glow A" width:MAX(1,w/4) height:MAX(1,h/4) format:MTLPixelFormatRGBA16Float samples:1];
    self.glowB=[self texture:@"Launcher glow B" width:MAX(1,w/4) height:MAX(1,h/4) format:MTLPixelFormatRGBA16Float samples:1];
}
- (id<MTLRenderCommandEncoder>)encodeTarget:(id<MTLTexture>)target buffer:(id<MTLCommandBuffer>)buffer
                                  pipeline:(id<MTLRenderPipelineState>)pipeline {
    MTLRenderPassDescriptor* pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=target;
    pass.colorAttachments[0].loadAction=MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    id<MTLRenderCommandEncoder> encoder=[buffer renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:pipeline]; return encoder;
}
- (void)drawInMTKView:(MTKView*)view {
    if(!self.window || !self.scene || !self.presentPipeline || !self.extractPipeline || !self.blurPipeline) return;
    // Never wait for the GPU on the UI thread or build an unbounded queue.
    if(dispatch_semaphore_wait(self.inFlight,DISPATCH_TIME_NOW)!=0) return;
    id<CAMetalDrawable> drawable=view.currentDrawable;
    if(!drawable) { dispatch_semaphore_signal(self.inFlight); return; }
    CGSize size=CGSizeMake(drawable.texture.width,drawable.texture.height);
    if(!self.sceneColor || self.sceneColor.width!=(NSUInteger)size.width || self.sceneColor.height!=(NSUInteger)size.height)
        [self allocateTargets:size];
    if(!self.sceneColor || !self.sceneDepth || !self.glowA || !self.glowB) {
        dispatch_semaphore_signal(self.inFlight); return;
    }
    CFTimeInterval now=CACurrentMediaTime();
    CFTimeInterval delta=self.lastTime?MIN(now-self.lastTime,.1):0;
    self.lastTime=now;
    if(self.animating) self.animationTime+=delta;
    if(self.updateScene) self.updateScene(self.animationTime,self.animating?delta:0);
    [self updateDisplayRange];
    float headroom=1;
    if(@available(iOS 16.0,*)) headroom=MAX(1,MIN(8,self.window.screen.currentEDRHeadroom));
#if defined(MCLA_LAUNCHER_HDR_TEST)
    // Simulator-only test of >1 radiance and the presentation shoulder.
    headroom=4;
#endif
    id<MTLCommandBuffer> buffer=[self.queue commandBuffer]; buffer.label=@"Launcher HDR frame";
    MTLRenderPassDescriptor* scenePass=[MTLRenderPassDescriptor renderPassDescriptor];
    scenePass.colorAttachments[0].texture=self.sceneMSAA?:self.sceneColor;
    scenePass.colorAttachments[0].resolveTexture=self.sceneMSAA?self.sceneColor:nil;
    scenePass.colorAttachments[0].loadAction=MTLLoadActionClear;
    scenePass.colorAttachments[0].storeAction=self.sceneMSAA?MTLStoreActionMultisampleResolve:MTLStoreActionStore;
    scenePass.depthAttachment.texture=self.sceneDepth;
    scenePass.depthAttachment.loadAction=MTLLoadActionClear; scenePass.depthAttachment.clearDepth=1;
    scenePass.depthAttachment.storeAction=MTLStoreActionDontCare;
    scenePass.stencilAttachment.texture=self.sceneDepth;
    scenePass.stencilAttachment.loadAction=MTLLoadActionClear;
    scenePass.stencilAttachment.storeAction=MTLStoreActionDontCare;
    [self.renderer renderAtTime:self.animationTime viewport:CGRectMake(0,0,size.width,size.height)
        commandBuffer:buffer passDescriptor:scenePass];
    id<MTLRenderCommandEncoder> e=[self encodeTarget:self.glowA buffer:buffer pipeline:self.extractPipeline];
    [e setFragmentTexture:self.sceneColor atIndex:0]; [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [e endEncoding];
    vector_float2 step={1.0f/self.glowA.width,0};
    e=[self encodeTarget:self.glowB buffer:buffer pipeline:self.blurPipeline];
    [e setFragmentTexture:self.glowA atIndex:0]; [e setFragmentBytes:&step length:sizeof(step) atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [e endEncoding];
    step={0,1.0f/self.glowA.height};
    e=[self encodeTarget:self.glowA buffer:buffer pipeline:self.blurPipeline];
    [e setFragmentTexture:self.glowB atIndex:0]; [e setFragmentBytes:&step length:sizeof(step) atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [e endEncoding];
    e=[self encodeTarget:drawable.texture buffer:buffer pipeline:self.presentPipeline];
    [e setFragmentTexture:self.sceneColor atIndex:0]; [e setFragmentTexture:self.glowA atIndex:1];
    [e setFragmentBytes:&headroom length:sizeof(headroom) atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [e endEncoding];
#if defined(MCLA_LAUNCHER_HDR_TEST)
    if(!self.capturedHDR && self.animationTime>2) {
        self.capturedHDR=YES;
        NSUInteger row=((NSUInteger)size.width*8+255)&~255UL;
        NSUInteger width=size.width,height=size.height;
        id<MTLBuffer> raw=[self.device newBufferWithLength:row*height options:MTLResourceStorageModeShared];
        id<MTLBuffer> output=[self.device newBufferWithLength:row*height options:MTLResourceStorageModeShared];
        id<MTLBlitCommandEncoder> blit=[buffer blitCommandEncoder];
        [blit copyFromTexture:self.sceneColor sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
            sourceSize:MTLSizeMake(width,height,1) toBuffer:raw destinationOffset:0 destinationBytesPerRow:row destinationBytesPerImage:row*height];
        [blit copyFromTexture:drawable.texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
            sourceSize:MTLSizeMake(width,height,1) toBuffer:output destinationOffset:0 destinationBytesPerRow:row destinationBytesPerImage:row*height];
        [blit endEncoding];
        [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
            assert(!completed.error);
            float rawPeak=0,outputPeak=0; NSUInteger bright=0;
            for(NSUInteger y=0;y<height;++y) {
                const __fp16* src=(const __fp16*)((const uint8_t*)raw.contents+y*row);
                const __fp16* dst=(const __fp16*)((const uint8_t*)output.contents+y*row);
                for(NSUInteger x=0;x<width;++x) for(int c=0;c<3;++c) {
                    float a=src[x*4+c],b=dst[x*4+c];
                    assert(std::isfinite(a) && std::isfinite(b));
                    rawPeak=MAX(rawPeak,a); outputPeak=MAX(outputPeak,b); bright+=b>1;
                }
            }
            if (mcla::DiagnosticsEnabled()) NSLog(@"MCLA_LAUNCHER_HDR_TEST rawPeak=%.3f outputPeak=%.3f EDRComponents=%lu size=%lux%lu",rawPeak,outputPeak,(unsigned long)bright,(unsigned long)width,(unsigned long)height);
            assert(rawPeak>1 && outputPeak>1 && outputPeak<=4.01 && bright>0);
            if (mcla::DiagnosticsEnabled()) puts("MCLA_LAUNCHER_HDR_TEST PASS: linear HDR radiance survives into a finite, headroom-bounded floating-point drawable");
            fflush(stdout);
        }];
    }
#endif
    dispatch_semaphore_t semaphore=self.inFlight;
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        if(completed.error) if (mcla::DiagnosticsEnabled()) NSLog(@"[launcher] GPU error: %@",completed.error);
        dispatch_semaphore_signal(semaphore);
    }];
    [buffer presentDrawable:drawable]; [buffer commit];
}
@end
