#!/usr/bin/env python3
"""find_noterng.py ROMDIR -- where each KN5000 program keeps the ring the keybed's notes land in.

Keybed notes come from the sub CPU as packets with header 0x42 (slot 2, 3 bytes): 90 note velocity,
velocity 0 for a release. The INT0/INTTC0 handlers pass them to SeqRingBuf_WriteDispatch_Table's slot 2,
SeqDMA_WriteMidi_NoteOn, which drops the 90 and writes note and velocity into a 256-byte ring through
SeqBuf_NoteEvent_WriteByte. The walk AW.CNV repeats at run time (cnv_platform.asm, CNV_FIND_NOTERING):
  1. the dispatch table at 0xE00012: entry 2 (0xE0001A);
  2. its first `push wa; call abs24` (28 1D lo mid hi) is SeqBuf_NoteEvent_WriteByte;
  3. there, the first `lda xde,abs24` (F2 lo mid hi 32) is the ring's buffer address X
     (X-8 read index, X-4 write index, X-2 free count; the main loop reads it with Seq_RingBuf_ReadByte).
"""
import glob
import os
import re
import sys

BASE = 0xE00000
for path in sorted(glob.glob(os.path.join(sys.argv[1], 'kn5000_v*_program.rom')), key=lambda p: int(re.search(r'_v(\d+)_', p).group(1))):
    r = open(path, 'rb').read()
    v = re.search(r'_v(\d+)_', path).group(1)
    e2 = int.from_bytes(r[0x1A:0x1E], 'little')
    i = r.index(b'\x28\x1d', e2 - BASE) + 1
    call = int.from_bytes(r[i + 1:i + 4], 'little')
    m = re.search(rb'\xf2(...)\x32', r[call - BASE:call - BASE + 32], re.S)
    ring = int.from_bytes(m.group(1), 'little')
    print(f'v{v}: dispatch[2]={e2:06x} call at {i + BASE:06x} -> {call:06x}, ring X={ring:06x}')
