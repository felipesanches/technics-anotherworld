#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# onelamp.py LEDLOG REG BIT -- a one-LED effect (the stranded guard's red lamp, src/leds.s W_GLIGHT: LATIN & WORLD,
# register 3 bit 0x02): the runs of frames that LED is lit and dark, from the first frame it lights to the last, and
# the frames in which any other LED is lit. LEDLOG: a MAME replay's LED log (probes/cnv/awcnv_inplog.lua AW_LEDLOG; a
# line a VM frame, field 0 the frame, field 6 the shadow: 20 registers, hex); the LEDs are led_all's bits (registers
# 14-19 also hold firmware bits that are not LEDs). Pass for the guard's lamp: lit 3, dark 2, over and over, nothing
# else lit.
#   python3 -I probes/onelamp.py T/lamp.led 3 0x02
import sys

ALL = bytes.fromhex("3F3F3F3F1F1F1F1FFFFAFFFFFFFF030103030303")
reg, bit = int(sys.argv[2], 0), int(sys.argv[3], 0)
rows = []
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) >= 7 and f[6] != "-":
        rows.append((int(f[0]), bytes.fromhex(f[6])))
lit = [sh[reg] & bit != 0 for _, sh in rows]
on = [i for i, x in enumerate(lit) if x]
if not on:
    sys.exit(f"onelamp: register {reg} bit 0x{bit:02X} never lit in {len(rows)} frames")
runs = []                                               # (lit?, frames)
for i in range(on[0], on[-1] + 1):
    if runs and runs[-1][0] == lit[i]:
        runs[-1][1] += 1
    else:
        runs.append([lit[i], 1])
pat = {}
for k in range(0, len(runs) - 1, 2):
    pat[(runs[k][1], runs[k + 1][1])] = pat.get((runs[k][1], runs[k + 1][1]), 0) + 1
other = [fr for fr, sh in rows if any(x & a & ~(bit if r == reg else 0) for r, (x, a) in enumerate(zip(sh, ALL)))]
print(f"onelamp: register {reg} bit 0x{bit:02X} lit from frame {rows[on[0]][0]} to {rows[on[-1]][0]}, {len(runs) // 2 + 1} "
      f"times; (lit, dark) frames: " + ", ".join(f"{a}+{b} x{n}" for (a, b), n in sorted(pat.items(), key=lambda t: -t[1])))
print(f"onelamp: frames with another LED lit: {len(other)}" + (f" ({other[0]}..{other[-1]})" if other else ""))
