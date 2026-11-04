#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# finalecheck.py LEDLOG VARS [FINE [END]] -- the finale's LEDs (src/leds.s led_finale; part 0x3E87, code KRTD): the dragon's
# wings on the RHYTHM GROUP's red LEDs (left) and the SOUND GROUP's (right), the flight's shrinking wave, the credits'
# blinking with the music. LEDLOG: a MAME replay's LED log (probes/cnv/awcnv_inplog.lua AW_LEDLOG: field 0 the frame,
# field 6 the shadow, field 9 the kernel ms); VARS: its run_inplog.sh vars.bin (256 x int16 a frame); FINE: its 60 Hz
# log (AW_LEDFINE: "tick ms shadow [pc]", with AW_LEDFINE_THREAD=10 thread 10's pc). The columns are led_wing_l/_r's
# (probes/ledwings.py), from the panel's centre out; a column is lit when its top or bottom LED is.
#   wings    frames 455-500 (the session's wings: left 468-471, right 480-483, research-scratch ninth pass): each
#            frame's lit columns, left/right; with FINE, the columns at each 60 Hz line from the left wing's first
#            step to the right wing's last (one column every 60 ms: the steps' 120 ms, 2 columns a step)
#   flight   frames 501-646: each wing's outermost lit column + 1 against ceil(var 0x03 x 8 / 64), the zoom's share
#            of 8 (this frame's or the one before's: the shadow is written at the next yield), frames equal / all (a
#            column with no bottom LED is dark while the wave is on its bottom row: one column less is allowed); the distinct row patterns seen (the wave moving)
#   credits  frames 647 to END (default 1928: the port asks for the intro at 1929 in this session): the share of frames each of the four sets is lit (the bottom rows: the
#            bass; the greens: the drums; the left / right top rows: the chords) and its on-off changes; LEDs lit
#            outside the four sets
#   python3 -I probes/finalecheck.py T/fin.led T/fin/vars.bin T/fin.fine
import struct
import sys

WL = [(6, 0x02, 0, 0), (4, 0x02, 0, 0), (2, 0x02, 3, 0x02), (0, 0x02, 1, 0x02), (6, 0x04, 7, 0x04), (4, 0x04, 5, 0x04),
      (2, 0x04, 3, 0x04), (0, 0x04, 1, 0x04)]
WR = [(13, 0x10, 19, 0x02), (13, 0x08, 19, 0x01), (13, 0x04, 13, 0x80), (13, 0x02, 13, 0x40), (13, 0x01, 13, 0x20),
      (16, 0x02, 17, 0x02), (16, 0x01, 17, 0x01), (10, 0x80, 0, 0)]
GREEN = bytes.fromhex("00101010111301127FF203830000000100000200")
ALL = bytes.fromhex("3F3F3F3F1F1F1F1FFFFAFFFFFFFF030103030303")


def lit(sh, r, b):
    return b and sh[r] & b


def cols(sh, w):
    return [bool(lit(sh, t, tb) or lit(sh, bo, bb)) for t, tb, bo, bb in w]


def rows(sh, w):
    return "".join("B" if lit(sh, t, tb) and lit(sh, bo, bb) else "t" if lit(sh, t, tb) else "b" if lit(sh, bo, bb)
                   else "." for t, tb, bo, bb in w)


def mask(w, top, bot):
    m = bytearray(20)
    for t, tb, bo, bb in w:
        if top and tb:
            m[t] |= tb
        if bot and bb:
            m[bo] |= bb
    return bytes(m)


sh, ms = {}, {}
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) >= 10 and f[6] != "-":
        sh[int(f[0])] = bytes.fromhex(f[6])
        ms[int(f[0])] = int(f[9])
raw = open(sys.argv[2], "rb").read()
var = {i: struct.unpack_from("<256h", raw, 512 * i) for i in range(len(raw) // 512)}
print("finalecheck: wings, frame: left columns / right columns (from the centre out)")
for k in range(455, 501):
    if k in sh:
        print(f"finalecheck:   {k} {''.join('#' if c else '.' for c in cols(sh[k], WL))} / "
              f"{''.join('#' if c else '.' for c in cols(sh[k], WR))}")
if len(sys.argv) > 3:
    fine = []
    for line in open(sys.argv[3]):
        f = line.split()
        if len(f) >= 3:
            fine.append((int(f[1]), bytes.fromhex(f[2]), f[3] if len(f) > 3 else "-"))
    t0, t1 = ms.get(466, 0), ms.get(486, 0)
    seq, last = [], None
    for t, s, pc in fine:
        if t0 <= t <= t1:
            n = (sum(cols(s, WL)), sum(cols(s, WR)))
            if n != last:
                seq.append(f"{t - t0}:{n[0]}/{n[1]}(pc {pc})")
                last = n
    print("finalecheck: wings at 60 Hz, ms from frame 466: left/right columns: " + " ".join(seq))
eq = tot = 0
pats = set()
for k in range(501, 647):
    if k not in sh or k not in var:
        continue
    got = [max([i + 1 for i, c in enumerate(cols(sh[k], w)) if c], default=0) for w in (WL, WR)]
    tot += 1
    for d in (0, 1):                # the shadow is written at the next yield: one frame's lag allowed
        v = var.get(k - d, var[k])[3]
        want = 0 if v <= 0 else min(8, (v * 8 + 63) // 64)
        if got[0] <= want and got[1] <= want and max(got) >= want - 1:
            eq += 1
            break
    pats.add(rows(sh[k], WL))
print(f"finalecheck: flight: {eq}/{tot} frames with the wings' extent the zoom's share of 8 (within one column); "
      f"{len(pats)} row patterns on the left wing")
sets = {"bass (bottom rows)": bytes(a | b for a, b in zip(mask(WL, False, True), mask(WR, False, True))),
        "drums (greens)": GREEN, "chord L (top row)": mask(WL, True, False), "chord R (top row)": mask(WR, True, False)}
union = bytes(a | b | c | d for a, b, c, d in zip(*sets.values()))
end = int(sys.argv[4]) if len(sys.argv) > 4 else 1928       # the part's last frame (MAME: the intro asked at 1929)
frames = [k for k in range(647, end + 1) if k in sh]
for name, m in sets.items():
    on = [all(x & y == y for x, y in zip(sh[k], m)) for k in frames]
    changes = sum(1 for a, b in zip(on, on[1:]) if a != b)
    print(f"finalecheck: credits {name}: lit in {sum(on)} of {len(frames)} frames, {changes} changes")
outside = sum(1 for k in frames if any(x & a & ~u for x, a, u in zip(sh[k], ALL, union)))
print(f"finalecheck: credits: frames {frames[0] if frames else '-'}-{frames[-1] if frames else '-'}, with an LED lit "
      f"outside the four sets: {outside}")
