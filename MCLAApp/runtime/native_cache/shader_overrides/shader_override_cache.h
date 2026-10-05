#pragma once

#include <cstddef>
#include <cstdint>

constexpr uint32_t kShaderOverrideStagePixel = 0;
constexpr uint32_t kShaderOverrideStageVertex = 1;
constexpr uint32_t kShaderOverrideActivationStage = 0;
constexpr uint32_t kShaderOverrideActivationPipelinePair = 1;
constexpr uint32_t kShaderOverrideUseStockTextureMask = UINT32_MAX;

struct ShaderOverrideCacheEntry {
  uint64_t hash;
  uint32_t stage;
  uint32_t specialization_constants_mask;
  uint32_t activation;
  uint32_t pipeline_pair_id;
  uint32_t used_texture_mask;
  uint32_t support_radius_bits;
  uint32_t supported_sample_count_mask;
  const uint64_t* counterpart_hashes;
  size_t counterpart_hash_count;
  const uint32_t* spirv;
  size_t spirv_size;
  const uint32_t* late_spirv;
  size_t late_spirv_size;
  const char* filename;
};

extern const ShaderOverrideCacheEntry g_shaderOverrideEntries[];
extern const size_t g_shaderOverrideEntryCount;
