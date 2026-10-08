#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${1:-$ROOT/artifacts/MCLA Game Prep.app}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mcla-prep-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$WORK/cache"
for ARCH in arm64 x86_64; do
    xcrun swiftc -O -runtime-compatibility-version none -target "$ARCH-apple-macosx13.0" -module-cache-path "$WORK/cache" "$ROOT/tools/mac-game-preparer/GameData.swift" "$ROOT/tools/mac-game-preparer/ISODropZone.swift" "$ROOT/tools/mac-game-preparer/GameInput.swift" "$ROOT/tools/mac-game-preparer/main.swift" -larchive.2 -o "$WORK/prep-$ARCH"
done
xcrun lipo -create "$WORK/prep-arm64" "$WORK/prep-x86_64" -output "$DEST/Contents/MacOS/MCLA Game Prep"
xcrun swiftc -module-cache-path "$WORK/cache" "$ROOT/tools/mac-game-preparer/PackIcon.swift" -o "$WORK/icon"
"$WORK/icon" "$ROOT/tools/mac-game-preparer/IconArtwork.png" "$DEST/Contents/Resources/AppIcon.icns"
cp "$ROOT/MCLAApp/Resources/GameDataManifest.json" "$DEST/Contents/Resources/"
cat > "$DEST/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MCLA Game Prep</string>
<key>CFBundleIdentifier</key><string>com.mcla.gameprep</string>
<key>CFBundleName</key><string>MCLA Game Prep</string>
<key>CFBundleDisplayName</key><string>MCLA Game Prep</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.2</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$DEST"
printf 'Built %s\n' "$DEST"
