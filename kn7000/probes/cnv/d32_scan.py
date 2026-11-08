#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# d32_scan.py KN7APP_BIN MAP UNIDASM [FROM:TO ...] -- does the code between those labels (default: the code wheel page's,
# src/wheel.s WheelService .. wh_items, and the routines the code wheel setting added) use a load or store with a
# register and a 32-bit displacement whose top byte is not 0? On the owner's KN7000 such an operand raises a system-error
# NMI and restarts the instrument (MAME models it since kn7000_mame a582ec5; Pinball Fantasies' notes, 2026-10-26).
# Disassembles with MAME's unidasm (-arch mn10300) from APP_BASE and prints every hit; exit status 1 when any.
import re
import subprocess
import sys

binf, mapf, unidasm = sys.argv[1:4]
spans = sys.argv[4:] or ["WheelService:wh_items", "GameStart:SetupPalette", "PrefsWheelLive:PrefsPageBuild",
                         "fw_pring:InWorkRam", "InpLogRestart:InpLogPart"]
sym = {}
for line in open(mapf):
    a, n = line.split()[:2]
    sym[n] = int(a, 16)
dis = subprocess.run([unidasm, binf, "-arch", "mn10300", "-basepc", "0x502BA000"], capture_output=True, text=True).stdout
lines = [(int(l[:8], 16), l.rstrip()) for l in dis.splitlines() if re.match(r"[0-9a-f]{8}:", l)]
hits = n = 0
for sp in spans:
    lo, hi = (sym[x] for x in sp.split(":"))
    for a, l in lines:
        if lo <= a < hi:
            n += 1
            m = re.search(r"\((0x[0-9a-f]+|\d+), (a[0-3]|sp)\)", l)
            if m and (int(m.group(1), 0) >> 24) & 0xFF:
                print(l)
                hits += 1
print(f"d32_scan: {n} instructions in {len(spans)} ranges, {hits} with a register + displacement whose top byte is not 0")
# The indexed form (Dn, Am) adds a register, whose value a scan cannot know: listed for review. The code wheel page's LCD
# store through (d1, a2), d1 = 0x4C..., is the suspect of the owner's unit restarting (2026-11-08); every one left must
# have an index far below 2^24 (the texel, the colour, the lane, the INV entry, the shadow level).
idx = [l for sp in spans for a, l in lines if (lambda lo, hi: lo <= a < hi)(*(sym[x] for x in sp.split(":")))
       and re.search(r"\(d[0-3], ?a[0-3]\)", l)]
print(f"d32_scan: {len(idx)} indexed (Dn, Am) operands in those ranges, for review:")
for l in idx:
    print("  " + l)
sys.exit(1 if hits else 0)
