#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# aw_hires.py -- the screen bitmaps at 384x240, made at build time for the high-resolution pages.
#
# The game's twelve bitmaps are 320x200, 16 colours. The 384x240 page shows each one 6/5 larger. Enlarging it at
# run time by repeating every fifth row and column (display.s PageUp) gives uneven line widths and stepped
# diagonals; blending at run time cost the game a pause at each bitmap. So the enlargement is made here, once, and
# the card carries it (AWHxx.AW, aw_extract.py --parts).
#
# Method, for each output pixel (x, y) (centre-aligned: source point u = (x + 0.5) * 5/6 - 0.5, v likewise):
#   1. interpolate the picture's colours there with a Catmull-Rom bicubic over the 4x4 source pixels around it, in
#      the palette's RGB (each channel 0..15), under the palette the game shows the bitmap with (PALETTES below);
#   2. choose, among the colours of the 2x2 source pixels around the point and those of the 4x4 that lie inside the
#      2x2's RGB box (a shade in between: no colour from elsewhere), the one nearest that value.
# Step 2 keeps the picture's own colours (a page pixel is one of 16 indices, and the palette changes under it):
# every output pixel is an index its neighbourhood has. Step 1 puts each edge where the smooth surface crosses
# halfway, so a contour follows the shape instead of repeating a row or column every fifth pixel.
#
# Output: 384x240 bytes, one index a pixel (the page's own format), ByteKiller-packed (pack(): the format
# aw_extract.unpack and cnv_main.s BkUnpack read).
#   python3 -I tools/aw_hires.py build/res 0x43 [-o cmp.png]     # nearest | this, x2, as a PNG
import os
import struct
import sys

import numpy as np

SW, SH, W, H = 320, 200, 384, 240
# bitmap id -> (palette resource, {palette number: weight}): the palettes the game shows each one with, weighted by
# how long (research-scratch kn7000-aw-reference/hires/bitmap_palettes.py over the reference VM's event logs), less
# those under which two of its colours look the same (the fades, the near-black 1D of 3E84). 0x46 and 0x90 are drawn
# just before 0x45 and 0x91 and shown later from a copy, under theirs; 0x48, 0x49: 3E83 bytecode 01B9 / 01F6; 0x53
# is the title's other version (0x13's palette).
PALETTES = {0x12: (0x14, {0x04: 1}), 0x13: (0x14, {0x09: 1}), 0x47: (0x14, {0x0F: 1}), 0x53: (0x14, {0x09: 1}),
            0x48: (0x1D, {0x19: 1}), 0x49: (0x1D, {0x19: 1}),
            0x43: (0x20, {0x06: 942, 0x11: 744, 0x09: 576, 0x18: 316}), 0x44: (0x20, {0x08: 286, 0x0D: 14}),
            0x45: (0x20, {0x08: 1}), 0x46: (0x20, {0x08: 1}),
            0x90: (0x26, {0x01: 1}), 0x91: (0x26, {0x01: 1})}


def planes_to_indices(b):
    """The MS-DOS bitmap: four 8000-byte planes, plane k = bit k of each pixel, MSB leftmost."""
    a = np.frombuffer(b, np.uint8).reshape(4, SH, SW // 8)
    bits = np.unpackbits(a, axis=2)                     # (4, 200, 320), MSB first
    return (bits[0] | bits[1] << 1 | bits[2] << 2 | bits[3] << 3).astype(np.uint8)


def palette(res, n):
    p = res[32 * n:32 * n + 32]
    return np.array([(p[2 * i] & 15, p[2 * i + 1] >> 4, p[2 * i + 1] & 15) for i in range(16)], np.float64)


def cubic(t):
    """Catmull-Rom weights for the 4 taps at -1, 0, 1, 2 given the fraction t."""
    t2, t3 = t * t, t * t * t
    return np.stack([(-t3 + 2 * t2 - t) / 2, (3 * t3 - 5 * t2 + 2) / 2, (-3 * t3 + 4 * t2 + t) / 2, (t3 - t2) / 2])


def upscale(src, pal):
    """src: (200, 320) indices; pal: (16, 3k) the RGB 0..15 of k palettes side by side, each scaled by the square
    root of its weight (a distance is then the weighted sum of the k palettes' distances) -> (240, 384) indices."""
    rgb = pal[src]                                      # (200, 320, 3)
    u = (np.arange(W) + 0.5) * SW / W - 0.5
    v = (np.arange(H) + 0.5) * SH / H - 0.5
    u0, v0 = np.floor(u).astype(int), np.floor(v).astype(int)
    wu, wv = cubic(u - u0), cubic(v - v0)               # (4, W), (4, H)
    cx = [np.clip(u0 + k, 0, SW - 1) for k in (-1, 0, 1, 2)]
    cy = [np.clip(v0 + k, 0, SH - 1) for k in (-1, 0, 1, 2)]
    val = np.zeros((H, W, pal.shape[1]))
    for j in range(4):
        for i in range(4):
            val += (wv[j][:, None] * wu[i][None, :])[..., None] * rgb[cy[j][:, None], cx[i][None, :]]
    idx = np.stack([src[cy[j][:, None], cx[i][None, :]] for j in range(4) for i in range(4)])  # (16, H, W)
    near = [5, 6, 9, 10]                                # the 2x2 around the point
    lo = np.min(pal[idx[near]], axis=0) - 0.5           # their RGB box (H, W, 3k), a half step of slack
    hi = np.max(pal[idx[near]], axis=0) + 0.5
    best = np.full((H, W), np.inf)
    out = np.zeros((H, W), np.uint8)
    for k in range(16):
        c = pal[idx[k]]                                 # (H, W, 3)
        ok = np.ones((H, W), bool) if k in near else np.all((c >= lo) & (c <= hi), axis=2)
        d = np.sum((c - val) ** 2, axis=2)
        d = np.where(ok, d, np.inf)
        # equal distance: the lower index, as a fixed rule (the same picture every build)
        better = (d < best) | ((d == best) & (idx[k] < out))
        out = np.where(better, idx[k], out).astype(np.uint8)
        best = np.where(better, d, best)
    # No source pixel's colour may vanish: when none of the page pixels whose centres fall inside a source pixel has
    # its colour (a lone dot, a one-pixel line seen diagonally), the one nearest its centre takes it.
    fx = np.floor((np.arange(W) + 0.5) * SW / W).astype(int)    # the source pixel each page centre falls in
    fy = np.floor((np.arange(H) + 0.5) * SH / H).astype(int)
    first = out.copy()
    for sy in range(SH):
        ys = np.nonzero(fy == sy)[0]
        for sx in range(SW):
            xs = np.nonzero(fx == sx)[0]
            c = src[sy, sx]
            if not np.any(first[ys[0]:ys[-1] + 1, xs[0]:xs[-1] + 1] == c):
                cy, cx = (sy + 0.5) * H / SH - 0.5, (sx + 0.5) * W / SW - 0.5
                out[ys[np.argmin(abs(ys - cy))], xs[np.argmin(abs(xs - cx))]] = c
    return out


def nearest(src):
    """The run-time enlargement (display.s PageUp): page pixel x from source pixel 5x // 6 (each 5 become 6)."""
    xs = np.arange(W) * 5 // 6
    ys = np.arange(H) * 5 // 6
    return src[ys[:, None], xs[None, :]]


def pack(data):
    """ByteKiller-pack DATA (greedy LZ over the reversed bytes); aw_extract.unpack(pack(d), len(d)) == d."""
    r = data[::-1]
    n = len(r)
    bits = []

    def put(v, k):
        for s in range(k - 1, -1, -1):
            bits.append((v >> s) & 1)
    lit = []

    def flush():
        while lit:
            m = min(len(lit), 264)
            if m >= 9:
                put(1, 1); put(3, 2); put(m - 9, 8)
            else:
                m = min(m, 8)
                put(0, 1); put(0, 1); put(m - 1, 3)
            for b in lit[:m]:
                put(b, 8)
            del lit[:m]
    heads = {}
    i = 0
    while i < n:
        best_len, best_off = 0, 0
        if i + 2 <= n:
            for j in reversed(heads.get(r[i:i + 2], [])[-64:]):
                off = i - j
                if off > 4095:
                    break
                m = 2
                while m < 256 and i + m < n and r[j + m] == r[i + m]:
                    m += 1
                if m > best_len:                        # (any length 2..256 at any offset 1..4095 is codable)
                    best_len, best_off = m, off
                    if m == 256:
                        break
        if best_len >= 2:
            flush()
            m, off = best_len, best_off
            if m == 2 and off <= 255:
                put(0, 1); put(1, 1); put(off, 8)
            elif m == 3 and off <= 511:
                put(1, 1); put(0, 2); put(off, 9)
            elif m == 4 and off <= 1023:
                put(1, 1); put(1, 2); put(off, 10)
            else:
                put(1, 1); put(2, 2); put(m - 1, 8); put(off, 12)
            step = m
        else:
            lit.append(r[i])
            step = 1
        for k in range(i, min(i + step, n - 1)):
            heads.setdefault(r[k:k + 2], []).append(k)
        i += step
    flush()
    k = len(bits) % 32                                  # the first word read: k bits under a marker bit
    words = [(1 << k) | sum(bits[t] << t for t in range(k))]
    for s in range(k, len(bits), 32):
        words.append(sum(bits[s + t] << t for t in range(32)))
    crc = 0
    for w in words:
        crc ^= w
    body = b"".join(struct.pack(">I", w) for w in reversed(words))
    return body + struct.pack(">II", crc, len(data))


def hires_from(bid, bitmap, palres):
    """Bitmap BID at 384x240 from its 32,000 bytes of planes and its palette resource's bytes:
    (source indices, the main palette, the 240x384 indices)."""
    src = planes_to_indices(bitmap)
    ws = PALETTES[bid][1]
    tot = sum(ws.values())
    pal = np.concatenate([palette(palres, n) * np.sqrt(w / tot) for n, w in ws.items()], axis=1)
    return src, palette(palres, max(ws, key=ws.get)), upscale(src, pal)


def hires(resdir, bid):
    """Bitmap BID from the unpacked resources in RESDIR (build/res/resource-0xNN.bin)."""
    rd = lambda i: open(os.path.join(resdir, f"resource-0x{i:02x}.bin"), "rb").read()
    return hires_from(bid, rd(bid), rd(PALETTES[bid][0]))


def main():
    args = sys.argv[1:]
    out = None
    if "-o" in args:
        k = args.index("-o")
        out = args[k + 1]
        args = args[:k] + args[k + 2:]
    resdir, bid = args[0], int(args[1], 0)
    src, pal, big = hires(resdir, bid)
    near = nearest(src)
    print(f"aw_hires: 0x{bid:02X}: {int(np.sum(big != near))} of {W * H} pixels differ from the repeated-row "
          f"enlargement; packed {len(pack(big.tobytes()))} bytes")
    if out:
        from PIL import Image
        rgb = (pal * 17).astype(np.uint8)
        im = np.concatenate([rgb[near], rgb[big]], axis=1)
        Image.fromarray(im).resize((4 * W, 2 * H), Image.NEAREST).save(out)


if __name__ == "__main__":
    main()
