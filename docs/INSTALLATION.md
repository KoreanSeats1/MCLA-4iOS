# Installation and game-file transfer

[Back to the README](../README.md)

## Detailed installation

### Option A: Sideloadly on macOS or Windows

Use the official [Sideloadly website](https://sideloadly.io/) and [FAQ](https://sideloadly.io/faq.html). Avoid repackaged downloads that request unrelated configuration profiles.

1. Download Sideloadly from its official website and install its current macOS/Windows prerequisites. On Windows, follow Sideloadly's own Apple driver/iTunes/iCloud requirements; the Apple Devices file-transfer instructions below are a separate step.
2. Download **MCLA-4iOS-1.0.2.ipa** from the release's **Assets** list. Keep it as an IPA. The source ZIP, checksum file and JSON manifest are not the app installer.
3. Connect your iPhone/iPad by USB, unlock it and accept **Trust This Computer** if prompted. Confirm the device appears in Sideloadly.
4. Select that device in Sideloadly. Drag the IPA onto its IPA area, or use the IPA selector to choose it.
5. Use the normal Apple-ID signing workflow, enter your Apple account and start installation. Complete any authentication prompts in the tool. Keep the same account and bundle identifier for future updates.
6. Wait until Sideloadly reports completion and the MCLA icon appears on the device. Installation places the app on the device; **it does not install the game files**.
7. If iOS asks you to trust the developer, open **Settings → General → VPN & Device Management**, select the development-app entry associated with your signing account and complete the trust prompt. This entry depends on the signing method; it may not appear for every installer.
8. If Developer Mode is required, open **Settings → Privacy & Security → Developer Mode**, enable it, restart when requested and confirm after restart. Follow Apple's [Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device). If the setting is absent, finish the development-app installation first.
9. Open **MCLA** once. The app automatically creates its game folder and may display **Filesystem created**. Dismiss the message. **WAITING FOR GAME DATA** is expected at this stage.
10. Close MCLA before transferring the game files. Continue with the folder instructions below.

A free account generally has short-lived signing and app-count limits; a paid account has different limits. Follow the signing tool's current documentation rather than assuming the app never needs refreshing. The release intentionally has no personal provisioning profile: your sideloading tool must sign it for your device.

### Option B: AltStore Classic

Follow the official [AltStore Classic installation guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos) for your platform. **AltStore Classic** is the relevant product for importing an arbitrary IPA; do not assume AltStore PAL is an equivalent installation route.

After AltStore Classic and AltServer are configured, download the IPA to Files, import it from AltStore's My Apps screen, and let AltStore sign/install it. Keep AltServer available as required for refreshing. Free-account restrictions include a small active-app limit; see [AltStore's app activation documentation](https://faq.altstore.io/altstore-classic/activating-apps). The game-data copy is a separate step after installation.

These are documented signing routes, not evidence that every signing-tool version has been tested against this beta. Report installation failures with the tool/version and the actual error.

### Prepare the game files on your computer

**Mac:** [MCLA Game Prep](GAME_PREP.md) prepares your Xbox 360 Complete Edition ISO, RAR/ZIP/7z containing extracted files, or existing game folder. Download the Mac ZIP from the release, open the app, drag one input into the cyan area and click **Prepare Game Folder**. Copy its completed `MCLA_Game_Files` output using the routes below. No title update is required for the supported copies. **Windows coming soon.** The companion requires macOS 13+ and supports Apple silicon and Intel.

The instructions below also apply when preparing the folder manually.

You need your own **extracted Xbox 360 Complete Edition** copy. The app does not download the game or extract an ISO. A `.iso`, `.zip`, `.7z` or PS3 folder cannot be launched directly. A ZIP can be used for transport only; it must be unpacked before play.

1. Open your extracted game folder on the computer.
2. Find the directory that directly contains **`default.xex`** and the **`xarchive_*.rpf`** files. If they are inside another directory, open that directory first.
3. Preserve **all** files and subfolders from that directory, with their original names and relative paths. The five files below are readiness checks, not the complete game.
4. For a whole-folder transfer, name the containing folder exactly **`MCLA_Game_Files`**. For a contents transfer, copy everything inside it into the app's existing folder of that name.

### Exact destination on the iPhone/iPad

**Files → Browse → On My iPhone / On My iPad → MCLA → MCLA_Game_Files**

The internal path is **the MCLA app's `Documents/MCLA_Game_Files/`**. Files displays the app's Documents directory as **MCLA**; you do **not** create another folder called `Documents` inside it. On some file-sharing lists the app may be shown as MCLAApp.

```text
Files → On My iPhone / On My iPad
└── MCLA                         ← the app's Documents location
    └── MCLA_Game_Files
        ├── default.xex          ← directly inside this folder
        ├── xarchive_audio.rpf
        ├── xarchive_audlo.rpf
        ├── xarchive_cache.rpf
        ├── xarchive_music.rpf
        └── …ALL remaining extracted files and subfolders…
```

Wrong layouts include:

```text
MCLA/default.xex                             ← outside the game folder
MCLA/Documents/MCLA_Game_Files/default.xex    ← extra Documents directory
MCLA/MCLA_Game_Files/MCLA_Game_Files/default.xex ← duplicated game folder
MCLA/MCLA_Game_Files/My Game/default.xex      ← extra extraction directory
MCLA/MCLA_Game_Files/game.iso                ← not extracted
```

### Transfer from a Mac with Finder

1. Open MCLA once on the device so its folder exists, then close it.
2. Connect by USB, unlock the device, and trust the computer if prompted.
3. Open Finder, select the device under **Locations**, then choose **Files**.
4. Find MCLA and expand its entry to see shared documents. This view represents the app's Documents location.
5. Drag the complete computer folder named **MCLA_Game_Files** onto the MCLA app entry. If a same-name folder prompts for replacement, proceed only for a new installation with an empty destination; back up existing content first.
6. Keep the device connected until copying finishes. Open Files on the device and verify the destination layout above.

If Finder will not transfer a folder or cannot merge into the existing folder, use the ZIP transport method below instead. Finder file sharing is documented by [Apple](https://support.apple.com/en-us/119585).

### Transfer from Windows with Apple Devices

Apple Devices' **Add File** action copies files into an app's shared documents. To preserve a large game folder and its subfolders, use a ZIP as a transport container:

1. On the PC, make **MCLA-transfer.zip** from your complete extracted game directory. This is a transport copy; retain your original extraction.
2. Connect/unlock the device, open **Apple Devices**, select the device, then **Files → MCLA**.
3. Click **Add File**, select `MCLA-transfer.zip` and complete the copy. Wait for the transfer to finish.
4. On the device, open **Files → Browse → On My iPhone/iPad → MCLA**. The ZIP should be here, beside `MCLA_Game_Files`.
5. Tap the ZIP to unpack it. Follow the ZIP placement steps below; the extracted folder's name can depend on how you created the archive.

Allow space for both the ZIP and unpacked game. This route uses [Apple's documented file-sharing interface](https://support.apple.com/en-us/120402); it is not an in-app game importer.

### Place unpacked files using the device's Files app

These steps also work when your extracted folder arrived through iCloud Drive, an external drive or another Files location.

1. If using a ZIP, tap it in Files to extract it. Open the resulting folder, then any enclosing folders, until **you can see `default.xex` directly**.
2. In that directory, use **… → Select**, select **every file and subfolder**, then choose **Move**. Do not select only the XEX or the five readiness-check archives.
3. Browse to **On My iPhone/iPad → MCLA → MCLA_Game_Files** and move the selected contents into that directory. If using Copy instead, open this directory and paste the contents there. Do not paste the enclosing game folder inside it.
4. Open `MCLA_Game_Files` and confirm `default.xex` and the archive files are immediately visible, with the remaining extracted content beside them.
5. Once verified, the transport ZIP and empty staging folder can be removed to recover space. Keep your computer's original extraction/backup.

If **MCLA** is not visible, launch the installed app once, close it, and return to **Files → Browse → On My iPhone/iPad**. Downloads and iCloud Drive are staging locations; files left there are not in the game's active directory.

### Verify the copy and launch

1. Wait for all transfer/extraction activity to finish. Do not launch while archives are still copying.
2. Reopen MCLA. With the core files detected and the renderer available, the launcher displays **READY TO DRIVE**.
3. Configure controls and graphics, then use the launch button. Start with standard 30 FPS; enable experimental 60 FPS before launch if desired.
4. If it still says **WAITING FOR GAME DATA**, inspect the exact folder layout. Common causes are an extra parent folder, a duplicate `MCLA_Game_Files`, a compressed/unextracted game, or files copied into Downloads rather than MCLA.
5. If detection succeeds but later content is missing or launch fails, confirm the **entire** extraction copied successfully and that its Xbox 360 Complete Edition revision matches the supported baseline. Filename detection does not validate every archive's integrity.

The game folder belongs in the app's Documents storage, not inside the IPA, app bundle, saves folder or diagnostic folder. Reinstalling after deleting MCLA can remove that storage; export saves and keep a separate game-file backup before doing so.

### Controls, saves and updates

Pair your controller through iOS, then configure the launcher's Controls panel before starting. The host uses Apple's GameController framework and maps controls into the title's guest input contract. Touch controls can be repositioned/resized, and tilt steering has enable/invert preferences. Your saved layouts are independent of the renderer defaults.

The launcher has save-management actions, including export/import. **Export a backup before changing signing identity, deleting the app, or installing a substantially different build.** Imported backups can replace current saves only after the UI's confirmation. Changing an app's bundle identifier normally creates a different container; deleting the app can remove its game folder and saves. An update installed over the same signed app is preferable to uninstalling first. Do not upload your entire game folder with bug reports.

