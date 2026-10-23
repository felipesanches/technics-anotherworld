#!/usr/bin/env python3
"""dspmix.py OUT.inc [TESTPROG.txt] -- the four-channel MIXER, a program of ours for the KN5000's effects DSP
(IC311, uPD6383GF), as the 83 I-RAM words src/awsub.asm loads (`db` lines, 5 bytes a word, big-endian), and
optionally as a UPD6383_TESTPROG file for the MAME core's harness (kn7000_mame upd6383.cpp test_load()).

Every frame (44,100 a second) it computes  DO1 = sum over c of C-RAM[c] x D-RAM[0x40 + c]:  the four channels'
current samples, which the sub CPU writes (src/awsub.asm SUB_TICK), times their volumes, summed, and hands the
sum to the output stage's own presentation word (epilogue w73, unit 0 -> DO1). Only decoded word forms
(tools/upd6383_asm.py); the frame terminator at I-RAM 82 is the firmware's own."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from upd6383_asm import ldptr, rstcur, dptr, mul, acc_step, program, PRESENT_UNIT0, NOP, FRAME_WAIT  # noqa: E402

CELL_SAMPLE = 0x40

WORDS = [
    ldptr(0x00), rstcur(), dptr(CELL_SAMPLE),
    mul('hold'),                 # P0 = vol0 * s0
    mul('load'),                 # acc = P0;   P1 = vol1 * s1
    mul('add'),                  # acc += P1;  P2
    mul('add'),                  # acc += P2;  P3
    acc_step('add'),             # acc += P3
    PRESENT_UNIT0,
]


def image():
    return list(WORDS) + [NOP] * (82 - len(WORDS)) + [FRAME_WAIT]


def main():
    with open(sys.argv[1], 'w') as f:
        f.write('; dspmix.inc -- written by tools/dspmix.py; do not edit. The mixer, I-RAM 0..82, 5 bytes a word\n')
        for i, w in enumerate(image()):
            f.write('\tdb ' + ', '.join('0%02Xh' % ((w >> (8 * k)) & 0xFF) for k in range(4, -1, -1)) + '\t; %d\n' % i)
    if len(sys.argv) > 2:
        vol = 0x200000
        open(sys.argv[2], 'w').write(program(
            WORDS, cram={0: vol, 1: vol, 2: vol, 3: vol},
            sines=[(CELL_SAMPLE, 220, 1 << 21), (CELL_SAMPLE + 1, 330, 1 << 21), (CELL_SAMPLE + 2, 440, 1 << 21),
                   (CELL_SAMPLE + 3, 660, 1 << 21)],
            frame=300000, log=4410))


if __name__ == '__main__':
    main()
