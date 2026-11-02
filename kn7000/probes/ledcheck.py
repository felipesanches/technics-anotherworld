#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# ledcheck.py LEDLOG FP -- do the panel LEDs follow the game (src/leds.s)? LEDLOG: a MAME replay's LED log
# (probes/cnv/awcnv_inplog.lua AW_LEDLOG: "tick active charge red_ms all_ms blinks shadow mirror lit" per frame);
# FP: the reference VM's events for the same session through awfp.py (research-scratch kn7000-aw-reference/
# fingerprints: replayawr AW_EVENTS=EV, then awfp.py EV PART > FP; lines "tick KIND part=.. ch=.."). For each event,
# in the frames from it to 4 later:
#   LASER_LESTER / LASER_OTHER   every red LED bit set in the shadow, and in the mirror (sent) within 7 frames
#   CHARGE_START / MEGA_CHARGE   the charge state >= 1 / 2
#   SHIELD                       the charge state 0
#   MEGA_RELEASE                 blinking (blinks to go > 0), the charge state 0
#   STORM_FLASH / STORM_THUNDER  every LED bit set, shadow and mirror; STORM_STRIKE: blinking
# (the lit bits, not the effect's timer: a 100 ms flash can end inside one game frame, before the frame is logged)
# the pulse: the frames with a charge on and the non-red LEDs lit (should be near half); and, over the whole log: the frames with an effect, the most panel outputs MAME had lit, and whether the shadow's
# LED bits were back to what they were before the first effect once all ended (the last frame).
import sys
ALL = bytes.fromhex("3F3F3F3F1F1F1F1FFFFAFFFFFFFF030103030303")
RED = bytes.fromhex("3F2F2F2F0E0C1E0D8008FC7CFFFF030003030103")
KINDS = {"LASER_LESTER": "laser", "LASER_OTHER": "laser", "CHARGE_START": "charge", "MEGA_CHARGE": "mega",
         "SHIELD": "shield", "MEGA_RELEASE": "blast", "STORM_FLASH": "flash", "STORM_THUNDER": "thunder",
         "STORM_STRIKE": "strike"}


def load_log(p):
    rows = {}
    for line in open(p):
        f = line.split()
        if len(f) < 9 or f[6] == "-":
            continue
        rows[int(f[0])] = dict(active=int(f[1]), charge=int(f[2]), red=int(f[3]), all=int(f[4]), blinks=int(f[5]),
                               sh=bytes.fromhex(f[6]), mi=bytes.fromhex(f[7]), lit=int(f[8]))
    return rows


def covers(b, mask):
    return all((x & m) == m for x, m in zip(b, mask))


def main():
    log, evp = load_log(sys.argv[1]), sys.argv[2]
    events = []
    for line in open(evp):
        f = line.split()
        if len(f) >= 2 and f[0].isdigit() and f[1] in KINDS:
            events.append((int(f[0]), KINDS[f[1]]))
    want = {
        "laser": lambda r: covers(r["sh"], RED),
        "charge": lambda r: r["charge"] >= 1,
        "mega": lambda r: r["charge"] == 2,
        "shield": lambda r: r["charge"] == 0,
        "blast": lambda r: r["blinks"] > 0 and r["charge"] == 0,
        "flash": lambda r: covers(r["sh"], ALL),
        "thunder": lambda r: covers(r["sh"], ALL),
        "strike": lambda r: r["blinks"] > 0,
    }
    sent = {"laser": RED, "flash": ALL, "thunder": ALL}
    counts, bad = {}, []
    for tick, kind in events:
        ok = any(t in log and want[kind](log[t]) for t in range(tick, tick + 5))
        if ok and kind in sent:    # and on its way to the panel: the mirror holds it within 3 frames more
            ok = any(t in log and covers(log[t]["mi"], sent[kind]) for t in range(tick, tick + 8))
        c = counts.setdefault(kind, [0, 0])
        c[0] += 1
        c[1] += ok
        if not ok:
            bad.append(f"{kind}@{tick}")
    ticks = sorted(log)
    # the pulse: of the frames with a charge, those with the non-red LEDs lit (about half, if it pulses)
    nonred = bytes(a & ~r & 0xFF for a, r in zip(ALL, RED))
    ch = [t for t in ticks if log[t]["charge"] and not log[t]["blinks"]]
    lit_ch = sum(1 for t in ch if covers(log[t]["sh"], nonred))
    if ch:
        print(f"ledcheck: pulse    {lit_ch}/{len(ch)} frames of a charge with the non-red LEDs lit")
    active = sum(1 for t in ticks if log[t]["active"])
    first = next((t for t in ticks if log[t]["active"]), None)
    before = log[ticks[0]]["sh"] if ticks else b""
    if first is not None:
        before = log[max(t for t in ticks if t < first)]["sh"] if any(t < first for t in ticks) else before
    last = log[ticks[-1]]
    back = (not last["active"]) and bytes(a & m for a, m in zip(last["sh"], ALL)) == bytes(a & m for a, m in zip(before, ALL))
    print(f"ledcheck: {len(ticks)} frames logged, {active} with an effect; panel outputs lit at most {max(r['lit'] for r in log.values())}")
    for kind, (n, ok) in sorted(counts.items()):
        print(f"ledcheck: {kind:8s} {ok}/{n}")
    print(f"ledcheck: at the end the effects over {not last['active']}, the LED bits as before the first effect {back}"
          + (f"; missed: {' '.join(bad)}" if bad else ""))


if __name__ == "__main__":
    main()
