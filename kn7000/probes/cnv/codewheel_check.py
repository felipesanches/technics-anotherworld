#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# codewheel_check.py OUT [BLOB] -- is each picture of the code wheel page that awcnv_wheel.lua took from the LCD's
# display memory (the shown region's 240 rows of the tall frame's wheel, 480 entries each, OUT/<name>.bin; each row's
# state, the angle it was drawn at | 0x10000 bilinear, OUT/<name>.st; "name first-row kind" in OUT/index.txt) exactly
# what tools/codewheel_render.py render_row() makes of the blob (BLOB, default build/wheel/wheel.bin) for every row at
# its own state? A picture at rest ("rest") must also have every row bilinear at one of the 20 numbers' angles, all
# the same; a turning one ("turning") every row nearest at one angle, between numbers. Prints a line a picture and the
# count; writes OUT/<name>.png (the entries in the wheel's colours) for "open" and the first turning picture. Exit
# status 1 when any differs.
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import codewheel_render as cw  # noqa: E402
import numpy as np  # noqa: E402

out = sys.argv[1]
blob = open(sys.argv[2] if len(sys.argv) > 2 else "build/wheel/wheel.bin", "rb").read()
t = cw.tables(blob)
angles = struct.unpack_from("<20H", blob, cw.W_ANGLES)
bad = n = 0
pngs = set()
for line in open(os.path.join(out, "index.txt")):
    name, r0, kind = line.split()
    r0 = int(r0)
    got = np.frombuffer(open(os.path.join(out, name + ".bin"), "rb").read(), np.uint8).reshape(240, 480)
    st = struct.unpack("<240I", open(os.path.join(out, name + ".st"), "rb").read())
    differ, unknown = 0, 0
    for k, s in enumerate(st):
        if s == 0xFFFFFFFF:
            unknown += 1
            continue
        want = cw.render_row(t, r0 + k, s & 0xFFFF, bool(s >> 16))
        differ += int((got[k] != want).sum())
    kinds = set(st)
    one = len(kinds) == 1 and unknown == 0
    s0 = st[0]
    ang, smooth = s0 & 0xFFFF, s0 >> 16
    where = ("number %d" % (angles.index(ang) + 1)) if ang in angles else "between numbers"
    if kind == "rest":
        shape = one and smooth == 1 and ang in angles
    else:
        shape = one and smooth == 0 and ang not in angles
    ok = differ == 0 and shape
    bad += not ok
    n += 1
    print(f"{name:10s} rows {r0:3d}-{r0 + 239:3d}, {kind:7s}: angle {ang:5d} ({ang * 360 / 65536:6.2f} deg, {where}), "
          f"{'bilinear' if smooth else 'nearest '}, one state for every row {one}: {differ} of 115200 entries differ "
          f"from render_row()  {'ok' if ok else 'WRONG'}")
    if name == "open" or (kind == "turning" and "turning" not in pngs):
        pngs.add(kind)
        cw.to_png(got, blob, os.path.join(out, name + ".png"))
print(f"codewheel_check: {n} pictures, {n - bad} exactly render_row()'s, {bad} not")
sys.exit(1 if bad else 0)
