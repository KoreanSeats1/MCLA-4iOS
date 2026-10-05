#pragma once
#include <optional>
#include <string>
#include <string_view>

// Xenos preloads r0.x with the vertex index. XenosRecomp's attribute-only
// path currently initializes it to zero. Preserve all guest shader math and
// give it the host built-in, including baseVertex for converted quad lists.
inline std::optional<std::string> MCLAVertexIdABI(std::string_view source) {
  std::string result(source);
  const auto replaceOnce = [&](std::string_view from, std::string_view to) {
    const auto pos=result.find(from);
    if (pos==std::string::npos || result.find(from,pos+from.size())!=std::string::npos)
      return false;
    result.replace(pos,from.size(),to);
    return true;
  };
  if (!replaceOnce("\tVertexShaderInput input [[stage_in]]\n",
                   "\tuint mclaVertexID [[vertex_id]],\n\tVertexShaderInput input [[stage_in]]\n") ||
      !replaceOnce("\tVertexShaderInput input\n",
                   "\tuint mclaVertexID : SV_VertexID,\n\tVertexShaderInput input\n") ||
      !replaceOnce("\tfloat4 r0 = 0.0;\n",
                   "\tfloat4 r0 = float4(float(mclaVertexID), 0.0, 0.0, 0.0);\n"))
    return std::nullopt;
  return result;
}
