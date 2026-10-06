<p align="center"><img src="docs/images/app-icon.png" width="160" alt="MCLA 4iOS app icon"></p>
<h1 align="center">MCLA 4iOS</h1>
<p align="center">Midnight Club: Los Angeles — Complete Edition on iPhone and iPad<br><strong>Version 1.0</strong></p>
<p align="center"><a href="https://github.com/KoreanSeats1/MCLA-4iOS/releases/tag/v1.0">Download IPA</a> · <a href="CHANGELOG.md">Changelog</a> · <a href="docs/FEATURES.md">UI and feature guide</a> · <a href="docs/KNOWN_BUGS.md">Known issues</a> · <a href="https://youtu.be/zmHd-WfsaX4">Gameplay video</a></p>

An unofficial iOS adaptation built on LARecomp, ReXGlue and the Theft4 Apple foundation. The app combines ahead-of-time ARM64 execution with a title-specific native Metal renderer, a custom UIKit launcher, editable touch controls, tilt steering and physical controllers.

**No original game files are included. You need your own extracted Xbox 360 Complete Edition copy.** Version 1.0 is a release milestone; the [known issues](docs/KNOWN_BUGS.md) still apply.

## What's new in 1.0

- Redesigned cyan touch artwork: circular utility controls, a split gas/drift pedal, a separate steering base and knob, and distinct pressed/disabled states.
- Continuous thumb slides between Gas, Gas + Handbrake and Brake. The middle of the drift/brake connection holds all three driving inputs together.
- Slide into Weight while retaining the preceding driving input; Weight releases when the finger leaves its button.
- The approved M5 arrangement is the new default. Drag, resize, add or remove controls and keep your own saved layout.
- A larger minimap at the upper left and speed/RPM panel at the upper right. The map's padded circular border now receives the same position and scale as the map fill.
- Fresh Weight, Lights and previous/next track icons, plus a combined pause/play symbol.
- Corrected red signals and distant light glows in the two identified post-tonemap glow passes, with GPU tests and M5 gameplay confirmation.

See the [detailed changelog](CHANGELOG.md) for additions, fixes, validation and remaining work.

## Requirements and supported devices

| Requirement | Details |
|---|---|
| Operating system | iOS/iPadOS 18.0 or newer |
| Game | Your own complete extraction of Midnight Club: Los Angeles — Complete Edition for Xbox 360 |
| Installation | Re-sign the release IPA with your own account using a compatible sideloading tool |
| Storage | Space for the app, the complete extraction and saves; ZIP transfers also need unpacking space |
| Devices exercised | iPhone Air and M5 iPad Pro |

Playable performance is expected on iPhone 15 Pro or newer, but devices outside the tested Air/M5 pair are unverified. The deployment minimum does not establish that every iOS 18 device has suitable performance. Scene resolution, graphics options and heat affect frame rate.

## Installation and game data

### 1. Install the IPA

1. Download **MCLA-4iOS-1.0.ipa** from the [1.0 release assets](https://github.com/KoreanSeats1/MCLA-4iOS/releases/tag/v1.0).
2. Re-sign and install with [Sideloadly](https://sideloadly.io/) or [AltStore Classic](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos), using your own Apple account.
3. Follow the installer's trust and Developer Mode instructions if required.
4. Open MCLA once so it creates its game-data folder, then close it before transferring the game.

The public IPA is ad-hoc signed for recipient re-signing. It has no personal provisioning profile. The source ZIP, manifest and checksum file are supporting downloads, not app installers. See the [full installation guide](docs/INSTALLATION.md) for signing, updates and troubleshooting.

### 2. Transfer the complete extraction

Destination on the device:

**Files → Browse → On My iPhone/iPad → MCLA → MCLA_Game_Files**

```text
MCLA/
└── MCLA_Game_Files/
    ├── default.xex
    ├── xarchive_audio.rpf
    ├── xarchive_audlo.rpf
    ├── xarchive_cache.rpf
    ├── xarchive_music.rpf
    └── all remaining extracted game files and folders
```

`default.xex` must be directly inside `MCLA_Game_Files`. Copy the entire extraction, not just these examples. An ISO or unopened ZIP cannot be used directly. Avoid a second nested `MCLA_Game_Files` or `Documents` directory.

- **Mac:** Finder → device → Files → MCLA; drag in the complete folder named `MCLA_Game_Files`.
- **Windows:** use Apple Devices file sharing to transfer a ZIP, then unpack it in Files and move the extracted contents into the destination.
- **On-device Files:** select the contents of your unpacked game folder and move them into `MCLA_Game_Files`.

Detailed routes: [Mac](docs/INSTALLATION.md#transfer-from-a-mac-with-finder) · [Windows](docs/INSTALLATION.md#transfer-from-windows-with-apple-devices) · [Files app](docs/INSTALLATION.md#place-unpacked-files-using-the-devices-files-app).

### 3. Launch

Wait for copying to finish, reopen MCLA and check for **READY TO DRIVE**. Choose Driving Controls and Graphics, then launch. **WAITING FOR GAME DATA** means the expected executable was not found; check the folder structure and extraction. Detection alone does not prove every required archive was copied.

## Custom touch controls and HUD

### Driving without lifting your thumb

| Region | Input |
|---|---|
| Gas | Accelerator |
| Gas + Handbrake | Accelerator and handbrake together |
| Brake / Reverse | Brake/reverse trigger |
| Center of drift/brake connection | Accelerator, handbrake and brake together |
| Weight | Weight transfer; while sliding in, also retains that finger's preceding driving combination |

The connected areas follow the actual saved button positions. Sliding changes the held input without a fresh tap. The Weight button is held only while the finger is inside its visible region. Moving out releases Weight, and lifting or cancelling a finger releases that finger's inputs. Multiple fingers have independent state and their active inputs combine.

Cyan bridges show the driving connections; a plus marks the three-input drift/brake area. Dashed links lead to Weight. A docked gas/drift pedal has a shared outline; separated controls retain their own outlines.

### Layout editing

Use **EDIT** during gameplay to drag controls and pinch to resize. Double-tap a palette item to add it; double-tap a deployed optional item to return it to the palette. Choose **DONE** to drive. Changes save automatically. **Driving Controls → Reset touch layout** restores the default for the selected layout.

The redesigned arrangement is enabled by default, including Pause, Camera, Nitro, Ability, map/GPS actions, Lights, Weight, Horn and track controls. Existing saved edits take precedence. The **Experimental control overhaul** switch retains the earlier arrangement as an alternative; each arrangement keeps its own saved control preferences. **PAD** exposes the complete virtual Xbox controller for menus and less common actions.

The minimap and speed/RPM panels use fixed upper-corner placements when the redesign is enabled. Touch editing moves the touch buttons; it does not expose arbitrary dragging of the game's HUD panels. No persistent “tilt steering” tutorial banner was added.

### Steering and controllers

Use the touch stick or enable **Tilt steering**. Recenter in a comfortable straight-ahead position and use **Invert tilt direction** if needed. Tilt replaces left-stick steering. Physical controllers use the Apple GameController bridge; the full virtual pad remains available. Game-defined bindings are retained, including music track controls and Weight.

More artwork, editing, input and save details: [UI and feature guide](docs/FEATURES.md).

## Graphics, timing and diagnostics

| Option | What it does |
|---|---|
| Scene Resolution | 720p, 900p or 1080p scene height, with device-aspect gameplay rendering |
| FSR Upscaling | Optional AMD FSR 1 spatial EASU/RCAS presentation |
| Texture Filtering | Game Default, 1× bilinear, or 4×/8×/16× trilinear settings |
| Glow & Bloom | Balanced, Original Intensity or Low |
| Disable Motion Blur | Disables identified guest motion-blur paths |
| Disable Depth of Field | Disables identified guest focus-blur paths separately from motion blur |
| Retail Mode | Bypasses ordinary diagnostic logs, captures, profiling and the graph |
| FPS & Frame-Time Graph | Diagnostic frame-pacing display; double-tap for a bounded capture |
| Native 60 FPS | Experimental real-frame timing, camera and chassis smoothing corrections |

Fresh defaults: **30 FPS**, 720p scene height on iPhone/1080p on iPad, FSR off, 4× filtering, balanced bloom, motion blur and depth of field on. Retail Mode defaults on for iPhone and off for iPad; turn it on for an ordinary session without diagnostics. Existing preferences survive updates. Most scene/effect/timing choices require relaunching; FSR has an independent live presentation switch.

The 60 FPS option renders real frames. It adapts both fixed-delta paths, swap interval, host pacing, chase-camera smoothing and chassis ground-depth filtering while retaining the game's physics substep count and hitch guards. It is experimental: long races, collisions, cinematics and warmed-device behavior need broader testing. FSR is spatial upscaling; MetalFX frame generation is not implemented.

The release packages **603 offline native Metal title libraries** and runs the handwritten renderer without Vulkan/MoltenVK or a generic Xbox GPU command processor. Automatic packed-color, full-screen fade classification and original material LOD behavior reduce manual workaround switches. The two identified glow passes now preserve red. Small blue/purple street-name signs exist in the game's source textures and original gameplay references; green freeway boards are a separate material class.

Sun-reflection math and road specular inputs are present. A night-versus-sunset image comparison has not demonstrated missing pavement shine, and no artificial gold-reflection boost is included. See [technical notes](docs/TECHNICAL_NOTES.md) for architecture, optimization, timing math and evidence limits.

## Saves, updates and troubleshooting

**Save Management** imports/exports the complete save set, including nested profiles and autosaves, as a `.mclasave` file. It is available before starting the game. Export a backup before deleting the app or changing signing identity. Import validates archive paths and size and stages the data before replacement.

Keep the same signing account and bundle identifier when updating to preserve the app container. Deleting MCLA can delete game data and saves. Graphics Defaults and Reset touch layout are separate actions.

Outstanding reports include two missing shader programs, road shimmer, checkpoint smoke/colors, some full-screen transitions, new-game ride height and broader 60 FPS/thermal compatibility. [Known issues](docs/KNOWN_BUGS.md) distinguishes confirmed fixes from incomplete validation. Report device, OS, settings and reproduction steps through [GitHub Issues](https://github.com/KoreanSeats1/MCLA-4iOS/issues/new/choose). Do not upload game archives, full private app containers or credentials.

## Source, build and release records

- [Detailed changelog](CHANGELOG.md)
- [UI and feature guide](docs/FEATURES.md)
- [Technical architecture and optimization](docs/TECHNICAL_NOTES.md)
- [Developer/build guide](docs/DEVELOPMENT.md)
- [Control-overhaul implementation notes](docs/CONTROL_OVERHAUL.md)
- [1.0 release notes](docs/releases/1.0.md) and [validation](docs/releases/1.0-validation.md)

Clone recursively and apply the tracked patches against the pinned dependency revisions. The source excludes original game data and generated AOT/shader caches. A fresh source ZIP alone is not a turnkey build; staged user-owned inputs are required. The public IPA includes compiled application code and shader libraries, with notices and SHA-256 checksums.

## Credits and license

Thanks to **mzzvxm/LARecomp**, **BadassBaboon**, **Graine25**, **Foxxyyy**, **ReXGlue**, **LibertyRecomp/Theft4**, **Xenia/XeniOS**, **XenosRecomp**, **AMD/GPUOpen** and all upstream contributors. **KoreanSeats1** maintains this iOS adaptation. Rockstar San Diego created the original game.

[Full credits](CREDITS.md) · [GPL-3.0 project license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md).

Dependencies retain their own terms. This project is unofficial and unaffiliated with Rockstar. No license to original game content is granted.
