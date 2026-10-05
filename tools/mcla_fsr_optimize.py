"""Mixed-precision Metal specialization of the reference AMD FSR1 EASU.

Keep sampling coordinates, edge detection, reciprocal estimates, RGB values,
accumulation and normalization FP32. Only bounded filter weights use FP16.
Retain every tap, the original kernel and the anti-ringing clamp.
"""
import re


def optimize_easu(source):
    start=source.index('    float2 _15703 =')
    prefix,body=source[:start],source[start:]
    if prefix.count('.gather(')!=12 or 'out.m_5777.w = 1.0;' not in body:
        raise ValueError('Unexpected reference EASU layout')
    # Only the bounded 12-tap filter weights use half. Edge detection,
    # normalization, texture values and RGB accumulation remain full FP32.
    body=re.sub(r'\bfloat(2?)\b',r'half\1',body)
    body=body.replace('fast::','metal::')
    body=re.sub(r'(?<![\w.])(\d+\.\d+(?:[eE][+-]?\d+)?)(?![\w.])',r'\1h',body)
    for name in ['_13240','_23570','_9267','_16389']:
        body=body.replace(name,f'half({name})')
    for name in ['_21577','_10727']:
        body=body.replace(name,f'half2({name})')
    denominator='float3(1.0h / (((((((((((_7155'
    if body.count(denominator)!=1 or 'float3 _6963' not in body:
        raise ValueError('Unexpected EASU accumulation/normalization layout')
    body=body.replace(denominator,
                      'float3(1.0f / (((((((((((float(_7155)')
    return prefix+body
