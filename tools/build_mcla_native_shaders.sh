#!/bin/zsh

set -u
set -o pipefail

if (( $# != 3 )); then
  print -u2 "usage: build_mcla_native_shaders.sh <container-dir> <output-dir> <xenosrecomp-root>"
  exit 2
fi

container_dir="$1"
output_dir="$2"
xenos_root="$3"
xenos_bin="${MCLA_XENOSRECOMP_BIN:-$PWD/tools/build-xenosrecomp/XenosRecomp/XenosRecomp}"
common_header="$xenos_root/XenosRecomp/shader_common.h"
dxc_bin="$xenos_root/thirdparty/dxc-bin/bin/arm64/dxc-macos"
dxc_lib="$xenos_root/thirdparty/dxc-bin/lib/arm64"

if [[ ! -x "$xenos_bin" || ! -f "$common_header" || ! -x "$dxc_bin" ]]; then
  print -u2 "missing XenosRecomp compiler, common header, or DXC"
  exit 1
fi

mkdir -p "$output_dir/hlsl" "$output_dir/spirv" "$output_dir/logs"
abi_patcher="$output_dir/patch_mcla_shader_abi"
if ! clang++ -std=c++20 -O2 "${0:A:h}/patch_mcla_shader_abi.cpp" -o "$abi_patcher"; then
  exit 1
fi
manifest="$output_dir/manifest.tsv"
summary="$output_dir/summary.txt"
print 'stage\tidentity\thlsl\tspirv\tspirv_bytes\tstatus' > "$manifest"

typeset -i vertex_ok=0
typeset -i pixel_ok=0
typeset -i failed=0
typeset -i repaired_empty_fetch=0

setopt null_glob
for container in "$container_dir"/(vs|ps)-*.bin; do
  filename="${container:t}"
  stem="${filename:r}"
  stage_prefix="${stem[1,2]}"
  identity="${stem[4,-1]}"
  hlsl="$output_dir/hlsl/$stem.hlsl"
  fixed_hlsl="$output_dir/hlsl/$stem.fixed.hlsl"
  spirv="$output_dir/spirv/$stem.spv"
  log="$output_dir/logs/$stem.log"

  if ! "$xenos_bin" "$container" "$hlsl" "$common_header" >"$log" 2>&1; then
    print "$stage_prefix\t$identity\thlsl/$stem.hlsl\t-\t0\trecompile-failed" >> "$manifest"
    (( ++failed ))
    continue
  fi

  # XenosRecomp currently emits `rN. = (...).;` when a vfetch writes only
  # ZERO/ONE/KEEP destination components. The following constant writes are
  # the complete architectural effect, so remove only the empty source-copy
  # statement and retain those writes.
  empty_count=$(grep -Ec '^[[:space:]]*r[0-9]+\. = ' "$hlsl" || true)
  if (( empty_count > 0 )); then
    sed -E '/^[[:space:]]*r[0-9]+\. = /d' "$hlsl" > "$fixed_hlsl"
    mv "$fixed_hlsl" "$hlsl"
    (( repaired_empty_fetch += empty_count ))
  fi

  target='vs_6_0'
  stage_args=('-fvk-invert-y')
  if [[ "$stage_prefix" == ps ]]; then
    target='ps_6_0'
    stage_args=('-DXENOS_RECOMP_PIXEL_SHADER')
  fi
  if ! "$abi_patcher" "$hlsl" "$stage_prefix" >>"$log" 2>&1; then
    print "$stage_prefix\t$identity\thlsl/$stem.hlsl\t-\t0\tshader-abi-failed" >> "$manifest"
    (( ++failed ))
    continue
  fi

  if env DYLD_LIBRARY_PATH="$dxc_lib" "$dxc_bin" \
      -E shaderMain -T "$target" -HV 2021 -all-resources-bound \
      -spirv -fvk-use-dx-layout -Qstrip_debug -DGTA4_RECOMP \
      "${stage_args[@]}" -Fo "$spirv" "$hlsl" >>"$log" 2>&1; then
    spirv_bytes=$(stat -f '%z' "$spirv")
    print "$stage_prefix\t$identity\thlsl/$stem.hlsl\tspirv/$stem.spv\t$spirv_bytes\tok" >> "$manifest"
    if [[ "$stage_prefix" == ps ]]; then
      (( ++pixel_ok ))
    else
      (( ++vertex_ok ))
    fi
  else
    print "$stage_prefix\t$identity\thlsl/$stem.hlsl\t-\t0\tcompile-failed" >> "$manifest"
    (( ++failed ))
  fi
done

{
  print "vertex_spirv=$vertex_ok"
  print "pixel_spirv=$pixel_ok"
  print "failed=$failed"
  print "repaired_empty_fetch_assignments=$repaired_empty_fetch"
} > "$summary"

print "MCLA native shader compile: $vertex_ok vertex, $pixel_ok pixel, $failed failed, $repaired_empty_fetch empty-fetch assignments repaired"
exit $(( failed == 0 ? 0 : 1 ))
