"""Summarize proc_pid_rusage snapshots; CPU is percent of one core."""
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'build/thumbnail-prototype')
result = {}
for path in sorted(root.glob('*.jsonl')):
    name = path.stem
    if not path.exists():
        continue
    records = [json.loads(line) for line in path.read_text().splitlines()]
    phases = {r['event']: r for r in records}
    summary = {'phases': {r['event']: {'footprintMiB': r['footprintBytes']/2**20,
                                     'residentMiB': r['residentBytes']/2**20} for r in records}}
    for first, last, label in [('idle-before', 'idle-after', 'idle'), ('released-before', 'released-after', 'released')]:
        if first not in phases or last not in phases:
            continue
        a, b = phases[first], phases[last]
        cpu_ns = (b['userTicks']+b['systemTicks']-a['userTicks']-a['systemTicks'])*b['timebaseNumer']/b['timebaseDenom']
        summary[label+'CPUPercent'] = cpu_ns/(b['timeNs']-a['timeNs'])*100
        summary[label+'Wakeups'] = b['wakeups']-a['wakeups']
    for event in ['copied', 'shown']:
        if event in phases:
            summary[event+'Ms'] = phases[event]['elapsedMs']
    summary['clipboardVerified'] = phases.get('copied', {}).get('clipboardVerified', False)
    summary['largestObservedFootprintMiB'] = max(r['footprintBytes'] for r in records)/2**20
    summary['peakFootprintMiB'] = max(r.get('peakFootprintBytes', 0) for r in records)/2**20 or None
    result[name] = summary
print(json.dumps(result, indent=2))
