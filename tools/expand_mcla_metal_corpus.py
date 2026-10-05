#!/usr/bin/env python3
"""Build newly captured title shader sources, keeping audited existing ones.
No Vulkan/DXC output or original Theft4 writes are involved.
"""
from pathlib import Path
import concurrent.futures
import subprocess
ROOT=Path(__file__).resolve().parents[1]
CONTAINERS=ROOT/'artifacts/mcla-metal-containers-full'
OUT=ROOT/'artifacts/mcla-native-compiled-expanded/hlsl'
COMPILER=ROOT/'tools/build-xenosrecomp/XenosRecomp/XenosRecomp'
COMMON=ROOT/'tools/mcla-xenosrecomp/shader_common.h'
PATCHER=ROOT/'artifacts/mcla-native-compiled-expanded/patch_mcla_shader_abi'
def build(path):
    dst=OUT/(path.stem+'.hlsl')
    if dst.exists(): return
    result=subprocess.run([str(COMPILER),str(path),str(dst),str(COMMON)],capture_output=True,text=True)
    if result.returncode: raise RuntimeError(path.name+result.stderr)
    text=dst.read_text()
    import re
    text=re.sub(r'^\s*r[0-9]+\. = .*\n','',text,flags=re.M)
    dst.write_text(text)
    subprocess.run([str(PATCHER),str(dst),path.stem[:2]],check=True)
    return path.stem
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    for result in pool.map(build,sorted(CONTAINERS.glob('*.bin'))):
        if result: print('Added',result,flush=True)
