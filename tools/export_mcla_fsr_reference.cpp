// Offline export of the same AMD FSR 1 programs used by the isolated foundation.
// No Vulkan code or runtime is linked into MCLA by this build-time utility.
#include <cstdint>
#include <fstream>
#include "../theft4-foundation/glue/rexglue-sdk-main/src/ui/shaders/vulkan_spirv/guest_output_ffx_fsr_easu_ps.h"
#include "../theft4-foundation/glue/rexglue-sdk-main/src/ui/shaders/vulkan_spirv/guest_output_ffx_fsr_rcas_ps.h"
int main() {
  std::ofstream a("artifacts/mcla-fsr-easu.spv",std::ios::binary);
  a.write(reinterpret_cast<const char*>(guest_output_ffx_fsr_easu_ps),sizeof(guest_output_ffx_fsr_easu_ps));
  std::ofstream b("artifacts/mcla-fsr-rcas.spv",std::ios::binary);
  b.write(reinterpret_cast<const char*>(guest_output_ffx_fsr_rcas_ps),sizeof(guest_output_ffx_fsr_rcas_ps));
  return a.good() && b.good()?0:1;
}
