<p align="center"><img src="docs/images/app-icon.png" width="160" alt="MCLA 4iOS app icon"></p>
<h1 align="center">MCLA 4iOS</h1>
<p align="center"><strong><a href="https://youtu.be/zmHd-WfsaX4">▶ Watch my MCLA gameplay on YouTube</a></strong></p>
<p align="center">Midnight Club: Los Angeles — Complete Edition on iPhone and iPad<br><strong>Version 1.0.4</strong></p>
<p align="center"><a href="https://github.com/KoreanSeats1/MCLA-4iOS/releases/tag/v1.0.4">Download IPA</a> · <a href="CHANGELOG.md">Changelog</a> · <a href="docs/FEATURES.md">UI and feature guide</a> · <a href="docs/KNOWN_BUGS.md">Known issues</a></p>

An unofficial iOS adaptation built on LARecomp, ReXGlue and the Theft4 Apple foundation. The app combines ahead-of-time ARM64 execution with a title-specific native Metal renderer, a custom UIKit launcher, editable touch controls, tilt steering and physical controllers.

**No original game files are included. You need your own extracted Xbox 360 Complete Edition copy.** Version 1.0.4 is a release milestone; the [known issues](docs/KNOWN_BUGS.md) still apply.

## What's new in 1.0.4

Startup compatibility hotfix: rebuild FSR and all 603 title Metal shader libraries with an explicit **iOS 18.0 minimum**. Earlier shader builds inherited iOS 27 from the development SDK and could stop at **Xbox/AOT runtime setup failed** on older systems. Release packaging now rejects shader targets newer than the app minimum. Export Logs remains included. See [1.0.4 release notes](docs/releases/1.0.4.md).

## What's new in 1.0.3

**Export Logs** on the launcher creates a ZIP of existing runtime and performance diagnostics plus device, version, settings and failure details. It remains available after a failed startup. Save it to Files or share it directly. For detailed startup logs, turn **Graphics → Retail Mode OFF**, close and reopen MCLA, reproduce the error and export. See [1.0.3 release notes](docs/releases/1.0.3.md).

## What's new in 1.0.2

- **MCLA Game Prep for Mac:** drag an Xbox 360 ISO, RAR, ZIP, 7z or extracted game folder into a standalone app and prepare the complete `MCLA_Game_Files` layout.
- Exact compatibility checking now accepts the verified alternate Complete Edition executable whose game code matches our baseline. No title update needed.
- Clear platform errors, safe staging/cancellation, complete extraction, lowercase paths and a preparation report.
- Mac applet download, related icon and [step-by-step preparation guide](docs/GAME_PREP.md). **Windows coming soon.**
- The alternate copy passed extraction and static compatibility checks; physical-device gameplay with it remains untested.

See [1.0.2 release notes](docs/releases/1.0.2.md). The 1.0.1 improvements remain included:

- New app icon provided by **Ricioly**.
- Minimap borders and GPS decorations follow the map through rotation.
- Hold a control and pinch anywhere to resize it, with a wider size range.
- Skip Intro Videos defaults on and preserves startup initialization; title-logo visual acceptance remains pending.
- Reduced CPU preparation through equivalent geometry reuse, shader-consumed vertex streams and contiguous constant snapshots. Sustained warm-device FPS improvement remains unverified.

The redesigned controls and graphics corrections from 1.0 remain included:

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

### Copy-and-paste setup prompt

Copy the entire block below into Codex or Claude to get help with your setup. An agent with computer/file access can carry out the steps its tools support; a chat-only agent can guide you. You supply your own game copy and complete device trust/signing prompts. Successful gameplay must be verified on your device.

```text
Help me install and launch MCLA 4iOS (Midnight Club: Los Angeles — Complete Edition) on my iPhone or iPad. Work through the setup with me until we verify that the game launches, or identify the exact remaining blocker.

Start by reading the project's current instructions and latest published release:
https://github.com/KoreanSeats1/MCLA-4iOS
https://github.com/KoreanSeats1/MCLA-4iOS/blob/main/docs/INSTALLATION.md
https://github.com/KoreanSeats1/MCLA-4iOS/blob/main/docs/GAME_PREP.md
https://github.com/KoreanSeats1/MCLA-4iOS/releases/latest

Ask only for missing details, preferably together: my device model and iOS version; whether I have a Mac, Windows PC, or only the phone; where my own Xbox 360 Complete Edition game files are and whether they are an ISO, archive, or extracted folder; whether MCLA is already installed; and my signing method (such as Sideloadly, AltStore Classic, or SideStore). If I use LiveContainer, establish that explicitly because its file locations can differ. Inspect accessible files and connected devices instead of asking me to repeat information you can verify.

Use your available tools to perform the computer-side setup, download the latest published IPA and check its supplied checksum, prepare my game files, and assist with installation and transfer. Guide me through steps you cannot operate, including phone-only actions and entering credentials directly in the official signing tool. Never ask me to paste passwords or authentication codes into chat. Preserve existing saves, game files, signing identity, and bundle identifier; ask before deleting or replacing existing data. A source ZIP is not the IPA, and the public IPA needs signing for my device.

On Mac, use the project's released MCLA Game Prep app for my own Xbox 360 Complete Edition input. Locate the companion asset through the Game Prep guide: it may be in an earlier release than the IPA. On Windows or phone-only setups, follow the documented options for my actual input; explain any extraction step that requires a computer instead of promising the Mac prep tool works on Windows. Use the entire verified extraction, including every file and subfolder. Keep my original input. The supported copies need no title update; do not apply an arbitrary update or use PS3 files.

Open MCLA once, close it, then transfer the complete extraction into Files > On My iPhone/iPad > MCLA > MCLA_Game_Files. default.xex and xarchive_*.rpf must be directly inside that folder, with all remaining content beside them. Avoid an extra Documents folder, duplicate MCLA_Game_Files, or unopened archive. Wait for copying to finish and verify the layout. READY TO DRIVE confirms basic detection, not the integrity of the whole game.

Start with 30 FPS, 720p, and FSR off. Help me launch in landscape and confirm the game reaches its menu and gameplay; do not report success based only on installation or READY TO DRIVE. iOS/iPadOS 18 or newer is required, and performance depends on the device.

If launch fails, record the exact message. Use MCLA 1.0.4 or newer for the Metal deployment-target hotfix. For diagnosis, turn Graphics > Retail Mode OFF, fully close and reopen MCLA, reproduce the failure, then tap Export Logs and inspect the ZIP I provide. Trace the specific underlying error instead of assuming my archive or signing method is responsible. Finish with the verified result and any remaining action I must take.
```

### 1. Install the IPA

1. Download **MCLA-4iOS-1.0.4.ipa** from the [1.0.4 release assets](https://github.com/KoreanSeats1/MCLA-4iOS/releases/tag/v1.0.4).
2. Re-sign and install with [Sideloadly](https://sideloadly.io/) or [AltStore Classic](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos), using your own Apple account.
3. Follow the installer's trust and Developer Mode instructions if required.
4. Open MCLA once so it creates its game-data folder, then close it before transferring the game.

The public IPA is ad-hoc signed for recipient re-signing. It has no personal provisioning profile. The source ZIP, manifest and checksum file are supporting downloads, not app installers. See the [full installation guide](docs/INSTALLATION.md) for signing, updates and troubleshooting.

### 2. Prepare and transfer the complete extraction

On a Mac, download **MCLA-Game-Prep-1.0.2-macOS.zip** from the [1.0.2 release](https://github.com/KoreanSeats1/MCLA-4iOS/releases/tag/v1.0.2), unzip it and open **MCLA Game Prep.app**. Drag your Xbox 360 Complete Edition ISO, RAR/ZIP/7z of extracted files, or extracted folder onto **Drop your game here**, then click **Prepare Game Folder**. The finished folder appears beside your input. See the [Game Prep guide](docs/GAME_PREP.md) for compatibility, title updates and troubleshooting. **Windows coming soon.**

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

Use **EDIT** during gameplay to drag controls, or hold a control and pinch anywhere to resize. Double-tap a palette item to add it; double-tap a deployed optional item to return it to the palette. Choose **DONE** to drive. Changes save automatically. **Driving Controls → Reset touch layout** restores the default for the selected layout.

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
- [Game Prep guide](docs/GAME_PREP.md)
- [1.0.2 release notes](docs/releases/1.0.2.md) and [validation](docs/releases/1.0.2-validation.md)
- [1.0.1 release notes](docs/releases/1.0.1.md) and [validation](docs/releases/1.0.1-validation.md)
- [1.0 release notes](docs/releases/1.0.md) and [validation](docs/releases/1.0-validation.md)

Clone recursively and apply the tracked patches against the pinned dependency revisions. The source excludes original game data and generated AOT/shader caches. A fresh source ZIP alone is not a turnkey build; staged user-owned inputs are required. The public IPA includes compiled application code and shader libraries, with notices and SHA-256 checksums.

## Credits and license

App icon provided by **Ricioly**.

Thanks to **mzzvxm/LARecomp**, **BadassBaboon**, **Graine25**, **Foxxyyy**, **ReXGlue**, **LibertyRecomp/Theft4**, **Xenia/XeniOS**, **XenosRecomp**, **AMD/GPUOpen** and all upstream contributors. **KoreanSeats1** maintains this iOS adaptation. Rockstar San Diego created the original game.

[Full credits](CREDITS.md) · [GPL-3.0 project license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md).

Dependencies retain their own terms. This project is unofficial and unaffiliated with Rockstar. No license to original game content is granted.
