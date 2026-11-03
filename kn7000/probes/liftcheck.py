#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# liftcheck.py LEDLOG -- the lift's chase round the PANEL MEMORY ring (src/leds.s led_lift): for every frame with a
# ring LED lit, the ring positions lit (0-7: PANEL MEMORY 2, 1, 8, 7, 6, 5, 4, 3, left to right) as a row of digits;
# then the lead's path (the position lit in a frame and not in the one before, or the only one lit), which must sweep
# 0..7 and back, and the most positions lit at once (the lead and the one behind it: 2). LEDLOG: a MAME replay's LED
# log (probes/cnv/awcnv_inplog.lua AW_LEDLOG).
#   python3 -I probes/liftcheck.py OUT.led
import sys

SEQ = [(8, 0x40), (15, 0x01), (9, 0x80), (9, 0x40), (9, 0x20), (8, 0x08), (8, 0x10), (8, 0x20)]
frames = []
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) >= 9 and f[6] != "-":
        sh = bytes.fromhex(f[6])
        lit = [k for k, (r, b) in enumerate(SEQ) if sh[r] & b]
        if lit:
            frames.append((int(f[0]), lit))
if not frames:
    print("liftcheck: no ring LED lit")
    sys.exit()
most = max(len(l) for _, l in frames)
path, prev = [], set()
for t, lit in frames:
    new = [k for k in lit if k not in prev]
    if len(new) == 1 and (not path or path[-1] != new[0]):
        path.append(new[0])
    prev = set(lit)
for t, lit in frames[:60]:
    print(f"liftcheck: {t:5d} {''.join(str(k) for k in lit)}")
print(f"liftcheck: {len(frames)} frames with ring LEDs (frames {frames[0][0]}-{frames[-1][0]}); at most {most} lit at once")
print(f"liftcheck: the lead's path {''.join(str(k) for k in path)}")
