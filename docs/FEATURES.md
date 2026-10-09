# UI and feature guide — 1.0.1

[README](../README.md) · [Changelog](../CHANGELOG.md) · [Technical notes](TECHNICAL_NOTES.md)

## Launcher and session ownership

The native UIKit launcher detects the supported game executable in the user-visible game-data directory and reports readiness before launch. Driving Controls, Graphics and Save Management configure the session without requiring desktop settings files. The host owns the Metal view, audio, controller bridge and lifecycle; backgrounding suspends guest work without blocking UIKit's main thread.

Settings that affect scene allocation, shaders or engine timing are selected before launch. During gameplay, those choices are locked rather than rebuilding guest render targets under an active frame. The FSR presentation switch is independent. Saved preferences override registered defaults.

## Redesigned artwork

The supplied touch-control sheet was a flattened JPG reference. The app reconstructs the artwork as scalable native paths rather than shipping cropped JPG buttons with an opaque background.

- Utility buttons use translucent circular faces and cyan double rings.
- Core symbols and short labels remain legible against gameplay.
- The gas/drift pedal uses rounded split regions and accelerator/skid symbols.
- Brake has a distinct brake/reverse symbol.
- The steering control draws a separate base, directional markers and movable knob.
- Weight uses a car with lateral arrows; Lights uses a headlamp with beams.
- Previous/next music controls use mirrored skip-track icons.
- Pause shows pause bars and a play/start symbol together; its game binding remains Start.
- Normal, pressed and disabled variants are cached. Held-state feedback changes immediately without an opacity animation.

The same artwork system is used for the default arrangement, the alternative arrangement and the editing palette. Only controls with existing game bindings are deployed; the reference sheet does not create new shift-up/down actions or add a tilt tutorial banner.

## Default arrangement

The redesigned layout is on by default. Its factory positions are based on the approved live M5 arrangement, normalized within the safe area. Button sizes scale from authored dimensions to the device frame. Existing saved positions and sizes continue to win.

The layout places steering on the lower left, Nitro above it, Gas and Gas + Handbrake on the lower right, Brake nearby, and Weight beside the driving cluster. Pause and Camera occupy the top corners; small utility/music/map actions remain independently configurable.

The default optional actions are Nitro, Gas + Handbrake, Camera, Pause, expand-map/HUD, Ability, previous/next track, map/GPS, Lights, Weight and Horn. Steering, Gas and Brake form the driving foundation.

The original arrangement remains selectable through **Experimental control overhaul**. Dedicated preference namespaces preserve each arrangement. Disabling the redesign also disables the raised in-game HUD. Reset acts on the selected arrangement, not both.

## Editing controls

1. Enter **EDIT** during gameplay. Driving inputs are released while editing.
2. Drag a control to reposition it. Its center is saved as normalized safe-area coordinates.
3. Hold a control with one finger and pinch anywhere with a second finger to resize it. Sizes range from 35% to 250% of the authored size, bounded by the screen.
4. Double-tap a palette item to deploy it. Double-tap a deployed optional action to return it to the palette.
5. Choose **DONE**. The changed layout is used immediately and stored automatically.

A saved gas/drift separation is respected. Automatic docking applies to the default placement; it does not overwrite custom positions. Docked regions share a split outline, while separated regions draw complete outlines. Sliding corridors recalculate from the current control frames, so moving a button moves its connections too.

**Driving Controls → Reset touch layout** asks before clearing layout overrides. It restores the approved factory arrangement, including sizes and available actions. It does not reset graphics settings, saves or game data.

## Continuous sliding input

A dedicated multi-touch owner handles Gas, Gas + Handbrake, Brake and Weight. Each finger keeps its own active inputs and preceding driving combination. Active fingers combine rather than cancelling one another.

| Touch location | Held guest controls | Meaning |
|---|---|---|
| Gas | RT | Accelerator |
| Gas + Handbrake | RT + A | Accelerator with handbrake |
| Brake / Reverse | LT | Brake/reverse |
| Middle of Gas + Handbrake ↔ Brake link | RT + A + LT | Three-input driving combination |
| Weight entered from Gas | RT + B | Accelerator retained while Weight is held |
| Weight entered from drift/brake blend | RT + A + LT + B | Prior driving combination plus Weight |
| Weight touched directly | B | Weight alone |

There is no release/re-tap requirement when crossing connected driving areas. The middle 40% of a driving corridor combines its endpoint inputs. At the endpoint sides it transitions to the corresponding button. Overlapping visible driving frames also combine their masks.

Weight adds B only inside the visible Weight button. Its connecting corridor retains the previous driving input without prematurely pressing B. Sliding off the button releases Weight immediately. Moving outside the driving cluster releases the active driving input; lifting or cancellation clears that finger's state. Layout switches, editing and lifecycle reset paths clear held input.

Other controls such as Lights, tracks and menus keep their own hit areas. The sliding router does not intercept them. The full virtual pad bypasses the custom driving router.

## Connection graphics

Translucent cyan strips show the continuous driving corridors. Thin center lines make the slide direction visible. The drift/brake midpoint has a plus symbol to mark combined input. Weight links are dashed and narrower because Weight is held only in its visible region. Connector drawing is clipped away from visible button faces and icons.

The hit regions follow saved geometry, not a screenshot or fixed image overlay. Multiple fingers can hold different actions simultaneously.

## Stick, tilt and full pad

The steering base and knob are independently drawn. The knob's visual travel fits the base while the established input normalization is retained. CoreMotion supplies tilt steering; recenter in your preferred straight-ahead posture and use Invert if necessary. Tilt substitutes for the left-stick steering channel.

**PAD** exposes the complete Xbox-style virtual controller, including menu/navigation actions. **Show full pad at launch** changes its initial visibility. The physical-controller path uses Apple's GameController framework. The redesigned artwork does not change the title's controller mappings.

## Raised in-game HUD

The minimap fill and its authored decorations move from the lower-left region to an upper-left anchor; speed/RPM and associated gauge elements move to the upper right. These are the game's original HUD assets, not a replacement dial or map generated from the mockups.

Placement uses the game's 1280×720 movie coordinates. The map scale is 0.90, with its reference anchor at x=28/y=76; the gauge keeps its original scale with a 28-pixel right margin and y=76 anchor. This is larger than the initial prototype. Both panels anchor to device corners rather than the vertical gutter of the centered 16:9 frame on iPad.

The padded map-border quad extends beyond the map fill's bounds. Version 1.0 recognizes that square and gives it the exact same translation, scale, viewport and scissor handling. Eligible mixed triangle/quad batches are classified per primitive, preserving draw order. Full-screen backgrounds and unrelated geometry retain their previous presentation.

Touch layout editing does not change those fixed HUD anchors. The HUD relocation is deliberately bounded, not a semantic rewrite of every movie/menu draw. Broader pause/GPS/race-overlay coverage remains a validation task.

## Graphics controls

The October 6 follow-up adds Skip Intro Videos under Graphics → Play Mode, enabled by default and applied at launch. The companion guest mask fix keeps the uninitialized intro-only render stage disabled. This option skips startup movies; it does not disable story cinematics.

The standard app exposes scene height, spatial FSR, filtering, bloom intensity, separate motion-blur/DoF switches, Retail Mode, the diagnostic graph and experimental Native 60 FPS. A separate SMAA lab build exists in source; its SMAA switch is not a feature of the standard 1.0 IPA.

The old individual Packed Color Correction, Full-Screen Fades and Stable Road Detail toggles were removed in favor of automatic renderer behavior. Glow/color correction uses the actual shader/storage contract; it does not recolor every light or sign uniformly. Blue small street-name textures are retained to match original content. No golden-road recolor or reflection boost was added.

See [technical notes](TECHNICAL_NOTES.md) for defaults, timing math, direct Metal architecture, texture channel handling and performance work.

## Save Management

Before launching the title, export or import a `.mclasave` archive containing the complete save set, including nested profiles and autosaves. The importer checks archive size and entries and stages files before replacement. It is a save transfer facility, not a disc/game-file installer.

Keep a backup when changing signing identity or deleting the app. A different bundle identifier may create a separate container. Keeping the same identity during an update is necessary for retaining the existing app data.

## Diagnostics and release limits

Retail Mode bypasses ordinary logs and capture/profiling work. With diagnostics enabled, the graph displays FPS/frame pacing and can start a bounded capture by double tap. Timing, sparse GPU-pass and thermal-pressure evidence are available for development. OS thermal state is not a temperature sensor, and latest-completion GPU samples are not necessarily exact-row measurements.

Version 1.0 retains known shader, road, checkpoint, fade, ride-height and warm-device reports. Real Metal color tests establish the audited fetch paths; they do not prove every effect or location is correct. See [known issues](KNOWN_BUGS.md) and the [release validation record](releases/1.0-validation.md).

## Export Logs

The launcher’s **Export Logs** button creates a ZIP and opens the iOS share sheet, including Save to Files. It is available before gameplay and after a failed startup. It includes runtime logs/status, performance diagnostic text files, render/control reports and a device/version/settings/failure summary. Game files, saves and caches are excluded. Turn **Graphics → Retail Mode OFF** and reopen the app before reproducing an issue that needs detailed runtime logs.
