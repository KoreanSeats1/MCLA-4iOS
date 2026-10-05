#!/usr/bin/env python3
"""Compile only observed missing MCLA shaders from an opt-in device capture.

The existing audited corpus is left intact. New HLSL files are generated into
the same source directory for the ordinary offline Metal builder to validate.
"""
import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("log", type=Path)
parser.add_argument("containers", type=Path)
args = parser.parse_args()
out = ROOT / "artifacts/mcla-alu-order-compiled/hlsl"
compiler = ROOT / "tools/build-mcla-alu/mcla-xenosrecomp"
patcher = ROOT / "artifacts/mcla-alu-order-compiled/patch_mcla_shader_abi"
common = ROOT / "tools/mcla-xenosrecomp/shader_common.h"
missing = set(re.findall(
    r"MCLA native shader missing stage=(vs|ps) hash=([A-F0-9]{16})",
    args.log.read_text(errors="replace")))
if not missing:
    raise SystemExit("No missing shader identities in log")
added = []
uncaptured = []
for stage, identity in sorted(missing):
    name = f"{stage}-{identity}"
    target = out / f"{name}.hlsl"
    if target.exists():
        continue
    source = args.containers / f"{name}.bin"
    if not source.exists():
        uncaptured.append(name)
        continue
    subprocess.run([compiler, source, target, common], check=True)
    text = target.read_text()
    text = re.sub(r"^[\t ]*r[0-9]+\. = .*\n", "", text, flags=re.M)
    target.write_text(text)
    subprocess.run([patcher, target, stage], check=True)
    added.append(name)
print(f"Added {len(added)} shader sources; corpus now has {len(list(out.glob('*.hlsl')))} shaders")
print("\n".join(added))
if uncaptured:
    print(f"Not in this capture ({len(uncaptured)}): " + ", ".join(uncaptured))
