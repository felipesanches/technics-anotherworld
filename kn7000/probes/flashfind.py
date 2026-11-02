#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# flashfind.py OUT -- the frames awcnv_flash.lua saved that show something between two of the game's pictures: for
# each saved frame (OUT/flash.txt, the PNGs in OUT/snap/), how many MAME frames it stayed, and whether its pixels
# are those of the picture before it with another palette ("old picture, new colours": the same pixels are equal,
# by an exact colour-to-colour map from the frame before, in the LCD window) or a mix of the one before and the one
# after (a picture half written). A frame that stayed 2 MAME frames or less between two that stayed longer is
# printed with its verdict.
#   python3 -I probes/flashfind.py ~/compartilhado/tmp/aw-leds2/flash
import glob
import os
import sys
from PIL import Image

out = sys.argv[1]
rows = []
for l in open(os.path.join(out, "flash.txt")):
    f = l.split()
    if f and f[0].endswith(".png"):
        rows.append((int(f[0][1:6]), f[0], int(f[2]), " ".join(f[6:10])))
snaps = {os.path.basename(p): p for p in glob.glob(os.path.join(out, "snap", "**", "*.png"), recursive=True)}


def img(name):
    return Image.open(snaps[name]).convert("RGB")


def mapped(a, b):
    """b's pixels are a's through one colour map (each colour of a becomes one colour of b)."""
    m = {}
    for pa, pb in zip(a.getdata(), b.getdata()):
        if m.setdefault(pa, pb) != pb:
            return False
    return True


def mix(a, b, c):
    """every pixel of b is a's or c's."""
    return all(pb == pa or pb == pc for pa, pb, pc in zip(a.getdata(), b.getdata(), c.getdata()))


stay = [rows[i + 1][0] - rows[i][0] for i in range(len(rows) - 1)] + [99]
n = 0
for i in range(1, len(rows) - 1):
    if stay[i] <= 2 and stay[i - 1] > 2 and stay[i + 1] > 2 or (stay[i] <= 2 and (stay[i - 1] > 2) != (stay[i + 1] > 2)):
        a, b, c = img(rows[i - 1][1]), img(rows[i][1]), img(rows[i + 1][1])
        v = []
        if mapped(a, b) and not mapped(b, a):
            v.append("the picture before through a new palette")
        if mapped(a, b) and mapped(b, a) and a.getdata() != b.getdata():
            v.append("the picture before, recoloured 1:1")
        if mix(a, b, c):
            v.append("a mix of the pictures before and after")
        print(f"{rows[i][1]} vmframe {rows[i][2]} stayed {stay[i]} (before {stay[i - 1]}, after {stay[i + 1]}) pal {rows[i][3]}: "
              + ("; ".join(v) or "neither"))
        n += 1
print(f"flashfind: {len(rows)} frames saved, {n} short ones between longer ones")
