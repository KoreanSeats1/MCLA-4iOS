#!/usr/bin/env python3
"""Reject offline libraries that cannot meet the packaged app's minimum iOS."""
import argparse
from pathlib import Path
import plistlib
from mcla_metal_target import validate_library


def verify_app(app):
    info = plistlib.loads((app/'Info.plist').read_bytes())
    minimum = info['MinimumOSVersion']
    libraries = sorted(app.rglob('*.metallib'))
    if not libraries:
        raise RuntimeError('No offline Metal libraries found')
    if not (app/'MCLAFsr.metallib').is_file():
        raise RuntimeError('Missing FSR library')
    failures = []
    targets = set()
    for library in libraries:
        try:
            targets.update(validate_library(library.read_bytes(), minimum))
        except ValueError as error:
            failures.append(f'{library.relative_to(app)}: {error}')
    if failures:
        raise RuntimeError('\n'.join(failures))
    print(f'PASS: all {len(libraries)} offline Metal libraries target iOS {", ".join(sorted(targets))}; app minimum {minimum}')
    return len(libraries)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    verify_app(args.app)
