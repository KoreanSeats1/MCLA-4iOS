#include <rex/cvar.h>

// The desktop GraphicsSystem normally owns this shared command-processor
// setting. MCLA embeds the processor directly, so its app target supplies the
// title-neutral definition just as Theft4's iOS bridge does.
REXCVAR_DEFINE_STRING(trace_gpu_prefix, "", "GPU", "GPU trace file prefix");
