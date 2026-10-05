#!/usr/bin/env python3
"""Offline Metal compilation of the foundation's AMD FSR 1 EASU/RCAS.
SPIRV-Cross is a build tool only; the app loads plain Metal libraries.
"""
from pathlib import Path
import os, subprocess
from mcla_fsr_optimize import optimize_easu
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/mcla-metal-upscale'
OUT.mkdir(parents=True,exist_ok=True)
ENV=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
airs=[]
for part,entry in [('easu','mclaFsrEasu'),('rcas','mclaFsrRcas')]:
    reference=OUT/(part+'-reference.metal')
    source=OUT/(part+'.metal')
    air=OUT/(part+'.air')
    subprocess.run([str(ROOT/'tools/build-metal-upscale/spirv-cross'),
        str(ROOT/f'artifacts/mcla-fsr-{part}.spv'),'--msl','--msl-ios',
        '--msl-version','20100','--rename-entry-point','main',entry,'frag',
        '--output',str(reference)],check=True)
    code=reference.read_text()
    if part=='easu':code=optimize_easu(code)
    source.write_text('// AMD FSR 1, offline cross-compiled from the isolated ReXGlue reference.\n'
        '// Copyright AMD 2021; Xenia shader integration Ben Vanik 2022. See MCLAFsr-LICENSE.txt.\n'+code)
    subprocess.run(['xcrun','-sdk','iphoneos','metal','-std=metal3.1','-O2',
        '-fmodules-cache-path=/private/tmp/mcla-metal-module-cache',
        '-c',str(source),'-o',str(air)],check=True,env=ENV)
    airs.append(str(air))
subprocess.run(['xcrun','-sdk','iphoneos','metal',*airs,'-o',str(OUT/'MCLAFsr.metallib')],check=True,env=ENV)
print('Compiled AMD FSR 1 EASU + RCAS as an offline Metal library.')
