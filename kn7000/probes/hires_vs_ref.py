#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
# hires_vs_ref.py HI.bin HI.idx REF.bin REF.idx [-o DIR FRAME...] -- the KN7000 build's 384x240 pages (run_inplog.sh
# with AW_HIRES=1, or awcnv_cksum.lua with AWCK_HIRES=1) against the reference's 320x200 ones (rustyworld replayawr REF_BIN) for the same ticks: each 384x240
# page brought to 320x200 as display.s PageDown does (row t from t + ceil(t/5), pixel 5g+k from 6g + (0,2,3,4,5)[k])
# and compared pixel by pixel. The two cannot be equal (the polygons are drawn at the higher resolution: their
# edges fall elsewhere); a scene the high-resolution path got wrong shows as agreement far below the rest.
# Prints per-tick agreement percentiles and the worst ticks; -o writes, for the frames given, ref | hi (x1) PNGs.
import sys
args = sys.argv[1:]
out, frames = None, []
if '-o' in args:
    i = args.index('-o'); out = args[i + 1]; frames = [int(x) for x in args[i + 2:]]; args = args[:i]
hb, hi_idx, rb, rf_idx = args
def idx(p): return [int(l.split()[0]) for l in open(p) if l.strip()]
ht, rt = idx(hi_idx), idx(rf_idx)
H, R = open(hb, 'rb').read(), open(rb, 'rb').read()
HS, RS = 384 * 240, 320 * 200
assert len(H) == len(ht) * HS and len(R) == len(rt) * RS
hpos = {t: i for i, t in enumerate(ht)}
rpos = {t: i for i, t in enumerate(rt)}
cols = [6 * (x // 5) + (0, 2, 3, 4, 5)[x % 5] for x in range(320)]
rows = [t + (t + 4) // 5 for t in range(200)]
import numpy as np
Hn = np.frombuffer(H, dtype=np.uint8).reshape(-1, 240, 384) & 15
Rn = np.frombuffer(R, dtype=np.uint8).reshape(-1, 200, 320) & 15
sel = np.ix_(rows, cols)
res = []
for t in sorted(set(ht) & set(rt)):
    down = Hn[hpos[t]][sel]
    res.append((float((down == Rn[rpos[t]]).mean() * 100), t))
v = sorted(p for p, _ in res)
print(f'{len(res)} ticks; agreement % min {v[0]:.1f}, 1st pct {v[len(v)//100]:.1f}, median {v[len(v)//2]:.1f}, max {v[-1]:.1f}')
print('worst:', ', '.join(f'{t}:{p:.1f}' for p, t in sorted(res)[:10]))
if out:
    from PIL import Image
    ramp = [(i * 17,) * 3 for i in range(16)]
    for t in frames:
        h = H[hpos[t] * HS:(hpos[t] + 1) * HS]; r = R[rpos[t] * RS:(rpos[t] + 1) * RS]
        im = Image.new('RGB', (320 + 8 + 384, 240))
        px = im.load()
        for y in range(200):
            for x in range(320): px[x, y + 20] = ramp[r[y * 320 + x] & 15]
        for y in range(240):
            for x in range(384): px[328 + x, y] = ramp[h[y * 384 + x] & 15]
        im.resize((im.width * 2, im.height * 2), Image.NEAREST).save(f'{out}/hi_{t:05d}.png')
