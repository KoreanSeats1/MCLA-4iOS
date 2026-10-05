#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <regex>
#include <string>
#include <vector>

// Convert our MCLA-only SPIR-V corpus into the stock native-renderer cache ABI.
// Generated source contains game-derived data and stays in ignored generated/.
int main(int argc, char** argv) {
  if (argc != 4) return 2;
  std::ifstream input(argv[1], std::ios::binary);
  std::vector<uint8_t> data((std::istreambuf_iterator<char>(input)), {});
  auto u32 = [&](size_t p) { if (p + 4 > data.size()) throw std::runtime_error("pack range");
    return uint32_t(data[p]) | uint32_t(data[p+1])<<8 | uint32_t(data[p+2])<<16 | uint32_t(data[p+3])<<24; };
  auto u64 = [&](size_t p) { return uint64_t(u32(p)) | uint64_t(u32(p+4))<<32; };
  if (data.size()<32 || u32(0)!=0x5650534d || u32(4)!=1 || u32(12)!=24) return 1;
  const auto count=u32(8); const auto offset=u64(16); const auto bytes=u64(24);
  if (offset+bytes!=data.size() || count>4096 || offset<32+count*24ull) return 1;
  std::vector<uint8_t> blob(data.begin()+offset, data.end());
  std::ofstream out(argv[3]);
  out << "#include <shader/shader_cache.h>\nShaderCacheEntry g_shaderCacheEntries[] = {\n";
  for(uint32_t i=0;i<count;++i) {
    const size_t p=32+i*24; const auto hash=u64(p); const bool pixel=u32(p+8)==1;
    char identity[17]; std::snprintf(identity,sizeof(identity),"%016llX",(unsigned long long)hash);
    std::string stem=std::string(pixel?"ps-":"vs-")+identity;
    std::ifstream hlsl(std::filesystem::path(argv[2])/(stem+".hlsl"));
    if(!hlsl) return 1;
    std::string source((std::istreambuf_iterator<char>(hlsl)),{});
    const std::regex stage("s([0-9]+)_(Texture[[:alnum:]]+|Sampler)DescriptorIndex");
    uint32_t mask=0;
    for(auto m=std::sregex_iterator(source.begin(),source.end(),stage);m!=std::sregex_iterator();++m) {
      unsigned slot=std::stoul((*m)[1]); if(slot>=26) return 1; mask|=1u<<slot;
    }
    const auto start=u32(p+16), length=u32(p+20);
    if(uint64_t(start)+length>bytes || length%4 || length<20 || u32(offset+start)!=0x07230203) return 1;
    // Alpha testing/discard must run before the depth write. Preserve the
    // compiled program and remove only OpExecutionMode EarlyFragmentTests
    // to provide the native engine's mandatory late fragment variant.
    const auto lateStart = pixel ? blob.size() : 0;
    if (pixel) {
      blob.insert(blob.end(),data.begin()+offset+start,data.begin()+offset+start+20);
      for (size_t instruction=20; instruction<length;) {
        const auto word=u32(offset+start+instruction);
        const auto size=(word>>16)*4;
        if (!size || instruction+size>length) return 1;
        const bool earlyTests=(word&0xffff)==16 && size==12 &&
            u32(offset+start+instruction+8)==9;
        if (!earlyTests) blob.insert(blob.end(),data.begin()+offset+start+instruction,
                                    data.begin()+offset+start+instruction+size);
        instruction+=size;
      }
    }
    const auto lateLength=pixel ? blob.size()-lateStart : 0;
    out << "{0x"<<identity<<"ull,0,0,"<<start<<","<<length<<","<<lateStart<<","<<lateLength<<",0,0,"<<(pixel?0x702:1)
        <<",\"mcla_"<<(pixel?"ps_":"vs_")<<identity<<"\",nullptr,"<<mask<<"},\n";
  }
  out << "};\nconst size_t g_shaderCacheEntryCount="<<count<<";\nconst uint8_t g_compressedSpirvCache[]={\n";
  for(size_t i=0;i<blob.size();++i) { out<<unsigned(blob[i])<<","; if(i%32==31)out<<"\n"; }
  out << "};\nconst size_t g_spirvCacheCompressedSize="<<blob.size()<<";\nconst size_t g_spirvCacheDecompressedSize="<<blob.size()<<";\n";
  if(!out) return 1;
  std::cout<<"MCLA native cache: "<<count<<" programs, "<<blob.size()<<" bytes (including late fragment variants)\n";
}
