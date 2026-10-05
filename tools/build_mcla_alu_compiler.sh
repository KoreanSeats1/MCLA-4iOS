#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
source_root=${MCLA_XENOSRECOMP_SOURCE:-"$PWD/theft4-foundation/tools/XenosRecomp"}
mkdir -p tools/build-mcla-alu
clang++ -std=c++17 -O2 -DGTA4_RECOMP -Wno-switch -Wno-unused-variable \
  -Wno-null-arithmetic -fms-extensions \
  -I"$source_root/thirdparty/smol-v/source" \
  -I"$source_root/thirdparty/xxHash" -I"$source_root/thirdparty/zstd/lib" \
  -I"$source_root/thirdparty/fmt/include" -isystem "$source_root/thirdparty/dxc-bin/inc" \
  -include tools/mcla-xenosrecomp/pch.h \
  tools/mcla-xenosrecomp/shader_recompiler.cpp tools/mcla-xenosrecomp/main.cpp \
  tools/build-xenosrecomp/thirdparty/fmt/libfmt.a \
  -o tools/build-mcla-alu/mcla-xenosrecomp
clang++ -std=c++17 -O2 -DGTA4_RECOMP -Wno-switch -fms-extensions \
  -I"$source_root/thirdparty/smol-v/source" \
  -I"$source_root/thirdparty/xxHash" -I"$source_root/thirdparty/zstd/lib" \
  -I"$source_root/thirdparty/fmt/include" -isystem "$source_root/thirdparty/dxc-bin/inc" \
  -include tools/mcla-xenosrecomp/pch.h \
  tools/mcla-xenosrecomp/shader_recompiler.cpp tools/test_mcla_alu_order.mm \
  tools/build-xenosrecomp/thirdparty/fmt/libfmt.a -framework Foundation -framework Metal \
  -o tools/build-mcla-alu/test-mcla-alu-order
tools/build-mcla-alu/test-mcla-alu-order
