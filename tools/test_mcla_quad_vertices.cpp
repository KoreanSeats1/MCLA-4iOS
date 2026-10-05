#include "mcla_vertex_id_abi.h"
#include "../MCLAApp/runtime/MCLAQuadVertexFetch.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <set>

int main(int argc, char** argv) {
  using namespace mcla::native;
  assert(!QuadFetchScaleWord(0));
  assert(QuadFetchScaleWord(0xD36D9DAFC2C3F4B1ull)==1020);
  assert(QuadFetchScaleWord(0x28160E3F809C1C64ull)==1023);
  assert(QuadFetchScaleWord(0xB11D7CEC72A529CFull)==1017);
  assert(QuadFetchRequiredBytes(0,32,9376,4)==75040);
  assert(QuadFetchRequiredBytes(7,32,9377,4)==75079);
  assert(QuadFetchRequiredBytes(UINT32_MAX,UINT32_MAX,UINT32_MAX,UINT32_MAX)>
         uint64_t(UINT32_MAX));
  const std::vector<uint8_t> source={99,88,1,2,3,4,5,6,77}; // Prefix + 2 vertices + tail.
  const auto expanded=ExpandQuadFetchPayload(source,2,3);
  assert(expanded && expanded->size()==26 && (*expanded)[0]==99 && (*expanded)[1]==88);
  for(unsigned v=0;v<8;++v)
    for(unsigned b=0;b<3;++b)assert((*expanded)[2+v*3+b]==source[2+(v/4)*3+b]);
  assert(!ExpandQuadFetchPayload(source,source.size(),3));
  assert(!ExpandQuadFetchPayload(source,2,0));
  assert(!ExpandQuadFetchPayload(source,8,3));
  // Model IA reads with a non-zero base vertex: all corners must source the
  // same prop, while the shader gets four distinct original VertexIDs.
  std::vector<uint8_t> vertices(128*32);
  for(unsigned v=0;v<128;++v)vertices[v*32]=uint8_t(v);
  const auto model=ExpandQuadFetchPayload(vertices,0,32);
  assert(model);
  for(unsigned start : {0u,4u,128u,504u})
    for(unsigned corner=0;corner<4;++corner) {
      const auto id=start+corner;
      assert((*model)[id*32]==id/4);
      assert(id%4==corner);
    }
  const std::string fixture="\tVertexShaderInput input [[stage_in]]\n"
                            "\tVertexShaderInput input\n\tfloat4 r0 = 0.0;\nmath";
  const auto patched=MCLAVertexIdABI(fixture);
  assert(patched && patched->ends_with("math") && patched->find("SV_VertexID")!=std::string::npos);
  assert(!MCLAVertexIdABI(*patched));
  assert(!MCLAVertexIdABI(fixture+"\tfloat4 r0 = 0.0;\n"));
  unsigned count=0;
  std::set<std::string> identities;
  if(argc==2)for(const auto& entry:std::filesystem::directory_iterator(argv[1])) {
    const auto name=entry.path().filename().string();
    if(!name.starts_with("vs-") || entry.path().extension()!=".hlsl")continue;
    std::ifstream file(entry.path());
    const std::string sourceText{std::istreambuf_iterator<char>(file),{}};
    assert(sourceText.find("uint mclaVertexID : SV_VertexID")!=std::string::npos);
    assert(sourceText.find("float4 r0 = float4(float(mclaVertexID), 0.0, 0.0, 0.0)")!=std::string::npos);
    identities.insert(entry.path().stem().string().substr(3));
    ++count;
  }
  if(argc==2) {
    assert(count==272);
    assert(identities.contains("6FF331E9D5D18B00"));
    assert(identities.contains("0B1D6AF146371303"));
    assert(identities.contains("DB7BF8BCAD6EBC54"));
    assert(identities.contains("3824CF1922C60398"));
    assert(identities.contains("35B35386C9A91B5D"));
    assert(identities.contains("1D0835E272D5BA62"));
    assert(identities.contains("FB765199F861B325"));
    assert(identities.contains("3D7B4AE034CE0DD6"));
    assert(identities.contains("D22C983D3F5330C9"));
    assert(identities.contains("0BF8E0681E8B4055"));
  }
  std::cout<<"Quad-fetch/VertexID tests passed; vertex shader audit="<<count<<'\n';
}
