#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
# varsdiff.py A.vars B.vars [first last] -- two per-frame dumps of the 256 VM variables (int16 LE, 512 bytes a frame:
# run_inplog.sh vars.bin, replayawr REF_VARS) compared: the first frame where any variable differs, then each frame
# range over which a variable's difference holds (variable, frames, values at the range's start).
import struct, sys
a = open(sys.argv[1], 'rb').read(); b = open(sys.argv[2], 'rb').read()
n = min(len(a), len(b)) // 512
lo, hi = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (0, n - 1)
fa = [struct.unpack_from('<256h', a, i * 512) for i in range(n)]
fb = [struct.unpack_from('<256h', b, i * 512) for i in range(n)]
print(f'{n} frames in common')
open_ = {}
ranges = []
for f in range(lo, hi + 1):
    d = {v for v in range(256) if fa[f][v] != fb[f][v]}
    for v in list(open_):
        if v not in d: ranges.append((v, open_.pop(v), f - 1))
    for v in d:
        if v not in open_: open_[v] = f
for v, s in open_.items(): ranges.append((v, s, hi))
ranges.sort(key=lambda r: (r[1], r[0]))
for v, s, e in ranges[:80]:
    print(f'var 0x{v:02X}: frames {s}..{e} ({e - s + 1}); at {s}: A={fa[s][v]} B={fb[s][v]}; at {s - 1}: A={fa[s-1][v]} B={fb[s-1][v]}')
print(f'{len(ranges)} ranges')
