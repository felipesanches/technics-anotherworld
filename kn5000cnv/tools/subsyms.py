#!/usr/bin/env python3
"""subsyms.py AWSUB.SYM OUT.inc -- the src/awsub.asm symbols the main CPU's code needs, as ASL EQUs."""
import sys

NEED = ('SUB_BASE', 'SUB_ORIG_JP', 'SUB_HOOK', 'SUB_TICK', 'SUB_REQ', 'SUB_STATE', 'SUB_TICKS', 'CH0', 'SUB_END')
syms = {}
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) == 2:
        syms[p[0]] = p[1]
with open(sys.argv[2], 'w') as f:
    f.write('; awsub.inc -- written by tools/subsyms.py from src/awsub.asm; do not edit\n')
    for n in NEED:
        f.write('%s\tEQU 0%sh\n' % (n, syms[n]))
