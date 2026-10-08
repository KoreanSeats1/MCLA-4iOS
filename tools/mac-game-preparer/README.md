# MCLA Game Prep for Mac

A standalone native macOS 13+ app for Apple silicon and Intel. It needs no Python, Homebrew, ISO mounting, network connection, or game content in its bundle.

1. Copy `MCLA Game Prep.app` beside your own Xbox 360 **Midnight Club: Los Angeles — Complete Edition (USA / NTSC-U)** ISO or game archive. The main screen shows this expected edition and region.
2. Open the app and drag one ISO, RAR, ZIP, 7z or extracted folder onto the large **Drop your game here** area. It highlights while dragging and confirms **Game selected** after the drop. You can also click this area or use **Choose Game…**. With one ISO beside the app, it selects that file automatically.
3. Click **Prepare Game Folder**. The output is `MCLA_Game_Files` beside the selected input.
4. Copy that entire folder into **Files → On My iPhone/iPad → MCLA**, with the iOS app closed. Do not nest it inside another `Documents` folder.

The app checks the ISO's XDVDFS structure, required archives, Xbox title ID `545407F8`, media ID and SHA-256 from the iOS project's `GameDataManifest.json`. It supports raw Xbox disc images at the common full-disc partition offsets and game-partition-only images. This identifies the recorded supported executables; it does not promise gameplay correctness. Unsupported executables stop before extraction. A PS3 ISO containing PS3 disc metadata receives a specific platform error: extraction cannot convert it into compatible Xbox files. No title update is required or applied.

All files and folders are extracted, including movies and empty files. Filenames are normalized to lowercase for the iOS app's expected paths. Extraction uses bounded memory and a temporary folder. Cancellation and errors remove that folder, and the final folder appears only after completion. Existing `MCLA_Game_Files` folders are never overwritten. `PREPARATION.txt` inside the result contains verification and transfer information.

## Build

From the repository root with Apple Command Line Tools installed:

```sh
./tools/mac-game-preparer/build.sh
```

Default output: `artifacts/MCLA Game Prep.app`. Supply an optional output path as the first argument. The build embeds the current iOS manifest and packages the generated road/disc/download artwork as a multi-resolution Mac icon using AppKit. The universal binary is ad-hoc signed for local use, not Developer ID signed or notarized for public distribution. For a downloaded copy, macOS may require **Open Anyway** in Privacy & Security.

## Tests

Synthetic disc fixtures contain no game content:

```sh
xcrun swiftc -module-cache-path /tmp/mcla-test-cache \
  tools/mac-game-preparer/GameData.swift tools/mac-game-preparer/GameInput.swift tools/mac-game-preparer/test.swift \
  -larchive.2 -o /tmp/mcla-prep-tests
/tmp/mcla-prep-tests
```

Checks extraction bytes, nested folders, case normalization, compatibility rejections, malformed directory cycles, unsafe names, truncated files, existing-output preservation, and cleanup after cancellation.

Drop-input and PS3 detection checks:

```sh
xcrun swiftc -module-cache-path /tmp/mcla-test-cache \
  tools/mac-game-preparer/GameData.swift tools/mac-game-preparer/GameInput.swift tools/mac-game-preparer/ISODropZone.swift \
  tools/mac-game-preparer/test_drop.swift -larchive.2 -o /tmp/mcla-drop-tests
/tmp/mcla-drop-tests
```

The fingerprint for media ID `0F1CB201`, header version `0.0.0.13`, is also accepted: its entire program payload and loading configuration match the baseline, with header-only differences. No title update is applied. This establishes executable equivalence, not a physical-device gameplay test. Archive parsing uses macOS libarchive; no extra software is installed.

Archive safety tests (synthetic fixtures):

```sh
python3 tools/mac-game-preparer/archive_fixtures.py /tmp/mcla-archive-fixtures
xcrun swiftc -module-cache-path /tmp/mcla-test-cache \
  tools/mac-game-preparer/GameData.swift tools/mac-game-preparer/GameInput.swift \
  tools/mac-game-preparer/test_archive.swift -larchive.2 -o /tmp/mcla-archive-tests
/tmp/mcla-archive-tests /tmp/mcla-archive-fixtures
```

Archives or folders containing a `default.xexp` title-update patch are rejected until that patch is verified against the compiled iOS game code.
