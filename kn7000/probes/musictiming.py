#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# musictiming.py -- the intro's music against its picture (probes/MUSIC-TIMING.md says what each table answers).
#
#   musictiming.py marks DATA                    the intro module's sync marks (resource 0x07 of the MS-DOS release
#                                                in DATA: MEMLIST.BIN + BANKxx) as AW_VMARKS for the rustyworld
#                                                virtual-clock runs (musictiming.sh)
#   musictiming.py report DATA [options]         the tables, Markdown, to stdout:
#       --sim MODEL=FILE ...    rustyworld's virtual-clock runs (AW_VOUT files: "T tick ms pause blits", "M tick chan
#                               value row ms"), each an engine's row period with the picture taking no CPU time
#       --unit NAME=AWR:VARS:EV a session from the instrument (tools/aw_inplog.py's .awr: the M records give the frame
#                               each mark arrived) and rustyworld's replay of it (REF_VARS: var 0xFF at every tick;
#                               AW_VOUT: its PLAY_MUSIC calls)
#       --mame NAME=TIMELOG     a MAME run's AW_TIMELOG (probes/cnv/awcnv_inplog.lua: F, K, S records)
#
# Python 3 alone; tools/aw_extract.py unpacks the module.
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import aw_extract  # noqa: E402

INTRO_MODULE = 0x07
DELAYS = (0x3D54, 0x3E1C)       # the intro's PLAY_MUSIC delay, and the retime the biometric scene asks for

# ---- each engine's row period (ms) for a module delay, and its pause slice (ms) -------------------------------
PAL_E = 709379.0                # Amiga PAL E clock (CIA), 7.09379 MHz / 10
NTSC_E = 715909.0               # NTSC: 7.15909 MHz / 10
PIT = 1193182.0
DOS_RATE = PIT / 119            # the DOS player's timer (PIT reload 119: the 10 kHz mode; [0x1A0], [0x1A2] = 10000)


def row_ms(model, delay):
    if model == 'amiga_pal':     # CIA-A timer A latch = delay ($916A4, $917DC), a row at every 6th underflow ($91878)
        return 6 * delay / PAL_E * 1000
    if model == 'amiga_ntsc':
        return 6 * delay / NTSC_E * 1000
    if model == 'dos':           # ANOTHER.EXE 0x4091: limit = delay * 600 / 7050; the ISR plays a row at limit + 1 ticks
        return (delay * 600 // 7050 + 1) / DOS_RATE * 1000
    if model == 'rawgl':         # sfxplayer.cpp: _delay * 60 * 1000 / kPaulaFreq ms (int), then samples at 44.1 kHz
        ms = delay * 60 * 1000 // 7159092
        return (44100 * ms // 1000) / 44100 * 1000
    if model in ('sanglard', 'rustyworld'):    # delay * 60 / 7050 ms (int); Sanglard's SDL timer, rustyworld's beat
        return float(delay * 60 // 7050)
    if model == 'ours':          # audio.s MusicPeriod: delay * 2146 / 1000 in 1/256 ms, on the kernel's 1 ms counter
        return (delay * 2146 // 1000) / 256
    if model == 'ours_pal':      # audio.s MusicPeriod since this branch: the Amiga PAL player's row
        return (delay * 35476 >> 14) / 256
    raise ValueError(model)


def slice_ms(model):
    if model == 'dos':           # 200 ticks of the timer (ANOTHER.EXE 0x820: [0x1A2] / 50) per VM slice
        return 200 / DOS_RATE * 1000
    return 20.0                  # a 50 Hz frame (Amiga PAL VBL; rawgl, Sanglard, rustyworld, ours: 20 ms)


MODELS = ('amiga_pal', 'dos', 'amiga_ntsc', 'rawgl', 'sanglard', 'rustyworld', 'ours', 'ours_pal')
WHERE = {
    'amiga_pal': 'Amiga original (ADF disk 1), PAL',
    'amiga_ntsc': 'the same player on an NTSC E clock',
    'dos': 'MS-DOS original (ANOTHER.EXE), 10 kHz mode',
    'rawgl': 'rawgl 049e4ad sfxplayer.cpp:109',
    'sanglard': 'Sanglard 170b7d4 sfxplayer.cpp:42,67',
    'rustyworld': 'rustyworld 2e9a5ab music.rs:36,64',
    'ours': 'KN7000 port audio.s MusicPeriod (7c2d2c06)',
    'ours_pal': 'KN7000 port audio.s MusicPeriod (this branch)',
}


def resource(data, rid):
    ents = aw_extract.memlist(os.path.join(data, 'MEMLIST.BIN'))
    e = ents[rid]
    with open(os.path.join(data, f"BANK{e['bank']:02X}"), 'rb') as f:
        f.seek(e['offset'])
        raw = f.read(e['packed'])
    return raw if e['packed'] == e['size'] else aw_extract.unpack(raw, e['size'])


def module_marks(data):
    """(rows in the module, [(row, mark value)]) of the intro's module, rows counted from order 0."""
    d = resource(data, INTRO_MODULE)
    nord = struct.unpack('>H', d[0x3E:0x40])[0]
    marks, row = [], 0
    for p in d[0x40:0x40 + nord]:
        for r in range(64):
            for ch in range(4):
                note, val = struct.unpack_from('>HH', d, 0xC0 + p * 1024 + r * 16 + ch * 4)
                if note == 0xFFFD:
                    marks.append((row, val))
            row += 1
    return row, marks


def table(rows, head):
    w = [max(len(str(x)) for x in col) for col in zip(head, *rows)]
    out = ['| ' + ' | '.join(str(h).ljust(n) for h, n in zip(head, w)) + ' |',
           '|' + '|'.join('-' * (n + 2) for n in w) + '|']
    out += ['| ' + ' | '.join(str(c).ljust(n) for c, n in zip(r, w)) + ' |' for r in rows]
    return '\n'.join(out)


# ---- the picture's scenes around the countdown, from var 0xFF's runs (the pause each scene sets) ----------------
# The intro (part 0x3E81) from "- Phase 2: EJECTION" to the experiment: 5 (Phase 2, 19 frames), 4 (ANALYSIS 19,
# RESULT up to 25, "Practical verification" up to 10: both left at mark > 0x20), 5 (the countdown 20, 19, 18),
# 6 / 4 / 9 (the soda; its last pose held up to 18 frames until mark 0x2B), 5 (5 4 3 2 1, each until its mark or 11
# frames), 4 ("0", then up to 39 frames until mark 0x31, which stops the music), 3 (the experiment runs).
SCENES = ('phase2', 'analysis', 'countdown', 'soda_open', 'soda_flick', 'soda_drink', 'count5', 'zero', 'run')
PATTERN = (5, 4, 5, 6, 4, 9, 5, 4, 3)


def scenes(pauses, lo, hi):
    """{scene: (first tick, frames)} for the countdown's run pattern in pauses[lo:hi] (pauses: tick -> var 0xFF)."""
    runs, prev, start = [], None, None
    for t in range(lo, hi):
        p = pauses.get(t)
        if p is None:
            continue
        if p != prev:
            if prev is not None:
                runs.append((start, prev, t - start))
            prev, start = p, t
    runs.append((start, prev, None))
    for i in range(len(runs) - len(PATTERN) + 1):
        if tuple(r[1] for r in runs[i:i + len(PATTERN)]) == PATTERN and runs[i][2] and runs[i][2] >= 15:
            return {s: (r[0], r[2]) for s, r in zip(SCENES, runs[i:i + len(PATTERN)])}
    return None


class Timeline:
    """A run: the tick each mark's row arrived, var 0xFF at each tick, the music's ms at a row."""

    def __init__(self, name, model):
        self.name, self.model, self.mark_tick, self.pause, self.note = name, model, {}, {}, ''
        self.start_tick, self.retime_row, self.frame_ms, self.krec, self.starts = None, None, {}, [], []
        self.mark_ms = {}

    def row_at(self, tick):
        """The module row playing at that tick's start, interpolated between the marks' ticks (and the start's)."""
        pts = sorted([(t, r) for r, t in self.mark_tick.items()] + ([(self.start_tick, 0)] if self.start_tick else []))
        for (t0, r0), (t1, r1) in zip(pts, pts[1:]):
            if t0 <= tick <= t1 and t1 > t0:
                return r0 + (r1 - r0) * (tick - t0) / (t1 - t0)
        return None

    def music_ms(self, row):
        """ms from the module's start to that row: measured (MAME), else the row periods with the retime."""
        if row in self.mark_ms:
            return self.mark_ms[row]
        p0, p1 = row_ms(self.model, DELAYS[0]), row_ms(self.model, DELAYS[1])
        first = p0 if self.model == 'dos' else 0.0
        if self.retime_row is None or row <= self.retime_row:
            return first + row * p0
        return first + self.retime_row * p0 + (row - self.retime_row) * p1


def read_events(tl, path):
    """rustyworld's AW_VOUT: T (tick, ms, pause), M (the marks the virtual clock wrote), P (PLAY_MUSIC calls)."""
    seen = []
    for line in open(path):
        a = line.split()
        if a[0] == 'T':
            tl.pause[int(a[1])] = int(a[3])
        elif a[0] == 'M':
            seen.append((int(a[4]), int(a[1])))
            tl.last_mark = (int(a[4]), float(a[5]))
        elif a[0] == 'P':
            tick, res, delay = int(a[1]), int(a[2], 16), int(a[3])
            if res == 0 and delay == 0 and tl.start_tick is not None and not hasattr(tl, 'stop'):
                tl.stop = (tick, float(a[5]))
            if res == INTRO_MODULE and tl.start_tick is None:
                tl.start_tick = tick
            elif res == 0 and delay == DELAYS[1] and tl.start_tick is not None and tl.retime_row is None:
                tl.retime_tick = tick
    return seen


def load_sim(name, path, marks):
    tl = Timeline(name, name.split()[1])           # 'sim MODEL [...]'
    want = {r for r, _ in marks}
    for r, t in read_events(tl, path):
        if r in want:
            tl.mark_tick.setdefault(r, t)
    if hasattr(tl, 'retime_tick'):
        tl.retime_row = tl.row_at(tl.retime_tick)
    return tl


def load_unit(name, awr, varsfile, evfile, marks):
    """The instrument's own marks (each M record one mark row, in the module's order, from its first PLAY_MUSIC)."""
    tl = Timeline(name, 'ours')
    read_events(tl, evfile)                         # (the replay's: its own marks are the log's)
    tl.pause = {}
    recs = [line.split() for line in open(awr) if line.startswith('M ')]
    k = 0
    for r, v in marks:
        if k < len(recs) and int(recs[k][3]) == v:
            tl.mark_tick[r] = int(recs[k][1])
            k += 1
    if k != len(recs):
        tl.note = (f'{len(recs) - k} M record(s) after the intro module\'s {len(marks)} marks: '
                   f'{", ".join(" ".join(x[1:]) for x in recs[k:])} (the module started again later in the session)')
    v = open(varsfile, 'rb').read()
    for t in range(len(v) // 512):
        tl.pause[t] = struct.unpack_from('<h', v, t * 512 + 0xFF * 2)[0]
    if hasattr(tl, 'retime_tick'):
        tl.retime_row = tl.row_at(tl.retime_tick)
    return tl


def load_mame(name, path, marks):
    """AW_TIMELOG: the kernel ms of every frame's end and of every mark, as the module player wrote it."""
    tl = Timeline(name, 'ours')
    want = {r for r, _ in marks}
    krec, prev, base, start_ms = [], None, None, None
    for line in open(path):
        a = line.split()
        if a[0] == 'S':
            tl.starts.append((int(a[1]), int(a[2]), int(a[3]), int(a[4])))
            if base is None:
                tl.start_tick, base, start_ms = int(a[1]), int(a[3]), int(a[2])
        elif a[0] == 'K' and base is not None:
            tick, kms, rows, due, val = map(int, a[1:6])
            krec.append((tick, kms, rows, due, val))
            r = rows - base - 1
            if r in want and r not in tl.mark_tick:
                tl.mark_tick[r] = tick
                tl.mark_ms[r] = kms - start_ms
        elif a[0] == 'F':
            tick, kms, pause = int(a[1]), int(a[2]), int(a[3])
            tl.pause[tick] = pause
            if prev is not None:
                tl.frame_ms[tick] = kms - prev
            prev = kms
        elif a[0] == 'P' and base is not None:          # AU_PER: the start's (written after AU_MOD), then a retime
            if not hasattr(tl, 'start_per'):
                tl.start_per = int(a[3])
            elif int(a[3]) != tl.start_per and not hasattr(tl, 'retime_tick'):
                tl.retime_tick = int(a[1])
    tl.krec = krec
    return tl


ANCHORS = (0, 64, 128, 288, 415, 767, 831, 936)


def report(data, sims, units, mames):
    nrows, marks = module_marks(data)
    out = []
    p = lambda s='': out.append(s)
    p('# The intro\'s music and picture: measured')
    p()
    p(f'Generated by `probes/musictiming.py report` (`probes/musictiming.sh`). The intro module (resource 0x07): '
      f'{nrows} rows, {len(marks)} sync marks.')
    p()
    p('## 1. The row period of each engine')
    p()
    rows = []
    for m in MODELS:
        r0, r1 = row_ms(m, DELAYS[0]), row_ms(m, DELAYS[1])
        sl = slice_ms(m)
        rows.append((m, WHERE[m], f'{r0:.3f}', f'{r1:.3f}', f'{sl:.3f}', f'{r0 / sl:.4f}',
                     f'{(r0 / sl) / (row_ms("amiga_pal", DELAYS[0]) / 20.0) * 100 - 100:+.2f} %'))
    p(table(rows, ('engine', 'source', 'row ms, delay 0x3D54', 'row ms, 0x3E1C', 'slice ms', 'slices a row',
                   'row against the slice, vs the Amiga')))
    p()
    p('## 2. The marks')
    p()
    p('Seconds from PLAY_MUSIC to each mark\'s row at delay 0x3D54 throughout (the biometric scene retimes the module '
      'to 0x3E1C some 57 s in; the runs below include that).')
    p()
    eng = ('amiga_pal', 'dos', 'rawgl', 'ours')
    rows = [[r, f'0x{v:02X}'] + [f'{(r + (1 if m == "dos" else 0)) * row_ms(m, DELAYS[0]) / 1000:.2f}' for m in eng]
            for r, v in marks]
    p(table(rows, ['row', 'mark'] + [f'{m} s' for m in eng]))
    p()
    d = resource(data, INTRO_MODULE)
    nord = struct.unpack('>H', d[0x3E:0x40])[0]
    rows = []
    for oi, pat in enumerate(d[0x40:0x40 + nord]):
        if oi < 11:
            continue
        notes = lambda r: [struct.unpack_from('>H', d, 0xC0 + pat * 1024 + r * 16 + c * 4)[0] for c in range(3)]
        same = sum(1 for r in range(56) if notes(r) == notes(r + 8))
        rows.append((oi, pat, f'{oi * 64}-{oi * 64 + 63}', f'{same} / 56'))
    p('The last orders: how many rows repeat the notes (channels 0-2) of the row 8 before them.')
    p()
    p(table(rows, ('order', 'pattern', 'rows', 'rows equal to 8 rows later')))
    p()
    tls = [load_sim(n, f, marks) for n, f in sims] + [load_unit(n, a, v, e, marks) for n, a, v, e in units] + \
          [load_mame(n, f, marks) for n, f in mames]
    p('## 3. Where the picture is when the music reaches its countdown')
    p()
    p('The module row playing when each scene around the countdown starts (interpolated between the marks\' ticks). '
      'In the bytecode the picture leaves a scene early only for the music (mark > 0x20 ends RESULT and "Practical '
      'verification"; 0x22, 0x23 end "20", "19"; 0x2B ends the soda pose; 0x2C-0x30 end "5"-"1"; 0x31 after "0" '
      'stops the music); everything else runs on frame counts. The music\'s countdown starts at row 831 (mark 0x21), '
      'its "0" at row 936 (0x30). "lead" is how long the music\'s countdown had been playing when the picture\'s '
      'began (negative: how long the picture\'s waited for it), at the run\'s row period.')
    p()
    rows = []
    for tl in tls:
        sc = scenes(tl.pause, 1500, 3000)
        if not sc:
            rows.append((tl.name,) + ('-',) * 9)
            continue
        def r(s):
            x = tl.row_at(sc[s][0])
            return x
        rc = r('countdown')
        lead = (tl.music_ms(rc) - tl.music_ms(831)) / 1000 if rc is not None else None
        stopped = 'yes' if 948 in tl.mark_tick and sc['zero'][0] <= tl.mark_tick[948] < sc['zero'][0] + 39 else 'no'
        rows.append((tl.name, f'{r("phase2"):.1f}', f'{rc:.1f}', f'{lead:+.2f}', sc['analysis'][1], sc['countdown'][1],
                     sc['soda_drink'][1], sc['count5'][1], f'{r("zero"):.1f}' if r('zero') is not None else '-', stopped))
    p(table(rows, ('run', 'Phase 2 at row', 'countdown at row', 'lead s', 'ANALYSIS..Y/N frames',
                   '20 19 18 frames', 'soda drink frames', '5..1 frames', '"0" at row', 'music stopped by 0x31')))
    p()
    p('The ideal pacing (each frame exactly var 0xFF x 20 ms, as rawgl, Sanglard and rustyworld run on a PC) shows '
      'ANALYSIS..Y/N 54 frames, 20 19 18 32 frames, the soda pose 24 and 5..1 55: every one of those scenes ran its '
      'full count, no mark arrived in time.')
    p()
    for tl in tls:
        if tl.name.startswith('sim') and hasattr(tl, 'stop') and hasattr(tl, 'last_mark'):
            r, ms = tl.last_mark
            row = r + (tl.stop[1] - ms) / row_ms(tl.model, DELAYS[1])
            p(f'{tl.name}: the music stopped (PLAY_MUSIC 0, 0) at tick {tl.stop[0]}, module row {row:.1f}.')
    p()
    for tl in tls:
        if tl.note:
            p(f'{tl.name}: {tl.note}.')
            p()
    p('## 4. Frames: what the bytecode asked, what they took')
    p()
    p('Between marks, from the module\'s start: the frames the picture ran, the time those frames ask (var 0xFF x 20 ms '
      'each), the time they took (the music\'s time between the two marks: the module player keeps the kernel\'s '
      'clock), and the lag this adds (took - asked). MAME: the time measured with the kernel\'s counter.')
    p()
    for tl in tls:
        if tl.name.startswith('sim'):
            continue
        rows, lag = [], 0.0
        anchors = [a for a in ANCHORS if a == 0 or a in tl.mark_tick]
        for r0, r1 in zip(anchors, anchors[1:]):
            t0 = tl.start_tick if r0 == 0 else tl.mark_tick[r0]
            t1 = tl.mark_tick[r1]
            asked = sum(tl.pause.get(t, 0) * 20 for t in range(t0, t1))
            took = tl.music_ms(r1) - tl.music_ms(r0)
            lag += took - asked
            mf = ''
            if tl.frame_ms:
                mf = f'{sum(tl.frame_ms.get(t + 1, 0) for t in range(t0, t1)) / 1000:.2f}'
            rows.append((f'{r0}-{r1}', t1 - t0, f'{asked / 1000:.2f}', f'{took / 1000:.2f}', f'{took / asked:.3f}',
                         f'{lag / 1000:+.2f}', f'{asked / (t1 - t0):.1f}', f'{took / (t1 - t0):.1f}') +
                        ((mf,) if tl.frame_ms else ()))
        if 831 in tl.mark_tick:                     # the whole way to the music's countdown
            t0, t1 = tl.start_tick, tl.mark_tick[831]
            asked = sum(tl.pause.get(t, 0) * 20 for t in range(t0, t1))
            took = tl.music_ms(831) - tl.music_ms(0)
            rows.append(('0-831', t1 - t0, f'{asked / 1000:.2f}', f'{took / 1000:.2f}', f'{took / asked:.3f}', '',
                         f'{asked / (t1 - t0):.1f}', f'{took / (t1 - t0):.1f}') +
                        ((f'{sum(tl.frame_ms.get(t + 1, 0) for t in range(t0, t1)) / 1000:.2f}',) if tl.frame_ms else ()))
        p(f'### {tl.name}')
        p()
        if tl.retime_row is not None:
            p(f'Retimed to 0x3E1C at tick {tl.retime_tick} (row {tl.retime_row:.1f}).')
            p()
        head = ('rows', 'frames', 'asked s', 'took s', 'took / asked', 'lag so far s', 'asked ms a frame',
                'took ms a frame')
        p(table(rows, head + (('frames\' own sum s',) if tl.frame_ms else ())))
        p()
    for tl in tls:
        if tl.krec:
            base = tl.starts[0][2]
            due = {k[2] - base - 1: k[3] for k in tl.krec}
            per = [f'rows {a}-{b} {(due[b] - due[a]) / (b - a):.3f} ms a row' for a, b in ((64, 320), (767, 948))
                   if a in due and b in due]
            p(f'{tl.name}: the module player\'s schedule (AU_NEXT at each mark): {", ".join(per)}.')
            p()
            late = [k[1] - k[3] for k in tl.krec]
            p(f'{tl.name}: {len(tl.krec)} marks written by the module player, each {min(late)} to {max(late)} ms after '
              f'its row was due (AU_NEXT); module starts (tick, kernel ms): '
              f'{"; ".join(f"{s[0]} {s[1]}" for s in tl.starts)}.')
            p()
    return '\n'.join(out) + '\n'


def main(argv):
    if len(argv) >= 2 and argv[0] == 'marks':
        nrows, marks = module_marks(argv[1])
        print(f'{INTRO_MODULE:x}:{nrows}:' + ','.join(f'{r}={v}' for r, v in marks))
        return
    if len(argv) >= 2 and argv[0] == 'report':
        data, sims, units, mames = argv[1], [], [], []
        i = 2
        while i < len(argv):
            k, v = argv[i], argv[i + 1]
            n, f = v.split('=', 1)
            if k == '--sim':
                sims.append((n, f))
            elif k == '--unit':
                a, b, c = f.split(':')
                units.append((n, a, b, c))
            elif k == '--mame':
                mames.append((n, f))
            else:
                sys.exit(f'musictiming: {k}?')
            i += 2
        sys.stdout.write(report(data, sims, units, mames))
        return
    sys.exit(__doc__ if __doc__ else 'musictiming.py marks DATA | report DATA [--sim M=F] [--unit N=AWR:VARS] [--mame N=LOG]')


if __name__ == '__main__':
    main(sys.argv[1:])
