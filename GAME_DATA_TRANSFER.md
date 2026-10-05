# MCLA game-data preparation

Prepare your own extracted Complete Edition folder as `MCLA_Game_Files`.
No game content is copied into the source tree or app bundle.

## Core launch set

The app checks for these files inside `Documents/MCLA_Game_Files/`:

```text
default.xex
xarchive_audio.rpf
xarchive_audlo.rpf
xarchive_cache.rpf
xarchive_music.rpf
```

The recorded `default.xex` baseline is Xbox 360 title `TT-2040`, media ID
`5940C9DB`, all regions, with SHA-256:

```text
c386f4001fa569e6ad4b982f441f67412f00b3f47c166134555cd4b59854a432
```

Validate the source folder at any time:

```sh
./tools/validate_game_data.sh \
  "/path/to/your/extracted/MCLA_Game_Files"
```

## Recommended complete set

Copy the entire extracted folder for real game bring-up, not only the five core
files. That preserves the intro/attract Bink movies, `nxeart`, and the padding
file in case the title opens them later.

## Physical iPhone or iPad

Follow the [step-by-step installation and transfer guide](README.md#detailed-installation) for Sideloadly/AltStore, Mac Finder, Windows Apple Devices and on-device Files.

The exact visible destination is:

**Files → Browse → On My iPhone / On My iPad → MCLA → MCLA_Game_Files**

The app creates this directory automatically on first launch. The MCLA location in Files already represents its Documents directory: do not add a second Documents directory. `default.xex` must be directly inside `MCLA_Game_Files`, alongside all extracted archives and original subfolders. A ZIP/ISO left there is not a prepared game.

Keep the app closed while copying, and reopen after transfer completes. With the core files detected and Metal available, the launcher shows **READY TO DRIVE**. Copying only the five readiness-check files does not supply all game content.

The app enables iOS File Sharing and opening documents in place. Game data is never compiled into or signed inside the application.
