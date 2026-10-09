#!/usr/bin/env python3
"""Compile real Metal libraries and test the shipping deployment-target gate."""
from pathlib import Path
import os
import plistlib
import subprocess
import tempfile
from mcla_metal_target import METAL_DEPLOYMENT_FLAGS, validate_library, version_tuple
from verify_mcla_metal_targets import verify_app

env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
with tempfile.TemporaryDirectory(prefix='mcla-metal-target-test-') as tmp:
    tmp = Path(tmp)
    source = tmp/'test.metal'
    source.write_text('#include <metal_stdlib>\nusing namespace metal;\n'
                      'kernel void test(device uint* value [[buffer(0)]], uint i [[thread_position_in_grid]]) { value[i] = i; }\n')
    def compile_library(name, flags):
        air = tmp/(name+'.air')
        lib = tmp/(name+'.metallib')
        subprocess.run(['xcrun', '--sdk', 'iphoneos', 'metal', '-std=metal3.1',
            '-fmodules-cache-path=/private/tmp/mcla-metal-module-cache', *flags,
            '-c', str(source), '-o', str(air)], check=True, env=env)
        subprocess.run(['xcrun', '--sdk', 'iphoneos', 'metal', *flags,
            str(air), '-o', str(lib)], check=True, env=env)
        return lib.read_bytes()
    compatible = compile_library('ios18', METAL_DEPLOYMENT_FLAGS)
    assert validate_library(compatible) == ['18.0.0']
    try:
        validate_library(compatible, '17.0')
    except ValueError:
        pass
    else:
        raise AssertionError('Too-new Metal target was accepted')
    app = tmp/'Test.app'
    app.mkdir()
    (app/'Info.plist').write_bytes(plistlib.dumps({'MinimumOSVersion':'18.0'}))
    (app/'MCLAFsr.metallib').write_bytes(compatible)
    assert verify_app(app) == 1
    default = compile_library('sdk-default', [])
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], env=env, text=True).strip()
    if version_tuple(sdk) > version_tuple('18.0'):
        (app/'MCLAFsr.metallib').write_bytes(default)
        try:
            verify_app(app)
        except RuntimeError as error:
            assert 'above app minimum' in str(error)
        else:
            raise AssertionError('SDK-default regression was accepted')
    for invalid in [b'', b'MTLB-no-verifiable-target', b'not-a-library']:
        try:
            validate_library(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError('Unverifiable library was accepted')
print('PASS: real iOS 18 library accepted; newer/default-SDK targets and unverifiable libraries rejected')
