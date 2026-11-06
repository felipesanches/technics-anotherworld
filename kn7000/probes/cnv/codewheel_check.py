#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# codewheel_check.py OUT [BLOB] -- is each picture of the code wheel page that awcnv_wheel.lua took from the LCD (the
# wheel's 256 x 240 entries of FB8, OUT/<name>.bin, "name angle smooth" in OUT/index.txt) exactly what
# tools/codewheel_render.py render() makes of the blob (BLOB, default build/wheel/wheel.bin) at that angle, nearest
# (turning) or bilinear (at rest)? A picture at rest must also be at one of the 20 numbers' angles, one turning at none.
# Prints a line a picture and the count; writes OUT/<name>.png (the LCD's entries in the wheel's colours, 2x) for the
# two pictures named "open" and "p1_mid". Exit status 1 when any differs.
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import codewheel_render as cw  # noqa: E402
import numpy as np  # noqa: E402

out = sys.argv[1]
blob = open(sys.argv[2] if len(sys.argv) > 2 else "build/wheel/wheel.bin", "rb").read()
angles = struct.unpack_from("<20H", blob, cw.W_ANGLES)
bad = 0
n = 0
for line in open(os.path.join(out, "index.txt")):
    name, ang, smooth = line.split()
    ang, smooth = int(ang), int(smooth)
    got = np.frombuffer(open(os.path.join(out, name + ".bin"), "rb").read(), np.uint8).reshape(240, 256)
    want = cw.render(blob, ang, bool(smooth))
    differ = int((got != want).sum())
    where = ("number %d" % (angles.index(ang) + 1)) if ang in angles else "between numbers"
    ok = differ == 0 and ((smooth == 1) == (ang in angles))
    bad += not ok
    n += 1
    print(f"{name:10s} angle {ang:5d} ({ang * 360 / 65536:6.2f} deg, {where}), {'bilinear' if smooth else 'nearest '}: "
          f"{differ} of 61440 entries differ from render()  {'ok' if ok else 'WRONG'}")
    if name in ("open", "p1_mid"):
        cw.to_png(got, blob, os.path.join(out, name + ".png"), 2)
print(f"codewheel_check: {n} pictures, {n - bad} exactly render()'s, {bad} not")
sys.exit(1 if bad else 0)
