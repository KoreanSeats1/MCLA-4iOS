"""Shared deployment policy for every offline MCLA Metal library."""
import re

MINIMUM_IOS = '18.0'
METAL_DEPLOYMENT_FLAGS = [f'-mios-version-min={MINIMUM_IOS}']
# Include the target in title-shader stamps so SDK-default libraries cannot be reused.
METAL_CACHE_POLICY = f'mcla-metal-v2-ios{MINIMUM_IOS}-metal3.1\n'


def version_tuple(value):
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (3 - len(parts))


def validate_library(data, minimum_ios=MINIMUM_IOS):
    if not data.startswith(b'MTLB'):
        raise ValueError('not a Metal library')
    targets = re.findall(rb'air64(?:_v\d+)?-apple-ios(\d+\.\d+(?:\.\d+)?)', data)
    if not targets:
        raise ValueError('no verifiable iOS AIR deployment target')
    versions = sorted(set(target.decode('ascii') for target in targets))
    too_new = [version for version in versions if version_tuple(version) > version_tuple(minimum_ios)]
    if too_new:
        raise ValueError(f'Metal targets iOS {", ".join(too_new)}, above app minimum {minimum_ios}')
    return versions
