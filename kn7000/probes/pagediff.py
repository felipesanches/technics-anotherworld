#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
# pagediff.py A.bin B.bin FRAME [FRAME...] -o OUTDIR -- two 64000-byte-per-frame page dumps (run_inplog.sh pages.bin,
# replayawr REF_BIN) at the given frames: A | B | difference (red where they differ), x2, one PNG per frame; prints
# the count and bounding box of differing pixels. Colours are the 16 indices on a fixed ramp (not the game palette).
import sys
from PIL import Image
args = sys.argv[1:]
out = args[args.index('-o') + 1]; args = args[:args.index('-o')]
a, b, frames = args[0], args[1], [int(x) for x in args[2:]]
W, H, N = 320, 200, 64000
ramp = [(i * 17, i * 17, i * 17) for i in range(16)]
for f in frames:
    pa = open(a, 'rb'); pa.seek(f * N); da = pa.read(N)
    pb = open(b, 'rb'); pb.seek(f * N); db = pb.read(N)
    im = Image.new('RGB', (W * 3, H))
    px = im.load(); xs = []; ys = []
    for i in range(N):
        x, y = i % W, i // W
        px[x, y] = ramp[da[i] & 15]; px[x + W, y] = ramp[db[i] & 15]
        if da[i] != db[i]:
            px[x + 2 * W, y] = (255, 0, 0); xs.append(x); ys.append(y)
        else:
            px[x + 2 * W, y] = tuple(c // 3 for c in ramp[da[i] & 15])
    im.resize((W * 6, H * 2), Image.NEAREST).save(f'{out}/diff_{f:05d}.png')
    print(f, len(xs), (min(xs), min(ys), max(xs), max(ys)) if xs else '-')
