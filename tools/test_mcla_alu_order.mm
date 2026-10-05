#include "mcla-xenosrecomp/pch.h"
#include "mcla-xenosrecomp/shader_recompiler.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cmath>
#include <iostream>

static std::string Emit(AluInstruction instruction, bool fixed) {
    ShaderRecompiler compiler;
    compiler.preserveParallelAluSources = fixed;
    compiler.recompile(instruction);
    return compiler.out;
}

int main() {
  @autoreleasepool {
    auto device = MTLCreateSystemDefaultDevice();
    if (!device) return 2;
    // Exact ALU 105 of the captured barrel material, not a made-up operation.
    const uint32_t words[] = {0x5887151A, 0x00B4C9C6, 0xE000049A};
    AluInstruction instruction{};
    memcpy(&instruction, words, sizeof instruction);
    auto queue = [device newCommandQueue];
    for (unsigned variant = 0; variant < 4; ++variant) {
      bool fixed = variant != 0;
      instruction.isPredicated = variant >= 2;
      instruction.predicateCondition = true;
      auto body = Emit(instruction, fixed);
      if (fixed && body.find("rsqrt(abs(mclaPreAlu.z))") == std::string::npos) return 3;
      const std::string source =
        "#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void probe(device float* result [[buffer(0)]]) {\n"
        "float4 r26=float4(25,100,10000,400),r0=0,r4=.25,r21=0; float ps=0; bool p0=" +
        std::string(variant == 3 ? "false" : "true") + ";\n" + body +
        "result[0]=r21.w; result[1]=r26.z; }\n";
      NSError* error = nil;
      auto options = [MTLCompileOptions new];
      options.fastMathEnabled = NO;
      auto library = [device newLibraryWithSource:@(source.c_str()) options:options error:&error];
      if (!library) { std::cerr << error.description.UTF8String << '\n'; return 4; }
      auto pipeline = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"probe"] error:&error];
      if (!pipeline) return 5;
      auto buffer = [device newBufferWithLength:256 options:MTLResourceStorageModeShared];
      auto command = [queue commandBuffer];
      auto encoder = [command computeCommandEncoder];
      [encoder setComputePipelineState:pipeline];
      [encoder setBuffer:buffer offset:0 atIndex:0];
      [encoder dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
      [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
      if (command.status != MTLCommandBufferStatusCompleted) return 6;
      auto result = static_cast<const float*>(buffer.contents);
      float expected = variant == 0 ? 2.f : variant == 3 ? 0.f : .01f;
      float expectedVector = variant == 3 ? 10000.f : .25f;
      if (std::abs(result[0]-expected) > 1e-6f || result[1] != expectedVector) return 7;
      std::cout << "variant " << variant << ": scalar=" << result[0]
                << " vector=" << result[1] << " PASS\n";
    }
    // No vector write/export cannot clobber a scalar GPR input.
    instruction.isPredicated = false;
    instruction.vectorWriteMask = 0;
    if (Emit(instruction,true).find("mclaPreAlu") != std::string::npos) return 8;
    instruction.vectorWriteMask = 7;
    instruction.exportData = true;
    instruction.vectorDest = 0; // legal interpolator export
    instruction.src3Register = 0; // aliases the export number, but not a GPR write
    ShaderRecompiler compiler;
    compiler.interpolators[0] = "TexCoord0";
    compiler.recompile(instruction);
    if (compiler.out.find("mclaPreAlu") != std::string::npos) return 9;
    std::cout << "ALU ordering/predication/export regression tests PASS\n";
  }
}
