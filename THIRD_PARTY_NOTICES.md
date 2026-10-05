# Third-party notices and provenance

Project-authored Apple host/integration material follows the GPL-3.0 project license inherited through the Theft4/LibertyRecomp lineage. Individual dependencies retain their own licenses. This document does not apply a new license to LARecomp, Xenia, ReXGlue, XenosRecomp or the original game.

## Primary lineage

| Material | Origin / terms | Distribution treatment |
|---|---|---|
| Apple foundation / portable title renderer | [Theft4](https://github.com/KoreanSeats1/Theft4), following [LibertyRecomp](https://github.com/OZORDI/LibertyRecomp); GPL-3.0 project lineage | Exact dependency revision and local patch published. GPL text retained in LICENSE. |
| Guest runtime and toolkit | [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk); BSD-3-Clause, Tom Clay and Xenia-derived portions | Original notice in licenses/ReXGlue-BSD-3-Clause.txt; pinned forked implementation under the foundation reference. |
| Xbox runtime/GPU formats and research | [Xenia](https://github.com/xenia-project/xenia), [XeniOS](https://github.com/xenios-jp/XeniOS), [Xenia Edge](https://github.com/has207/xenia-edge); BSD lineage | Xenia notice retained; XeniOS pinned as development reference, not the app runtime backend. |
| Title manifests/hooks / reverse-engineering | [LARecomp](https://github.com/mzzvxm/LARecomp), [BadassBaboon/midnightclub](https://github.com/BadassBaboon/midnightclub), [CodeX.Games.MCLA](https://github.com/Foxxyyy/CodeX.Games.MCLA) | Upstream attribution and source links preserved. Pinned LARecomp has no top-level license file; no new license is asserted for it. |
| Shader compiler modifications | [hedge-dev/XenosRecomp](https://github.com/hedge-dev/XenosRecomp), [sonicnext-dev fork](https://github.com/sonicnext-dev/XenosRecomp); MIT | Local compiler source retains MIT license; original hedge-dev contributor notice included. |
| Static recompilation research | [XenonRecomp](https://github.com/hedge-dev/XenonRecomp), [rexdex/recompiler](https://github.com/rexdex/recompiler) | Research/codegen lineage acknowledged through ReXGlue. No claim of iOS-specific authorship for that work. |
| FSR spatial scaling | [AMD FidelityFX FSR](https://github.com/GPUOpen-Effects/FidelityFX-FSR); MIT | Original AMD notice in licenses and app resources. FSR 1 EASU/RCAS, not frame generation. |
| SMAA developer lab | [iryoku/smaa](https://github.com/iryoku/smaa); MIT | Original notice retained. Separate lab source, not active standard beta code path. |

## Runtime/build dependencies

The pinned foundation carries third-party dependencies including FFmpeg (XMA audio decode), fmt, spdlog, xxHash, toml++, libmspack, SIMDe, snappy, utfcpp, CLI11, o1heap, AES and other small support libraries. Retained notice texts are under `licenses/`; exact dependency sources/revisions follow the foundation's own `.gitmodules`/gitlinks. FFmpeg's license files for its included components are retained. Do not assume one blanket license covers every FFmpeg configuration.

Other components in the upstream tool/reference tree—SDL, SPIRV-Cross, glslang, SPIR-V tools/headers, Vulkan headers, MoltenVK, Dear ImGui, stb, zstd and shader tooling—may support development or historical backends. **Their presence in an upstream tree is not a claim they are all linked into the direct-Metal release.** Original upstream notices remain authoritative. The foundation's [attribution document](https://github.com/KoreanSeats1/Theft4/blob/main/docs/ATTRIBUTION.md) supplies additional lineage and dependency links.

The full upstream license texts retained locally are also copied into the release app's `OpenSourceNotices` directory for binary attribution. The release does not contain game archives, original XEX, music, movies, disc images, saves, personal signing certificates or provisioning profiles. Native AOT code and offline shader programs are application build outputs; recipients must still supply their own original title files.

## Original game and trademarks

Midnight Club: Los Angeles was made by Rockstar San Diego and its original credited development teams. No game asset ownership is claimed. Rockstar, Take-Two, Xbox, Apple, iOS, iPadOS, Metal and other names belong to their respective holders. This unofficial beta is not affiliated with or endorsed by those companies or the upstream maintainers.

## Attribution scope

CREDITS.md and docs/contributors.json enumerate public GitHub contributor profiles returned for primary lineage repositories as of 2026-10-05, plus explicit upstream acknowledgments. Accounts appearing in fork history can overlap; they are not being credited twice for a new iOS contribution. Bots, anonymous authors and non-code testers cannot be comprehensively reconstructed from this catalog. Retained notices, linked history and original in-game credits should be consulted for the full historical record. No private author email addresses were copied into the catalog.
