# Developer guide — 1.0.1

## Layout and exact dependency revisions

- `MCLAApp/ios`: UIKit lifecycle, launcher/graphics/controls/save UI, Metal view.
- `MCLAApp/runtime`: title adapter, direct Metal renderer, input/audio bridges, state/cache ownership and diagnostics.
- `tools`: local shader compiler changes, container/metadata utilities, regression tests and release packaging.
- `patches`: tracked local changes plus source additions against the pinned LARecomp and Theft4 checkouts.
- `dependencies.lock.json`: exact upstream commit IDs.
- `larecomp`, `theft4-foundation`, `XeniOS-reference`: Git submodule references; upstream copyright notices remain upstream.

Clone recursively, then run `sh tools/apply_dependency_patches.sh`. That script checks before applying and recognizes an already-applied patch; it does not discard local changes. GitHub's automatic source ZIP omits submodule contents. Use the recursive clone for dependency source.

The public source snapshot deliberately omits original game files, generated AOT source, captures, shader containers/HLSL/metallib caches and private engineering logs. The beta IPA already contains the compiled application and its offline shader libraries, but cannot launch the title without your own game files.

## Current build limitation

There is not yet a clean, automated end-to-end disc-to-IPA pipeline. A developer must stage the user-owned title inputs and the offline shader corpus expected by the existing tools. Current release builds use local, validated generated directories. Do not describe a successful incremental release build as proof that a fresh clone builds unaided.

Work toward a reproducible pipeline should preserve the exact dependency/config/compiler revisions, build all user-owned inputs outside Git, emit deterministic manifests, and verify coverage before packaging. Existing scripts are intentionally retained as engineering tools; some expect historical local directory layouts.

## Host code generation

The pinned foundation supplies a headless host-tools wrapper at `MCLAApp/tools/rexglue_host`. Build on macOS with a suitable modern Clang/CMake toolchain:

```sh
cmake -S MCLAApp/tools/rexglue_host -B MCLAApp/out/host-tools -DCMAKE_BUILD_TYPE=Release
cmake --build MCLAApp/out/host-tools --target rexglue
```

Prepare a local LARecomp manifest with `file_path` pointing to your own baseline `default.xex`, `out_directory_path` pointing to `MCLAApp/generated`, and the pinned LARecomp configuration included. Inspect the local tool's `codegen --help` before invoking it: the pinned SDK is not interchangeable with the newest upstream CLI. LARecomp's hook configuration already defines the two timer paths, swap interval, camera/chassis corrections and post-effect hooks; the published iOS patch implements their Apple branches.

Generated registration/initialization glue, AOT translation units, shader ABI metadata and the source list belong in the ignored generated directory. The app target refuses to enable the runtime if required generated source is missing.

## Offline shader path

1. Collect shader descriptors and semantic/constant metadata from your own game under diagnostics. Do not upload complete app containers or game archives.
2. Use `mcla_shader_containers.cpp` to reconstruct compiler containers from the captured program/interface metadata. This is compiler input, not replacement game content.
3. Build the isolated MCLA XenosRecomp compiler. The compiler preserves the original MIT attribution; its instruction-local ALU read-order handling differs from the earlier sequential translation.
4. Translate to HLSL/Metal-compatible source and apply the audited ABI mapping with `patch_mcla_shader_abi.cpp`.
5. Compile the corpus with `tools/build_mcla_metal_shaders.py`. Its current default source directory is `artifacts/mcla-alu-order-compiled/hlsl`; the tool emits native title libraries and `MCLAApp/generated/mcla_metal_shader_info.h`.
6. Prepare the vertex metadata map required by the title bridge and the optional/reference SPIR-V pack expected by the historical project. The production executable does not use a Vulkan runtime.
7. Prepare FSR EASU/RCAS inputs and run the offline FSR build. SPIRV-Cross here is a build tool; the app uses native Metal output. Its original shader-generator inputs are not published as game data.

The source contains a shader-resource scanner and corpus expanders, but capturing coverage is not the same as guaranteeing every shader permutation exists. The 1.0 package has 603 libraries and two newly observed unresolved gaps.

## Apple build and signing

```sh
MCLA_CMAKE="$(command -v cmake)" sh tools/generate_xcode.sh device YOUR_TEAM_ID
cmake --build out/build/ios-device-release --config Release --target MCLAApp
sh tools/verify_mcla_metal_build.sh
```

Xcode, the iPhoneOS SDK, your own signing profile and staged build inputs are required. The public entitlement template uses Xcode substitutions rather than a personal team ID. Do not commit generated Xcode caches, provisioning profiles, certificates or private keys. The bundle identifier is `com.koreanseats.mcla`; use your own identifier if needed and understand the effect on app data containers.

A launcher-only simulator can be configured with `MCLA_RUNTIME_ENABLED=OFF`, but some historical resource checks still expect staged renderer metadata. It is not a substitute for device validation.

## Tests and release validation

`sh tools/run_portable_tests.sh` runs the standalone CPU regressions. They exercise compact state equivalence, constant/state reuse, endian/fixup behavior, sizing/resolves, texture identity/invalidation, cache ownership, input transitions, timing and overlay classification. Tests requiring game-derived artifacts or external runtime headers are not silently substituted with fake inputs.

Metal `.mm` tests need Foundation/Metal and an actual usable Mac Metal device. For example:

```sh
clang++ -std=c++20 -fobjc-arc tools/test_mcla_metal_vertex_color.mm \
  -framework Foundation -framework Metal -o /tmp/mcla-color-test
/tmp/mcla-color-test
```

`verify_mcla_metal_build.sh` checks shader-library count against generated metadata, the handwritten backend symbol, absence of Vulkan/MoltenVK/generic command-processor symbols and code-signature integrity. It does not play the game. Color/math tests do not prove a lighting bug or collision bug is resolved in gameplay.

The re-signable release IPA is packaged from a copy of the verified device app. `package_beta.py` checks for prohibited original game files, strips personal profiles, adds notices, ad-hoc signs the copy and produces checksums. The recipient's installer must re-sign it. The original built/installed app is not stripped or modified.

## Profiling responsibly

Retail Mode gates ordinary diagnostics and captures. Turn it off before launching a deliberate diagnostic run. Double-tap the graph to collect a bounded timing capture; CSV, summary and sparse GPU-pass records are written to `Documents/Diagnostics`. Raw runtime diagnostics live separately in application support. Review files before making them public.

CPU wall time includes waits and descheduling. GPU execution does not include every CPU/queue/presentation delay. Some UI samples are the latest completion, not exact-row pairs. GPU passes/stages may overlap. Thermal state is pressure metadata, not a temperature reading. Keep these distinctions in benchmark reports.

The current bounded color trace records up to 128 unique shader/type/color-index entries and the first three color words during uncached geometry preparation. It does no forced recoloring and is entirely bypassed with Retail Mode enabled. It supports further effect validation; the two audited post-tonemap glow programs have a separate packed-color correction.

## Further work

Highest priorities: recover the missing programs, expand validation of corrected glow paths, reproduce the new-game suspension report, verify every fade and checkpoint path, compare blur controls, and test long/warm 30/60 FPS sessions. Performance follow-ups should inspect CPU preparation, resource maintenance, shared-upload pressure, pass/resolve bandwidth and compositor deadlines. MetalFX interpolation needs a separate implementation with depth/motion/UI/history/pacing contracts; it is not enabled by changing the frame limiter.

## Packaging a versioned release

The CMake project version controls the marketing version; the tracked build number is separate. Regenerate the Xcode project before building after changing either. Keep installed app signing intact and stage a copy for recipient re-signing:

```sh
python3 tools/package_beta.py --version 1.0.1 --output releases/1.0.1
```

The packager verifies the device app and ARM64 architecture, checks the expected 603-library inventory, excludes original-game/private-signing files, adds licenses/notices, ad-hoc signs the staged copy, tests ZIP integrity and writes SHA-256 sums plus a source-commit manifest. It does not export an App Store archive or grant recipients a provisioning profile. Versioned release notes and validation live under `docs/releases/`.
