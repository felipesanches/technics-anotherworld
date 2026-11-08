#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# codewheel_render.py -- the code wheel help page's pictures and tables (src/wheel.s), made from the owner's drawing
# of the original game's code wheel, aw_codewheel.svg (AnotherWorld_VMTools: two scanned disks, the lower one
# fixed, the upper one with the windows and the arrow a group of its own, g1139).
#
# Questions it answers:
#   * where are the wheel's pivot, the 20 numbers and the arrow, in the drawing? (measured, printed)
#   * what does the KN7000 draw for an angle of the upper disk? (render(): the device's own integer arithmetic,
#     pixel for pixel; the MAME probe compares the LCD with it)
#
# Measured in the drawing, at 4 pixels a unit:
#   * the lower disk's centre: the point the 20 radial tick marks between its numbers converge to (least squares
#     over the lines fitted to each tick), which is also the centre of the pivot hole in its scan;
#   * the upper disk's centre: the circle fitted to its outline (the clip path the drawing cuts it with);
#   * each number's angle (clockwise from up, about the lower disk's centre): half way between the two ticks around
#     it; number 1 is the one at the top left of 12 o'clock;
#   * the arrow's angle (about the upper disk's centre): where the arrow's principal axis (its dark pixels near the
#     rim) crosses the circle of the numbers.
# Upper disk at angle D (clockwise, the drawing's own position being 0): the arrow points at number k when
# D = number(k) - arrow. The KN7000 turns the upper disk about the lower disk's centre (the pin).
#
# Zoomed in (2026-11-08, Felipe: the symbols too small on the unit): rendered with librsvg (the Python GObject
# binding) at 480/679.13 pixels a unit, twice the LCD's height, the lower disk's centre at pixel (240.0, 240.0) of
# a 480 x 480 picture; the page shows 240 of its rows at a time (src/wheel.s: TOP, MIDDLE, BOTTOM). The scans in the
# drawing are 1.56 (lower) and 1.0 (upper) pixels a unit, so 0.71 still draws from real detail.
#   * BOT, 480 x 480: the lower disk alone, a byte a pixel (look-up table entries 16-255; 0 black, outside it);
#   * TOP, 512 x 512: the upper disk alone, its centre at (256.0, 256.0), unturned: entries 16-255 where it covers
#     (alpha >= 0.5), else 0-15, the shadow the drawing gives it at that point, in 15 levels (0 none); only its rows
#     TR0 .. TR1 - 1 are kept (the rest are never read: the spans keep every texel within R_ROT + 1 of its centre);
#   * SHADE, 16 x 256: entry e under shadow level s -> the nearest entry to e's colour darkened as the drawing does;
#   * LUT: entries 16-255, 4 bits a channel (0x0RGB), the 240 colours (weighted k-means over every colour of both
#     disks and of the shadowed lower one, in the LCD's own 4-bit depth);
#   * SPANS: for each row, the columns [x0, x1) (multiples of 4) the upper disk can reach at any angle (radius R_ROT
#     from the pin, its edge): only those are drawn again when the disk turns. Its shadow outside the edge is the same
#     all round, so it is in BOT, and TOP has no shadow level beyond the edge;
#   * BOTC: BOT inside the spans only, row after row (BOTOFF: each row's offset), what the device keeps in RAM;
#   * RING: BOT outside the spans, each row's [xl, xr) (the lower disk's extent, multiples of 4) less the span: drawn
#     into the page's frame once (it never changes);
#   * SIN: 4096 x s16, sin(2 pi i / 4096) x 32767; ANGLES: the 20 rest angles, in 1/65536 of a turn;
#   * LANES: each entry's colour as R << 20 | G << 10 | B (4-bit channels), for the blend; INV: 4096 entries, the
#     entry nearest each 4-bit colour R << 8 | G << 4 | B.
# The device draws a pixel (x, y) of the spans at angle A (wheel.s WheelDraw, render() here):
#   c = SIN[(A/16 + 1024) % 4096], s = SIN[A/16];  dx2 = 2x + 1 - 480, dy2 = 2y + 1 - 480
#   U = (256 << 16) + c*dx2 + s*dy2,  V = (256 << 16) - s*dx2 + c*dy2   (16.16; the pixel's centre turned back by A)
#   texel(i, j) = TOP[j][i] if >= 16, else SHADE[TOP[j][i]][BOT[y][x]]
#   while the disk turns (nearest, 9.7): the span in pieces of up to 128 pixels; at a piece's first pixel xs,
#     U7 = (U(xs) + 256) >> 9, V7 = (V(xs) + 256) >> 9, and at its k-th U7 + k ((2c + 256) >> 9), V7 + k ((-2s + 256)
#     >> 9) (one word V7 << 16 | U7 on the device: one add a pixel);  pixel = texel(U7 >> 7, V7 >> 7)
#   at rest (bilinear, in RGB):  U' = U - 0x8000, V' = V - 0x8000, i = U' >> 16, j = V' >> 16, fx = (U' >> 13) & 7,
#     fy likewise; sum = LANES[texel(i, j)] (8-fx)(8-fy) + LANES[texel(i+1, j)] fx(8-fy) + LANES[texel(i, j+1)]
#     (8-fx)fy + LANES[texel(i+1, j+1)] fx fy  (each lane at most 15 x 64);  pixel = INV[rounded lanes / 64]
#
# The blob (src/wheel.s WB_*: the same offsets) is three segments, each for its own place in the KN7000's RAM:
#   A, SEGA bytes (the VM's four pages): TOP's rows, SHADE (right after them: wheel.s finds it from TOP), SIN, LANES,
#      INV, LUT, SPANS, ANGLES, BOTOFF, the header, then BOTC's first rows;
#   B, SEGB bytes (SHADOW's room): BOTC's other rows (a row never straddles A's end);
#   C, SEGC bytes (ARENA5): RING's table (480 x u16 xl, u16 xr) and its bytes.
# The header: "AWWH", VERSION, SEGA, SEGB, SEGC, a word making A and B's words sum to 0, and C's words' sum.
#
# Output (OUT, e.g. build/wheel): AWWH0.AW .. AWWHD.AW (hex), the blob cut in 32 KB pieces (A in 11, B in 2, C in
# 1), each ByteKiller-packed (aw_hires.pack, checked with aw_extract.unpack; the game reads each to the scratch in
# ARENA6 and BkUnpack puts it in its place); sdfiles.lst; wheel.bin (the blob, A B C one after the other); wheel.txt
# (the measurements); and, with --previews DIR, PNGs of the device's picture at rest and between two numbers.
#   python3 -I tools/codewheel_render.py ../../AnotherWorld_VMTools/aw_codewheel.svg build/wheel [--previews DIR]
import argparse
import math
import os
import re
import struct
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# ---- the blob (src/wheel.s WB_* : the same offsets) ----
TS = 512                          # TOP's row stride (9-bit texel coordinates)
TR0, TR1 = 24, 488                # TOP's rows kept
W_TOP = 0x00000                   # (TR1 - TR0) x 512
W_SHADE = W_TOP + (TR1 - TR0) * TS  # 16 x 256, right after TOP's last row (wheel.s: TOP's row 0 + TR1 x 512)
W_SIN = 0x3B000                   # 4096 x s16
W_LANES = 0x3D000                 # 256 x u32
W_INV = 0x3D400                   # 4096
W_LUT = 0x3E400                   # 256 x u16
W_SPANS = 0x3E600                 # 480 x (u16 x0, u16 x1)
W_ANGLES = 0x3EE00                # 20 x u16
W_BOTOFF = 0x3EE80                # 480 x u32: BOTC's rows, offsets in the blob (A then B)
W_HDR = 0x3F600                   # "AWWH", version, SEGA, SEGB, SEGC, the sum's word
W_BOTC = 0x3F700                  # BOTC's first rows, to SEGA
SEGA, SEGB, SEGC = 0x58000, 0xF000, 0x8000
W_RING = SEGA + SEGB              # in the blob: C (480 x (u16 xl, u16 xr), then the bytes)
W_SIZE = SEGA + SEGB + SEGC
PIECE = 0x8000
SCRATCH_MAX = 0x9000              # a packed piece's room (wheel.s WB_SCRATCH, in ARENA6)
MAGIC, VERSION = b"AWWH", 2
BW, BH = 480, 480                 # BOT (and the page's wheel area)
PX, PY = 240.0, 240.0             # the pin, in BOT's pixels
TC = 256.0                        # the upper disk's centre in TOP
DIAM = 480                        # the lower disk's drawn diameter, in pixels (twice the LCD's height)
SEG_PX = 128                      # nearest: a span drawn in pieces of up to this many pixels, each from U, V exact
SHADOW_ROOM = ((0x50123000, 0x50148000), (0x50175000, 0x50180000))   # ARENA5, ARENA6: the LCD's copy (wheel.s)
SVG_SIZE = 679.13239
NUMBERS = 20
LEVELS = 16                       # shadow levels (0 none)
COLOURS = 240                     # entries 16-255


def rsvg_render(data, width, height, vx, vy, scale):
    """The SVG data drawn into a width x height RGBA float array (premultiplied), document point (0, 0) at pixel
    (vx, vy), `scale` pixels a unit."""
    import gi
    gi.require_version("Rsvg", "2.0")
    from gi.repository import Rsvg
    import cairo
    h = Rsvg.Handle.new_from_data(data)
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    cr = cairo.Context(surf)
    r = Rsvg.Rectangle()
    r.x, r.y, r.width, r.height = vx, vy, SVG_SIZE * scale, SVG_SIZE * scale
    h.render_document(cr, r)
    surf.flush()
    a = np.frombuffer(surf.get_data(), np.uint8).reshape(height, surf.get_stride() // 4, 4)[:, :width]
    return a[..., [2, 1, 0, 3]].astype(np.float64) / 255.0       # cairo's BGRA -> RGBA


def layers(src):
    """(lower disk, upper disk without its shadow, the shadow alone) as SVG documents."""
    group = re.compile(rb'<g\s+id="g1139".*?</g>', re.S)
    lower_img = re.compile(rb'<image\s+clip-path="url\(#clipPath3060\)".*?/>', re.S)
    shadow = re.compile(rb'<path\s+inkscape:connector-curvature="0"\s+id="path140".*?/>', re.S)
    upper_img = re.compile(rb'<image\s+inkscape:label="#image4146".*?/>', re.S)
    for rx in (group, lower_img, shadow, upper_img):
        if len(rx.findall(src)) != 1:
            sys.exit("codewheel_render: the drawing is not the one this script knows (aw_codewheel.svg)")
    lower = group.sub(b"", src)
    upper = shadow.sub(b"", lower_img.sub(b"", src))
    shade = upper_img.sub(b"", lower_img.sub(b"", src))
    return lower, upper, shade


def lum(a):
    return 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]


def components(mask):
    """8-connected components of a boolean array: list of (ys, xs)."""
    ys, xs = np.nonzero(mask)
    idx = {(y, x): i for i, (y, x) in enumerate(zip(ys.tolist(), xs.tolist()))}
    par = list(range(len(ys)))

    def f(i):
        while par[i] != i:
            par[i] = par[par[i]]
            i = par[i]
        return i
    for i, (y, x) in enumerate(zip(ys.tolist(), xs.tolist())):
        for dy, dx in ((0, 1), (1, -1), (1, 0), (1, 1)):
            j = idx.get((y + dy, x + dx))
            if j is not None:
                a, b = f(i), f(j)
                if a != b:
                    par[a] = b
    groups = {}
    for i in range(len(ys)):
        groups.setdefault(f(i), []).append(i)
    return [(ys[v], xs[v]) for v in groups.values()]


def cw_angle(x, y, cx, cy):
    """Degrees clockwise from up, of (x, y) about (cx, cy), in screen coordinates (y down)."""
    return math.degrees(math.atan2(x - cx, -(y - cy))) % 360


def measure(lower, upper):
    """The geometry, in document units (the measurement pictures: 4 pixels a unit)."""
    S = 4.0
    N = int(SVG_SIZE * S + 0.5)
    b = rsvg_render(lower, N, N, 0, 0, S)
    L = lum(b) * 255
    yy, xx = np.mgrid[0:N, 0:N]
    # the lower disk: its alpha's centroid, a first guess of the centre
    A = b[..., 3] > 0.5
    c0 = (xx[A].mean(), yy[A].mean())
    R = math.sqrt(A.sum() / math.pi)
    r = np.hypot(xx - c0[0], yy - c0[1])
    dark = (r > 0.84 * R) & (r < 0.995 * R) & (L < 175) & (b[..., 3] > 0.98)
    ticks = []
    for ys, xs in components(dark):
        if len(xs) < 30:
            continue
        X, Y = xs.astype(float), ys.astype(float)
        mx, my = X.mean(), Y.mean()
        w, V = np.linalg.eigh(np.cov(np.vstack([X - mx, Y - my])))
        d = V[:, 1]
        length = 4 * math.sqrt(w[1]) / S
        radial = abs((d[0] * (mx - c0[0]) + d[1] * (my - c0[1])) / math.hypot(mx - c0[0], my - c0[1]))
        if length > 20 and radial > 0.99 and math.sqrt(w[1] / max(w[0], 1e-9)) > 8:
            ticks.append((mx, my, d))
    if len(ticks) != NUMBERS:
        sys.exit(f"codewheel_render: {len(ticks)} tick marks found on the lower disk, not {NUMBERS}")
    M, B = np.zeros((2, 2)), np.zeros(2)
    for mx, my, d in ticks:
        n = np.array([-d[1], d[0]])
        M += np.outer(n, n)
        B += np.outer(n, n) @ np.array([mx, my])
    cb = np.linalg.solve(M, B)
    # (for the report: the pin hole in the scan, its dark pixels within 8 units of that point)
    hole = (np.hypot(xx - cb[0], yy - cb[1]) < 8 * S) & (L < 170) & (b[..., 3] > 0.98)
    hole_c = (xx[hole].mean() / S, yy[hole].mean() / S) if hole.any() else None
    tick_deg = sorted(cw_angle(mx, my, cb[0], cb[1]) for mx, my, _ in ticks)
    # number k between ticks: the gaps, in order clockwise; number 1 is the gap just left of 12 o'clock, i.e. the
    # one whose middle is the last before 360 (the drawing: "1" at the top left, "2" at the top right)
    mids = []
    for i in range(NUMBERS):
        a, b2 = tick_deg[i], tick_deg[(i + 1) % NUMBERS]
        if b2 < a:
            b2 += 360
        mids.append(((a + b2) / 2) % 360)
    mids.sort()
    first = max(range(NUMBERS), key=lambda i: mids[i])  # the middle nearest 360 from below
    numbers = [mids[(first + k) % NUMBERS] for k in range(NUMBERS)]
    # the upper disk: its outline (the clip circle), fitted
    t = rsvg_render(upper, N, N, 0, 0, S)
    At = t[..., 3]
    guess = cb
    pts = []
    for k in range(720):
        a = math.radians(k / 2)
        dx, dy = math.sin(a), -math.cos(a)
        rr = np.arange(250 * S, 335 * S, 0.25)
        xs = (guess[0] + dx * rr).astype(int)
        ys = (guess[1] + dy * rr).astype(int)
        ok = (xs >= 0) & (xs < N) & (ys >= 0) & (ys < N)
        inside = np.zeros(len(rr), bool)
        inside[ok] = At[ys[ok], xs[ok]] > 0.5
        if inside.any():
            j = np.nonzero(inside)[0][-1]
            pts.append((guess[0] + dx * rr[j], guess[1] + dy * rr[j]))
    P = np.array(pts)
    D_, E_, F_ = np.linalg.lstsq(np.column_stack([P[:, 0], P[:, 1], np.ones(len(P))]),
                                 -(P[:, 0] ** 2 + P[:, 1] ** 2), rcond=None)[0]
    ct = np.array([-D_ / 2, -E_ / 2])
    Rt = math.sqrt(ct[0] ** 2 + ct[1] ** 2 - F_)
    # the arrow: the dark pixels near the upper disk's rim, the one group of them that is not a letter
    Lt = lum(t) * 255
    rt = np.hypot(xx - ct[0], yy - ct[1])
    ar = (Lt < 80) & (At > 0.98) & (rt > 0.85 * Rt) & (rt < 0.99 * Rt)
    best = None
    for ys, xs in components(ar):
        if len(xs) < 2000:
            continue
        X, Y = xs.astype(float), ys.astype(float)
        mx, my = X.mean(), Y.mean()
        w, V = np.linalg.eigh(np.cov(np.vstack([X - mx, Y - my])))
        d = V[:, 1]
        radial = abs((d[0] * (mx - ct[0]) + d[1] * (my - ct[1])) / math.hypot(mx - ct[0], my - ct[1]))
        # the arrow: solid (its pixels fill its box), pointing outwards
        fill = len(xs) / ((X.max() - X.min() + 1) * (Y.max() - Y.min() + 1))
        if radial > 0.95 and (best is None or fill > best[0]):
            best = (fill, mx, my, d, len(xs))
    if best is None:
        sys.exit("codewheel_render: the arrow was not found on the upper disk")
    _, mx, my, d, npx = best
    # where its axis crosses the numbers' circle (the mean radius of the ticks' middles, about the upper centre)
    rn = 0.955 * R
    p = np.array([mx - ct[0], my - ct[1]])
    if d @ p < 0:
        d = -d
    bq = 2 * (p @ d)
    cq = p @ p - rn * rn
    tq = (-bq + math.sqrt(bq * bq - 4 * cq)) / 2
    hit = p + tq * d
    arrow = cw_angle(hit[0], hit[1], 0, 0)
    return dict(lower_centre=cb / S, upper_centre=ct / S, upper_radius=Rt / S, ticks=tick_deg, numbers=numbers,
                arrow=arrow, arrow_centroid=(mx / S, my / S), arrow_px=npx, hole=hole_c)


def upper_layers(upper, shade, g):
    """TOP's two pictures: the upper disk (RGBA) and its shadow (alpha), the disk's centre at (TC, TC)."""
    s = DIAM / SVG_SIZE
    vx, vy = TC - g["upper_centre"][0] * s, TC - g["upper_centre"][1] * s
    return rsvg_render(upper, TS, TS, vx, vy, s), rsvg_render(shade, TS, TS, vx, vy, s)


def kmeans(cols, weights, k, iters=30):
    """Weighted k-means of cols (n x 3, 0..15) to k centres; deterministic (the k heaviest colours to start)."""
    order = np.argsort(-weights, kind="stable")
    cent = cols[order[:k]].astype(float)
    for _ in range(iters):
        d = ((cols[:, None, :] - cent[None, :, :]) ** 2).sum(-1)
        lab = d.argmin(1)
        new = cent.copy()
        for j in range(k):
            m = lab == j
            if m.any():
                new[j] = (cols[m] * weights[m, None]).sum(0) / weights[m].sum()
        if np.allclose(new, cent):
            break
        cent = new
    return np.clip(np.rint(cent), 0, 15).astype(int)


def nearest_entry(rgb, pal):
    """rgb (n x 3, 0..15 floats) -> index into pal (k x 3)."""
    d = ((rgb[:, None, :] - pal[None, :, :]) ** 2).sum(-1)
    return d.argmin(1)


def spans_for(r_rot):
    """Each row's [x0, x1) (multiples of 4) within r_rot of the pin; (0, 0) when none."""
    spans = []
    for y in range(BH):
        dy = y + 0.5 - PY
        if abs(dy) >= r_rot:
            spans.append((0, 0))
            continue
        h = math.sqrt(r_rot * r_rot - dy * dy)
        x0 = max(0, int(math.floor(PX - h)) // 4 * 4)
        x1 = min(BW, (int(math.ceil(PX + h)) + 3) // 4 * 4)
        spans.append((x0, x1))
    return spans


def shadow_rows(spans):
    """Where wheel.s WheelLayout puts each row's copy of the LCD (its spans' bytes): ARENA5 first, then ARENA6, a row
    never straddling; -> the addresses (None when it does not fit)."""
    out, room = [], 0
    p = SHADOW_ROOM[0][0]
    for x0, x1 in spans:
        n = max(0, x1 - x0)
        if p + n > SHADOW_ROOM[room][1]:
            room += 1
            if room == len(SHADOW_ROOM):
                return None
            p = SHADOW_ROOM[room][0]
        out.append(p)
        p += n
    return out


def build(svg):
    src = open(svg, "rb").read()
    lower, upper, shade = layers(src)
    g = measure(lower, upper)
    s = DIAM / SVG_SIZE
    cb = g["lower_centre"]
    bot = rsvg_render(lower, BW, BH, PX - cb[0] * s, PY - cb[1] * s, s)       # premultiplied over black
    top, shad = upper_layers(upper, shade, g)
    shadow_rgb = 45 / 255.0                                                    # the shadow's #2d2d2d
    smax = shad[..., 3].max()
    # TOP's coverage and shadow level
    covered = top[..., 3] >= 0.5
    top_rgb = np.where(covered[..., None], top[..., :3] / np.maximum(top[..., 3:4], 1e-6), 0)
    level = np.clip(np.rint(shad[..., 3] / smax * (LEVELS - 1)), 0, LEVELS - 1).astype(int)
    level[covered] = 0
    alpha_of = np.arange(LEVELS) * smax / (LEVELS - 1)                         # a level's shadow opacity
    # the colours to choose the palette from, in 4-bit channels, weighted by how often they show
    bot_rgb = bot[..., :3] * 15
    tops = top_rgb[covered] * 15
    disk = bot[..., 3] > 0.02
    samples = [bot_rgb[disk], tops]
    wts = [np.full(disk.sum(), 1.0), np.full(len(tops), 1.0)]
    lv, cnt = np.unique(level[~covered], return_counts=True)
    frac = cnt / cnt.sum()
    for l, f in zip(lv, frac):                     # the lower disk under each shadow level, as often as it shows
        if l == 0:
            continue
        a = alpha_of[l]
        samples.append(bot_rgb[disk] * (1 - a) + shadow_rgb * 15 * a)
        wts.append(np.full(disk.sum(), f * 4))
    allc = np.rint(np.concatenate(samples)).clip(0, 15).astype(int)
    allw = np.concatenate(wts)
    key = allc[:, 0] * 256 + allc[:, 1] * 16 + allc[:, 2]
    uk, inv = np.unique(key, return_inverse=True)
    uw = np.bincount(inv, weights=allw)
    ucols = np.stack([uk // 256, (uk // 16) % 16, uk % 16], 1)
    pal = kmeans(ucols, uw, COLOURS)
    # the pictures in entries
    BOT = np.zeros((BH, BW), np.uint8)
    BOT[disk] = 16 + nearest_entry(np.rint(bot_rgb[disk]), pal)
    TOP = level.astype(np.uint8)
    TOP[covered] = 16 + nearest_entry(np.rint(tops), pal)
    lut_rgb = np.zeros((256, 3))
    lut_rgb[16:] = pal
    SHADE = np.zeros((LEVELS, 256), np.uint8)
    SHADE[0] = np.arange(256)
    for l in range(1, LEVELS):
        a = alpha_of[l]
        SHADE[l, :16] = 0                                               # (black stays black)
        SHADE[l, 16:] = 16 + nearest_entry(pal * (1 - a) + shadow_rgb * 15 * a, pal)
    # the shadow outside the upper disk's edge is the same all round (its blur of a circle), so it does not turn: it
    # goes into BOT once, and TOP keeps the levels inside the edge only. The spans then reach the edge alone.
    ty, tx = np.nonzero(covered)
    r_rot = math.sqrt(((tx + 0.5 - TC) ** 2 + (ty + 0.5 - TC) ** 2).max()) + 1.0
    yy, xx = np.mgrid[0:TS, 0:TS]
    TOP[(np.hypot(xx + 0.5 - TC, yy + 0.5 - TC) > r_rot) & ~covered] = 0
    by, bx = np.mgrid[0:BH, 0:BW]
    ring = (np.hypot(bx + 0.5 - PX, by + 0.5 - PY) > r_rot) & disk
    lv = level[(by + int(TC - PY))[ring], bx[ring]]             # the level there in TOP, unturned (the same all round)
    BOT[ring] = SHADE[lv, BOT[ring]]
    if TC - (r_rot + 2) < TR0 or TC + r_rot + 2 >= TR1:
        sys.exit(f"codewheel_render: the upper disk reaches {r_rot:.1f} px from its centre, past TOP's rows {TR0}-{TR1 - 1}")
    if (TOP[:TR0] != 0).any() or (TOP[TR1:] != 0).any():
        sys.exit("codewheel_render: TOP has pixels outside the rows kept")
    spans = spans_for(r_rot)
    # every texel a pixel of the spans reads, at any angle (the bilinear's i + 1, j + 1 too), within TOP's rows kept
    reach = max(math.hypot(x + 0.5 - PX, y + 0.5 - PY) for y, (x0, x1) in enumerate(spans) for x in (x0, x1 - 1) if x1 > x0)
    if TC - (reach + 2) < TR0 or TC + reach + 2 >= TR1:
        sys.exit(f"codewheel_render: the spans read texels {reach:.1f} px from TOP's centre, past its rows {TR0}-{TR1 - 1}")
    g["reach"] = reach
    sin = [int(round(32767 * math.sin(2 * math.pi * i / 4096))) for i in range(4096)]
    angles = []
    for k in range(NUMBERS):
        d = (g["numbers"][k] - g["arrow"]) % 360
        angles.append(int(round(d / 360 * 65536)) & 0xFFFF)
    blob = bytearray(W_SIZE)
    blob[W_TOP:W_TOP + (TR1 - TR0) * TS] = TOP[TR0:TR1].tobytes()
    blob[W_SHADE:W_SHADE + LEVELS * 256] = SHADE.tobytes()
    blob[W_SIN:W_SIN + 8192] = struct.pack("<4096h", *sin)
    lut = [(int(c[0]) << 8) | (int(c[1]) << 4) | int(c[2]) for c in lut_rgb]
    blob[W_LUT:W_LUT + 512] = struct.pack("<256H", *lut)
    blob[W_SPANS:W_SPANS + 4 * BH] = b"".join(struct.pack("<HH", a, b) for a, b in spans)
    blob[W_ANGLES:W_ANGLES + 2 * NUMBERS] = struct.pack(f"<{NUMBERS}H", *angles)
    lanes = [(int(c[0]) << 20) | (int(c[1]) << 10) | int(c[2]) for c in lut_rgb]
    blob[W_LANES:W_LANES + 1024] = struct.pack("<256I", *lanes)
    keys = np.arange(4096)
    krgb = np.stack([keys >> 8, (keys >> 4) & 15, keys & 15], 1)
    blob[W_INV:W_INV + 4096] = (16 + nearest_entry(krgb, pal)).astype(np.uint8).tobytes()
    # BOTC: A from W_BOTC, then B; a row never straddles A's end
    off, offs = W_BOTC, []
    for y, (x0, x1) in enumerate(spans):
        n = max(0, x1 - x0)
        if off < SEGA and off + n > SEGA:
            off = SEGA
        offs.append(off)
        blob[off:off + n] = BOT[y, x0:x0 + n].tobytes()
        off += n
    if off > SEGA + SEGB:
        sys.exit(f"codewheel_render: BOTC ends at 0x{off:X}, past A and B (0x{SEGA + SEGB:X})")
    botc_end = off
    blob[W_BOTOFF:W_BOTOFF + 4 * BH] = struct.pack(f"<{BH}I", *offs)
    # RING: each row's lower disk outside its span
    off = W_RING + 4 * BH
    ring_rows = []
    for y, (x0, x1) in enumerate(spans):
        nz = np.nonzero(BOT[y])[0]
        if len(nz) == 0:
            xl = xr = 0
        else:
            xl, xr = int(nz[0]) // 4 * 4, (int(nz[-1]) + 4) // 4 * 4
        if x0 < x1 and not (xl <= x0 and x1 <= xr):
            sys.exit(f"codewheel_render: row {y}: the span {x0}-{x1} outside the lower disk {xl}-{xr}")
        ring_rows.append((xl, xr))
        for a, b in ((xl, x0), (x1, xr)) if x0 < x1 else ((xl, xr),):
            if b > a:
                blob[off:off + b - a] = BOT[y, a:b].tobytes()
                off += b - a
    if off > W_SIZE:
        sys.exit(f"codewheel_render: RING ends at 0x{off:X}, past C (0x{W_SIZE:X})")
    blob[W_RING:W_RING + 4 * BH] = b"".join(struct.pack("<HH", a, b) for a, b in ring_rows)
    ring_end = off
    if shadow_rows(spans) is None:
        sys.exit("codewheel_render: the LCD's copy of the spans does not fit in ARENA5 and ARENA6")
    hdr = MAGIC + struct.pack("<IIII", VERSION, SEGA, SEGB, SEGC)
    blob[W_HDR:W_HDR + len(hdr)] = hdr
    csum = sum(struct.unpack_from(f"<{SEGC // 4}I", blob, W_RING)) & 0xFFFFFFFF
    struct.pack_into("<I", blob, W_HDR + 24, csum)                            # C's words' sum
    total = sum(struct.unpack_from(f"<{(SEGA + SEGB) // 4}I", blob, 0)) & 0xFFFFFFFF
    struct.pack_into("<I", blob, W_HDR + 20, (-total) & 0xFFFFFFFF)          # A and B's words sum to 0
    g.update(r_rot=r_rot, angles=angles, lut=lut, colours=len(uk), shadow_max=smax, botc_end=botc_end,
             ring_end=ring_end, sin=sin, spans=spans, TOP=TOP, BOT=BOT, SHADE=SHADE)
    return bytes(blob), g


def tables(blob):
    """The blob's pictures and tables, as numpy arrays: TOP (512 x 512, zero outside TR0..TR1), BOT (480 x 480: BOTC
    and RING put together), SIN, SHADE, LANES, INV, SPANS."""
    TOP = np.zeros((TS, TS), np.uint8)
    TOP[TR0:TR1] = np.frombuffer(blob, np.uint8, (TR1 - TR0) * TS, W_TOP).reshape(TR1 - TR0, TS)
    spans = [struct.unpack_from("<HH", blob, W_SPANS + 4 * y) for y in range(BH)]
    offs = struct.unpack_from(f"<{BH}I", blob, W_BOTOFF)
    BOT = np.zeros((BH, BW), np.uint8)
    off = W_RING + 4 * BH
    for y, (x0, x1) in enumerate(spans):
        if x1 > x0:
            BOT[y, x0:x1] = np.frombuffer(blob, np.uint8, x1 - x0, offs[y])
        xl, xr = struct.unpack_from("<HH", blob, W_RING + 4 * y)
        for a, b in ((xl, x0), (x1, xr)) if x0 < x1 else ((xl, xr),):
            if b > a:
                BOT[y, a:b] = np.frombuffer(blob, np.uint8, b - a, off)
                off += b - a
    return dict(TOP=TOP, BOT=BOT, SIN=np.frombuffer(blob, "<i2", 4096, W_SIN).astype(np.int64),
                SHADE=np.frombuffer(blob, np.uint8, LEVELS * 256, W_SHADE).reshape(LEVELS, 256),
                LANES=np.frombuffer(blob, "<u4", 256, W_LANES).astype(np.int64),
                INV=np.frombuffer(blob, np.uint8, 4096, W_INV), spans=spans)


def render_row(t, y, angle, smooth=False):
    """Row y of the wheel area (480 entries) as the device draws it at angle `angle` (1/65536 turn): BOT, the span
    drawn as wheel.s draws it, nearest (the disk turning) or bilinear (smooth: at rest)."""
    TOP, BOT, SIN, SHADE, LANES, INV = t["TOP"], t["BOT"], t["SIN"], t["SHADE"], t["LANES"], t["INV"]
    out = BOT[y].copy()
    x0, x1 = t["spans"][y]
    if x0 >= x1:
        return out
    i = (angle >> 4) & 4095
    c, s = int(SIN[(i + 1024) & 4095]), int(SIN[i])
    xs = np.arange(x0, x1, dtype=np.int64)
    dx2 = 2 * xs + 1 - BW
    dy2 = 2 * y + 1 - BH
    U = (int(TC) << 16) + c * dx2 + s * dy2
    V = (int(TC) << 16) - s * dx2 + c * dy2
    b = BOT[y, x0:x1]

    def texel(i, j):
        if (j < TR0).any() or (j >= TR1).any() or (i < 0).any() or (i >= TS).any():
            raise ValueError(f"row {y}: a texel outside TOP's rows kept")
        tt = TOP[j, i]
        return np.where(tt >= 16, tt, SHADE[np.minimum(tt, 15), b])
    if not smooth:                     # 9.7, packed in one word on the device: one add a pixel, from each piece's start
        k = (xs - x0) % SEG_PX
        p0 = xs - k                    # the piece's first pixel
        idx = p0 - x0
        U7 = ((U[idx] + 256) >> 9) + k * ((2 * c + 256) >> 9)
        V7 = ((V[idx] + 256) >> 9) + k * ((-2 * s + 256) >> 9)
        if (U7 < 0).any() or (U7 >= 65536).any() or (V7 < 0).any() or (V7 >= 65536).any():
            raise ValueError(f"row {y}: a 9.7 coordinate out of its lane")
        out[x0:x1] = texel(U7 >> 7, V7 >> 7)
        return out
    U, V = U - 0x8000, V - 0x8000
    i, j, fx, fy = U >> 16, V >> 16, (U >> 13) & 7, (V >> 13) & 7
    acc = (LANES[texel(i, j)] * ((8 - fx) * (8 - fy)) + LANES[texel(i + 1, j)] * (fx * (8 - fy))
           + LANES[texel(i, j + 1)] * ((8 - fx) * fy) + LANES[texel(i + 1, j + 1)] * (fx * fy))
    acc += (32 << 20) | (32 << 10) | 32
    out[x0:x1] = INV[(((acc >> 26) & 15) << 8) | (((acc >> 16) & 15) << 4) | ((acc >> 6) & 15)]
    return out


def render(blob, angle, smooth=False, rows=range(BH), t=None):
    """The wheel area's rows `rows` (480 entries each) as the device draws them at that angle."""
    t = t or tables(blob)
    return np.stack([render_row(t, y, angle, smooth) for y in rows])


def to_png(img, blob, path, scale=1):
    from PIL import Image
    lut = struct.unpack_from("<256H", blob, W_LUT)
    pal = []
    for e in range(256):
        v = lut[e] if e >= 16 else 0
        pal += [((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17]
    im = Image.fromarray(np.ascontiguousarray(img), "P")
    im.putpalette(pal)
    im = im.convert("RGB")
    if scale != 1:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    im.save(path)


def pieces(blob):
    """The blob cut in PIECE-byte pieces, each ByteKiller-packed (checked with aw_extract.unpack, as BkUnpack unpacks
    it: from the scratch in ARENA6 to its place). A in 11, B in 2 (the second 0x7000 bytes), C in 1."""
    import aw_extract
    import aw_hires
    out = []
    for base, size in ((0, SEGA), (SEGA, SEGB), (SEGA + SEGB, SEGC)):
        for k in range(base, base + size, PIECE):
            raw = blob[k:min(k + PIECE, base + size)]
            packed = aw_hires.pack(raw)
            if aw_extract.unpack(packed, len(raw)) != raw:
                sys.exit("codewheel_render: a piece does not unpack")
            if len(packed) > SCRATCH_MAX:
                sys.exit(f"codewheel_render: a packed piece of {len(packed)} bytes, past the scratch's {SCRATCH_MAX}")
            out.append((k, raw, packed))
    return out


def main():
    ap = argparse.ArgumentParser(description="the code wheel help page's files (src/wheel.s)")
    ap.add_argument("svg")
    ap.add_argument("out")
    ap.add_argument("--previews")
    a = ap.parse_args()
    blob, g = build(a.svg)
    os.makedirs(os.path.join(a.out, "sdfiles"), exist_ok=True)
    names, lines, packed_total, cached = [], [], 0, 0
    for k, (at, raw, packed) in enumerate(pieces(blob)):
        name = f"AWWH{k:X}.AW"
        open(os.path.join(a.out, "sdfiles", name), "wb").write(packed)
        names.append(name)
        packed_total += len(packed)
        if at < SEGA + SEGB:
            cached += (len(packed) + 3) // 4 * 4
        lines.append(f"{name}: blob 0x{at:05X}, {len(raw)} bytes, packed {len(packed)}")
    open(os.path.join(a.out, "sdfiles.lst"), "w").write("\n".join(names) + "\n")
    open(os.path.join(a.out, "wheel.bin"), "wb").write(blob)
    cb, ct = g["lower_centre"], g["upper_centre"]
    sp = g["spans"]
    rep = [f"drawing: {a.svg} sha1 {__import__('hashlib').sha1(open(a.svg, 'rb').read()).hexdigest()}",
           f"lower disk centre (tick marks' convergence): ({cb[0]:.3f}, {cb[1]:.3f}) units",
           f"lower disk's pin hole in the scan (its dark pixels): ({g['hole'][0]:.3f}, {g['hole'][1]:.3f}) units",
           f"upper disk centre (outline fit): ({ct[0]:.3f}, {ct[1]:.3f}), radius {g['upper_radius']:.3f} units",
           "tick marks (deg clockwise from up): " + " ".join(f"{t:.2f}" for t in g["ticks"]),
           "spacing between ticks (deg): " + " ".join(
               f"{(g['ticks'][(i + 1) % NUMBERS] - g['ticks'][i]) % 360:.2f}" for i in range(NUMBERS)),
           "numbers 1-20 (deg): " + " ".join(f"{n:.2f}" for n in g["numbers"]),
           f"arrow (deg, where its axis meets the numbers' circle): {g['arrow']:.3f} ({g['arrow_px']} px at 4x)",
           "rest angles of the upper disk (1/65536 turn): " + " ".join(str(x) for x in g["angles"]),
           f"rest angles (deg): " + " ".join(f"{x * 360 / 65536:.2f}" for x in g["angles"]),
           f"scale: {DIAM}/{SVG_SIZE} pixels a unit; rotating radius: {g['r_rot']:.2f} px; shadow opacity max "
           f"{g['shadow_max']:.3f}; the spans reach {g['reach']:.2f} px (TOP's rows kept {TR0}-{TR1 - 1})",
           f"pixels the spans cover: {sum(b - x for x, b in sp)} (all 480 rows); in the rows TOP 0-239 shows: "
           f"{sum(b - x for x, b in sp[0:240])}, MIDDLE 120-359: {sum(b - x for x, b in sp[120:360])}, BOTTOM 240-479: "
           f"{sum(b - x for x, b in sp[240:480])} (a turning picture's, its 32-bit stores a quarter of it at most)",
           f"BOTC ends at blob 0x{g['botc_end']:X} (A is 0x{SEGA:X}, B to 0x{SEGA + SEGB:X}); RING ends at 0x{g['ring_end']:X} "
           f"(C to 0x{W_SIZE:X})",
           f"colours (4-bit) in the pictures: {g['colours']}, as {COLOURS} entries",
           f"blob: {len(blob)} bytes; packed: {packed_total} bytes in {len(names)} files; A and B packed (what the LCD's "
           f"memory keeps): {cached}"] + lines
    open(os.path.join(a.out, "wheel.txt"), "w").write("\n".join(rep) + "\n")
    print("\n".join(rep))
    if a.previews:
        os.makedirs(a.previews, exist_ok=True)
        ang = g["angles"]
        t = tables(blob)
        to_png(render(blob, ang[0], True, t=t), blob, os.path.join(a.previews, "rest_1.png"))
        mid = (ang[0] + ((ang[1] - ang[0]) & 0xFFFF) // 2) & 0xFFFF
        to_png(render(blob, mid, t=t), blob, os.path.join(a.previews, "mid_1_2.png"))


if __name__ == "__main__":
    main()
