#!/usr/bin/env python3
"""sndtest_levels.py RUN.log OUT.wav [FROM] -- how loud each note of a run was: the note-ons in latch.lua's LATCH lines
(through latch_decode.py's packet cutting), each with its part's last program change, and the RMS of the recording
(MAME -wavwrite) over the 0.43 s after it, against the 0.19 s before it. For the SND_TEST=1 build (src/cnv_sound.asm
CNV_SND_TEST), whose notes are 0.75 s apart: which voices does MAME play?"""
import math
import struct
import subprocess
import sys
import wave
import os

here = os.path.dirname(os.path.abspath(__file__))
frm = sys.argv[3] if len(sys.argv) > 3 else '0'
recs = subprocess.run([sys.executable, '-I', os.path.join(here, 'latch_decode.py'), sys.argv[1], frm],
                      capture_output=True, text=True, check=True).stdout.split('\n')
w = wave.open(sys.argv[2])
rate = w.getframerate()


def db(a, b):
    w.setpos(int(a * rate))
    d = w.readframes(int((b - a) * rate))
    v = struct.unpack('<%dh' % (len(d) // 2), d)
    r = math.sqrt(sum(x * x for x in v) / len(v)) if v else 0
    return 20 * math.log10(r / 32768) if r else -999.0


prog = {}
for line in recs:
    p = line.split()
    if len(p) < 5:
        continue
    t = float(p[0])
    if p[1] == 'c0':
        prog[p[2]] = 'sel 0x%s prog %3d' % (p[4], int(p[3], 16))
    elif p[1] == '90' and p[4] != '00':
        print('%8.2f part %s note %3d  %-17s  %7.1f dBFS (before %7.1f)' % (
            t, p[2], int(p[3], 16), prog.get(p[2], '(unchanged)'), db(t + 0.02, t + 0.45), db(t - 0.2, t - 0.01)))
