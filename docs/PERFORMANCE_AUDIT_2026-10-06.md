# Geometry and frame-time audit — 2026-10-06

## Evidence and scope

This audit uses the current Theft4 0.3 source, including its October 5 geometry
work, rather than the older embedded foundation checkout. Reference commits:

- `a0738d6f3a4b4b90fbe59d26b7f664c5cbad71cf`: equivalent vertex conversion
  recipes and large immutable upload views.
- `eb9a14619df39f7efbdd6e1bf40aaf5983086948`: immutable converted geometry
  sharing through the command producer and Metal worker.
- `da3a646788c21c4b3d5396bc5d869b1f49452a02`: immutable constant reuse and
  bounded CPU payload pools.
- The build 122 index-range work recorded in Theft4's 0.3 architecture report:
  retain hot entries, evict cold entries individually, and borrow repeated ranges.

The user reported a large practical improvement in Theft4. That result does not
establish the same gain in MCLA: the two titles have different render frontends,
resource usage and workloads. This change targets redundant preparation while
retaining world detail, geometry, lighting and shadow resolution.

## Fresh iPhone Air baseline

Three completed October 6 captures were retrieved from the phone after the user's
“Log done” cue. The third capture contains 531 frame records, including the first
boundary interval which the analysis excludes for interval statistics. Captures
and device-specific raw logs remain private under `artifacts`.

| Measurement, third capture | Median | 95th percentile |
| --- | ---: | ---: |
| Frame submission interval | 36.82 ms | 44.42 ms |
| Submission thread CPU | 35.56 ms | 42.54 ms |
| Renderer command CPU wall span | 21.69 ms | 26.88 ms |
| Paired GPU frame time | 22.98 ms | 25.41 ms |

The observed submission rate was 26.44 frames/s. The device reported serious
thermal pressure throughout this capture. Scene extent was 1560×720, output was
2736×1260 and FSR was off. These numbers are a baseline, not an optimization A/B.

CPU work exceeded the 33.33 ms budget for 30 FPS at the median while paired GPU
work remained below it. Flight-slot wait was negligible. This supports CPU
preparation as the first target in this workload; it does not establish a
universal CPU bottleneck in every scene or thermal state.

Sampled successful draw stages averaged approximately 1.32 microseconds CPU for
vertices, 1.43 for indices and 3.06 for bindings. Constants, textures and encoding
are nested within bindings and must not be added again. Thousands of draws per
frame make small per-draw overhead relevant. Consecutive-draw reuse counters do
not describe the hit rate of the entire persistent geometry cache.

Sparse GPU pass spans also overlap. The largest sampled scene-color scope had a
6.58 ms median; color resolve scopes 1.58 ms, depth resolves 0.89 ms and 640×640
shadow/depth scopes 0.60 ms. These are sampled scope spans, not additive shader
costs. They do not justify reducing shadows or changing authored lighting.

## Transfer assessment

| Theft4 optimization | MCLA assessment and action |
| --- | --- |
| Equivalent conversion recipes | Applicable. MCLA previously keyed converted meshes by shader hash and declaration identity, even when their actual byte conversions matched. Added exact ordered recipes and shared conversion identities. |
| Share immutable CPU geometry through producer/worker packets | MCLA directly creates or suballocates Metal buffers; it does not have Theft4's duplicate geometry-vector packet transfer. Its existing GPU snapshots already persist. Adding that packet layer would not remove the same copy here. |
| Large immutable upload views | Existing MCLA immutable mesh buffers already persist across frames; locked/inline geometry uses the three-flight upload ring. Broaden sharing through recipes while retaining these lifetimes. |
| Hot index-range reuse with cold eviction | MCLA already retains converted index buffers and wrapper aliases, remembers the immediately repeated indexed draw and maintains resource age/ownership indices with bounded eviction. Avoid replacing it with a second overlapping cache. |
| Immutable constants and payload pools | MCLA already retains geometry scratch, masked constant snapshots, shared constant blocks and upload-ring allocations. The baseline constant-bank reuse fraction was 73.7%. Remaining binding work merits separate profiling. |
| Native LOD selection | Theft4's selector is game-specific. No MCLA LOD or residency policy was changed without a matching behavioral oracle. |

## Implemented geometry changes

`MCLAVertexConversionRecipe.h` describes the exact sequence of post-endian writes:
half-float fields, packed-normal fields and numeric-color swaps. Recipes preserve
declaration order, overlapping fields, duplicate color-match parity and MCLA's
conversion of unused half/packed fields. Ordinary shader/declaration identity no
longer prevents reuse when the writes are identical.

The vertex fast path, wrapper aliases, immutable payload cache and per-frame
locked/inline cache use the resulting conversion identity. Source address, size,
stride and absolute offset remain part of interpretation. Buffer-header checks,
resource revisions, payload validation, unlock/release invalidation and owner
tracking remain active. A newly seen wrapper still proves payload equality.

Foliage quad-fetch interpretation remains distinct. Rectangle expansion retains
its declaration generation because it separately reads position semantics.
Unlike Theft4's proven whole-record offset optimization, MCLA keeps absolute
offsets: offset normalization has not been established safe for its draw paths.

Recipe comparison is exact, with no recipe hash used as proof of equivalence.
Metadata is bounded to 4,096 sources/recipes; eviction never recycles an identity
still referenced by an upload. A repeated-source shortcut avoids map lookup.
The engineering launch override `MCLA_METAL_EQUIVALENT_GEOMETRY=0` restores the
prior shader/declaration interpretation keys for matched comparisons.

Opt-in runtime diagnostics report recipe count, equivalent source count,
immutable alias hits and payload hits. These counters show whether sharing fires;
they do not themselves establish improved frame time.

The pending HUD correction also retains projected positions for eligible draws,
so mixed minimap primitives reuse those positions rather than repeating guest
buffer reads and matrix projection. Invalid or unsupported draws retain the
previous inspection fallback.

## Validation and acceptance

- Portable suite: all 22 test executables passed.
- Vertex tests: 160,000 independent per-element conversions plus 20,000
  whole-buffer recipe comparisons. Cases include short tails, overlapping and
  unaligned fields, all 64 elements, unused shader inputs, different streams,
  duplicate numeric semantics and packed-color suppression.
- Cache tests: equivalent sources share identity; different quad/rectangle
  interpretations remain distinct; eviction preserves monotonic identities.
- AddressSanitizer and UndefinedBehaviorSanitizer: the vertex/recipe suite passed.
- Signed Release device build passed. Native Metal verification passed with
  603 libraries and no Vulkan/MoltenVK/generic command processor symbols.
- CoreDevice confirmed installation on both iPhone Air and M5 iPad Pro.
  Executable SHA-256: `3be374266246bb8eb9db6c0857278efe714ef2fbacb0934068ec8f21bef292dd`.
  Air was launched with bounded capture enabled for gameplay validation.

No measured MCLA frame-time gain is claimed yet. Acceptance needs the same route,
scene settings and comparable thermal state with recipe reuse on/off. Compare
submission CPU, median/p95 frame intervals, conversions, memory and visual
correctness. A cold start versus a warm cache is not a matched comparison.

The title-logo/black-texture regression and camera refocus-like blur remain
separate correctness investigations. Geometry reuse is not presented as their fix.
Further GPU work should establish resolve dependencies and full-overwrite cases
before changing load/store policy; further CPU work should profile bindings and
index preparation before adding workers or altering game streaming.


## Completed geometry-build Air run

After the user's fresh launch and “Log done” cue, two new captures were retrieved:
`mcla-performance-1791314577` (617 records) and `1791314607` (531 records).
Their executable is the geometry build identified above. The bounded third
capture had not produced an additional file at retrieval; do not count it as a
completed measurement.

| Measurement | First capture | Second capture |
| --- | ---: | ---: |
| Submission throughput | 30.00 FPS | 25.87 FPS |
| Median / p95 submission interval | 33.27 / 37.66 ms | 37.74 / 47.68 ms |
| Median / p95 submission thread CPU | 19.56 / 28.23 ms | 36.16 / 44.65 ms |
| Median / p95 renderer command wall span | 11.65 / 17.34 ms | 21.70 / 27.43 ms |
| Median / p95 paired GPU | 18.94 / 20.81 ms | 22.70 / 25.08 ms |
| Thermal state | Fair | Fair transitioning to serious, then serious |

The reuse mechanism is active: at the latest logged checkpoint, 31 exact recipes
served the observed source combinations, with 224 new combinations finding an
existing equivalent recipe. Immutable vertex alias hits reached 9,458,791.
These cumulative hits include ordinary repeat reuse; they are not 9.46 million
conversions saved specifically by the new equivalence optimization.

The warmed second capture still exceeds the 30 FPS CPU budget. Per-draw sampled
CPU costs rose across state, bindings, vertices and indices as thermal pressure
increased, rather than exposing only a vertex-conversion spike. Median GPU time
remained below the 30 FPS budget. Bounded cache maintenance had a 0.45 ms median
and 0.53 ms p95 in this capture, despite 14,281 evictions; eviction count alone
should not be described as the dominant frame-time problem.

This is not a matched on/off route comparison. The first capture's 30 FPS does
not prove a geometry-only speedup, and the later 25.87 FPS does not establish a
regression relative to the earlier 26.44 FPS capture. Scene, workload and thermal
conditions differ. Sustained improvement remains unproven; the original CPU/
thermal limitation persists in this run.

Runtime completion checkpoints reported zero GPU command-buffer errors. The
existing three startup resolve-source rejections recurred. Six missing shader
identities were reported (four seen previously, two additional identities in
this run); do not describe this as complete visual correctness. The title-logo/
texture and camera-blur investigations remain open.


## Follow-up: reduce CPU work under thermal pressure

The warmed run's 36.16 ms median submission CPU needs roughly 7.8% less work to
reach 33.33 ms. Its 44.65 ms p95 needs about 25.3% less work to fit that budget at
the 95th percentile. Neither number guarantees that every frame will fit.

Two additional implementation changes target the existing workload:

- **Active vertex streams:** the native frontend prepares only streams consumed
  by the current shader/declaration. It uses the same semantic mapping and first
  matching declaration element as the Metal vertex descriptor. Missing attributes
  are constants; unknown metadata retains the full 16-stream path. A declaration
  mutation invalidates its cached input selection. Deferred streams are reread
  when needed, including null bindings, changed headers and guest payload writes.
  Live buffer validation and conversion still run for all consumed streams.
- **Contiguous constant ranges:** masked snapshot comparison and materialization
  coalesce adjacent registers. Exact byte checks, validity masks, dynamic-index
  full banks, signed-zero/NaN distinctions and frame-reset behavior are retained.

The stream helper is shared by the frontend and renderer's semantic mapping.
Its 30,000 independent differential cases also test shader transitions, in-place
layout changes, deferred updates, explicit unbinds, duplicate semantics and
constant-attribute fallback. Constant tests compare against an independent old
register loop and cover random masks/mutations. The portable suite now has 23
executables; it passed. Both targeted suites passed AddressSanitizer and
UndefinedBehaviorSanitizer.

A clustered constant remember/compare host fixture took 14.74 ms with the old
loop and 9.19 ms with contiguous ranges (about 38% less time). This is a synthetic
component benchmark, not an iPhone frame-time improvement or sustained FPS claim.

Signed Release/native Metal verification passed with 603 libraries. The new
executable SHA-256 is
`3bfb560746c42b8df689e33c727970bddf92d0211bb905566365d2e49e836e05`.
Air and M5 installation succeeded (the initial M5 disconnect cleared on retry).
Warm gameplay acceptance is pending.

Engineering override `MCLA_ACTIVE_STREAM_PREPARATION=0` restores full stream
preparation. Opt-in diagnostics report performed/skipped stream checks. Normal
retail gameplay omits those counters. The follow-up capture launch uses bounded
capture activation without the always-on `MCLA_METAL_PROFILE` override, so draw
stage clocks stop after each capture. This instrumentation change is not counted
as a gameplay optimization; sampled and unsampled frames should be distinguished
when comparing results.


The subsequent intro initialization correction includes these CPU optimizations.
Its signed executable is
`8e80b7e7a8be5a7cf710761188b2b62d7ad75991f61325017347c8df5785017e`;
both device installations succeeded. The portable suite has 24 C++ executables
plus the startup hook wiring check. Logo acceptance and a warm gameplay capture
for the CPU changes are still pending.


Early live confirmation of the combined CPU/intro build: 7,616,220 stream checks
were performed and 114,243,300 skipped (93.75% of the former 16-stream work).
The runtime logged the initialization-preserving skip request. Two automatic
captures completed while the title/game surface was visible; the scene was not
user-annotated as the matched city route. The second capture had 30.01 FPS,
19.65 ms median / 21.84 ms p95 submission CPU and 22.62 ms median paired GPU,
with nominal thermal state throughout. This confirms operation and cool-device
headroom; it does not establish the requested serious-thermal budget result.
