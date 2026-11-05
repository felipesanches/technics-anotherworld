#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# ledcells.py LAYOUT COLOURS -- every panel LED with its place, for the credits' light show (src/leds.s fin_lights,
# fin_party): the 101 LEDs of COLOURS' table, ordered left to right (then top to bottom) by where the MAME layout's
# "Full Unit" view puts them (the left block at (0, 247), the screen block at (1000, 0), the right block at
# (3000, 247)), the screen block squeezed to a tenth of its width (it has 2 LEDs; the blocks' inner edges then meet
# 200 apart), each its register and bit, its column xq (0-63, the LEDs' leftmost to their rightmost) and its row yq
# (0-15, top to bottom). LAYOUT: kn7000_mame src/mame/layout/kn7000.lay; COLOURS: research-scratch
# kn7000-leds/README.md (reg | wire | bit | 893 byte | MAME output | function | colour). Prints the table as .byte
# lines, then one line per LED.
#   python3 -I probes/ledcells.py ~/compartilhado/kn7000_mame/src/mame/layout/kn7000.lay \
#       ~/compartilhado/research-scratch/kn7000-leds/README.md
import re
import sys

ORIGIN = {"left_block": (0, 247, 1), "screen_block": (1000, 0, 0.1), "right_block": (1200, 247, 1)}
cols = {}
for l in open(sys.argv[2]):
    f = [c.strip() for c in l.strip().strip("|").split("|")]
    if len(f) == 7 and f[0].isdigit():
        cols[f[4]] = (int(f[0]), int(f[2], 16), f[5], f[6])
pos, cur = {}, None
for l in open(sys.argv[1]):
    m = re.search(r'<group name="([^"]+)"', l)
    if m:
        cur = m.group(1)
    m = re.search(r'name="(cp[lr]_led\d+)"[^>]*>(?:<!--.*?-->)?<bounds x="([-\d.]+)" y="([-\d.]+)" width="([\d.]+)" '
                  r'height="([\d.]+)"', l)
    if m and cur in ORIGIN and m.group(1) not in pos:
        ox, oy, sx = ORIGIN[cur]
        pos[m.group(1)] = (ox + sx * (float(m.group(2)) + float(m.group(4)) / 2),
                           oy + float(m.group(3)) + float(m.group(5)) / 2)
leds = [(x, y, o) for o, (x, y) in pos.items() if o in cols]
missing = sorted(set(cols) - set(pos))
if missing:
    sys.exit(f"ledcells: no place in the layout for {', '.join(missing)}")
x0, x1 = min(x for x, _, _ in leds), max(x for x, _, _ in leds)
y0, y1 = min(y for _, y, _ in leds), max(y for _, y, _ in leds)
out = []
for x, y, o in leds:
    xq = round((x - x0) * 63 / (x1 - x0))
    yq = round((y - y0) * 15 / (y1 - y0))
    out.append((xq, yq, o))
out.sort()
print(f"ledcells: {len(out)} LEDs, x {x0:.0f}-{x1:.0f}, y {y0:.0f}-{y1:.0f}")
vals = []
for xq, yq, o in out:
    vals += [cols[o][0], cols[o][1], xq, yq]
for i in range(0, len(vals), 16):
    print("    .byte   " + ", ".join(f"0x{v:02X}" if k % 4 == 1 else f"{v}" for k, v in enumerate(vals[i:i + 16])))
for i, (xq, yq, o) in enumerate(out):
    print(f"ledcells:   {i:3d} xq {xq:2d} yq {yq:2d}  {o:10s} {cols[o][0]:2d} 0x{cols[o][1]:02X} {cols[o][3]:6s} {cols[o][2]}")
