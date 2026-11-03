#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# domecheck.py LEDLOG VARS [FINE] -- the guard under the glass globe (part 0x3E84, room 80, src/leds.s led_guard) and
# the globe's crash (led_glass): do the panel LEDs do what they should?
# LEDLOG: a MAME replay's LED log (probes/cnv/awcnv_inplog.lua AW_LEDLOG: a line a VM frame, the shadow in field 7);
# VARS: the same replay's VM variables (run_inplog.sh OUT/vars.bin, 256 x int16 LE a frame, in the LED log's order);
# FINE: its 60 Hz shadow log (AW_LEDFINE: "tick ms shadow [pc]").
#   guard   every frame of room 80 (var 0x67) with the guard alive (var 0xB2 bit 1 clear) and his reflection drawn
#           (the frames before and after it in room 80 too): PANEL MEMORY 1-4 lit as var 0xE6 says (-7..7 in seven half
#           steps: 1, 1+2, 2, 2+3, 3, 3+4, 4), 5-8 dark; one frame's lag allowed (the shadow is written at the next
#           yield)
#   crash   from the first frame var 0xB1 bit 1 is set (the globe hit; the crash sound 0x6B comes 11 frames later):
#           with FINE, the 60 Hz lines of the next 4 s: when all eight PANEL MEMORY LEDs first light (the crash),
#           how often they are all lit in its 1.8 s (about half: the pulse) and the share of each distance ring's LEDs
#           lit (led_fw0-3, probes/ledrings.py: falling from the nearest ring to the farthest), in its first and
#           second halves (falling too), and nothing lit after it
#   python3 -I probes/domecheck.py T/kill.led T/kill/vars.bin T/kill.fine
import struct
import sys

PM = [(15, 0x01), (8, 0x40), (8, 0x20), (8, 0x10), (8, 0x08), (9, 0x20), (9, 0x40), (9, 0x80)]   # PANEL MEMORY 1-8
FW = [bytes.fromhex(h) for h in (
    "0000000000000000861A003C0F00010000000000", "00000000000000000100FFC3F061020003030100",
    "000000000000000000000000009E000000000203", "3F3F3F3F1F1F1F1F000000000000000000000000")]
ALL = bytes.fromhex("3F3F3F3F1F1F1F1FFFFAFFFFFFFF030103030303")   # the bits that are LEDs (led_all)
NIB = [1, 1, 3, 3, 2, 2, 6, 6, 6, 4, 4, 12, 12, 8, 8]          # var 0xE6 + 7 -> PANEL MEMORY 1-4, a bit each


def pm(sh):
    return [k + 1 for k, (r, b) in enumerate(PM) if sh[r] & b]


rows = []
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) >= 9:
        rows.append((int(f[0]), bytes.fromhex(f[6]) if f[6] != "-" else bytes(20)))
raw = open(sys.argv[2], "rb").read()
n = min(len(rows), len(raw) // 512)
var = [struct.unpack_from("<256h", raw, 512 * i) for i in range(n)]
ok = tot = 0
wrong = []
room = [var[i][0x67] == 80 and not var[i][0xB2] & 2 for i in range(n)]
for i in range(1, n - 1):
    if not (room[i - 1] and room[i] and room[i + 1]):
        continue
    v = max(-7, min(7, var[i][0xE6]))
    want = [k + 1 for k in range(4) if NIB[v + 7] >> k & 1]
    tot += 1
    if any(pm(rows[i + d][1]) == want for d in (0, 1)):
        ok += 1
    elif len(wrong) < 10:
        wrong.append(f"{rows[i][0]}:e6={var[i][0xE6]}:{pm(rows[i][1])}/{pm(rows[i + 1][1])}")
print(f"domecheck: guard: {ok}/{tot} room-80 frames with PANEL MEMORY as var 0xE6 says" + (f"; wrong: {' '.join(wrong)}" if wrong else ""))
seen = sorted({max(-7, min(7, var[i][0xE6])) for i in range(n) if room[i]})
print(f"domecheck: guard: var 0xE6 took {seen}")
hit = next((i for i in range(n) if var[i][0xB1] & 2 and var[i][0x67] == 80), None)
print(f"domecheck: crash: the globe hit at frame {rows[hit][0] if hit is not None else None}, the guard "
      f"{'killed' if hit is not None and any(var[i][0xB2] & 2 for i in range(hit, n)) else 'not killed'}")
if hit is not None and len(sys.argv) > 3:
    fine = []
    for line in open(sys.argv[3]):
        f = line.split()
        if len(f) >= 3:
            fine.append((int(f[1]), bytes.fromhex(f[2])))
    # the hit's kernel ms: the LED log's field 10 at that frame
    t_hit = next(int(l.split()[9]) for l in open(sys.argv[1]) if l.split() and l.split()[0] == str(rows[hit][0]))
    win = [(t, sh) for t, sh in fine if t_hit <= t < t_hit + 4000]
    t0 = next((t for t, sh in win if len(pm(sh)) == 8), None)
    if t0 is None:
        print("domecheck: crash: the PANEL MEMORY ring never all lit")
        sys.exit()
    eff = [(t - t0, sh) for t, sh in win if t0 <= t < t0 + 1800]
    after = [sh for t, sh in win if t >= t0 + 1900]
    allpm = sum(len(pm(sh)) == 8 for _, sh in eff)
    print(f"domecheck: crash: the ring all lit {t0 - t_hit} ms after the hit; in the next 1.8 s all eight lit in "
          f"{allpm} of {len(eff)} lines, none in {sum(not pm(sh) for _, sh in eff)}")
    for half, sel in (("first", [sh for t, sh in eff if t < 900]), ("second", [sh for t, sh in eff if t >= 900])):
        share = []
        for m in FW:
            cnt = sum(bin(m[r]).count("1") for r in range(20))
            lit = sum(bin(sh[r] & m[r]).count("1") for sh in sel for r in range(20))
            share.append(f"{100 * lit / (cnt * max(1, len(sel))):.0f}%")
        print(f"domecheck: crash: {half} half, each ring's LEDs lit (nearest first): {' '.join(share)}")
    lit = sum(any(x & y for x, y in zip(sh, ALL)) for sh in after)
    print(f"domecheck: crash: after it (to 4 s from the hit), lines with an LED lit: {lit} of {len(after)}")
