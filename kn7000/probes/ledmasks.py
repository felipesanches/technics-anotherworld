#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# ledmasks.py LAYOUT COLOURS -- the LED groups src/leds.s lights, as its 20-byte register masks: which bits are red,
# red on the left half of the instrument, red on the right half, green, the eight PANEL MEMORY LEDs, and the tank's
# "lot of LEDs" set (30, a fixed draw).
# LAYOUT: the MAME layout kn7000_mame src/mame/layout/kn7000.lay (where each LED is: its "Full Unit" view puts the
# left panel block at x 0-1000, the screen block at 1000-3000, the right block at 3000-4000; left = x < 2000).
# COLOURS: research-scratch kn7000-leds/README.md (the table "reg | wire | bit | 893 byte | MAME output | function |
# colour", from the service manual's parts list). The MAME output names (cpl_ledN, cpr_ledN) join the two.
#   python3 -I probes/ledmasks.py ~/compartilhado/kn7000_mame/src/mame/layout/kn7000.lay \
#       ~/compartilhado/research-scratch/kn7000-leds/README.md
import re
import sys

lay = open(sys.argv[1]).read().split("\n")
blocks = {}                                  # group name -> (first line, last line)
cur = None
for i, l in enumerate(lay):
    m = re.search(r'<group name="([^"]+)"', l)
    if m:
        cur = (m.group(1), i)
    if "</group>" in l and cur:
        blocks[cur[0]] = (cur[1], i)
        cur = None
view = {}                                    # group -> x offset in the "Full Unit" view
inview = False
for l in lay:
    if '<view name="Full Unit"' in l:
        inview = True
    elif inview and "</view>" in l:
        break
    elif inview:
        m = re.search(r'<group ref="([^"]+)"><bounds x="([-\d.]+)"', l)
        if m:
            view[m.group(1)] = float(m.group(2))
x = {}
for i, l in enumerate(lay):
    m = re.search(r'name="(cp[lr]_led\d+)">(?:<!--.*?-->)?<bounds x="([-\d.]+)"', l)
    if not m:
        continue
    g = [n for n, (a, b) in blocks.items() if a <= i <= b]
    x[m.group(1)] = float(m.group(2)) + view[g[0]]
rows = []
for l in open(sys.argv[2]):
    f = [c.strip() for c in l.strip().strip("|").split("|")]
    if len(f) == 7 and f[0].isdigit():
        rows.append((int(f[0]), int(f[2], 16), f[4], f[5], f[6]))
masks = {k: [0] * 20 for k in ("red", "redl", "redr", "green", "pm", "all")}
missing = []
for reg, bit, out, func, col in rows:
    masks["all"][reg] |= bit
    if col == "red":
        masks["red"][reg] |= bit
        if out not in x:
            missing.append(out)
            continue
        masks["redl" if x[out] < 2000 else "redr"][reg] |= bit
    elif col == "green":
        masks["green"][reg] |= bit
    elif col == "amber":
        masks["pm"][reg] |= bit
# the tank's "lot of LEDs" (cell 0x0B, part 0x3E85): 30 LEDs drawn once with a fixed seed (7000) from all but those
# the tank's other lights use (registers 12 and 13, INTRO & ENDING 1 and 2, BEAT 2 and 3, the four AUTO PLAY CHORD /
# SOUND ARRANGER LEDs: bit 0x10 of registers 4-7)
import random
used = {(12, b) for b in range(8)} | {(13, b) for b in range(8)} | {(0, 0), (1, 0), (4, 0), (5, 0)} | {(r, 4) for r in range(4, 8)}
pool = [(r, b) for r in range(20) for b in range(8) if masks["all"][r] >> b & 1 and (r, b) not in used]
masks["tank"] = [0] * 20
for r, b in random.Random(7000).sample(pool, 30):
    masks["tank"][r] |= 1 << b
for k, v in masks.items():
    n = sum(bin(b).count("1") for b in v)
    print(f"led_{k:6s} {n:3d} LEDs: .byte " + ", ".join(f"0x{b:02X}" for b in v))
if missing:
    print("not in the layout:", " ".join(missing))
