#include "mcla_shader_constant_abi.h"
#include "mcla_vertex_id_abi.h"
#include <fstream>
#include <iostream>
#include <iterator>
int main(int argc,char** argv) {
  if(argc!=3 || (std::string_view(argv[2])!="vs" && std::string_view(argv[2])!="ps"))return 2;
  std::ifstream input(argv[1],std::ios::binary);
  if(!input)return 3;
  const std::string source{std::istreambuf_iterator<char>(input),{}};
  const auto patched=std::string_view(argv[2])=="vs" ? MCLAVertexIdABI(source) : MCLAFullPixelBank(source);
  if(!patched){std::cerr<<"Unexpected MCLA shader ABI: "<<argv[1]<<'\n';return 4;}
  input.close();
  std::ofstream output(argv[1],std::ios::binary|std::ios::trunc);
  output<<*patched;
  return output?0:5;
}
