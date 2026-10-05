#include "../MCLAApp/runtime/MCLAMetalVertexColor.h"
#include "../MCLAApp/runtime/MCLAGeometryScratch.h"
#include <array>
#include <cassert>
#include <cstdio>
int main() { @autoreleasepool {
    auto device=MTLCreateSystemDefaultDevice(); assert(device);
    NSError* error=nil;
    auto lib=[device newLibraryWithSource:@R"METAL(
#include <metal_stdlib>
using namespace metal;
struct F { float4 color [[attribute(0)]]; };
struct U { uint4 color [[attribute(0)]]; };
struct O { float4 pos [[position]]; float4 color; };
float4 position(uint id) { float2 p[]={float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(p[id],0,1); }
vertex O vf(F in [[stage_in]], uint id [[vertex_id]]) { return {position(id),in.color.zyxw}; }
vertex O vg(F in [[stage_in]], uint id [[vertex_id]]) { return {position(id),in.color}; }
vertex O vu(U in [[stage_in]], uint id [[vertex_id]]) { return {position(id),float4(in.color.zyxw)/255.f}; }
fragment float4 pf(O in [[stage_in]]) { return in.color; }
)METAL" options:nil error:&error]; assert(lib);
    auto queue=[device newCommandQueue];
    const std::array<std::array<uint8_t,4>,4> rgb{{{255,0,0,255},{255,255,0,255},{0,255,0,255},{0,0,255,255}}};
    for (unsigned path : {0u,1u,2u,3u}) {
        const unsigned numeric=path==1?1:0;
        const uint64_t shader=path==2?0xF52B50DA9C0F8997ull:
                              path==3?0x1B7B507E54AADA8Aull:0xACBA71021301E1DFull;
        auto vd=[MTLVertexDescriptor vertexDescriptor];
        vd.attributes[0].format=mcla::metal::PackedColorVertexFormat(numeric,
            mcla::metal::PackedColorShaderCorrection(shader,true));
        vd.attributes[0].bufferIndex=0; vd.layouts[0].stride=4;
        auto pd=[MTLRenderPipelineDescriptor new]; pd.vertexDescriptor=vd;
        pd.vertexFunction=[lib newFunctionWithName:path>=2?@"vg":numeric?@"vu":@"vf"];
        pd.fragmentFunction=[lib newFunctionWithName:@"pf"];
        pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
        auto pipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error]; assert(pipeline);
        for (auto rgba : rgb) {
            uint8_t guest[12],host[12];
            for(unsigned i=0;i<3;++i){guest[i*4]=rgba[3];guest[i*4+1]=rgba[0];guest[i*4+2]=rgba[1];guest[i*4+3]=rgba[2];}
            mcla::metal::SwapVertexWords(host,guest,sizeof(guest));
            auto buffer=[device newBufferWithBytes:host length:sizeof(host) options:MTLResourceStorageModeShared];
            auto td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
            td.usage=MTLTextureUsageRenderTarget; td.storageMode=MTLStorageModeShared;
            auto image=[device newTextureWithDescriptor:td]; assert(image);
            auto rp=[MTLRenderPassDescriptor renderPassDescriptor]; rp.colorAttachments[0].texture=image;
            rp.colorAttachments[0].loadAction=MTLLoadActionClear; rp.colorAttachments[0].storeAction=MTLStoreActionStore;
            auto cb=[queue commandBuffer]; auto enc=[cb renderCommandEncoderWithDescriptor:rp];
            [enc setRenderPipelineState:pipeline]; [enc setVertexBuffer:buffer offset:0 atIndex:0];
            [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [enc endEncoding];
            [cb commit];[cb waitUntilCompleted]; assert(cb.status==MTLCommandBufferStatusCompleted);
            uint8_t actual[4]; [image getBytes:actual bytesPerRow:4 fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];
            for(unsigned c=0;c<4;++c)assert(actual[c]==rgba[c]);
        }
    }
    puts("Metal packed vertex colors passed: red, yellow, green, blue; seed, integer and both post-tonemap glow paths");
} }
