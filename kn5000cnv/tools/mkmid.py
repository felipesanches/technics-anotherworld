#!/usr/bin/env python3
"""mkmid.py OUT.mid -- a type-0 MIDI file: 30 s of rest (the KN5000 boots), then for each GM program the
KN7000 sound map uses: a program change on channel 1 and one note; then GM drum keys on channel 10.
Each event is 1 s apart (96 ticks a quarter, 120 bpm: 192 ticks a second)."""
import struct
import sys

PROGS = [0, 11, 14, 38, 39, 50, 89, 115, 116, 118, 122, 127]
DRUMS = [35, 36, 38, 41, 42]
ev = []
t = 30 * 192
for p in PROGS:
    ev.append((t, bytes([0xC0, p]))); t += 96
    ev.append((t, bytes([0x90, 60, 100]))); t += 96
    ev.append((t, bytes([0x80, 60, 0]))); t += 96
for k in DRUMS:
    ev.append((t, bytes([0x99, k, 100]))); t += 96
    ev.append((t, bytes([0x89, k, 0]))); t += 96


def vlq(n):
    out = [n & 0x7f]
    n >>= 7
    while n:
        out.append(0x80 | (n & 0x7f))
        n >>= 7
    return bytes(reversed(out))


trk, last = b'', 0
for tick, msg in ev:
    trk += vlq(tick - last) + msg
    last = tick
trk += vlq(0) + b'\xff\x2f\x00'
open(sys.argv[1], 'wb').write(b'MThd' + struct.pack('>IHHH', 6, 0, 1, 96) + b'MTrk' + struct.pack('>I', len(trk)) + trk)
