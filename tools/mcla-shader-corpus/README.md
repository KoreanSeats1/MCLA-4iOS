# MCLA shader corpus scanner

This workspace-local diagnostic decrypts an MCLA RPF3 table, decompresses its
RSC5 resources with libmspack LZX, and searches both raw and decoded payloads
for the GTA IV RAGE shader-container structure consumed by Theft4's
`XenosRecomp`.

It deliberately references only the isolated `theft4-foundation/` checkout and
the pulled `larecomp/` tree. It does not modify the real Theft4 project.

Build:

```sh
cmake -S tools/mcla-shader-corpus -B tools/build-mcla-shader-corpus \
  -DCMAKE_BUILD_TYPE=Release
cmake --build tools/build-mcla-shader-corpus
```

Run:

```sh
tools/build-mcla-shader-corpus/mcla_shader_corpus OUTPUT_DIR \
  [--xsh cache.xsh] ARCHIVE.rpf
```

The Complete Edition `xarchive_cache.rpf` scan on 2026-09-16 successfully
decoded 14,932 of 14,962 RSC5 entries (30 malformed/unreadable archive records),
but found zero GTA IV-layout shader containers. This is a format result, not a
decompression failure: the successful resources consistently decode with a
17-bit (128 KB) LZX window.

With `--xsh`, the scanner also takes a bounded largest-first sample of live
pixel/vertex microcode from ReXGlue's warm shader cache and searches for it in
the decoded resources. Any match is saved with 128 KB of surrounding bytes on
each side so MCLA's container layout can be recovered without keeping the
multi-gigabyte decompressed archive.
