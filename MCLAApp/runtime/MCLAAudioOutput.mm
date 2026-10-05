#include "MCLAAudioOutput.h"

// Reuse the title-neutral AudioUnit ring from MCLA's isolated Theft4 foundation
// clone under MCLA-owned linker names. This keeps the proven 48 kHz, 32-block
// producer/consumer contract identical without changing or linking the GTA IV
// app itself. Historical diagnostic strings inside the shared implementation
// still say Theft4Audio and are intentionally treated as foundation labels.
#define theft4_ios_audio_output mcla_ios_audio_output
#define theft4_ios_audio_output_create mcla_ios_audio_output_create
#define theft4_ios_audio_output_destroy mcla_ios_audio_output_destroy
#define theft4_ios_audio_output_submit mcla_ios_audio_output_submit
#define theft4_ios_audio_output_requested_blocks \
    mcla_ios_audio_output_requested_blocks
#include "../../theft4-foundation/ios/bridge/theft4_ios_audio_output.mm"
