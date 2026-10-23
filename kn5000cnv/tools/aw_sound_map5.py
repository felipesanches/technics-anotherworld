#!/usr/bin/env python3
"""aw_sound_map5.py -- which KN5000 voice plays each Another World sound resource.

The KN7000 port's choice of a General MIDI program and note, or a GM drum key, per sound resource
(../kn7000/tools/aw_sound_map.py, SOUNDS) carried over to the KN5000's own voices. The KN5000's sub CPU
takes a program change as (program, bank selector) of its own tone database, not a GM program number
(technics-docs tone-database.md; the bank and program of every voice named below are in the tone
records' headers, technics-roms-disasm table_data/tone_database_records.s).

The voices are chosen among those MAME's KN5000 plays (kn5000cnv/README.md, "Sound": many voices are
silent there, the drum kits all of them, and an organ's note does not end); the instrument plays them all,
so this is a table to retune on the unit. The GM drum keys become melodic voices at a fixed note.

table(types, header) -> bytes: CNV_SND, 8 bytes per resource id 0x00..0x91:
  +0 kind: 0 none (silent), 1 melodic, 2 drum (a voice at a fixed note, 150 ms)
  +1 program, +2 bank selector
  +3 note the sample sounds at 8363 Hz (melodic), or the drum's fixed note
  +4 u16 LE: the sample's length in ms at 8363 Hz, 0xFFFF when it loops (held until stopped)
  +6 two bytes of padding
The lengths come from the resource headers of your own copy of the game, at build time.
Run alone, it lists the table: python3 -I tools/aw_sound_map5.py build/res
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'kn7000', 'tools'))
import aw_sound_map  # noqa: E402  (the KN7000's SOUNDS table)

# GM program (0-based) -> (bank selector, program, name) of the KN5000 voice standing in for it
GM_TO_KN5000 = {
    11: (0x00, 9, 'Glockenspiel'),       # (Vibraphone is silent in MAME)
    14: (0x00, 15, 'Steel Drum'),        # (Tubular Bells too)
    38: (0x00, 40, 'Electric Bass'),     # (Basic Synth Bass too)
    39: (0x00, 47, 'Mute Bass'),         # (Analog Bass too)
    50: (0x00, 94, 'Sine Lead'),         # (every string voice tried too)
    89: (0x00, 108, 'Dream'),            # (Warm Synth Pad and most pads too)
    115: (0x01, 122, 'Wood Block'),
    116: (0x03, 123, 'Taiko Drum'),
    118: (0x00, 124, 'Synth Drum'),
    122: (0x03, 124, 'Seashore'),
    127: (0x02, 123, 'Gun Shot'),
}
# GM drum key -> (bank selector, program, fixed note, name)
DRUM_TO_KN5000 = {
    35: (0x03, 123, 36, 'Taiko Drum'),   # bass drum
    36: (0x03, 123, 40, 'Taiko Drum'),   # kick
    38: (0x00, 124, 60, 'Synth Drum'),   # snare
    41: (0x03, 123, 48, 'Taiko Drum'),   # low floor tom
    42: (0x00, 125, 72, 'Sleigh Bell'),  # closed hi-hat
}
NRES = 0x92


def table(types, header):
    out, lines = bytearray(), []
    for i in range(NRES):
        typ = types[i] if i < len(types) else ''
        m = aw_sound_map.SOUNDS.get(i)
        d = header(i) if typ == 'sound' else b''
        if m is None or len(d) < 4:
            out += bytes(8)
            continue
        ln, lp = (d[0] << 8 | d[1]) * 2, (d[2] << 8 | d[3]) * 2
        ms = 0xFFFF if lp else min(0xFFFE, max(1, ln * 1000 // 8363))
        kind, a, n = m
        if kind == 'D':
            sel, prog, note, name = DRUM_TO_KN5000[a]
            out += bytes((2, prog, sel, note, ms & 0xFF, ms >> 8, 0, 0))
            lines.append(f'0x{i:02X}  drum {a:3d}: {name:16s} sel 0x{sel:02X} prog {prog:3d}  note {note:3d}')
        else:
            sel, prog, name = GM_TO_KN5000[a]
            out += bytes((1, prog, sel, n, ms & 0xFF, ms >> 8, 0, 0))
            lines.append(f'0x{i:02X}  {name:16s} sel 0x{sel:02X} prog {prog:3d}  note {n:3d}  '
                         f'{"held (loops)" if lp else str(ms) + " ms"}')
    return bytes(out), lines


def main():
    res = sys.argv[1]
    rows = [line.split('\t') for line in open(os.path.join(res, 'memlist.tsv')).read().split('\n')[1:] if line]
    types = [r[1] for r in rows]
    _, lines = table(types, lambda i: open(os.path.join(res, f'resource-0x{i:02x}.bin'), 'rb').read(4))
    print('\n'.join(lines))


if __name__ == '__main__':
    main()
