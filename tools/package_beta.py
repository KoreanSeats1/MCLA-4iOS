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
    parser.add_argument('--output', type=Path, default=ROOT/'releases/0.1.0')
    args = parser.parse_args()
    app, output = args.app.resolve(), args.output.resolve()
    info = plistlib.loads((app/'Info.plist').read_bytes())
    if info['CFBundleShortVersionString'] != '0.1.0':
        raise RuntimeError('Expected version 0.1.0')
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
    ipa = output/'MCLA-4iOS-0.1.0.ipa'
    archive(staging, ipa)
    with zipfile.ZipFile(ipa) as z:
        if z.testzip() is not None:
            raise RuntimeError('IPA archive integrity check failed')
    manifest = {
        'name': 'MCLA 4iOS', 'version': '0.1.0', 'build': info['CFBundleVersion'],
        'bundleIdentifier': info['CFBundleIdentifier'], 'architecture': 'arm64',
        'minimumOSVersion': info.get('MinimumOSVersion'), 'titleMetalLibraryCount': len(libraries),
        'gameDataIncluded': False, 'personalProvisioningIncluded': False,
        'signing': 'Ad-hoc; recipient must re-sign with their own account',
        'ipaSHA256': digest(ipa), 'executableSHA256': digest(target/info['CFBundleExecutable']),
    }
    metadata = output/'release-manifest.json'
    metadata.write_text(json.dumps(manifest, indent=2)+'\n')
    (output/'SHA256SUMS.txt').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in [ipa, metadata]))
    print(json.dumps(manifest, indent=2))
    print(f'Packaged {ipa.name}: {ipa.stat().st_size:,} bytes')

if __name__ == '__main__':
    main()
