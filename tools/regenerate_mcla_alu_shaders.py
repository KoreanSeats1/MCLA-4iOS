#!/usr/bin/env python3
"""Recompile MCLA in isolation, refusing any unrelated baseline source drift."""
from pathlib import Path
import concurrent.futures
import difflib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = ROOT / 'artifacts/mcla-native-compiled-expanded/hlsl'
OUT = ROOT / 'artifacts/mcla-alu-order-compiled'
COMPILER = ROOT / 'tools/build-mcla-alu/mcla-xenosrecomp'
COMMON = ROOT / 'tools/mcla-xenosrecomp/shader_common.h'
PATCHER = OUT / 'patch_mcla_shader_abi'

def run(args):
    subprocess.run([str(x) for x in args], check=True, capture_output=True, text=True)

def build(original):
    container = ROOT / 'artifacts/mcla-metal-containers-full' / (original.stem + '.bin')
    if not container.exists():
        container = OUT / 'gap4-containers' / (original.stem + '.bin')
    paths = [OUT / 'legacy' / original.name, OUT / 'hlsl' / original.name]
    for index, path in enumerate(paths):
        run([COMPILER, container, path, COMMON] + (['--legacy'] if index == 0 else []))
        source = path.read_text()
        source = re.sub(r'^[\t ]*r[0-9]+\. = .*\n', '', source, flags=re.M)
        path.write_text(source)
        run([PATCHER, path, original.stem[:2]])
    old, legacy, fixed = original.read_text(), paths[0].read_text(), paths[1].read_text()
    if old != legacy:
        delta = ''.join(difflib.unified_diff(old.splitlines(True), legacy.splitlines(True)))
        (OUT / (original.stem + '.unexpected.diff')).write_text(delta)
        raise RuntimeError(f'{original.stem}: unrelated baseline source drift; refusing')
    return {'shader': original.stem, 'baseline_exact': True,
            'snapshots': fixed.count('// MCLA parallel ALU source snapshot')}

def main():
    for directory in ('legacy', 'hlsl'):
        (OUT / directory).mkdir(parents=True, exist_ok=True)
    run(['clang++', '-std=c++20', '-O2', ROOT / 'tools/patch_mcla_shader_abi.cpp', '-o', PATCHER])
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(build, sorted(ORIGINAL.glob('*.hlsl'))))
    (OUT / 'manifest.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f'{len(results)} exact legacy baselines; '
          f'{sum(r["snapshots"] != 0 for r in results)} shaders with instruction snapshots; '
          f'{sum(r["snapshots"] for r in results)} snapshots total')

if __name__ == '__main__':
    main()
