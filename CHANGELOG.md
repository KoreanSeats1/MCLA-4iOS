# Changelog

Release entries describe shipped behavior and validation separately. Version numbers do not imply that every original-game effect, device or race has been verified.

## 1.0.1 — 2026-10-07

Bugfix and CPU performance update. Marketing version 1.0.1, build 3, tag `v1.0.1`.

- Replace the app and README icon with artwork provided by **Ricioly**.
- Resize controls by holding a control and pinching anywhere, with 35%–250% authored sizing; expose Skip Intro Videos in the Play Mode settings.

- Prepare only shader-consumed vertex streams, refreshing deferred bindings when needed; coalesce adjacent shader-constant snapshot ranges. Preserve live validation and byte-exact constants. Add differential stream/binding regressions and warm-device profiling support; sustained thermal frame-budget acceptance remains pending.

- Port Theft4 0.3 geometry conversion equivalence to MCLA: reuse transformed meshes across shaders/declarations requiring identical ordered byte conversions, with bounded exact recipes and existing resource invalidation retained. Add whole-buffer differential/eviction regressions and on/off profiling support. See [performance audit](docs/PERFORMANCE_AUDIT_2026-10-06.md); device frame-time improvement is not yet measured.

- Keep **Skip Intro Videos** enabled by default, but preserve the SWF constructor/context and request the game's natural skip before the startup video play call. The early Apple skip bypass caused a reported missing-title-logo regression; the revised build is installed on Air/M5, with title-screen visual acceptance pending. Gameplay cinematics remain governed by the game.
- Keep rotating minimap borders and GPS decorations on the same translation and scale as the map fill. Classify their rotating footprint rather than only the unrotated rectangle; inspect mixed triangle/quad batches through the existing 4,096-vertex safety limit.
- Add regressions covering all 360 map headings and orbiting GPS pointers, plus unrelated-panel rejection.
- Resolve the embedded SDK version from its own checkout, preventing the app's `v1.0` tag from breaking subsequent builds.
- Built and installed this correction on M5 iPad Pro and iPhone Air. Native Metal/signing verification passes with 603 shader libraries. Live fast-camera alignment remains to be checked.
- Camera refocus-like blur remains under investigation: the user confirms it persists with both blur switches enabled or disabled. The DoF hook clears the CoC vector before composite upload; the motion-blur hooks suppress two parameter lookups/updates. This audit does not establish which pass causes the reported effect.

## 1.0 — 2026-10-05

First 1.0 release of the custom control layout and related graphics corrections, built on the 0.1.0 Apple runtime/renderer baseline. Marketing version 1.0, build 2, release tag `v1.0`.

### UI and touch artwork

- Reconstructed the supplied flattened touch-control sheet as native scalable artwork.
- Added translucent cyan utility rings, short labels, dotted pedal faces and rounded split-pedal framing.
- Added cached normal, pressed and disabled visuals with immediate held-state changes.
- Split steering visuals into a base and knob, retaining established input normalization.
- Added Weight (car/lateral arrows), Lights (headlamp/beams), mirrored previous/next track icons and a combined pause/play symbol.
- Applied the artwork to both control arrangements and the editing palette.
- Retained original title/controller bindings. Artwork does not invent extra shift controls or add a persistent tilt tutorial banner.

### Default layout and customization

- Enabled the redesigned control/HUD arrangement by default.
- Adopted the approved live M5 positions and 12 optional actions as factory defaults.
- Preserved saved user overrides and separate preference namespaces for redesigned/original layouts.
- Retained drag positioning, pinch resizing, optional palette deployment/removal and reset of the selected layout.
- Preserved custom gas/drift separation; automatic docking does not overwrite saved positions.
- Added shared split framing when pedals dock and complete outlines when separated.
- Retained full virtual pad, physical controllers, tilt recentering and inversion.

### Continuous driving slides

- Added continuous touch transitions among Gas, Gas + Handbrake, Brake and Weight.
- Gas holds RT; Gas + Handbrake holds RT+A; Brake holds LT.
- The middle 40% of the drift/brake corridor holds RT+A+LT together.
- Entering Weight retains that finger's previous driving combination and adds B only within the visible Weight region.
- Leaving Weight releases B immediately; leaving driving regions, lifting or cancellation releases the corresponding held inputs.
- Independent fingers combine their masks. Editing, switching layouts and reset paths release held inputs.
- Excluded unrelated utility-button hit areas and full-pad handling from the sliding router.
- Added cyan connection strips, a plus at the drift/brake midpoint and dashed Weight links. Connections track the saved control geometry.

### In-game map and speed/RPM placement

- Isolated eligible authored HUD geometry and moved the minimap to the upper left and speed/RPM group to the upper right.
- Enlarged both compared with the initial prototype: minimap scale 0.90; gauge original scale.
- Anchored qualified panels to device corners rather than the centered 16:9 top gutter.
- Applied movement consistently to viewport and scissor.
- Classified eligible mixed triangle/quad batches per primitive, preserving draw order and unrelated elements.
- Fixed the remaining map circle: its padded quad extends beyond the fill classifier. Captured bounds `(23.3,407.6)..(359.8,744.2)` now receive the fill's exact translation/scale.
- Added a regression using the captured padded bounds. The build with this correction was installed on Air and M5; a final post-install alignment screenshot was not obtained during that check.

### Graphics and color correctness

- Isolated the blue/red glow defect with live M5 pixel history: two additive post-tonemap passes added blue over an already red signal.
- Corrected normalized packed COLOR0 interpretation for vertex shaders `F52B50DA9C0F8997` and `1B7B507E54AADA8A` while preserving the seed shader's existing `.zyxw` interpretation and integer fetch path.
- Added real Metal tests for red, yellow, green, blue and alpha across seed/integer and both affected glow paths.
- Updated M5 gameplay showed red signal glow and warm headlights; the user confirmed lights seemed fixed. Broader effect coverage remains unverified.
- Composed tiled RGBA8 host/guest channel mapping for format 6, endian 2 and swizzle `0x60A`; preserved the linear lookup and produced-target paths. This was an earlier candidate and did not itself resolve the glow report.
- Increased bounded diagnostic color-source coverage from 64 to 128 entries.
- Retained the blue/purple small street-name atlas after source inspection and original console reference comparison. Large green freeway/directional boards are a separate material class.
- Kept existing road specular math and source inputs. No unverified golden-road reflection boost was introduced.

### Documentation and release tooling

- Expanded the README with installation, UI, sliding combinations, HUD behavior, graphics defaults, saves, architecture and limitations.
- Added a detailed UI/feature guide, this changelog, 1.0 release notes and release validation record.
- Updated technical/known-issue descriptions to distinguish the confirmed glow correction from unresolved rendering reports.
- Made packaging version-selectable and added source commit identity to the artifact manifest.
- Retained re-signable IPA packaging, original-game/private-signing exclusions, notices, archive checks and SHA-256 sums.
- Integrated the control-overhaul work into `main`; retained local dependency modifications as published patches against pinned upstream commits.

### Validation and remaining work

The release validation record lists the checks actually run. Controls were user-confirmed in M5 gameplay and exercised in the native preview harness. The padded border shares the map transform in regression checks; its final installed screenshot was pending. Neither the library count nor tests prove all races/weather/menu paths are correct.

Outstanding work includes the two newly observed missing shaders, road shimmer, checkpoint smoke/colors, some fades, the Air new-game ride-height report, broader 60 FPS/thermal testing and clean-room build reproducibility. See [Known Issues](docs/KNOWN_BUGS.md).

### Implementation history

| Commit | Change |
|---|---|
| `38ecce3` | Initial raised HUD and driving layout |
| `1deece8` | Default-on redesign with isolated preferences |
| `ab9df1d` | Larger HUD panels and upper-corner anchors |
| `fd73220` | Supplied-sheet native artwork |
| `edd035d` | Continuous slides, icons and approved M5 defaults |
| `aa9f3a5` | Batched HUD primitives and tiled channel candidate |
| `5923402` | Audited post-tonemap glow correction |
| `794dc61` | M5 glow confirmation and sign report tracking |
| `ea28f5e` | Padded minimap border moves with the fill |

## 0.1.0 — 2026-10-05

Initial public beta; tag `v0.1.0`, build 1. Later README/installation refinements were committed before 1.0.

### Apple runtime and launcher

- Ahead-of-time translated PowerPC execution compiled for ARM64 with ReXGlue guest services.
- UIKit launcher, game-data readiness, lifecycle, native input/audio and save-management integration.
- iOS/iPadOS 18 deployment minimum; physical gameplay exercised on Air and M5 iPad Pro.
- Touch/tilt/controller paths, adjustable controls and user-visible game-data storage.
- Save-set import/export, Retail Mode and bounded diagnostics.

### Native Metal renderer

- Handwritten title-specific command adapter and Metal backend without a production Vulkan/MoltenVK/generic Xbox GPU command processor.
- 603 offline native title libraries with audited constant/semantic ABI handling.
- ALU source-read order preservation for shared vector/scalar destination registers.
- Guest texture decode/untile/endian handling, packed color/1_5_5_5 conversion and separate produced-target sampling.
- Device-aspect scene rendering, authored HUD safe framing and bounded full-screen rectangle classification.
- Original material LOD bias retained after removing hidden sharpening.
- Compact draw state, exact state/constant/binding reuse, invalidation-aware caches, scratch reuse and completion-owned upload rings.
- Steady-clock host pacing and fixed-phase presentation planning.

### Graphics and timing

- 720p/900p/1080p scene height, optional spatial FSR 1, filtering and bloom choices.
- Separate motion-blur and depth-of-field controls.
- Default 30 FPS plus experimental native 60 FPS through both real-delta paths and swap interval/host pacing.
- Frame-rate-independent chase-camera and chassis-depth smoothing, finite guards and hitch bounds.
- Frame graph, bounded captures and OS thermal-pressure reporting with Retail Mode gating.

### Distribution

- Public source, pinned dependency commits/patches, credits and retained upstream licenses.
- Re-signable IPA without original game data or personal provisioning material.
- SHA-256 sums and artifact manifest.
- Documented incomplete shader/effect, road, checkpoint, ride-height and broader performance coverage.

Historical details: [0.1.0 notes](docs/releases/0.1.0.md) · [0.1.0 validation](docs/releases/0.1.0-validation.md).
