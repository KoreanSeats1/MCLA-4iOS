#!/usr/bin/env python3
"""Package a verified device build for recipient re-signing; never include game data."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = {'.xex', '.rpf', '.iso', '.bik', '.mobileprovision', '.p12', '.p8', '.pem', '.key', '.cer'}

def digest(path):
    with path.open('rb') as stream:
        checksum = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(block)
        return checksum.hexdigest()

def archive(folder, output):
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for path in sorted(folder.rglob('*')):
            if path.is_symlink():
                raise RuntimeError(f'Unexpected symlink: {path.name}')
            if path.is_file():
                if path.suffix.lower() in FORBIDDEN:
                    raise RuntimeError(f'Prohibited release content: {path.name}')
                z.write(path, path.relative_to(folder))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT/'out/build/ios-device-release/Release-iphoneos/MCLAApp.app')
    parser.add_argument('--version', default='1.0', help='Expected marketing version')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--mac-applet', type=Path, help='Optional signed universal Mac preparation app')
    args = parser.parse_args()
    app = args.app.resolve()
    output = (args.output or ROOT/'releases'/args.version).resolve()
    info = plistlib.loads((app/'Info.plist').read_bytes())
    if info['CFBundleShortVersionString'] != args.version:
        raise RuntimeError(f'Expected version {args.version}')
    executable = app/info['CFBundleExecutable']
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    subprocess.run(['lipo', '-verify_arch', 'arm64', str(executable)], check=True)
    libraries = list((app/'MCLAMetalShaders').glob('*.metallib'))
    if len(libraries) != 603:
        raise RuntimeError(f'Expected 603 title libraries, found {len(libraries)}')
    output.mkdir(parents=True, exist_ok=True)
    staging = output/'staging'
    if staging.exists():
        shutil.rmtree(staging)
    payload = staging/'Payload'
    payload.mkdir(parents=True)
    target = payload/app.name
    shutil.copytree(app, target, ignore=shutil.ignore_patterns('_CodeSignature', '*.mobileprovision'))
    for path in target.rglob('*'):
        if path.suffix.lower() in FORBIDDEN or path.name in {'Documents', 'Library', 'MCLA_Game_Files'}:
            raise RuntimeError(f'Prohibited release content: {path.name}')
    notices = target/'OpenSourceNotices'
    shutil.copytree(ROOT/'licenses', notices/'licenses')
    for name in ['LICENSE', 'CREDITS.md', 'THIRD_PARTY_NOTICES.md']:
        shutil.copy2(ROOT/name, notices/name)
    subprocess.run(['codesign', '--remove-signature', str(target)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(target)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(target)], check=True)
    ipa = output/f'MCLA-4iOS-{args.version}.ipa'
    archive(staging, ipa)
    with zipfile.ZipFile(ipa) as z:
        if z.testzip() is not None:
            raise RuntimeError('IPA archive integrity check failed')
    manifest = {
        'name': 'MCLA 4iOS', 'version': args.version, 'build': info['CFBundleVersion'],
        'bundleIdentifier': info['CFBundleIdentifier'], 'architecture': 'arm64',
        'minimumOSVersion': info.get('MinimumOSVersion'), 'titleMetalLibraryCount': len(libraries),
        'gameDataIncluded': False, 'personalProvisioningIncluded': False,
        'signing': 'Ad-hoc; recipient must re-sign with their own account',
        'ipaSHA256': digest(ipa), 'executableSHA256': digest(target/info['CFBundleExecutable']),
        'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    }
    assets = [ipa]
    if args.mac_applet:
        mac_app = args.mac_applet.resolve()
        mac_info = plistlib.loads((mac_app/'Contents/Info.plist').read_bytes())
        if mac_info['CFBundleShortVersionString'] != args.version:
            raise RuntimeError('Mac applet release version mismatch')
        mac_executable = mac_app/'Contents/MacOS'/mac_info['CFBundleExecutable']
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(mac_app)], check=True)
        for architecture in ['arm64', 'x86_64']:
            subprocess.run(['lipo', '-verify_arch', architecture, str(mac_executable)], check=True)
        mac_staging = output/'mac-staging'
        if mac_staging.exists():
            shutil.rmtree(mac_staging)
        mac_staging.mkdir()
        shutil.copytree(mac_app, mac_staging/mac_app.name)
        shutil.copy2(ROOT/'docs/GAME_PREP.md', mac_staging/'GAME_PREP.md')
        shutil.copy2(ROOT/'docs/INSTALLATION.md', mac_staging/'INSTALLATION.md')
        shutil.copy2(ROOT/'LICENSE', mac_staging/'LICENSE')
        (mac_staging/'START-HERE.txt').write_text(
            f'MCLA Game Prep {args.version} for Mac\n\n'
            'Requires macOS 13+, Apple silicon or Intel. Windows coming soon.\n'
            'Open MCLA Game Prep.app. Drag one Xbox 360 Midnight Club: Los Angeles '
            'Complete Edition ISO, RAR, ZIP, 7z or extracted game folder into the cyan area. '
            'Click Prepare Game Folder and wait for the ready message.\n\n'
            'The complete MCLA_Game_Files output appears beside your input. '
            'Copy the entire folder into Files > On My iPhone/iPad > MCLA, '
            'with the iOS app closed. default.xex belongs directly inside MCLA_Game_Files. '
            'Do not add another Documents folder.\n\n'
            'Install the release IPA separately with your own signing account. '
            'Game files are not included. Supported copies need no title update. '
            'PS3 copies and unverified executable/update patches are incompatible. '
            'Existing output folders are never overwritten.\n\n'
            'The Mac app is ad-hoc signed, not notarized. macOS may require Open Anyway '
            'under Privacy & Security. See GAME_PREP.md for full instructions.\n'
            f'https://github.com/KoreanSeats1/MCLA-4iOS/releases/tag/v{args.version}\n')
        mac_zip = output/f'MCLA-Game-Prep-{args.version}-macOS.zip'
        archive(mac_staging, mac_zip)
        with zipfile.ZipFile(mac_zip) as z:
            if z.testzip() is not None:
                raise RuntimeError('Mac archive integrity check failed')
        manifest['macGamePrep'] = {
            'version': args.version, 'build': mac_info['CFBundleVersion'],
            'architectures': ['arm64', 'x86_64'],
            'minimumOSVersion': mac_info['LSMinimumSystemVersion'],
            'signing': 'Ad-hoc; not Developer ID signed or notarized',
            'asset': mac_zip.name, 'sha256': digest(mac_zip),
            'executableSHA256': digest(mac_executable), 'windows': 'Coming soon',
        }
        assets.append(mac_zip)
    manifest['compatibleGameExecutables'] = json.loads(
        (target/'GameDataManifest.json').read_text())
    metadata = output/'release-manifest.json'
    metadata.write_text(json.dumps(manifest, indent=2)+'\n')
    (output/'SHA256SUMS.txt').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in [*assets, metadata]))
    print(json.dumps(manifest, indent=2))
    print(f'Packaged {ipa.name}: {ipa.stat().st_size:,} bytes')

if __name__ == '__main__':
    main()
