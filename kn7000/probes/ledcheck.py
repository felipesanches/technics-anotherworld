#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# ledcheck.py LEDLOG [FP] -- do the panel LEDs follow the game (src/leds.s)? LEDLOG: a MAME replay's LED log
# (probes/cnv/awcnv_inplog.lua AW_LEDLOG, a line a frame: "tick active charge red_ms all_ms blinks shadow mirror lit
# ms pulse_t panel fifo blast water redl_ms redr_ms green_ms v04 [shield_ms tank]"); FP (optional): the reference VM's events for the
# same session through awfp.py (research-scratch kn7000-aw-reference/fingerprints: replayawr AW_EVENTS=EV, then
# awfp.py EV PART > FP; lines "tick KIND part=.. ch=.."). For each event, in the frames from it to 4 later:
#   LASER_OTHER                  every red LED bit set in the shadow, and in the mirror (sent) within 7 frames
#   LASER_LESTER                 the red LEDs of the half var 0x04 says he faces (bit 0x10: right) set, the other
#                                half's not (unless another shot lit them), and sent
#   CHARGE_START / MEGA_CHARGE   the charge state >= 1 / 2
#   SHIELD                       the charge state 0, and (a shield of the first stage) the flash: about 30% of the
#                                red LEDs and nothing else, a different set at each shield
#   MEGA_RELEASE                 the blast followed (its flag) and every LED bit set
#   STORM_FLASH / STORM_THUNDER  every LED bit set, shadow and mirror; STORM_STRIKE: blinking
# (the lit bits, not the effect's timer: a 100 ms flash can end inside one game frame, before the frame is logged).
# Over the whole log, from the first frame the effects own the LEDs: dark (no LED bit set in a frame with no effect
# on), the pulse (frames of a charge with the PANEL MEMORY ring lit: near half; with any other LED lit: none), the
# recharge (frames with the green on: the share of the green LEDs, the PANEL MEMORY ring's too, lit at random, the sets), the waterfall (frames
# with random LEDs, and the share lit against the chance), what MAME's panel shows (the registers rebuilt from its outputs) against the shadow, and
# the most panel outputs lit.
import sys

ALL = bytes.fromhex("3F3F3F3F1F1F1F1FFFFAFFFFFFFF030103030303")
RED = bytes.fromhex("3F2F2F2F0E0C1E0D8008FC7CFFFF030003030103")
REDL = bytes.fromhex("1F2F2F2F0E0C1E0D000000000000000000000000")
REDR = bytes.fromhex("20000000000000008008FC7CFFFF030003030103")
GREEN = bytes.fromhex("0010101011130112071203830000000000000200")
PM = bytes.fromhex("000000000000000078E000000000000100000000")
GRNALL = bytes(g | p for g, p in zip(GREEN, PM))  # every green LED: the PANEL MEMORY ring is green too (Felipe)
KINDS = {"LASER_LESTER": "lester", "LASER_OTHER": "laser", "CHARGE_START": "charge", "MEGA_CHARGE": "mega",
         "SHIELD": "shield", "MEGA_RELEASE": "blast", "STORM_FLASH": "flash", "STORM_THUNDER": "thunder",
         "STORM_STRIKE": "strike"}


def load_log(p):
    rows = {}
    for line in open(p):
        f = line.split()
        if len(f) < 19 or f[6] == "-":
            continue
        rows[int(f[0])] = dict(active=int(f[1]), charge=int(f[2]), red=int(f[3]), all=int(f[4]), blinks=int(f[5]),
                               sh=bytes.fromhex(f[6]), mi=bytes.fromhex(f[7]), lit=int(f[8]),
                               panel=bytes.fromhex(f[11]), blast=int(f[13]), water=int(f[14]), redl=int(f[15]),
                               redr=int(f[16]), green=int(f[17]), v04=int(f[18], 16),
                               shield=int(f[19]) if len(f) > 19 else 0, tank=int(f[20]) if len(f) > 20 else 0)
    return rows


def covers(b, mask):
    return all((x & m) == m for x, m in zip(b, mask))


def none_of(b, mask):
    return all((x & m) == 0 for x, m in zip(b, mask))


def bits(b, mask=ALL):
    return sum(bin(x & m).count("1") for x, m in zip(b, mask))


def main():
    log = load_log(sys.argv[1])
    ticks = sorted(log)
    events = []
    if len(sys.argv) > 2:
        for line in open(sys.argv[2]):
            f = line.split()
            if len(f) >= 2 and f[0].isdigit() and f[1] in KINDS:
                events.append((int(f[0]), KINDS[f[1]]))

    def lester(r):
        side, other = (REDR, REDL) if r["v04"] & 0x10 else (REDL, REDR)
        return covers(r["sh"], side) and (none_of(r["sh"], other) or r["red"] or (r["redl"] and r["redr"]))

    want = {
        "laser": lambda r: covers(r["sh"], RED),
        "lester": lester,
        "charge": lambda r: r["charge"] >= 1,
        "mega": lambda r: r["charge"] == 2,
        "shield": lambda r: r["charge"] == 0,
        "blast": lambda r: r["blast"] == 1 and covers(r["sh"], ALL),
        "flash": lambda r: covers(r["sh"], ALL),
        "thunder": lambda r: covers(r["sh"], ALL),
        "strike": lambda r: r["blinks"] > 0,
    }
    sent = {"laser": RED, "flash": ALL, "thunder": ALL, "blast": ALL}
    counts, bad = {}, []
    for tick, kind in events:
        hit = [t for t in range(tick, tick + 5) if t in log and want[kind](log[t])]
        ok = bool(hit)
        if ok and kind == "lester":
            side = REDR if log[hit[0]]["v04"] & 0x10 else REDL
            ok = any(t in log and covers(log[t]["mi"], side) for t in range(tick, tick + 8))
            kind = "lester_" + ("right" if side is REDR else "left")
        elif ok and kind in sent:    # and on its way to the panel: the mirror holds it within 3 frames more
            ok = any(t in log and covers(log[t]["mi"], sent[kind]) for t in range(tick, tick + 8))
        c = counts.setdefault(kind, [0, 0])
        c[0] += 1
        c[1] += ok
        if not ok:
            bad.append(f"{kind}@{tick}")
    own = [t for t in ticks if log[t]["active"]]
    first = own[0] if own else None
    print(f"ledcheck: {len(ticks)} frames logged; the effects own the LEDs from frame {first}; "
          f"panel outputs lit at most {max(r['lit'] for r in log.values())}")
    # dark: no effect on (in that frame and the one before: the shadow is written at the game task's next yield,
    # after the frame is logged), no LED lit
    def calm(t):
        r = log.get(t)
        return r is not None and not (r["charge"] or r["red"] or r["all"] or r["blinks"] or r["blast"] or r["water"]
                                      or r["redl"] or r["redr"] or r["green"] or r["shield"] or r["tank"])
    quiet = [t for t in own if calm(t) and calm(t - 1)]
    dark = [t for t in quiet if bits(log[t]["sh"]) == 0]
    print(f"ledcheck: dark     {len(dark)}/{len(quiet)} frames with no effect have every LED off"
          + (f"; first lit {[t for t in quiet if t not in dark][:5]}" if len(dark) < len(quiet) else ""))
    # the panel (the registers rebuilt from MAME's LED outputs) against the shadow: a frame is stale when the
    # panel's LED bits match none of the shadows of that frame and the 3 before (the flush runs every 24 ms)
    def led(b):
        return bytes(x & m for x, m in zip(b, ALL))
    stale = [t for i, t in enumerate(ticks)
             if all(led(log[t]["panel"]) != led(log[u]["sh"]) for u in ticks[max(0, i - 3):i + 1])]
    endok = led(log[ticks[-1]]["panel"]) == led(log[ticks[-1]]["sh"])
    print(f"ledcheck: panel    {len(ticks) - len(stale)}/{len(ticks)} frames as the shadow (3 frames' lag allowed);"
          f" at the end {'the same' if endok else 'DIFFERENT'}" + (f"; first stale {stale[:5]}" if stale else ""))
    # the pulse: frames of a charge alone (no other effect): the ring lit about half of them; at the first stage
    # nothing else lit, at the big blob the green LEDs with the ring (and nothing else)
    calm_fx = lambda r: not (r["blinks"] or r["blast"] or r["red"] or r["redl"] or r["redr"] or r["all"] or r["shield"])
    pmg = bytes(p | g for p, g in zip(PM, GREEN))
    for stage, other in ((1, PM), (2, pmg)):
        ch = [t for t in ticks if log[t]["charge"] == stage and calm_fx(log[t]) and t - 1 in log and calm_fx(log[t - 1])]
        if ch:
            ring = sum(1 for t in ch if covers(log[t]["sh"], PM))
            grn = sum(1 for t in ch if covers(log[t]["sh"], GREEN))
            both = sum(1 for t in ch if covers(log[t]["sh"], PM) == covers(log[t]["sh"], GREEN))
            stray = sum(1 for t in ch if bits(log[t]["sh"], bytes(a & ~o & 0xFF for a, o in zip(ALL, other))))
            print(f"ledcheck: pulse{stage}   {ring}/{len(ch)} frames of {'a charge' if stage == 1 else 'the big blob'} with the PANEL MEMORY ring lit,"
                  f" {grn} with every green LED{f' ({both} with the two together)' if stage == 2 else ''}; {stray} with another LED lit")
    # the shield's flash: its frames, the share of the red LEDs lit, nothing but red, the sets differ
    sh = [t for t in ticks if log[t]["shield"]]
    if sh:
        groups, cur = [], []
        for t in sh:
            if cur and t != cur[-1] + 1:
                groups.append(cur); cur = []
            cur.append(t)
        groups.append(cur)
        sets = []
        for g in groups:
            t = next((u for u in g if bits(log[u]["sh"], RED)), g[0])
            sets.append(bytes(x & m for x, m in zip(log[t]["sh"], RED)))
            share = bits(log[t]["sh"], RED) / 71
            only = bits(log[t]["sh"], bytes(a & ~r & 0xFF for a, r in zip(ALL, RED))) == 0 or not calm_fx(dict(log[t], shield=0))
            print(f"ledcheck: shield   frames {g[0]}-{g[-1]}: {share:.0%} of the red LEDs lit, {'nothing else' if only else 'OTHER LEDs too'}")
        print(f"ledcheck: shield   {len(sets)} flashes, {len(set(sets))} different sets")
    gr = [t for t in ticks if log[t]["green"]]
    if gr:                       # the recharge: the green LEDs (the ring's too) at random (half, every 60 ms), nothing else
        share = sum(bits(log[t]["sh"], GRNALL) for t in gr) / (30 * len(gr))
        ring = sum(bits(log[t]["sh"], PM) for t in gr) / (8 * len(gr))
        sets = len({bytes(x & m for x, m in zip(log[t]["sh"], GRNALL)) for t in gr})
        other = sum(1 for t in gr if bits(log[t]["sh"], bytes(a & ~g & 0xFF for a, g in zip(ALL, GRNALL))))
        print(f"ledcheck: green    the recharge, frames {gr[0]}-{gr[-1]}: {share:.0%} of the 30 green LEDs lit on average"
              f" ({ring:.0%} of the PANEL MEMORY ring's), {sets} different sets in {len(gr)} frames;"
              f" {other} frames with another LED lit")
    wf = [t for t in ticks if log[t]["water"]]
    if wf:
        by = {}
        for t in wf:
            by.setdefault(log[t]["water"], []).append(bits(log[t]["sh"]) / 101)
        for w, v in sorted(by.items()):
            print(f"ledcheck: water    chance {w}/256 ({w / 256:.0%}): {len(v)} frames, {sum(v) / len(v):.0%} of the LEDs lit on average")
    for kind, (n, ok) in sorted(counts.items()):
        print(f"ledcheck: {kind:13s} {ok}/{n}")
    if bad:
        print(f"ledcheck: missed: {' '.join(bad)}")


if __name__ == "__main__":
    main()
