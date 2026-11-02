#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# jump_session.py AWR PART SETVARS [POKES] JUMP > OUT.awr -- a session the reference VM starts in a part (research-scratch
# kn7000-aw-reference/fingerprints: "P 0 PART" with AW_SETVARS / AW_POKE) made into one the port replays
# (probes/cnv/run_inplog.sh, awcnv_inplog.lua): the game starts as always (the splash, the intro), and at frame JUMP
# the variables are set and the part asked for, as the code screen (0x3E88) does ("V" and "R" records); every input
# record and poke of AWR then comes JUMP + 1 frames later (the part starts at the frame after the request).
# SETVARS "00=31,06=200" and POKES "20:67=78:01=340" as the reference VM takes them (hex var, decimal value).
#   python3 -I probes/jump_session.py SESSION.awr 3E84 00=31 "" 300 > probes/sessions/2026-11-02-3e84-cp31-recharge.awr
import sys

awr, part, setvars = sys.argv[1], int(sys.argv[2], 16), sys.argv[3]
pokes, jump = (sys.argv[4], int(sys.argv[5])) if len(sys.argv) > 5 else ("", int(sys.argv[4]))
off = jump + 1
print(f"# made by probes/jump_session.py from {awr.split('/')[-1]}: part 0x{part:04X} at frame {jump}, {setvars or 'no vars'}"
      + (f", pokes {pokes}" if pokes else ""))
print("P 0 0x3E80")
print(f"I 1 intro 0x00")
for kv in filter(None, setvars.split(",")):
    k, v = kv.split("=")
    print(f"V {jump} 0x{int(k, 16):02X} {int(v)}")
print(f"R {jump} 0x{part:04X}")
for e in filter(None, pokes.split(",")):
    t, *kvs = e.split(":")
    for kv in kvs:
        k, v = kv.split("=")
        print(f"V {int(t) + off} 0x{int(k, 16):02X} {int(v)}")
for line in open(awr):
    f = line.split()
    if not f or f[0] == "#" or f[0] == "P":
        continue
    if f[0] in ("I", "E", "R", "M"):
        f[1] = str(int(f[1]) + off)
        print(" ".join(f))
