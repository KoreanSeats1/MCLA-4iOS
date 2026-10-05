#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
compiler=${CXX:-clang++}
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mcla-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
for name in canonical_draw_state control_overhaul constant_snapshot draw_reuse encoder_state fast_hash frame_delta_guard frame_rate_scaling geometry_scratch metal_presentation metal_texture_key packed_texture raster_state resource_binding_reuse resource_cache_index shader_constant_abi shader_definition_snapshot texture_validation thread_cpu_timing touch_input vertex_fixup visual_experiments; do
    "$compiler" -std=c++20 -O2 -DXXH_INLINE_ALL -Itheft4-foundation/glue/rexglue-sdk-main/thirdparty/xxHash -Itools "tools/test_mcla_${name}.cpp" -o "$test_dir/$name"
    "$test_dir/$name"
done
