#pragma once

#include <cstddef>
#include <cstdint>

struct mcla_ios_audio_output;

// MCLA names for the title-neutral iOS AudioUnit ring proven by Theft4. The
// implementation is compiled from MCLA's isolated foundation clone so the two
// apps keep identical guest-mixer pacing without modifying the Theft4 project.
mcla_ios_audio_output* mcla_ios_audio_output_create();
void mcla_ios_audio_output_destroy(mcla_ios_audio_output* output);
bool mcla_ios_audio_output_submit(mcla_ios_audio_output* output,
                                  const float* guest_samples,
                                  size_t guest_frame_count);
uint64_t mcla_ios_audio_output_requested_blocks(
    const mcla_ios_audio_output* output);
