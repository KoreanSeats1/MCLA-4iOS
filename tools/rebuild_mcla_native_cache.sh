#!/bin/sh
set -eu
if [ "$#" -ne 2 ]; then
    echo "usage: sh tools/rebuild_mcla_native_cache.sh CAPTURE_DIRECTORY XENOSRECOMP_ROOT" >&2
    exit 2
fi
workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
capture_dir=$1
compiler_root=$2
task_build_dir="$workspace_dir/tools/build-native-cache"
container_dir="$workspace_dir/artifacts/mcla-native-containers-expanded"
compiled_dir="$workspace_dir/artifacts/mcla-native-compiled-expanded"
pack_path="$workspace_dir/artifacts/mcla-native-metadata/mcla_native_shaders.mspv"
mkdir -p "$task_build_dir" "$workspace_dir/artifacts/mcla-native-metadata"
cd "$workspace_dir"
clang++ -std=c++20 -Wall -Wextra -Werror tools/audit_mcla_computed_fetch.cpp \
    -o "$task_build_dir/audit_mcla_computed_fetch"
"$task_build_dir/audit_mcla_computed_fetch" "$capture_dir/shaders"
for tool in mcla_shader_containers mcla_spirv_pack mcla_native_cache; do
    clang++ -std=c++20 -O2 "tools/$tool.cpp" -o "$task_build_dir/$tool"
done
"$task_build_dir/mcla_shader_containers" "$capture_dir" "$container_dir"
tools/build_mcla_native_shaders.sh "$container_dir" "$compiled_dir" "$compiler_root"
clang++ -std=c++20 -Wall -Wextra -Werror tools/test_mcla_shader_constant_abi.cpp \
    -o "$task_build_dir/test_mcla_shader_constant_abi"
"$task_build_dir/test_mcla_shader_constant_abi" "$compiled_dir/hlsl"
clang++ -std=c++20 -Wall -Wextra -Werror tools/test_mcla_quad_vertices.cpp \
    -o "$task_build_dir/test_mcla_quad_vertices"
"$task_build_dir/test_mcla_quad_vertices" "$compiled_dir/hlsl"
"$task_build_dir/mcla_spirv_pack" "$compiled_dir" "$pack_path"
"$task_build_dir/mcla_native_cache" "$pack_path" "$compiled_dir/hlsl" MCLAApp/generated/mcla_native_cache.cpp
clang++ -std=c++20 -O1 -I MCLAApp/runtime/native_cache \
    -I theft4-foundation/glue/rexglue-sdk-main/gta4-recomp/src \
    tools/test_mcla_native_cache.cpp MCLAApp/generated/mcla_native_cache.cpp \
    -o "$task_build_dir/test_mcla_native_cache"
"$task_build_dir/test_mcla_native_cache"
clang++ -std=c++20 -O1 \
    -I theft4-foundation/glue/rexglue-sdk-main/thirdparty/vulkan-headers/include \
    tools/test_mcla_native_gpu_compatibility.cpp \
    -o "$task_build_dir/test_mcla_native_gpu_compatibility"
"$task_build_dir/test_mcla_native_gpu_compatibility" "$compiled_dir/spirv"
