#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# greenframes.py LEDLOG -- the runs of frames in which every green LED (the PANEL MEMORY ring's too) is lit (the green flashes: a skeleton, the
# lake's explosion; src/leds.s LED_SKEL_T) and whether any non-green LED is lit with them. LEDLOG: a MAME replay's LED
# log (probes/cnv/awcnv_inplog.lua AW_LEDLOG); column 6 is the shadow (20 registers, hex). Frames where every LED is
# lit (a flash of the intro, a blast) are not counted.
#   python3 -I probes/greenframes.py OUT.led
import sys

GREEN = bytes.fromhex("00101010111301127FF203830000000100000200")  # the green LEDs and the PANEL MEMORY ring (green too)
ALL = bytes.fromhex("3F3F3F3F1F1F1F1FFFFAFFFFFFFF030103030303")


def covers(b, m):
    return all((x & y) == y for x, y in zip(b, m))


runs, cur = [], None
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) < 9 or f[6] == "-":
        continue
    t, sh = int(f[0]), bytes.fromhex(f[6])
    if covers(sh, GREEN) and not covers(sh, ALL):
        other = any(x & a & ~g & 0xFF for x, a, g in zip(sh, ALL, GREEN))
        if cur and cur[1] == t - 1:
            cur[1], cur[2] = t, cur[2] or other
        else:
            cur = [t, t, other]
            runs.append(cur)
for a, b, o in runs:
    print(f"greenframes: {a}-{b}{' (another LED lit too)' if o else ''}")
print(f"greenframes: {len(runs)} runs")
