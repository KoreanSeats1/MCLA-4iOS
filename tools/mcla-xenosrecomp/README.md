# Isolated MCLA ALU-order compiler

Vendored September 18, 2026 from the local XenosRecomp checkout at
the Theft4 foundation’s XenosRecomp lineage.
MIT attribution is retained in LICENSE.md. The shared source is read-only.

The only translator modification is instruction-local preservation of vector
destinations that scalar operands also read. Both Xenos ALUs read operands
before either result is stored (compare XeniOS-reference's
`SpirvShaderTranslator::ProcessAluInstruction`). Snapshot scopes stay inside
instruction predication; scalar writeback still follows vector writeback.
Constants, swizzles, masks, output scaling, and texture behavior are unchanged.

Observed MCLA pixel shader `1828537C26EB239A`, ALU 105, words
`5887151A 00B4C9C6 E000049A`, writes r26.xyz and takes rsqrt(abs(r26.z)) in
the same instruction. The old sequential code reads the new direction value
instead of the old light-distance-squared value. Visual impact requires an
on-device comparison; an HDR highlight alone is not proof of causation.

Build/test: `sh tools/build_mcla_alu_compiler.sh` (requires Mac GPU access).
Then run `python3 tools/regenerate_mcla_alu_shaders.py` and
`python3 tools/build_mcla_metal_shaders.py`. Missing gap4 containers can be
recreated using `tools/build-native-cache/mcla_shader_containers
artifacts/mcla-shader-gap4-native-capture artifacts/mcla-alu-order-compiled/gap4-containers`.
The regenerator refuses source drift against all 534 existing baseline files.
The Metal builder now defaults to the corrected source directory; old sources
are preserved and can be explicitly selected via `--source` for an A/B.
