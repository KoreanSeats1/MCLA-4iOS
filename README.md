<p align="center"><img src="docs/images/app-icon.png" width="160" alt="MCLA 4iOS app icon"></p>
<h1 align="center">MCLA 4iOS</h1>
<p align="center">Midnight Club: Los Angeles — Complete Edition on iPhone and iPad<br><strong>0.1.0 · Initial beta</strong></p>
<p align="center"><a href="https://github.com/KoreanSeats1/MCLA-4iOS/releases/tag/v0.1.0">Download IPA</a> · <a href="https://youtu.be/zmHd-WfsaX4">Gameplay video</a> · <a href="docs/KNOWN_BUGS.md">Known bugs</a></p>

An unofficial iOS port built on LARecomp, with native Metal rendering, controller/touch support and an experimental 60 FPS patch.

**No game files are included. You need your own extracted Xbox 360 Complete Edition copy.**

## What you need

- iOS/iPadOS **18 or newer**.
- Your own extracted **Midnight Club: Los Angeles — Complete Edition for Xbox 360**.
- Enough storage for the app and the complete game folder.
- Sideloadly or AltStore Classic to install the IPA.

Built and tested for **iPhone Air and M5 iPad Pro**. Playable performance is expected on iPhone 15 Pro or newer, but other models are untested. Settings and heat affect performance—YMMV.

## Detailed installation

### 1. Install the app

1. Download **MCLA-4iOS-0.1.0.ipa** from the [release assets](https://github.com/KoreanSeats1/MCLA-4iOS/releases/tag/v0.1.0).
2. Install it with [Sideloadly](https://sideloadly.io/) or [AltStore Classic](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos), using your own Apple account.
3. Follow the installer's prompts to trust the app and enable Developer Mode if required.
4. Open MCLA once. It creates the game folder automatically. Close it before copying files.

Need help signing? See the [step-by-step installation guide](docs/INSTALLATION.md).

### 2. Add your game files

Put **all extracted files and subfolders** here:

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

`default.xex` must be directly inside `MCLA_Game_Files`. Copy the whole extraction, not just the five files shown. Don't add another `Documents` folder or nest a second `MCLA_Game_Files` inside it. An ISO or unopened ZIP will not work.

- **Mac:** Finder → your device → Files → MCLA. Drag in the complete folder named `MCLA_Game_Files`.
- **Windows:** Apple Devices → your device → Files → MCLA. Use **Add File** to transfer a ZIP of your extraction, then unpack it in the device's Files app and move its contents into `MCLA_Game_Files`.
- **Files app:** open your extracted game folder, select everything inside it and move it into the destination above.

For ZIP transfers, leave room for both the ZIP and unpacked files. Full instructions: [Mac](docs/INSTALLATION.md#transfer-from-a-mac-with-finder) · [Windows](docs/INSTALLATION.md#transfer-from-windows-with-apple-devices) · [Files app](docs/INSTALLATION.md#place-unpacked-files-using-the-devices-files-app).

### 3. Play

Wait for the copy to finish, reopen MCLA and look for **READY TO DRIVE**. Choose your controls/settings, then launch.

Still seeing **WAITING FOR GAME DATA**? Check that `default.xex` is directly in the correct folder and that the files are fully extracted and copied. If launch fails after detection, check that you copied the entire supported Complete Edition extraction.

## Settings and performance

- **30 FPS** is the default. Enable **Graphics → Experimental → Native 60 FPS** before launching to try 60 FPS. This uses real rendered frames; it is not frame generation.
- Scene resolution, FSR upscaling, filtering and bloom are adjustable.
- Motion blur and depth of field have separate disable switches. Depth of field is enabled by default.
- Turn **Retail Mode on** for play without diagnostic logging or captures.
- Controllers, touch controls and tilt steering are supported.

Export a save backup before deleting the app or changing your signing account. Deleting MCLA can also delete its game files and saves. Keep the same signing account and bundle identifier when updating.

## Known bugs

This is an early beta. Blue distant light glows, missing shaders/effects, road flicker, checkpoint smoke/colors and some fades still need work. A new-game ride-height issue was also reported. Experimental 60 FPS needs more physics and warm-device testing.

See the [full known-bugs list](docs/KNOWN_BUGS.md). Report problems through [GitHub Issues](https://github.com/KoreanSeats1/MCLA-4iOS/issues/new/choose), with your device, OS, settings and steps to reproduce. Don't upload game files or signing credentials.

## Credits, attribution and license

Huge thanks to **mzzvxm/LARecomp**, **BadassBaboon**, **Graine25**, **Foxxyyy**, **ReXGlue**, **LibertyRecomp/Theft4**, **Xenia/XeniOS**, **XenosRecomp**, **AMD/GPUOpen** and all upstream contributors. **KoreanSeats1** maintains this iOS adaptation. Rockstar San Diego created the original game.

[Full credits and developer links](CREDITS.md) · [License](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)

Project-authored code uses GPL-3.0; dependencies retain their own terms. This unofficial project is not affiliated with Rockstar. No license to the original game content is granted.

## Technical details and building

[Technical notes and 60 FPS patch](docs/TECHNICAL_NOTES.md) · [Developer/build guide](docs/DEVELOPMENT.md) · [Release validation](docs/releases/0.1.0-validation.md)

The source requires your own game inputs and generated build files. It is not yet a one-command build; use the release IPA to install and play.
