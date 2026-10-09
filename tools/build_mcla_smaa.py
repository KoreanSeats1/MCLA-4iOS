#!/usr/bin/env python3
"""Build the canonical Theft4 SMAA fragment shaders for MCLA's Metal Lab.

Reads the shared foundation without modifying it. Output is generated into
artifacts/ and is bundled only by the MCLA SMAA Lab preset.
"""

from pathlib import Path
import os
import re
import struct
import subprocess
from mcla_metal_target import METAL_DEPLOYMENT_FLAGS, validate_library

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "theft4-foundation/glue/rexglue-sdk-main/src/graphics/gta4_native/smaa/smaa_shaders.inc"
OUT = ROOT / "artifacts/mcla-metal-smaa"
OUT.mkdir(parents=True, exist_ok=True)
ENV = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
source = SOURCE.read_text()
airs = []
for array, entry in (
    ("smaa_edge_high_ps", "mclaSmaaEdge"),
    ("smaa_weight_high_ps", "mclaSmaaWeight"),
    ("smaa_neighborhood_ps", "mclaSmaaNeighborhood"),
):
    match = re.search(r"inline constexpr uint32_t " + array + r"\[\] = \{(.*?)\};", source, re.S)
    if not match:
        raise RuntimeError(f"missing canonical SMAA shader: {array}")
    words = [int(value, 16) for value in re.findall(r"0x[0-9A-Fa-f]+", match.group(1))]
    if words[0] != 0x07230203:
        raise RuntimeError(f"invalid SPIR-V header: {array}")
    spirv = OUT / f"{array}.spv"
    spirv.write_bytes(struct.pack(f"<{len(words)}I", *words))
    metal = OUT / f"{array}.metal"
    air = OUT / f"{array}.air"
    subprocess.run([
        str(ROOT / "tools/build-metal-upscale/spirv-cross"), str(spirv),
        "--msl", "--msl-ios", "--msl-version", "20100",
        "--rename-entry-point", "main", entry, "frag", "--output", str(metal),
    ], check=True)
    subprocess.run([
        "xcrun", "-sdk", "iphoneos", "metal", "-std=metal3.1", "-O2", *METAL_DEPLOYMENT_FLAGS,
        "-fmodules-cache-path=/private/tmp/mcla-metal-module-cache",
        "-c", str(metal), "-o", str(air),
    ], check=True, env=ENV)
    airs.append(str(air))

subprocess.run(["xcrun", "-sdk", "iphoneos", "metal", *METAL_DEPLOYMENT_FLAGS, *airs,
                "-o", str(OUT / "MCLASmaa.metallib")], check=True, env=ENV)
validate_library((OUT / "MCLASmaa.metallib").read_bytes())
print("Compiled high-quality canonical SMAA edge/weight/neighborhood shaders for Metal Lab.")
