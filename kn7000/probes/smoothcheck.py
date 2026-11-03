#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# smoothcheck.py NEAREST.bin SMOOTH.bin FRAME PALRES PALID [-o OUT.png] -- is the bilinear filter (src/smooth.s) what
# it should be? NEAREST.bin and SMOOTH.bin: two replays' page dumps of the same session (run_inplog.sh OUT/pages.bin,
# 384x240 a frame, a byte a pixel), the first with the filter off (or a build before it), the second with it on.
# At FRAME, the 320x200 picture is read back from NEAREST's page (source pixel s at page pixel ceil(6s/5)) and
# enlarged here as smooth.s does it, in palette PALID of the palette resource PALRES (build/res/resource-0xNN.bin, 32
# bytes a palette: 16 colours, red in byte 0's low nibble, green and blue in byte 1's): output (x, y) samples source
# ((10x - 1) / 12, (10y - 1) / 12), clamped at 0, the four neighbours weighted in twelfths; four equal indices give
# that index, else the mix of their 4-bit channels, each (sum + 72) x 3641 >> 19, and the nearest colour (squared
# distance, the lowest index on a tie). Prints how many of SMOOTH's pixels differ from that (0: the filter as
# designed) and from NEAREST; with -o, NEAREST | SMOOTH | the model, in the palette's colours, x2.
#   python3 -I probes/smoothcheck.py A/pages.bin B/pages.bin 150 build/res/resource-0x14.bin 0x17 -o cmp.png
import sys

args = sys.argv[1:]
out = None
if "-o" in args:
    i = args.index("-o")
    out = args[i + 1]
    args = args[:i] + args[i + 2:]
na, sm, frame, palres, palid = args[0], args[1], int(args[2]), args[3], int(args[4], 0)
W, H, SW, SH = 384, 240, 320, 200
N = W * H


def page(path):
    with open(path, "rb") as f:
        f.seek(N * frame)
        return f.read(N)


a, b = page(na), page(sm)
p = open(palres, "rb").read()[32 * palid: 32 * palid + 32]
pal = [(p[2 * i] & 15, p[2 * i + 1] >> 4, p[2 * i + 1] & 15) for i in range(16)]
src = [[a[((6 * sy + 4) // 5) * W + (6 * sx + 4) // 5] & 15 for sx in range(SW)] for sy in range(SH)]
near = {}


def nearest(c):
    if c not in near:
        near[c] = min(range(16), key=lambda i: (sum((u - v) ** 2 for u, v in zip(c, pal[i])), i))
    return near[c]


model = bytearray(N)
for y in range(H):
    Y = max(0, 10 * y - 1)
    y0, fy = divmod(Y, 12)
    y1 = min(y0 + 1, SH - 1)
    for x in range(W):
        X = max(0, 10 * x - 1)
        x0, fx = divmod(X, 12)
        x1 = min(x0 + 1, SW - 1)
        q = (src[y0][x0], src[y0][x1], src[y1][x0], src[y1][x1])
        if q[0] == q[1] == q[2] == q[3]:
            model[y * W + x] = q[0]
            continue
        w = ((12 - fx) * (12 - fy), fx * (12 - fy), (12 - fx) * fy, fx * fy)
        c = tuple(((sum(wk * pal[qk][ch] for wk, qk in zip(w, q)) + 72) * 3641) >> 19 for ch in range(3))
        model[y * W + x] = nearest(c)
dm = sum(1 for u, v in zip(b, model) if u != v)
dn = sum(1 for u, v in zip(b, a) if u != v)
print(f"smoothcheck: frame {frame}: {dm} pixels differ from the model, {dn} from the nearest-pixel page")
if out:
    from PIL import Image
    rgb = [(r * 17, g * 17, bl * 17) for r, g, bl in pal]
    flat = [c for t in rgb for c in t] + [0] * (768 - 48)
    im2 = Image.new("P", (3 * W, H))
    for k, buf in enumerate((a, b, bytes(model))):
        im2.paste(Image.frombytes("P", (W, H), bytes(v & 15 for v in buf)), (k * W, 0))
    im2.putpalette(flat)
    im2.convert("RGB").resize((6 * W, 2 * H), Image.NEAREST).save(out)
