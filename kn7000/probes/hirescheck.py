#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# hirescheck.py PAGES.bin [IDS] -- does the 384x240 page show the build-time enlargement of each bitmap
# (tools/aw_hires.py, the card's AWHxx.AW) rather than the repeated-row one (display.s PageUp)? PAGES.bin: a
# replay's page dumps (probes/cnv/run_inplog.sh OUT/pages.bin, 384x240 a frame, a byte a pixel), at 384x240
# (AW_HIRES=1). For each bitmap id (default: all twelve), the frame whose page agrees best with AWHxx.AW unpacked
# from build/sdcard/, and how many of its pixels agree with that and with the repeated-row enlargement of the
# 320x200 bitmap (build/res/resource-0xNN.bin), over the whole page and over the pixels where the two enlargements
# differ (polygons and Lester drawn over the bitmap lower both alike). Pass ("hires"): more of the page as AWH, and
# where they differ ten times more as AWH than as the repeated rows; "-" for a bitmap the replay never shows. With
# --scroll, every third frame also scrolled -180..180 rows (a bitmap shown through a scrolled copy: 3E84's 0x43).
#   python3 -I probes/hirescheck.py ~/compartilhado/tmp/aw-hires/in/pages.bin 0x12 0x13 0x47
#   python3 -I probes/hirescheck.py ~/compartilhado/tmp/aw-hires/wf/pages.bin --scroll 0x43
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import aw_extract  # noqa: E402
import aw_hires  # noqa: E402

W, H = aw_hires.W, aw_hires.H
N = W * H
root = os.path.join(HERE, "..", "build")
pages = np.fromfile(sys.argv[1], np.uint8)
pages = pages[:len(pages) // N * N].reshape(-1, H, W) & 15
args = sys.argv[2:]
scroll = "--scroll" in args                             # also the page scrolled vertically (a scrolled copy of it)
args = [a for a in args if a != "--scroll"]
ids = [int(a, 0) for a in args] or sorted(aw_hires.PALETTES)
for b in ids:
    packed = open(os.path.join(root, "sdcard", f"AWH{b:02X}.AW"), "rb").read()
    big = np.frombuffer(aw_extract.unpack(packed, N), np.uint8).reshape(H, W)
    src = aw_hires.planes_to_indices(open(os.path.join(root, "res", f"resource-0x{b:02x}.bin"), "rb").read())
    near = aw_hires.nearest(src)
    differ = big != near                                # where the two enlargements differ: what tells them apart
    best = (0,)
    for f in range(0, len(pages), 3 if scroll else 1):
        for dy in (range(-180, 181) if scroll else (0,)):
            pg = pages[f][max(dy, 0):H + min(dy, 0)]    # page row r + dy against bitmap row r
            sl = slice(max(-dy, 0), H - max(dy, 0))
            m = (pg == big[sl]).mean()
            if m > best[0]:
                d = differ[sl]
                best = (m, f, dy, (pg == near[sl]).mean(), (pg[d] == big[sl][d]).mean(), (pg[d] == near[sl][d]).mean())
    if best[0] < 0.5:
        print(f"hirescheck: 0x{b:02X}: -")
        continue
    a_big, f, dy, a_near, d_big, d_near = best
    ok = a_big > a_near and d_big > 10 * d_near
    print(f"hirescheck: 0x{b:02X}: frame {f}" + (f", scrolled {dy} rows" if dy else "") +
          f": {100 * a_big:.1f} % of the page as AWH{b:02X}.AW, {100 * a_near:.1f} % as the repeated rows; where they "
          f"differ {100 * d_big:.1f} % as AWH, {100 * d_near:.1f} % as the repeated rows: {'hires' if ok else 'NOT hires'}")
