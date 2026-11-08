#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# codewheel_estimate.py DIR -- how long will the code wheel page's pictures take on the owner's KN7000, from what they
# took in MAME? DIR holds awcnv_wheel.lua's pictimes.txt (each turning picture: its time in 1/2001 ms, its 32-bit stores
# into the LCD), run_wheel.txt (its "times (MAME)" line: the pictures at rest), mame_benchmark.txt (the game's own
# benchmark in that MAME run, AWPERF0.TXT) and unit_benchmark.txt (the same benchmark from AWPERFn.TXT files the unit
# wrote). perf.s's benchmark gives ns per access ("ns x 10": one decimal); the ALU, RAM and LCD loads are close in
# MAME and on the unit, the LCD's 32-bit stores are not, so a picture on the unit is estimated as its MAME time plus
# its stores times (unit's LCD w32 - MAME's). Prints the estimate for each unit benchmark; with a third column in
# pictimes.txt (the zoomed page's region: 0 TOP, 1 MIDDLE, 2 BOTTOM, since 2026-11-08), each region's too.
import os
import re
import sys

import numpy as np

d = sys.argv[1]


def bench(path):
    rows, lines = [], open(path).read().splitlines()
    for i, l in enumerate(lines):
        if l.startswith("benchmark, ns x 10"):
            rows.append([float(x) for x in lines[i + 1].split()])
    return rows


names = "ALU LCDw16 LCDw32 LCDr16 RAMw8 RAMw32 RAMr8 RAMr32 UNCr32".split()
mame = bench(os.path.join(d, "mame_benchmark.txt"))[0]
units = bench(os.path.join(d, "unit_benchmark.txt"))
print("ns per access    " + " ".join(f"{n:>7}" for n in names))
print("MAME             " + " ".join(f"{v:7.1f}" for v in mame))
for u in units:
    print("unit             " + " ".join(f"{v:7.1f}" for v in u))
p = np.loadtxt(os.path.join(d, "pictimes.txt"), ndmin=2)
p = p[p[:, 0] >= 2001]                              # (a picture of under 1 ms: nothing moved, not a turning one)
ms, st = p[:, 0] / 2001, p[:, 1]
times = open(os.path.join(d, "run_wheel.txt")).read()
m = re.search(r"each picture at rest ([\d. ]+) ms \(([\d ]+) stores\)", times)
rest_ms = np.array([float(x) for x in m.group(1).split()])
rest_st = np.array([float(x) for x in m.group(2).split()])
print(f"MAME: {len(ms)} turning pictures, ms median {np.median(ms):.1f} (min {ms.min():.1f}, max {ms.max():.1f}), "
      f"LCD stores median {np.median(st):.0f} (max {st.max():.0f}); at rest median {np.median(rest_ms):.1f} ms")
for u in units:
    extra = (u[2] - mame[2]) / 1e6                  # ms a store more on the unit
    t = ms + st * extra
    r = rest_ms + rest_st * extra
    print(f"unit, LCD w32 {u[2]:.0f} ns: turning median {np.median(t):.1f} ms (max {t.max():.1f}), "
          f"{1000 / np.median(t):.1f} pictures a second; at rest median {np.median(r):.1f} ms")
if p.shape[1] > 2:
    for r, name in enumerate(("TOP", "MIDDLE", "BOTTOM")):
        m = p[:, 2] == r
        if not m.any():
            continue
        line = f"{name}: {m.sum()} turning pictures, MAME median {np.median(ms[m]):.1f} ms, {np.median(st[m]):.0f} stores"
        for u in units:
            t = ms[m] + st[m] * (u[2] - mame[2]) / 1e6
            line += f"; unit (LCD w32 {u[2]:.0f} ns) median {np.median(t):.1f} ms, {1000 / np.median(t):.1f} a second"
        print(line)
