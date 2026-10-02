#!/usr/bin/env python3
"""从原始累计计数计算资源分布；录像、trace 和无效轮次不进入资源对照。"""
import argparse
import json
import math
from pathlib import Path
import re
import statistics


def distribution(values):
    values = sorted(value for value in values if value is not None)
    if not values:
        return None
    return dict(n=len(values), median=statistics.median(values),
                p95=values[max(0, math.ceil(len(values) * .95) - 1)],
                minimum=values[0], maximum=values[-1])


def summarize(path):
    receipt = json.loads(path.read_text())
    if not isinstance(receipt, dict) or 'activity' not in receipt:
        return None
    log = path.with_suffix('.app.log').read_text(errors='replace')
    samples = receipt['activity']
    points = []
    for before, after in zip(samples, samples[1:]):
        elapsed = after['uptime'] - before['uptime']
        if elapsed <= 0:
            continue
        def cpu(pid):
            first = next((p for p in before['processes'] if p['pid'] == pid and p['status'] == 0), None)
            last = next((p for p in after['processes'] if p['pid'] == pid and p['status'] == 0), None)
            if not first or not last or 'user_ticks' not in first or first['process_start'] != last['process_start']:
                return None
            ticks = last['user_ticks'] + last['system_ticks'] - first['user_ticks'] - first['system_ticks']
            return ticks * after['timebase_numer'] / after['timebase_denom'] / 1e9 / elapsed * 100
        app = next((p for p in after['processes'] if p['pid'] == receipt['pid'] and p['status'] == 0), None)
        ticks = sum(after['system_cpu_ticks']) - sum(before['system_cpu_ticks'])
        idle = after['system_cpu_ticks'][2] - before['system_cpu_ticks'][2]
        points.append(dict(phase=after['phase'], cpu=cpu(receipt['pid']),
            stress_cpu=cpu(receipt.get('stress_pid')),
            rss=app['resident_bytes'] / 1048576 if app else None,
            footprint=app['footprint_bytes'] / 1048576 if app else None,
            gpu=next((g.get('Device Utilization %') for g in after['gpu']), None),
            system_cpu=(1 - idle / ticks) * 100 if ticks > 0 and after['system_cpu_status'] == 0 else None))
    operations = re.findall(r'\[panel-bench\] operation=(\d+) mode=(\S+) unoccluded=1', log)
    valid = receipt['complete'] and not receipt.get('invalid_reason') and len(operations) == 50 and len(re.findall('scope=live-full', log)) == 1
    frames = re.findall(r'\[panel-window\] width=([\d.]+) height=([\d.]+)', log)
    hidden = [point for point in points if point['phase'] == 'hidden']
    phases = {phase: {metric: distribution(point[metric] for point in points if point['phase'] == phase)
        for metric in ['cpu', 'stress_cpu', 'rss', 'footprint', 'gpu', 'system_cpu']}
        for phase in ['warmup', 'operations', 'hidden']}
    return dict(name=path.stem, pid=receipt['pid'], executable_sha256=receipt['executable_sha256'],
        configuration_sha256=receipt.get('configuration_sha256'), native=receipt['native'], host=receipt['host'],
        mode=receipt['mode'], load=receipt['load'], valid=valid,
        resource_comparison=valid and not receipt.get('capture') and not receipt.get('trace'),
        phases=phases, hidden_tail5={metric:distribution(point[metric] for point in hidden[-5:])
            for metric in ['cpu', 'rss', 'footprint']},
        operations=len(operations), window_frame_commits=len(frames), window_frames=frames,
        plan_count=len(re.findall(r'\[native-plan\]',log)),
        plan_prepare_ms=distribution(float(v) for v in re.findall(r'prepare-ms=([\d.]+)',log)),
        main_cpu_window_ms=distribution(float(v) for v in re.findall(r'expand main=([\d.]+)ms',log)),
        process_cpu_window_ms=distribution(float(v) for v in re.findall(r'expand main=[\d.]+ms proc=([\d.]+)ms',log)),
        screens=samples[0]['screens'] if samples else [],
        checkpoints=re.findall(r'\[panel-measure\] (.+)',log),
        page_commands=re.findall(r'\[panel-bench\] (page(?:-skipped)?=.+)',log),
        archive_commands=re.findall(r'\[panel-bench\] (archive=.+)',log))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    result=[]
    errors=[]
    exclusions_path=args.directory / 'analysis-exclusions.json'
    exclusions=json.loads(exclusions_path.read_text()) if exclusions_path.exists() else {}
    for path in sorted(args.directory.glob('*.json')):
        try:
            summary=summarize(path)
            if summary:
                if path.stem in exclusions:
                    summary['resource_comparison']=False
                    summary['exclusion_reason']=exclusions[path.stem]
                result.append(summary)
        except (json.JSONDecodeError, KeyError, OSError, TypeError) as error:
            errors.append(dict(path=str(path),error=str(error)))
    args.output.write_text(json.dumps(dict(summaries=result,errors=errors),ensure_ascii=False,indent=2))
    print(json.dumps(dict(rounds=len(result),invalid=sum(not r['valid'] for r in result),errors=errors),ensure_ascii=False))


if __name__=='__main__':main()
