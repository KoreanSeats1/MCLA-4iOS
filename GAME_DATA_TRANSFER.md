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

1. Sideload the release IPA, or build and install MCLA from the device Xcode project.
2. Connect the device to the Mac and open Finder.
3. Select the device, then **Files**, then the **MCLA** app.
4. Drag the complete folder into the app and keep its name exactly
   `MCLA_Game_Files`.
5. Relaunch MCLA. The shell should report `GAME DATA READY`.

The app enables iOS File Sharing and opening documents in place. Game data is
never compiled into or signed inside the application.
