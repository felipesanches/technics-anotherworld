#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# ledrings.py LAYOUT COLOURS [R1 R2 ...] -- the panel's LEDs by their distance from the PANEL MEMORY ring: the masks
# src/leds.s led_fw0.. (the glass crash's fireworks, LEV_GLASS) light, one per ring of distance, nearest first.
# LAYOUT: the MAME layout kn7000_mame src/mame/layout/kn7000.lay (its "Full Unit" view: the left block at (0, 247),
# the screen block at (1000, 0), the right block at (3000, 247), each at scale 1); an LED's place is its bounds'
# centre there. COLOURS: research-scratch kn7000-leds/README.md (the table "reg | wire | bit | 893 byte | MAME output
# | function | colour"; the PANEL MEMORY LEDs are its "amber"). The distance is from the ring's centre (the mean of its 8
# LEDs), in layout units; R1 R2 ...: the rings' outer radii (default 250 500 900 1400; past the last: the last ring).
# Prints each LED's distance, then each ring's mask as the 20 register bytes.
#   python3 -I probes/ledrings.py ~/compartilhado/kn7000_mame/src/mame/layout/kn7000.lay \
#       ~/compartilhado/research-scratch/kn7000-leds/README.md
import math
import re
import sys

OFFS = {"left_block": (0, 247), "screen_block": (1000, 0), "right_block": (3000, 247), "sd_block": (1750, 916)}
lay = open(sys.argv[1]).read().split("\n")
radii = [float(a) for a in sys.argv[3:]] or [250, 500, 900, 1400]
pos, cur = {}, None
for l in lay:
    m = re.search(r'<group name="([^"]+)"', l)
    if m:
        cur = m.group(1)
    if "</group>" in l:
        cur = None
    m = re.search(r'name="(cp[lr]_led\d+)"[^>]*>(?:<!--.*?-->)?<bounds x="([-\d.]+)" y="([-\d.]+)" width="([\d.]+)" '
                  r'height="([\d.]+)"', l)
    if m and cur in OFFS:
        ox, oy = OFFS[cur]
        pos[m.group(1)] = (float(m.group(2)) + float(m.group(4)) / 2 + ox, float(m.group(3)) + float(m.group(5)) / 2 + oy)
rows = []
for l in open(sys.argv[2]):
    f = [c.strip() for c in l.strip().strip("|").split("|")]
    if len(f) == 7 and f[0].isdigit():
        rows.append((int(f[0]), int(f[2], 16), f[4], f[5], f[6]))
pm = [pos[o] for r, b, o, fn, c in rows if c == "amber"]
cx, cy = sum(p[0] for p in pm) / len(pm), sum(p[1] for p in pm) / len(pm)
print(f"ledrings: the PANEL MEMORY ring's centre ({cx:.0f}, {cy:.0f})")
masks = [[0] * 20 for _ in radii]
missing = []
for reg, bit, out, fn, col in sorted(rows, key=lambda r: math.dist(pos.get(r[2], (1e9, 1e9)), (cx, cy))):
    if out not in pos:
        missing.append(out)
        continue
    if col == "amber":
        continue
    d = math.dist(pos[out], (cx, cy))
    k = next((i for i, r in enumerate(radii) if d < r), len(radii) - 1)
    masks[k][reg] |= bit
    print(f"ledrings: {d:6.0f} ring {k} reg {reg:2d} bit 0x{bit:02X} {out:10s} {fn} ({col})")
for k, m in enumerate(masks):
    n = sum(bin(b).count("1") for b in m)
    print(f"led_fw{k} {n:3d} LEDs: .byte " + ", ".join(f"0x{b:02X}" for b in m))
if missing:
    print("ledrings: not in the layout:", " ".join(missing))
