#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# aw_inplog.py FILE_OR_FOLDER... [-o SESSION.awr] -- the game's input log (src/inplog.s: AWIN00.BIN, AWIN01.BIN ...
# from the SD card's root folder) as one text file, the session to replay: in MAME (probes/cnv/awcnv_inplog.lua
# AW_REPLAY=SESSION.awr) and in rustyworld (research-scratch kn7000-aw-reference/replay-mods replayawr). A folder
# means its AWIN*.BIN. Checks that the files are one session's, in order, with nothing missing, and prints what the
# session holds. Python 3 alone.
#
# The text file, one record a line, frames as the game counts them (FRAME_NO, counted on past 65535):
#   # comments (the session's stamp, the files, the counts)
#   P frame part        a part started (hex)            R frame part   ReadInput asked for that part (hex)
#   I frame mode mask   from this frame on, ReadInput applied the mask (var 0xFE; hex); mode intro: only var 0xFA
#                       (1 when the mask has 0x80) and var 0xFE written; mode play: the six hero variables
#   M frame thread v    the music's sync mark v (var 0xF4) appeared before that thread of that frame ran
#   E frame dropped     the end; records lost for want of room (0: none)
import glob
import os
import struct
import sys

REC = struct.Struct('<IBBH')


def load(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += sorted(f for f in glob.glob(os.path.join(p, '*')) if os.path.basename(f).upper().startswith('AWIN')
                            and f.upper().endswith('.BIN'))
        else:
            files.append(p)
    halves = []
    for f in files:
        data = open(f, 'rb').read()
        if len(data) < 8 or len(data) % 8:
            sys.exit(f'{f}: {len(data)} bytes, not whole records')
        recs = [REC.unpack_from(data, i) for i in range(0, len(data), 8)]
        frame, kind, a, b = recs[0]
        if kind != ord('H'):
            sys.exit(f'{f}: does not start with an H record')
        if a != 1:
            sys.exit(f'{f}: format version {a}, this reads 1')
        halves.append((frame, b, f, recs))
    if not halves:
        sys.exit('aw_inplog: no AWIN*.BIN files')
    sessions = {h[0] for h in halves}
    if len(sessions) > 1:
        # every session writes AWIN00.BIN first, over the last one's: its stamp (the kernel's ms since power-on,
        # which a power cycle starts again) names the latest session; files with another are an older one's
        first = [h for h in halves if h[1] == 0]
        if len(first) != 1:
            sys.exit(f'aw_inplog: files of {len(sessions)} sessions and {len(first)} first files: give one session\'s')
        latest = first[0][0]
        old = sorted(os.path.basename(h[2]) for h in halves if h[0] != latest)
        print(f'aw_inplog: {", ".join(old)}: an older session\'s, left out', file=sys.stderr)
        halves = [h for h in halves if h[0] == latest]
    halves.sort(key=lambda h: h[1])
    for i, h in enumerate(halves):
        if h[1] != i:
            sys.exit(f'aw_inplog: half {i} is missing (have {[x[1] for x in halves]})')
    return halves


def main(args):
    out = None
    if '-o' in args:
        i = args.index('-o')
        out, args = args[i + 1], args[:i] + args[i + 2:]
    if not args:
        sys.exit('aw_inplog.py FILE_OR_FOLDER... [-o SESSION.awr]')
    halves = load(args)
    lines, counts, last, ended, dropped = [], {}, -1, False, 0
    for _, num, f, recs in halves:
        for frame, kind, a, b in recs[1:]:
            k = chr(kind)
            counts[k] = counts.get(k, 0) + 1
            if frame < last:
                sys.exit(f'{f}: frame {frame} after {last}: out of order')
            last = frame
            if k == 'I':
                lines.append(f'I {frame} {"intro" if a else "play"} 0x{b:02X}')
            elif k == 'P':
                lines.append(f'P {frame} 0x{b:04X}')
            elif k == 'R':
                lines.append(f'R {frame} 0x{b:04X}')
            elif k == 'M':
                lines.append(f'M {frame} {a} {b - 0x10000 if b >= 0x8000 else b}')
            elif k == 'E':
                lines.append(f'E {frame} {b}')
                ended, dropped = True, b
            else:
                sys.exit(f'{f}: unknown record kind {kind:#x}')
    head = [f'# Another World input log (kn7000 src/inplog.s, version 1): session stamp {halves[0][0]} ms, '
            f'{len(halves)} files ({", ".join(os.path.basename(h[2]) for h in halves)})',
            f'# {sum(counts.values())} records: ' + ', '.join(f'{k} {v}' for k, v in sorted(counts.items())) +
            f'; frames 0-{last}; ' + ('ended at quit' if ended else 'NO END RECORD: the session did not quit')]
    text = '\n'.join(head + lines) + '\n'
    if out:
        open(out, 'w').write(text)
    else:
        sys.stdout.write(text)
    parts = [l.split()[2] for l in lines if l.startswith('P ')]
    print(f'aw_inplog: {len(halves)} files, {sum(counts.values())} records, frames 0-{last}, parts {" ".join(parts)}; '
          f'{counts.get("I", 0)} input changes, {counts.get("M", 0)} sync marks, {counts.get("R", 0)} part requests; '
          + (f'{dropped} records lost' if dropped else ('none lost' if ended else 'no end record')), file=sys.stderr)


if __name__ == '__main__':
    main(sys.argv[1:])
