#!/usr/bin/env python3
"""Make Lab-only AOT hook copies without changing the working MCLA sources."""

from pathlib import Path
import sys


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one hook anchor, found {count}")
    return source.replace(old, new, 1)


def write_if_changed(path: Path, content: str) -> None:
    if path.exists() and path.read_text() == content:
        return
    path.write_text(content)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate_single_tile_lab.py SOURCE_DIR OUTPUT_DIR")
    source_dir = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)

    begin = (source_dir / "larecomp_recomp.2.cpp").read_text()
    begin = replace_once(
        begin,
        "extern void Patch_SingleTile(PPCRegister& r7, PPCRegister& r8, PPCRegister& r25, PPCRegister& r28);",
        "extern void Patch_SingleTile(PPCRegister& r7, PPCRegister& r8, PPCRegister& r25, PPCRegister& r28);\n"
        "extern void MCLASingleTileLabBegin(PPCRegister& r7, PPCRegister& r8, const PPCRegister& r17,\n"
        "                                   const PPCRegister& r25, const PPCRegister& r28, uint8_t* base);",
        "BeginTiledRendering declaration",
    )
    begin = replace_once(
        begin,
        "\tPatch_SingleTile(ctx.r7, ctx.r8, ctx.r25, ctx.r28);",
        "\tMCLASingleTileLabBegin(ctx.r7, ctx.r8, ctx.r17, ctx.r25, ctx.r28, base);\n"
        "\tPatch_SingleTile(ctx.r7, ctx.r8, ctx.r25, ctx.r28);",
        "BeginTiledRendering call",
    )
    write_if_changed(output_dir / "larecomp_recomp.2.cpp", begin)

    edram = (source_dir / "larecomp_recomp.25.cpp").read_text()
    edram = replace_once(
        edram,
        "extern bool Patch_EdramLimit(PPCRegister& r11);",
        "extern bool Patch_EdramLimit(PPCRegister& r11);\n"
        "extern bool MCLASingleTileLabAllowEdram(const PPCRegister& r3, const PPCRegister& r30,\n"
        "                                        const PPCRegister& r11);",
        "CreateSurface declaration",
    )
    edram = replace_once(
        edram,
        "\tif (Patch_EdramLimit(ctx.r11)) {",
        "\tif (MCLASingleTileLabAllowEdram(ctx.r3, ctx.r30, ctx.r11)) {\n"
        "\t\tgoto loc_82410E48;\n"
        "\t}\n"
        "\tif (Patch_EdramLimit(ctx.r11)) {",
        "CreateSurface call",
    )
    write_if_changed(output_dir / "larecomp_recomp.25.cpp", edram)


if __name__ == "__main__":
    main()
