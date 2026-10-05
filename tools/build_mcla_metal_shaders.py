#!/usr/bin/env python3
"""Compile the audited XenosRecomp Metal branch, offline, without SPIR-V.

Generated artifacts stay in the MCLA workspace; original Theft4 is read-only.
Attribute renumbering preserves explicit semantic/type metadata for the host.
"""
import concurrent.futures
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path,
    default=ROOT / 'artifacts/mcla-alu-order-compiled/hlsl',
    help='Audited ALU-order sources (generate with regenerate_mcla_alu_shaders.py)')
SOURCE = parser.parse_args().source
if len(list(SOURCE.glob('*.hlsl'))) < 534:
    raise SystemExit(f'{SOURCE}: expected at least 534 audited shader sources')
OUT = ROOT / 'artifacts/mcla-metal-shaders'
OUT.mkdir(parents=True, exist_ok=True)
ENV = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')

GAMMA_HELPERS = r'''
#ifdef __air__
// Xenos texture-sign value 3 is not ordinary sRGB. It requests the console's
// piecewise-linear gamma-to-linear conversion in the texture unit. MCLA uses
// it on albedo RGB (alpha stays linear). Bit 31 rides beside the small argument
// buffer index and is masked before indexing; this mirrors the measured native
// oracle without changing resource identity or host texture storage.
uint mclaTextureIndex(uint descriptorIndex) {
    return descriptorIndex & 0x0FFFFFFFu;
}
uint2 mclaLogicalTexture2DDimensions(texture2d<float> texture, uint descriptorIndex) {
    // Full-scene storage can extend beyond the title's 1280x720 logical
    // frontbuffer; preserve guest texture-coordinate arithmetic exactly.
    if (descriptorIndex & 0x10000000u) return uint2(1280u, 720u);
    // Produced full-scene textures have larger host storage, but shader fetch
    // offsets, getWeights and getPixelCoord remain in guest texel units.
    float inverseScale = (descriptorIndex & 0x40000000u) ? 0.8f :
                         (descriptorIndex & 0x20000000u) ? (2.0f/3.0f) : 1.0f;
    return uint2(round(float2(texture.get_width(),texture.get_height()) * inverseScale));
}
float3 mclaPWLGammaToLinear(float3 gamma) {
    gamma = saturate(gamma);
    float3 scale = select(float3(1.0f / 1024.0f),
                          float3(2.0f / 1024.0f), gamma >= 64.0f / 255.0f);
    float3 offset = select(float3(0.0f), float3(-64.0f),
                           gamma >= 64.0f / 255.0f);
    scale = select(scale, float3(4.0f / 1024.0f), gamma >= 96.0f / 255.0f);
    offset = select(offset, float3(-256.0f), gamma >= 96.0f / 255.0f);
    scale = select(scale, float3(8.0f / 1024.0f), gamma >= 192.0f / 255.0f);
    offset = select(offset, float3(-1024.0f), gamma >= 192.0f / 255.0f);
    float3 linear = gamma * (255.0f * 1024.0f) * scale + offset;
    linear += trunc(linear * scale);
    return linear * (1.0f / 1023.0f);
}
float4 mclaDecodeTextureSample(float4 value, uint descriptorIndex) {
    if (!(descriptorIndex & 0x80000000u)) return value;
    return float4(mclaPWLGammaToLinear(value.rgb), value.a);
}
#endif
'''

def add_xenos_texture_gamma(text, path):
    marker = 'struct AtomicUintBuffer\n{\n    device atomic_uint* buffer;\n};'
    if text.count(marker) != 1:
        raise ValueError(f'{path}: Metal helper insertion point changed')
    text = text.replace(marker, marker + '\n' + GAMMA_HELPERS, 1)
    text = text.replace('textureHeap[resourceDescriptorIndex]',
                        'textureHeap[mclaTextureIndex(resourceDescriptorIndex)]')
    # Only rewrite calls in __air__ branches, including the separate bicubic
    # and getPixelCoord blocks. Keep the source compiler's HLSL branch intact.
    branches = []
    rewritten = []
    dimension_calls = 0
    for line in text.splitlines(keepends=True):
        directive = line.strip()
        if directive.startswith(('#if ', '#ifdef ', '#ifndef ')):
            branches.append(True if directive == '#ifdef __air__' else
                            False if directive == '#ifndef __air__' else None)
        elif directive == '#else' and branches and branches[-1] is not None:
            branches[-1] = not branches[-1]
        elif directive == '#endif' and branches:
            branches.pop()
        if True in branches and False not in branches:
            dimension_calls += line.count('getTexture2DDimensions(texture)')
            line = line.replace('getTexture2DDimensions(texture)',
                'mclaLogicalTexture2DDimensions(texture, resourceDescriptorIndex)')
        rewritten.append(line)
    if dimension_calls != 6:
        raise ValueError(f'{path}: expected 6 Metal logical-dimension calls, got {dimension_calls}')
    text = ''.join(rewritten)
    # Only the __air__ branch uses lowercase .sample. Wrap every actual sample,
    # including multiline explicit-LOD forms, while leaving dimension queries
    # and the inactive HLSL branch untouched.
    pattern = r'return (texture\.sample\(.*?\));'
    text, ordinary = re.subn(pattern,
        r'return mclaDecodeTextureSample(\1, resourceDescriptorIndex);',
        text, flags=re.DOTALL)
    direct = (r'return (textureHeap\[mclaTextureIndex\(resourceDescriptorIndex\)\]'
              r'\.tex\.sample\(.*?\));')
    text, cube = re.subn(direct,
        r'return mclaDecodeTextureSample(\1, resourceDescriptorIndex);',
        text, flags=re.DOTALL)
    if ordinary != 10 or cube != 1:
        raise ValueError(f'{path}: expected 11 Metal fetch returns, got {ordinary}+{cube}')
    if 'textureHeap[resourceDescriptorIndex]' in text:
        raise ValueError(f'{path}: unmasked Metal texture index remains')
    return text

def compile_shader(path):
    text = path.read_text()
    text = add_xenos_texture_gamma(text, path)
    stage, identity = path.stem.split('-')
    attrs = []
    def attribute(match):
        typ, name, semantic = match.groups()
        attrs.append((int(semantic), len(attrs), typ, name))
        return f'{typ} {name} [[attribute({len(attrs)-1})]]'
    text = re.sub(r'(float[1-4]?|uint[1-4]?|int[1-4]?)\s+(\w+)\s+\[\[attribute\((\d+)\)\]\]', attribute, text)
    # Let discard/alpha test execute before depth commits. The legacy Metal
    # branch forced early tests even for alpha-tested foliage.
    text = text.replace('[[early_fragment_tests]]', '')
    if stage == 'ps':
        outputs = sorted(set(map(int, re.findall(r'float4 oC(\d+) \[\[color\(', text))))
        epilogue = ['#ifdef __air__']
        for index in outputs:
            offset = 864 + index * 48
            epilogue += [f'output.oC{index} *= *reinterpret_cast<device float4*>(g_PushConstants.SharedConstants + {offset});',
                         f'float4 lo{index}=*reinterpret_cast<device float4*>(g_PushConstants.SharedConstants + {offset+16});',
                         f'float4 hi{index}=*reinterpret_cast<device float4*>(g_PushConstants.SharedConstants + {offset+32});',
                         f'output.oC{index} = select(output.oC{index}, clamp(output.oC{index}, lo{index}, hi{index}), lo{index} <= hi{index});']
        epilogue += ['#endif', '\treturn output;']
        if text.count('\treturn output;') < 1: raise ValueError(path)
        text = text.replace('\treturn output;', '\n'.join(epilogue))
    src = OUT / (path.stem + '.metal')
    air = OUT / (path.stem + '.air')
    lib = OUT / (path.stem + '.metallib')
    digest = hashlib.sha256(('mcla-metal-v1\n' + text).encode()).hexdigest()
    stamp = OUT / (path.stem + '.sha256')
    if not (lib.exists() and stamp.exists() and stamp.read_text() == digest):
        src.write_text(text)
        args = ['xcrun', '-sdk', 'iphoneos', 'metal', '-w', '-O2',
                '-fmodules-cache-path=/private/tmp/mcla-metal-module-cache',
                '-std=metal3.1', '-D__air__', '-DGTA4_RECOMP']
        if stage == 'ps': args.append('-DXENOS_RECOMP_PIXEL_SHADER')
        result = subprocess.run(args + ['-c', str(src), '-o', str(air)], env=ENV, capture_output=True, text=True)
        if result.returncode == 0:
            result = subprocess.run(['xcrun', '-sdk', 'iphoneos', 'metal', str(air), '-o', str(lib)], env=ENV, capture_output=True, text=True)
        (OUT / (path.stem + '.log')).write_text(result.stdout + result.stderr)
        if result.returncode: return {'shader': path.stem, 'error': result.stderr[:2000]}
        stamp.write_text(digest)
    mask = 0
    for slot in set(re.findall(r's(\d+)_Texture(?:2D|3D|Cube)DescriptorIndex', text)):
        mask |= 1 << int(slot)
    colors = 0
    for slot in re.findall(r'\[\[color\((\d+)\)\]\]', text): colors |= 1 << int(slot)
    constant_expressions = [value.strip() for value in
        re.findall(r'g_MCLAConstants\(([^)]+)\)', text)
        if value.strip() != 'INDEX']
    # Direct-index shaders can upload only the float4 registers they read.
    # Any address-register expression remains fully conservative because its
    # runtime range is title data and may legally reach any bank register.
    constant_masks = [0, 0, 0, 0]
    if any(not value.isdigit() for value in constant_expressions):
        constant_masks = [(1 << 64) - 1] * 4
    else:
        for value in constant_expressions:
            register = int(value)
            if not 0 <= register < 256:
                raise ValueError(f'{path}: constant register {register}')
            constant_masks[register // 64] |= 1 << (register % 64)
    return {'shader': path.stem, 'hash': identity, 'vertex': stage == 'vs',
            'textures': mask, 'colors': colors, 'constants': constant_masks,
            'attributes': attrs}

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(compile_shader, sorted(SOURCE.glob('*.hlsl'))))
(OUT / 'manifest.json').write_text(json.dumps(results, indent=2))
errors = [r for r in results if 'error' in r]
for error in errors: print(error['shader'], error['error'], flush=True)
if errors: raise SystemExit(f'{len(errors)}/{len(results)} Metal shaders failed')
header = ['// Generated by tools/build_mcla_metal_shaders.py. Do not edit.', '#pragma once',
          '#include <cstdint>', 'struct MCLAMetalAttribute { uint8_t semantic, location, components, numeric; };',
          'struct MCLAMetalShaderInfo { uint64_t hash; bool vertex; uint32_t textures, colors; uint64_t constants[4]; uint32_t count; MCLAMetalAttribute attributes[32]; };',
          'inline constexpr MCLAMetalShaderInfo kMCLAMetalShaders[] = {']
for r in results:
    fields = []
    for semantic, location, typ, name in r['attributes']:
        fields.append('{%d,%d,%d,%d}' % (semantic, location, int(typ[-1]) if typ[-1].isdigit() else 1, 1 if typ.startswith('uint') else 2 if typ.startswith('int') else 0))
    masks = ','.join('0x%016Xull' % value for value in r['constants'])
    header.append('{0x%sull,%s,0x%Xu,0x%Xu,{%s},%d,{%s}},' % (r['hash'], str(r['vertex']).lower(), r['textures'], r['colors'], masks, len(fields), ','.join(fields)))
header += ['};', '']
(ROOT / 'MCLAApp/generated/mcla_metal_shader_info.h').write_text('\n'.join(header))
print(f'Compiled {len(results)} direct Metal libraries; no SPIR-V runtime.', flush=True)
