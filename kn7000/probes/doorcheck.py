#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# doorcheck.py LEDLOG FRAME... -- the door bursts' green flashes (src/leds.s LEV_DOOR: PLAY_SOUND 0x56 at pc 0x6B85 or
# 0x6CE6 of part 0x3E84, a mega-blast beam knocking a panel out of a door): for each FRAME a burst's sound plays in
# (research-scratch kn7000-aw-reference/fingerprints, "Eighth pass": the frames each session's header lists), is every
# green LED (the PANEL MEMORY ring's too) lit in the next frame, the LED shadow being written at the next yield; and,
# over each flash (the frames from FRAME+1 whose kernel ms is less than FRAME's + 600: LED_DOOR_MS), how many frames
# had all greens lit, how many none, and in how many any LED that is not green was lit. LEDLOG: a MAME replay's LED
# log (probes/cnv/awcnv_inplog.lua AW_LEDLOG; field 0 the frame, field 6 the shadow, field 9 the kernel ms). Pass: lit at FRAME+1 every time, nothing else lit meanwhile.
#   python3 -I probes/doorcheck.py T/lb.led 525 527 568 579 607 618 648 658
import sys

GREEN = bytes.fromhex("00101010111301127FF203830000000100000200")  # the green LEDs and the PANEL MEMORY ring
ALL = bytes.fromhex("3F3F3F3F1F1F1F1FFFFAFFFFFFFF030103030303")
sh, ms = {}, {}
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) >= 10 and f[6] != "-":
        sh[int(f[0])] = bytes.fromhex(f[6])
        ms[int(f[0])] = int(f[9])
ok = 0
hits = [int(a) for a in sys.argv[2:]]
for h in hits:
    first = sh.get(h + 1, bytes(20))
    lit = all(x & m == m for x, m in zip(first, GREEN))
    on = off = other = 0
    win = [k for k in range(h + 1, h + 20) if k in ms and ms[k] < ms[h] + 600]
    for k in win:
        s = sh.get(k, bytes(20))
        if all(x & m == m for x, m in zip(s, GREEN)):
            on += 1
        elif not any(x & m for x, m in zip(s, GREEN)):
            off += 1
        if any(x & a & ~m for x, a, m in zip(s, ALL, GREEN)):
            other += 1
    ok += lit and other == 0
    print(f"doorcheck: burst at {h}: every green LED at {h + 1} {'yes' if lit else 'NO'}; frames {win[0]}-{win[-1]}: "
          f"{on} all green, {off} none, {other} with another LED lit")
print(f"doorcheck: {ok} of {len(hits)} bursts flashed green from the next frame, nothing else lit")
