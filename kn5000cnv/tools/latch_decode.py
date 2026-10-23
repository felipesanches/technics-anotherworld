#!/usr/bin/env python3
"""decode.py LOG [FROM] -- latch.lua's LATCH lines cut into main->sub packets (header: bits 7-5 handler, 4-0 length-1;
E1/E2/E3 skipped by length), printed with time. Only handler-0 (MIDI ring) packets from FROM s."""
import sys
toks = []
for line in open(sys.argv[1]):
    if line.startswith('LATCH '):
        p = line.split()
        toks.append((float(p[1]), int(p[2], 16)))
frm = float(sys.argv[2]) if len(sys.argv) > 2 else 0
i = 0
while i < len(toks):
    t, b = toks[i]
    if b == 0xE1:
        n = 6
    elif b == 0xE2:
        n = 10
    elif b == 0xE3:
        n = 0
    else:
        n = (b & 0x1f) + 1
    pay = [x[1] for x in toks[i + 1:i + 1 + n]]
    if t >= frm and b < 0x20:
        print('%.3f %s' % (t, ' '.join('%02x' % x for x in pay)))
    i += 1 + n
