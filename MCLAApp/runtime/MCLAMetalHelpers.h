#pragma once
#import <Foundation/Foundation.h>
// Hand-written Metal utilities. These run in the same queue as title draws.
static NSString *const kMCLAMetalHelpers = @R"METAL(
#include <metal_stdlib>
using namespace metal;
struct CopyOut { float4 position [[position]]; float2 uv; };
vertex CopyOut copyVertex(uint i [[vertex_id]]) {
  float2 p = float2((i << 1) & 2, i & 2);
  return {float4(p * 2 - 1, 0, 1), float2(p.x, 1-p.y)};
}
fragment float4 copyFragment(CopyOut i [[stage_in]],
                              texture2d<float> source [[texture(0)]],
                              constant float4* parameters [[buffer(0)]]) {
  constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
  float2 uv=parameters[0].yz+i.uv*parameters[1].xy;
  return source.sample(s, uv) * parameters[0].x;
}
fragment float4 clearColorFragment(constant float4& value [[buffer(0)]]) {
  return value;
}
struct ClearDepthOut { float depth [[depth(any)]]; };
fragment ClearDepthOut clearDepthFragment(
    constant float& value [[buffer(0)]]) {
  return {value};
}
uint depth20e4(float depth) {
  if (!(depth > 0.0)) return 0;
  uint bits=as_type<uint>(depth);
  if(bits>=0x3FFFFFF8u) return 0xFFFFFF;
  if(bits<0x38800000u) bits=(0x800000u|(bits&0x7FFFFFu))>>min(113u-(bits>>23u),24u);
  else bits+=0xC8000000u;
  return (bits>>3u)&0xFFFFFFu;
}
fragment float4 packDepth(CopyOut i [[stage_in]],
                          depth2d<float> depth [[texture(0)]],
                          texture2d<uint> stencil [[texture(1)]],
                          constant uint* parameters [[buffer(0)]]) {
  // Fragment position is in destination coordinates. Resolve regions can
  // place a small source tile anywhere in a larger texture (or mip).
  float2 local=i.position.xy-float2(parameters[4],parameters[5]);
  uint2 p=uint2(local*float2(parameters[6],parameters[7])/
                         float2(parameters[8],parameters[9]))+
          uint2(parameters[2],parameters[3]);
  float d=depth.read(p);
  uint bits=parameters[0]?depth20e4(d):uint(rint(clamp(d,0.f,1.f)*16777215.f));
  uint packed=(bits<<8u)|(stencil.read(p).r&255u);
  float4 raw=float4(uint4(packed,packed>>8,packed>>16,packed>>24)&255u)/255.f;
  float4 result;
  for(uint c=0;c<4;++c){uint v=(parameters[1]>>(c*3))&7;result[c]=v<4?raw[v]:float(v&1);}
  return result;
}
)METAL";
