#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# tankcheck.py LEDLOG VARS -- do the panel LEDs mirror the battle tank's panel (part 0x3E85, src/leds.s)? LEDLOG: a
# MAME replay's LED log (probes/cnv/awcnv_inplog.lua AW_LEDLOG); VARS: the same replay's VM variables at each captured
# frame (AWCK_VARS: 256 x int16 LE a frame, in the LED log's order; run_inplog.sh writes OUT/vars.bin). For every frame
# from the first press of cell 0x0B (var 0xFA != 0 with var 0x5F == 0x0B) while the panel's progress var 0x67 is set:
# the shadow holds the tank's LED set after that press, register 13's red LEDs from var 0x67 >= 2, register 12's from
# >= 3, INTRO & ENDING 1 / 2 with vars 0x72 / 0x71, BEAT 2 / 3 with 0x74 / 0x75, and, from var 0x67 = 6 at frame t6,
# the four AUTO PLAY CHORD / SOUND ARRANGER LEDs lit exactly while (frame - t6 - 1) mod 4 < 2. One frame's lag is
# allowed (the shadow is written at the game task's next yield), and an "off" not checked while another effect (a
# laser: every red LED) is on; up to the eject (var 0x63 = 1) or the panel's end
# (the LED log's tank column: thread 59 stopped).
# Prints each rule's frames right / checked.
#   python3 -I probes/tankcheck.py OUT.led OUT/vars.bin
import struct
import sys

TANK = bytes.fromhex("282A1C090800070AE58004520000020001000101")
R13 = bytes(13 * [0]) + b"\xFF" + bytes(6)
R12 = bytes(12 * [0]) + b"\xFF" + bytes(7)
IE1 = b"\x01" + bytes(19)
IE2 = b"\x00\x01" + bytes(18)
BEAT2 = bytes(4) + b"\x01" + bytes(15)
BEAT3 = bytes(5) + b"\x01" + bytes(14)
APC = bytes(4) + b"\x10\x10\x10\x10" + bytes(12)


def covers(b, m):
    return all((x & y) == y for x, y in zip(b, m))


def none_of(b, m):
    return all((x & y) == 0 for x, y in zip(b, m))


rows, shown, other = [], [], []           # every line (the variables are a record for each): '-' before the shadow
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) >= 9:
        rows.append((int(f[0]), bytes.fromhex(f[6]) if f[6] != "-" else bytes(20)))
        shown.append(int(f[20]) if len(f) > 20 else 1)
        other.append(len(f) > 17 and any(int(x) for x in (f[3], f[4], f[5], f[15], f[16], f[17])))  # a laser, flash...
raw = open(sys.argv[2], "rb").read()
n = min(len(rows), len(raw) // 512)
var = [struct.unpack_from("<256h", raw, 512 * i) for i in range(n)]
press = next((i for i in range(n) if var[i][0xFA] != 0 and var[i][0x5F] == 0x0B and var[i][0x67] >= 0), None)
t6 = next((rows[i][0] for i in range(n) if var[i][0x67] == 6), None)
print(f"tankcheck: {n} frames; the first press of cell 0x0B at frame {rows[press][0] if press is not None else None}, var 0x67 = 6 from frame {t6}")
rules = {k: [0, 0] for k in ("leds", "block1", "block2", "ie1", "ie2", "beat2", "beat3", "white")}
wrong = []


def check(name, i, mask, on):
    """frame i: mask lit when on, or not lit when not (in frame i or i + 1: the lag)."""
    if not on and any(0 <= i + d < n and other[i + d] for d in (-1, 0, 1)):
        return                            # (another effect lighting them meanwhile: a laser lights every red LED)
    ok = any(i + d < n and (covers(rows[i + d][1], mask) if on else none_of(rows[i + d][1], mask)) for d in (0, 1))
    rules[name][0] += ok
    rules[name][1] += 1
    if not ok and len(wrong) < 12:
        wrong.append(f"{name}@{rows[i][0]}")


if press is not None:
    for i in range(press + 1, n - 1):
        v = var[i]
        if v[0x63] == 1 or not shown[i]:  # the eject (var 0x63 = 1), or the panel gone (the log's tank column: the
            break                         # tank destroyed): its LEDs with it
        if v[0x67] < 0 or v[0x67] > 6 or var[i + 1][0x67] != v[0x67]:
            continue                      # (the panel's progress changing this frame: next frame's rule)
        check("leds", i, TANK, True)
        check("block1", i, R13, v[0x67] >= 2)
        check("block2", i, R12, v[0x67] >= 3)
        check("ie1", i, IE1, v[0x72] != 0)
        check("ie2", i, IE2, v[0x71] != 0)
        check("beat2", i, BEAT2, v[0x74] != 0)
        check("beat3", i, BEAT3, v[0x75] != 0)
        if v[0x67] == 6 and t6 is not None:
            check("white", i, APC, (rows[i][0] - t6 - 1) % 4 < 2)
for k, (ok, tot) in rules.items():
    print(f"tankcheck: {k:7s} {ok}/{tot}")
if wrong:
    print("tankcheck: wrong: " + " ".join(wrong))
