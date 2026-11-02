#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
# screen2png.py SCREEN.bin... -- awcnv_lcd8.lua's AWL_DUMPAT dumps (640 x 240 32-bit pixels, little-endian 0xAARRGGBB,
# MAME's screen) to PNGs beside them; with --sheet OUT.png also all of them stacked (scaled x2 vertically: the LCD's dots
# are about as tall as wide... the MAME layout's aspect, roughly).
import sys
from PIL import Image
args = sys.argv[1:]
sheet = None
if '--sheet' in args:
    i = args.index('--sheet'); sheet = args[i + 1]; args = args[:i] + args[i + 2:]
ims = []
for p in args:
    d = open(p, 'rb').read()
    im = Image.frombuffer('RGBA', (640, 240), d, 'raw', 'BGRA', 0, 1).convert('RGB')
    im.save(p.replace('.bin', '.png'))
    ims.append(im)
if sheet and ims:
    o = Image.new('RGB', (640, 244 * len(ims)), (90, 90, 90))
    for k, im in enumerate(ims):
        o.paste(im, (0, k * 244))
    o.save(sheet)
