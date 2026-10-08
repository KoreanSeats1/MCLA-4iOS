# MCLA Game Prep for Mac

Download **MCLA-Game-Prep-1.0.2-macOS.zip** from the [1.0.2 release](https://github.com/KoreanSeats1/MCLA-4iOS/releases/tag/v1.0.2). This companion app prepares your own Xbox 360 game files for MCLA 4iOS. **Windows coming soon.**

## What you need

- macOS 13 or newer, on Apple silicon or Intel.
- Your own **Midnight Club: Los Angeles — Complete Edition for Xbox 360**, expected USA / NTSC-U edition.
- A raw disc ISO, game-partition ISO, RAR/ZIP/7z containing an extracted game folder, or an already extracted folder.
- Enough free space for the complete extracted game while retaining the input.

The app is standalone: no Python, Homebrew, extra extractor, ISO mounting or network connection is needed. The release contains no original game files. A PS3 release cannot be converted into Xbox 360 files.

## Prepare your game

1. Unzip the Mac download and open **MCLA Game Prep.app**. You can put it beside your ISO; if exactly one ISO is present, the app selects it automatically. You can also run it from another directory.
2. Drag **one ISO, RAR, ZIP, 7z or extracted folder** onto the cyan **Drop your game here** area. Alternatively, click the area or **Choose Game…**. Check the displayed path; **Game selected** confirms the choice.
3. Click **Prepare Game Folder**. For an ISO, the app reads the Xbox disc filesystem directly. For an archive, it unpacks the extracted game folder. For a folder, it copies and normalizes the files.
4. Wait for **Verified executable. MCLA_Game_Files is ready to copy.** Use **Show in Finder** to locate the output beside your selected input.
5. Copy the entire output folder to your iPhone/iPad as described below. Keep all movies and other files, not just the five required files.

If an archive contains an ISO rather than extracted game files, unpack that archive first and drop the ISO into the app. An extracted game folder must contain `default.xex` directly inside it; an archive may wrap that folder in one parent directory.

The app never overwrites an existing `MCLA_Game_Files` folder. Move an old output aside before preparing another copy. **Cancel** stops preparation and removes unfinished staging data. The final folder appears only after validation completes. Filenames are normalized to lowercase, and `PREPARATION.txt` records the executable identity and transfer instructions.

The Mac app is ad-hoc signed, not Developer ID signed or notarized. macOS may require **Open Anyway** under Privacy & Security for a downloaded copy.

## Install the IPA and transfer the result

1. Download **MCLA-4iOS-1.0.2.ipa** from the same release. Re-sign and install it with your own Apple account using your sideloading tool. iOS/iPadOS 18.0 or newer is required. The public IPA contains no personal provisioning profile.
2. Open MCLA once so it creates its game-data location, then close it.
3. On a Mac, connect and unlock the device, open **Finder → device → Files → MCLA**, and drag in the complete `MCLA_Game_Files` folder. You can also use the device's Files app to place it here:

   **Files → Browse → On My iPhone/iPad → MCLA → MCLA_Game_Files**

```text
MCLA/
└── MCLA_Game_Files/
    ├── default.xex
    ├── xarchive_audio.rpf
    ├── xarchive_audlo.rpf
    ├── xarchive_cache.rpf
    ├── xarchive_music.rpf
    └── all other extracted files and folders
```

Do not add another `Documents` folder or nest a second `MCLA_Game_Files`. Wait for the transfer to finish, then open MCLA and look for **READY TO DRIVE**. See [installation and update instructions](INSTALLATION.md) for signing, saves and file sharing.

## Compatibility and title updates

The prep app checks Xbox title ID `545407F8`, media ID, an exact SHA-256 executable fingerprint and required game archives. The supported executable profiles are:

| Media ID | Header version | Support |
|---|---|---|
| `5940C9DB` | `0.0.0.8` | Recorded iOS bring-up baseline |
| `0F1CB201` | `0.0.0.13` | Verified identical program payload and loading configuration |

The second profile has different header metadata, but its complete program payload, entry point, encryption/compression configuration and import addresses match the code compiled into our iOS app. Its audio/music archives and movies match the existing copy. The cache archive uses the same entries and directory structure; a small number of asset payloads differ. Preparation and static compatibility passed on a real RAR package. **Physical-device gameplay with that alternate copy has not been tested.**

No title update is needed or applied for these supported copies. An unverified `default.xexp` update patch stops preparation. A matching game name, title ID or version number alone is not sufficient: any future update must match both the disc and the compiled iOS code. An unrelated GTA IV title update cannot be used for MCLA.

## If preparation stops

| Message or symptom | What to do |
|---|---|
| PlayStation 3 release | Supply the Xbox 360 Complete Edition instead. |
| Executable has not been verified | Use a supported disc copy; do not rename files or apply an arbitrary update to bypass the check. |
| Missing required game file | Supply the full extraction or an intact Xbox ISO. |
| Existing output folder | Move the old `MCLA_Game_Files` aside and retry. |
| Damaged archive, unsafe path, links or duplicate filenames | Use a complete, clean archive of your own game files. |
| Not enough space | Free enough space for the complete unpacked game and retry. |

**Windows coming soon:** this release ships the Mac preparation app only. Existing Windows IPA signing and device file-transfer routes remain documented in the installation guide.
