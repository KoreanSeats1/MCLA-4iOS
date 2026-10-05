#include "../MCLAApp/runtime/MCLATextureSwizzle.h"
#import <Metal/Metal.h>
#include <array>
#include <cassert>
#include <cstdio>
int main() { @autoreleasepool {
    auto device=MTLCreateSystemDefaultDevice(); assert(device);
    NSError* error=nil;
    auto library=[device newLibraryWithSource:@R"METAL(
#include <metal_stdlib>
using namespace metal;
struct O { float4 position [[position]]; };
vertex O vs(uint id [[vertex_id]]) { float2 p[]={float2(-1,-1),float2(3,-1),float2(-1,3)}; return {float4(p[id],0,1)}; }
fragment float4 ps(texture2d<float> source [[texture(0)]]) { return source.read(uint2(0)); }
)METAL" options:nil error:&error]; assert(library);
    auto pd=[MTLRenderPipelineDescriptor new];
    pd.vertexFunction=[library newFunctionWithName:@"vs"]; pd.fragmentFunction=[library newFunctionWithName:@"ps"];
    pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
    auto pipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error]; assert(pipeline);
    auto queue=[device newCommandQueue];
    const MTLTextureSwizzle channels[]={MTLTextureSwizzleRed,MTLTextureSwizzleGreen,MTLTextureSwizzleBlue,MTLTextureSwizzleAlpha,MTLTextureSwizzleZero,MTLTextureSwizzleOne};
    // Tiled grading surfaces retain decoded RGB. Linear light tables store
    // BGR and must exchange R/B. Verify colored samples through real Metal views.
    for (bool tiled : {false,true}) for (std::array<uint8_t,4> rgb : {
        std::array<uint8_t,4>{255,0,0,255},{255,180,30,255},{0,255,0,128},{0,0,255,255}}) {
        auto td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
        td.storageMode=MTLStorageModeShared; td.usage=MTLTextureUsageShaderRead|MTLTextureUsagePixelFormatView;
        auto source=[device newTextureWithDescriptor:td];
        auto raw=rgb; if(!tiled) std::swap(raw[0],raw[2]);
        [source replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:raw.data() bytesPerRow:4];
        auto host=mcla::metal::DecodedTextureHostSwizzle(6,tiled,2,0x60A);
        auto sw=mcla::metal::ComposeTextureSwizzle(0x60A,host);
        auto view=[source newTextureViewWithPixelFormat:source.pixelFormat textureType:MTLTextureType2D levels:NSMakeRange(0,1) slices:NSMakeRange(0,1) swizzle:MTLTextureSwizzleChannelsMake(channels[sw&7],channels[(sw>>3)&7],channels[(sw>>6)&7],channels[(sw>>9)&7])]; assert(view);
        td.usage=MTLTextureUsageRenderTarget; auto result=[device newTextureWithDescriptor:td];
        auto rp=[MTLRenderPassDescriptor renderPassDescriptor]; rp.colorAttachments[0].texture=result;
        rp.colorAttachments[0].loadAction=MTLLoadActionClear; rp.colorAttachments[0].storeAction=MTLStoreActionStore;
        auto cb=[queue commandBuffer]; auto encoder=[cb renderCommandEncoderWithDescriptor:rp];
        [encoder setRenderPipelineState:pipeline]; [encoder setFragmentTexture:view atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [encoder endEncoding];
        [cb commit]; [cb waitUntilCompleted]; assert(cb.status==MTLCommandBufferStatusCompleted);
        std::array<uint8_t,4> actual{}; [result getBytes:actual.data() bytesPerRow:4 fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];
        assert(actual==rgb);
    }
    // Unrelated formats, identity fetches, and other endian modes retain policy.
    assert(mcla::metal::DecodedTextureHostSwizzle(6,true,2,0x688)==0x688);
    assert(mcla::metal::DecodedTextureHostSwizzle(6,true,0,0x60A)==0x688);
    assert(mcla::metal::DecodedTextureHostSwizzle(18,true,2,0x60A)==0x688);
    assert(mcla::metal::ComposeTextureSwizzle(0xB68,0)==0xB68);
    assert(mcla::metal::ComposeTextureSwizzle(0x60A,mcla::metal::DecodedTextureHostSwizzle(6,true,2,0x60A,false))==0x60A);
    puts("Metal texture mapping passed: tiled grading and linear light tables; red, gold, green, blue and alpha preserved");
} }
