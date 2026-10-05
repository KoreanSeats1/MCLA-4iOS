#pragma once
#include <optional>
#include <string>
#include <string_view>

// XenosRecomp's GTA4 ABI guards pixel arrays at 224. MCLA's raw synthetic
// CTAB names a complete 256-register bank instead. Rewrite only that exact
// macro in each backend, leaving shader math and unrelated arrays unchanged.
inline std::optional<std::string> MCLAFullPixelBank(std::string_view input) {
  constexpr std::string_view prefix = "#define g_MCLAConstants(INDEX) ";
  std::string output;
  unsigned macros = 0;
  for(size_t start=0;start<input.size();) {
    const auto newline=input.find('\n',start);
    const auto end=newline==std::string_view::npos?input.size():newline;
    std::string line(input.substr(start,end-start));
    if(line.starts_with(prefix)) {
      const auto bound=line.find("(INDEX) < 224,");
      const auto clamp=line.find("223");
      if(bound==std::string::npos || clamp==std::string::npos ||
         line.find("223",clamp+3)!=std::string::npos) return std::nullopt;
      line.replace(clamp,3,"255");
      line.replace(bound,std::string_view("(INDEX) < 224,").size(),"(INDEX) < 256,");
      ++macros;
    }
    output+=line;
    if(newline!=std::string_view::npos)output+='\n';
    start=end+(newline!=std::string_view::npos);
  }
  if(macros!=3)return std::nullopt;
  return output;
}
