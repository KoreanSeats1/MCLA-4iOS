# Experimental driving controls

Branch: `control-overhaul`. Enable **Driving Controls → Experimental control overhaul** and **Touch driving controls**. The experiment is off by default. `MCLA_CONTROL_OVERHAUL=1` temporarily selects it for a development launch; `0` forces the original layout.

The experiment adds a cyan steering ring, left-side nitro, pause/camera buttons at the top, and gas, brake and combined gas/handbrake controls at the bottom right. Tilt steering still replaces the joystick when enabled. Other actions remain available through the existing pad/palette. Experimental positions, sizes and active controls use separate `…Overhaul` preference keys. Reset only affects the selected layout. Switching layouts restores original button titles, colors and fonts and releases held input.

## HUD isolation

The renderer evaluates the existing audited 2D HUD vertex transform for the known shader pair `F8B6972A1D56B354 / 5CA2EECD341441FF`. It reads draw bounds in the movie's 1280×720 coordinate system before safe framing. Only complete draws inside the lower-left mini map region or lower-right gauge region qualify. The map is scaled to 78% and positioned near y=80; the gauges are scaled to 85%, positioned near y=90 and retain their right edge. These transforms apply to viewport and scissor together, including the centered safe frame on taller displays. Original guest memory, textures and UI resources are untouched.

Inline and indexed vertex reads are range checked and bounded to 4,096 vertices. Mixed-panel batches, full-screen backgrounds, invalid geometry, unrelated shaders and other logical target sizes remain in place. With diagnostics enabled, `MCLA_HUD_TRACE_FRAME=<frame>` also emits `MCLA HUD MOVE` bounds, group and transform information for that frame.

This is a spatial renderer experiment, not semantic identification of a game movie. The same shader also draws menus. In gameplay, masks or text using other programs and batches spanning both panels may remain behind; corner menu elements may qualify. Verify the map circle, rotating streets, route arrow, gauge digits/needle, nitro, race overlays and pause/GPS/garage screens before merging. No physical-device gameplay verification or performance result is claimed yet.

## Validation and preview

- Device Release build passed with the production Metal renderer. Signed bundle verification passed with all 603 Metal libraries and the expected native backend.
- All portable tests passed, including panel-boundary, mixed/full-screen rejection, target anchors, invalid bounds and scaled scissor coverage in `test_mcla_control_overhaul.cpp`.
- Isolated iPad simulator harness passed production combined-pedal overlap/release, experimental reset isolation and original-title restoration checks.
- `artifacts/control-overhaul/ipad-layout-study.png` shows the production UIKit controls with captured HUD crops placed using the same transform policy. The center image is a captured scene slice. This is a layout study, not a screenshot proving live HUD relocation. No replacement artwork has been supplied yet.

The preview harness is `tools/launcher_preview/control_preview.mm`; substitute it for `integration.mm` in the launcher integration build, include `MCLASaveArchive.mm` and UniformTypeIdentifiers, and use C++20. Bundle a 1904×1312 capture as `capture.png` from `artifacts/mcla-528-driving.png`. Use a separate bundle identifier such as `com.koreanseats.mcla.control-preview`; it never links the game runtime or accesses physical-device game data. It generates `Documents/layout.png` in its own simulator container.
