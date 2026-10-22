#!/usr/bin/env python3
"""ftsum.py LOG -- frametime.lua's FT lines summarised per (part, pause slices): frames, overruns, mean frame
length in emulated ms against the script's target (slices x 20 ms). Lines with dt=0 (a second write in the same
frame) are skipped."""
import collections
import sys
g = collections.defaultdict(list)
for line in open(sys.argv[1]):
    if not line.startswith('FT '):
        continue
    f = dict(x.split('=') for x in line.split()[1:])
    if float(f['dt']) <= 0:
        continue
    g[(f['part'], int(f['slices']))].append((int(f['overran']), float(f['dt'])))
for (part, sl), v in sorted(g.items()):
    n = len(v)
    print('part %s slices %d: frames %4d  overran %4d  mean %6.1f ms  target %3d ms' %
          (part, sl, n, sum(o for o, _ in v), sum(d for _, d in v) / n, sl * 20))
