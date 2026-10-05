#include "mcla_shader_constant_abi.h"
#include "../MCLAApp/runtime/MCLAShaderConstants.h"
#include "../theft4-foundation/glue/rexglue-sdk-main/src/graphics/gta4_native/stateful_constant_state.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <set>

int main(int argc,char** argv) {
  const std::vector<uint8_t> psDefinitions={1,255,0,4, 0,0,0x10,0, 0,0,0,0};
  auto defs=mcla::native::DecodeShaderFloatDefinitions(psDefinitions,256);
  assert(defs && defs->size()==1 && (*defs)[0].destination==4080 &&
         (*defs)[0].source==4096 && (*defs)[0].bytes==16);
  std::array<mcla::native::ShaderFloatDefinition,256> drawDefinitions;
  size_t drawCount=0;
  assert(mcla::native::DecodeShaderFloatDefinitionsInto(
      psDefinitions,256,drawDefinitions,drawCount));
  assert(drawCount==1 && drawDefinitions[0].destination==(*defs)[0].destination &&
         drawDefinitions[0].source==(*defs)[0].source &&
         drawDefinitions[0].bytes==(*defs)[0].bytes);
  std::array<mcla::native::ShaderFloatDefinition,0> noStorage;
  assert(!mcla::native::DecodeShaderFloatDefinitionsInto(
      psDefinitions,256,noStorage,drawCount));
  auto bad=psDefinitions;bad[3]=5;
  assert(!mcla::native::DecodeShaderFloatDefinitions(bad,256)); // Bank overflow.
  bad=psDefinitions;bad.pop_back();
  assert(!mcla::native::DecodeShaderFloatDefinitions(bad,256)); // Terminator truncated.
  assert(!mcla::native::DecodeShaderFloatDefinitionsInto(
      bad,256,drawDefinitions,drawCount));
  assert(!mcla::native::DecodeShaderFloatDefinitions(psDefinitions,0)); // Wrong stage.
  bad=psDefinitions;bad[0]=0;
  defs=mcla::native::DecodeShaderFloatDefinitions(bad,0);
  assert(defs && (*defs)[0].destination==4080);
  bad[7]=1;assert(!mcla::native::DecodeShaderFloatDefinitions(bad,0)); // Alignment.
  // Exercise the actual renderer transport, including the previously omitted
  // final dirty bit (c252..255), and preserve GTA IV's 224-register layout.
  using namespace rex::graphics::gta4_native;
  const std::array<DirtyBitSpan,1> mclaSpans{{{1,0,64,0,true}}};
  const std::array<DirtyBitSpan,1> gtaSpans{{{1,8,56,0,true}}};
  DirtyStateLayout layout{};layout.pixel_constants={mclaSpans,64};
  NativeDirtyWords dirty{};dirty[1]=1;
  auto delta=BuildDirtyStateDelta(dirty,layout);
  assert(delta.validation.valid());
  const auto& ranges=delta.delta.pixel_constant_ranges.ranges;
  assert(ranges.size()==1 && ranges[0].first==63 && ranges[0].count==1);
  std::array<uint8_t,4096> bank{};bank[255*16]=0x3E;bank[255*16+1]=0x80; // BE .25
  ConstantPayloadDelta captured;
  assert(CaptureConstantPayloadDelta(bank,delta.delta.pixel_constant_ranges,64,captured));
  assert(captured.ranges[0].destination_offset==4032 && captured.payload[48]==0x3E &&
         captured.payload[49]==0x80);
  assert(CaptureCompleteConstantSnapshot(bank,captured) && captured.payload.size()==4096);
  assert(captured.payload[4080]==0x3E && captured.payload[4081]==0x80);
  layout.pixel_constants={gtaSpans,56};
  assert(BuildDirtyStateDelta(dirty,layout).delta.pixel_constant_ranges.ranges.empty());
  dirty[1]=UINT64_MAX;layout.pixel_constants={mclaSpans,64};
  delta=BuildDirtyStateDelta(dirty,layout);
  assert(delta.delta.pixel_constant_ranges.ranges.size()==1 &&
         delta.delta.pixel_constant_ranges.ranges[0].count==64);
  const std::string fixture=
      "#define g_MCLAConstants(INDEX) selectWrapper((INDEX) < 224, vk::RawBufferLoad<float4>(base + min(INDEX, 223)*16), 0.0)\n"
      "#define g_MCLAConstants(INDEX) selectWrapper((INDEX) < 224, bank[min((uint)(INDEX), (uint)223)], 0.0)\n"
      "#define g_MCLAConstants(INDEX) selectWrapper((INDEX) < 224, g_MCLAConstants[min(INDEX, 223)], 0.0)\n";
  const std::string math="r0 = g_MCLAConstants(255).xxxx;\nif (index < 224) r1 = 223;\n";
  const auto patched=MCLAFullPixelBank(fixture+math);
  assert(patched && patched->ends_with(math));
  assert(patched->find("(INDEX) < 224")==std::string::npos);
  assert(patched->find("min(INDEX, 255)")!=std::string::npos);
  assert(!MCLAFullPixelBank(*patched)); // Unexpected/already-patched ABI rejects.
  assert(!MCLAFullPixelBank(fixture.substr(fixture.find('\n')+1)));
  auto malformed=fixture;malformed.replace(malformed.find("223"),3,"222");
  assert(!MCLAFullPixelBank(malformed));
  unsigned audited=0,highRegisterUsers=0;
  std::set<std::string> identities;
  if(argc==2)for(const auto& entry:std::filesystem::directory_iterator(argv[1])) {
    const auto name=entry.path().filename().string();
    if(!name.starts_with("ps-") || entry.path().extension()!=".hlsl")continue;
    std::ifstream file(entry.path());
    const std::string source{std::istreambuf_iterator<char>(file),{}};
    unsigned guards=0;
    for(size_t pos=0;(pos=source.find("#define g_MCLAConstants(INDEX) selectWrapper((INDEX) < 256,",pos))!=std::string::npos;++pos)++guards;
    assert(guards==3 && source.find("(INDEX) < 224")==std::string::npos);
    bool high=false;
    for(unsigned reg=224;reg<256;++reg)
      high|=source.find("g_MCLAConstants("+std::to_string(reg)+")")!=std::string::npos;
    identities.insert(entry.path().stem().string().substr(3));
    highRegisterUsers+=high;++audited;
  }
  if(argc==2) {
    assert(audited>=262 && highRegisterUsers); // Captured coverage grows with new races.
    assert(identities.contains("3505182426A9688F"));
    assert(identities.contains("26D2793089FF918B"));
    assert(identities.contains("B6D8B71D0255189C"));
    assert(identities.contains("82C096AEDD04120E"));
    assert(identities.contains("22169B59950EFA42"));
    assert(identities.contains("866A92229AB761A1"));
    assert(identities.contains("07155EC4AB4C5B9A"));
  }
  std::cout<<"MCLA pixel-bank ABI tests passed: "<<audited<<" pixel shaders, "
           <<highRegisterUsers<<" use c224..255\n";
}
