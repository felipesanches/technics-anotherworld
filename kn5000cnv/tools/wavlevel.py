#!/usr/bin/env python3
"""wavlevel.py WAV [FROM TO] -- the RMS level, in dBFS, of each second of a 16-bit stereo WAV (MAME -wavwrite),
and the peak; for 'is anything heard here, and when'."""
import math
import struct
import sys
import wave

w = wave.open(sys.argv[1])
rate, ch = w.getframerate(), w.getnchannels()
frm, to = (float(sys.argv[2]), float(sys.argv[3])) if len(sys.argv) > 3 else (0, 1e9)
w.setpos(int(frm * rate))
t = frm
while t < to:
    data = w.readframes(rate)
    if not data:
        break
    n = len(data) // 2
    v = struct.unpack('<%dh' % n, data)
    rms = math.sqrt(sum(x * x for x in v) / n) if n else 0
    peak = max(abs(x) for x in v) if n else 0
    print('%5.0f s  rms %6.1f dBFS  peak %5d' % (t, 20 * math.log10(rms / 32768) if rms else -999, peak))
    t += 1
