#!/usr/bin/env python3
"""dspmix.py OUT.inc [TESTPROG.txt] -- the four-channel MIXER, a program of ours for the KN5000's effects DSP
(IC311, uPD6383GF), as the I-RAM words src/awsub.asm loads from address 0 (`db` lines, 5 bytes a word,
big-endian), and optionally as a UPD6383_TESTPROG file for the MAME core's harness (kn7000_mame upd6383.cpp
test_load()), which drives the sample cells with four sines.

Every frame (44,100 a second) it computes  DO1 = sum over c of C-RAM[c] x sample c:  the four channels' current
samples, which the sub CPU writes (src/awsub.asm SUB_TICK), times their volumes, summed, and hands the sum to
the output stage's own presentation word (epilogue w73, unit 0 -> DO1). Its layout follows what the MAME core's
model required of the same program in kn7000_mame notes/kn5000-dsp-mixer/README.md, where it was measured:
  I-RAM 0      the per-unit CALL: on to the body at 84, the D-RAM pointer to 0x05
  I-RAM 2      the presentation word (the return lands at the CALL + 2)
  I-RAM 82     the frame terminator, the firmware's own
  I-RAM 84..   the body: the four multiplies, then the return
  D-RAM 0x05, 0x07, 0x08, 0x09   the samples (SAMPLE_CELLS)
  D-RAM 0x06   the presentation's level, 0x7FFFFF (~1.0): the sub CPU writes it between the first two samples
  C-RAM 0..3   the volumes, 0x400000 = 1.0 (the multiplies scale as Q1.22)
  C-RAM 4      the coefficient under the cursor at the presentation word: 0x400000, so the sum comes out the
               same if the real w73 scales by it (the decode's other reading) instead of by D-RAM 0x06
Only decoded word forms, but the presentation word."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from upd6383_asm import (ldptr, rstcur, call, mul, acc_step, program, PRESENT_UNIT0, HOLD, FRAME_WAIT,  # noqa: E402
                         UNIT0_ENTRY, DRAM_UNIT_BASE)

SAMPLE_CELLS = (DRAM_UNIT_BASE, DRAM_UNIT_BASE + 2, DRAM_UNIT_BASE + 3, DRAM_UNIT_BASE + 4)
LEVEL_CELL = 0x06
UNITY = 0x400000

HEADER = [call(0), HOLD, PRESENT_UNIT0]
BODY = [
    ldptr(0x00), rstcur(),
    mul('load', dp=2),           # P0 = vol0 * s0 (a HOLD step would skip the multiply), then over the level cell
    mul('load'),                 # acc = P0;   P1 = vol1 * s1
    mul('add'),                  # acc += P1;  P2
    mul('add'),                  # acc += P2;  P3
    acc_step('add'),             # acc += P3
    call(0),                     # the return
]


def image():
    """I-RAM 0 .. the body's end"""
    return list(HEADER) + [HOLD] * (82 - len(HEADER)) + [FRAME_WAIT, HOLD] + list(BODY)


def main():
    img = image()
    assert img[UNIT0_ENTRY] == BODY[0]
    with open(sys.argv[1], 'w') as f:
        f.write('; dspmix.inc -- written by tools/dspmix.py; do not edit. The mixer, I-RAM 0..%d, 5 bytes a word\n'
                % (len(img) - 1))
        for i, w in enumerate(img):
            f.write('\tdb ' + ', '.join('0%02Xh' % ((w >> (8 * k)) & 0xFF) for k in range(4, -1, -1)) + '\t; %d\n' % i)
    if len(sys.argv) > 2:
        vol = UNITY // 4
        open(sys.argv[2], 'w').write(program(
            HEADER, body=BODY, cram={0: vol, 1: vol, 2: vol, 3: vol, 4: UNITY}, dram={LEVEL_CELL: 0x7FFFFF},
            sines=[(c, hz, 1 << 22) for c, hz in zip(SAMPLE_CELLS, (220, 330, 440, 660))],
            frame=300000, log=4410))


if __name__ == '__main__':
    main()
