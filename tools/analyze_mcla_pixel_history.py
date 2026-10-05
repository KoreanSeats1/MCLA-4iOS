#!/usr/bin/env python3
"""Read paired GPU pixels without clamping HDR; report draws that changed them."""
import argparse
import json
import math
import struct
from pathlib import Path


def read_pixel(raw, record, point):
    offset = record["offset"] + 256 * point
    if record["format"] == "rgba16f":
        return struct.unpack_from("<4e", raw, offset)
    if record["format"] == "rgba8":
        return tuple(x / 255 for x in struct.unpack_from("4B", raw, offset))
    raise ValueError(f"Unsupported format: {record['format']}")


def changes(meta, raw, point):
    before = {}
    for record in meta["records"]:
        key = record["draw"], record["surface"]
        if record.get("phase") == "before":
            before[key] = record
            continue
        if record.get("phase") != "after" or key not in before:
            continue
        baseline = before.pop(key)
        if any(record[k] != baseline[k] for k in ("format", "width", "height", "points")):
            raise ValueError("Incompatible before/after target coordinates")
        a, b = read_pixel(raw, baseline, point), read_pixel(raw, record, point)
        delta = max(abs(x - y) for x, y in zip(a[:3], b[:3]))
        if not all(math.isfinite(x) for x in (*a, *b)):
            delta = math.inf
        if delta:
            yield delta, a, b, record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("metadata", type=Path)
    parser.add_argument("--point", type=int, choices=(0, 1), default=0)
    parser.add_argument("--limit", type=int, default=30)
    args = parser.parse_args()
    meta = json.loads(args.metadata.read_text())
    if not meta.get("gpu_completed"):
        raise ValueError("Capture did not complete on GPU")
    raw = args.metadata.with_suffix(".bin").read_bytes()
    changed = sorted(changes(meta, raw, args.point), key=lambda v: v[0], reverse=True)
    print(f"frame={meta['frame']} token={meta['token']} records={len(meta['records'])} "
          f"changed={len(changed)} truncated={meta['truncated']}")
    for delta, a, b, r in changed[:args.limit]:
        print(f"draw={r['draw']} ps={r['ps']} surface={r['surface']:08X} "
              f"{r['width']}x{r['height']} {r['format']} delta={delta:.6g}")
        print(f"  {a} -> {b}")
        for t in r.get("textures", []):
            f = t["fetch"]
            exponent = (f[3] >> 13) & 63
            if exponent >= 32:
                exponent -= 64
            print(f"  slot={t['slot']} handle={t['handle']:08X} fmt={f[1]&63} "
                  f"signs={(f[0]>>2)&255:02X} exp={exponent} "
                  f"base={f[1]&0xfffff000:08X} produced={t['produced']}")


if __name__ == "__main__":
    main()
