#!/usr/bin/env python3
"""dsnd_sine.py OUT.inc -- 256 signed 8-bit samples of one sine cycle (amplitude 100), for the DSND_TEST build."""
import math
import sys

v = [int(round(100 * math.sin(2 * math.pi * i / 256))) & 0xFF for i in range(256)]
with open(sys.argv[1], 'w') as f:
    for i in range(0, 256, 16):
        f.write('\tdb ' + ', '.join('0%02Xh' % x for x in v[i:i + 16]) + '\n')
