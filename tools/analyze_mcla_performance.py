#!/usr/bin/env python3
"""Summarize MCLA captures (schemas 1–5), including sparse GPU pass timings."""
import argparse
import csv
import statistics
from pathlib import Path
from collections import Counter, defaultdict


def percentile(values, fraction):
    values = sorted(values)
    return values[int((len(values) - 1) * fraction)] if values else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture")
    args = parser.parse_args()
    with open(args.capture, newline="") as stream:
        rows = [{k: float(v) for k, v in row.items()} for row in csv.DictReader(stream)]
    if not rows:
        raise SystemExit("Empty capture")
    # First interval starts before capture; omit it for interval statistics.
    intervals = [r["submit_ms"] for r in rows[1:] if r["submit_ms"] > 0]
    print(f"Frames: {len(rows)}; submission throughput: {1000/statistics.mean(intervals):.2f} fps"
          if intervals else f"Frames: {len(rows)}; insufficient intervals")
    metrics = ["submit_ms", "latest_completed_gpu_ms", "paired_gpu_ms",
               "renderer_commands_cpu_ms", "native_draw_cpu_ms", "present_cpu_ms",
               "drawable_wait_ms", "slot_wait_ms", "previous_pacing_ms", "commit_to_gpu_ms",
               "cache_maintenance_ms", "resource_invalidation_ms"]
    for key in metrics:
        values = [r[key] for r in rows[1:] if key in r and r[key] >= 0]
        if values:
            print(f"{key}: p50={percentile(values,.5):.2f} p95={percentile(values,.95):.2f}"
                  f" max={max(values):.2f}")
    print("5-second windows: seconds, fps (submission), mean draws, mean GPU ms, thermal states")
    for bucket in range(int(rows[-1]["seconds"] // 5) + 1):
        group = [r for r in rows[1:] if int(r["seconds"] // 5) == bucket]
        if not group:
            continue
        gpu_key = "paired_gpu_ms" if "paired_gpu_ms" in group[0] else "latest_completed_gpu_ms"
        gpu = [r[gpu_key] for r in group if r[gpu_key] >= 0]
        thermal = sorted({int(r["thermal_state"]) for r in group if "thermal_state" in r})
        print(f"{bucket*5:2d}–{bucket*5+5:2d}: {1000/statistics.mean(r['submit_ms'] for r in group):.2f}, "
              f"{statistics.mean(r['draws'] for r in group):.0f}, "
              f"{statistics.mean(gpu) if gpu else -1:.2f}, {thermal or 'unrecorded'}")
    if "constant_reuses_total" in rows[0]:
        reused = rows[-1]["constant_reuses_total"] - rows[0]["constant_reuses_total"]
        uploaded = rows[-1]["constant_uploads_total"] - rows[0]["constant_uploads_total"]
        total = reused + uploaded
        print(f"Constant bank reuse: {reused/total:.1%}" if total else "No constant bank samples")
        print(f"Mean upload allocation: {statistics.mean(r['upload_bytes'] for r in rows)/1048576:.2f} MiB/frame")
    if "cache_evictions" in rows[0]:
        print(f"Cache evictions: {sum(r['cache_evictions'] for r in rows):.0f}; "
              f"max oldest-cache age: {max(r['oldest_cache_age_frames'] for r in rows):.0f} frames")
        print(f"Invalidation calls: {sum(r['invalidation_calls'] for r in rows):.0f}; "
              f"invalidated keys: {sum(r['invalidated_keys'] for r in rows):.0f}")
    if "attachment_reuses_total" in rows[0]:
        draws = sum(r['draws'] for r in rows[1:])
        for name in ['attachment_reuses', 'pipeline_reuses', 'vertex_reuses',
                     'index_reuses', 'texture_group_reuses', 'vertex_bind_skips']:
            count = rows[-1][name+'_total']-rows[0][name+'_total']
            print(f"{name}: {count:.0f} ({count/draws if draws else 0:.3f}/draw)")
        print("GPU trace status counts:", dict(Counter(int(r['gpu_pass_trace_status']) for r in rows)))
        # Counter sampling may perturb sampled frames: retain unsampled stats.
        ordinary = [r for r in rows[1:] if r['gpu_pass_trace_status'] == 0]
        for name in ['renderer_commands_cpu_ms', 'paired_gpu_ms']:
            values = [r[name] for r in ordinary if r[name] >= 0]
            if values:
                print(f"Unsampled {name}: p50={percentile(values,.5):.2f} p95={percentile(values,.95):.2f}")
    passes_path = Path(args.capture).with_suffix('').with_name(Path(args.capture).stem+'-gpu-passes.csv')
    if 'fsr_enabled' in rows[0]:
        for mode in [0,1]:
            group=[r for r in rows[1:] if int(r['fsr_enabled'])==mode]
            gpu=[r['paired_gpu_ms'] for r in group if r['paired_gpu_ms']>=0]
            if gpu:
                print(f"FSR {'on' if mode else 'off'}: n={len(group)} paired GPU p50={percentile(gpu,.5):.2f} p95={percentile(gpu,.95):.2f} ms (scene/thermal must be comparable)")
    if 'submission_thread_cpu_ms' in rows[0]:
        valid=[r for r in rows[1:] if r['submission_thread_cpu_ms']>=0 and
               r['submission_thread_wall_ms']>=0]
        if valid:
            for label,values in (
                ('submission thread CPU',[r['submission_thread_cpu_ms'] for r in valid]),
                ('submission thread wall',[r['submission_thread_wall_ms'] for r in valid]),
                ('non-CPU wall',[max(0,r['submission_thread_wall_ms']-r['submission_thread_cpu_ms']) for r in valid]),
                ('non-CPU wall minus prior pacing',[max(0,r['submission_thread_wall_ms']-r['submission_thread_cpu_ms']-r['previous_pacing_ms']) for r in valid])):
                print(f'{label}: p50={percentile(values,.5):.2f} p95={percentile(values,.95):.2f} ms (n={len(values)})')
            print('Non-CPU time includes descheduling, blocking and sleep; pacing subtraction is approximate.')
        stages=('state','pipeline','dynamic','vertices','bindings','indices','constants','textures','encode')
        sampled=[r for r in rows if r['draw_profile_samples']>0]
        samples=sum(r['draw_profile_samples'] for r in sampled)
        if samples:
            print(f'Draw preparation, {samples:.0f} sampled successful draws, weighted mean microseconds/draw:')
            for stage in stages:
                wall=sum(r[f'draw_{stage}_wall_us']*r['draw_profile_samples'] for r in sampled)/samples
                cpu=sum(r[f'draw_{stage}_cpu_us']*r['draw_profile_samples'] for r in sampled)/samples
                print(f'  {stage}: wall={wall:.2f} CPU={cpu:.2f}')
            print('Bindings contains constants, textures and encode: nested stages are not additive.')
    if passes_path.exists():
        groups = defaultdict(list)
        with passes_path.open(newline='') as stream:
            for row in csv.DictReader(stream):
                value = float(row['span_ms'])
                if value >= 0:
                    key = (row['kind'],row['width']+'x'+row['height'],row['first_ps'],row['mixed_shaders'])
                    groups[key].append(value)
        print("Largest sampled pass spans (overlapping intervals, NOT additive GPU costs):")
        for key, values in sorted(groups.items(), key=lambda item: max(item[1]), reverse=True)[:20]:
            print(f"{key}: n={len(values)} p50={percentile(values,.5):.3f} p95={percentile(values,.95):.3f} max={max(values):.3f} ms")
    print("Latest GPU samples are not frame-paired; schema 2 paired_gpu_ms is. "
          "Native draw and renderer CPU timings overlap—do not sum them.")


if __name__ == "__main__":
    main()
