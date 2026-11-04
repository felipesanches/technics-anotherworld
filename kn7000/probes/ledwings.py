#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# ledwings.py LAYOUT COLOURS -- the dragon's wings (src/leds.s led_wing_l / led_wing_r): the red LEDs of the RHYTHM
# GROUP (left of the screen: the left wing) and of the SOUND GROUP (right of it: the right wing), in columns ordered
# from the panel's centre outwards, each column its top row's LED and its bottom row's (or none).
# LAYOUT: the MAME layout kn7000_mame src/mame/layout/kn7000.lay ("Full Unit": the left block at (0, 247), the right
# block at (3000, 247)); COLOURS: research-scratch kn7000-leds/README.md (reg | wire | bit | 893 byte | MAME output |
# function | colour). A group is the red LEDs of its block under its label: the rhythm group x 560-990 of the left
# block, the sound group x 30-450 of the right block, both y 60-160 (the two rows of buttons, y 77 and 149).
# Prints each column (x, its LEDs' functions) and the tables as .byte lines: per column, the top LED's register and
# bit, then the bottom's (0, 0: none).
#   python3 -I probes/ledwings.py ~/compartilhado/kn7000_mame/src/mame/layout/kn7000.lay \
#       ~/compartilhado/research-scratch/kn7000-leds/README.md
import re
import sys

lay = open(sys.argv[1]).read().split("\n")
cols = {}
for l in open(sys.argv[2]):
    f = [c.strip() for c in l.strip().strip("|").split("|")]
    if len(f) == 7 and f[0].isdigit():
        cols[f[4]] = (int(f[0]), int(f[2], 16), f[5], f[6])
pos, cur = {}, None
for l in lay:
    m = re.search(r'<group name="([^"]+)"', l)
    if m:
        cur = m.group(1)
    m = re.search(r'name="(cp[lr]_led\d+)"[^>]*>(?:<!--.*?-->)?<bounds x="([-\d.]+)" y="([-\d.]+)" width="([\d.]+)" '
                  r'height="([\d.]+)"', l)
    if m and cur in ("left_block", "right_block"):
        pos[m.group(1)] = (cur, float(m.group(2)) + float(m.group(4)) / 2, float(m.group(3)) + float(m.group(5)) / 2)


def group(block, x0, x1, centre_right):
    leds = [(x, y, o) for o, (b, x, y) in pos.items() if b == block and x0 <= x <= x1 and 60 <= y <= 160
            and o in cols and cols[o][3] == "red"]
    xs = sorted({round(x) for x, _, _ in leds}, reverse=centre_right)
    out = []
    for x in xs:
        top = [o for lx, y, o in leds if round(lx) == x and y < 110]
        bot = [o for lx, y, o in leds if round(lx) == x and y >= 110]
        out.append((x, top[0] if top else None, bot[0] if bot else None))
    return out


for name, block, x0, x1, cr in (("led_wing_l", "left_block", 560, 990, True), ("led_wing_r", "right_block", 30, 450, False)):
    g = group(block, x0, x1, cr)
    print(f"ledwings: {name}: {len(g)} columns, {sum((t is not None) + (b is not None) for _, t, b in g)} LEDs, "
          f"from the centre out")
    for x, t, b in g:
        print(f"ledwings:   x {x:4d}  {cols[t][2] if t else '-':22s} {cols[b][2] if b else '-'}")
    vals = []
    for _, t, b in g:
        vals += [cols[t][0], cols[t][1]] if t else [0, 0]
        vals += [cols[b][0], cols[b][1]] if b else [0, 0]
    print(f"{name}: .byte " + ", ".join(f"{v}" if i % 2 == 0 else f"0x{v:02X}" for i, v in enumerate(vals)))
