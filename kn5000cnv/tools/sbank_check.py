#!/usr/bin/env python3
"""sbank_check.py RESDIR PART_INDEX DUMP -- is the sound bank the DSP sound loaded into the sub CPU (DUMP: the sub
CPU's DRAM from SUB_BANK = 0xA0000, probes/subdump.lua) what tools/aw_sbank.py says it should be? For each of the
part's sounds (aw_partinfo.PARTS order, PART_INDEX 0..9): the samples CNV_SBANK_LOAD should have sent, decoded from
the same ADPCM by aw_sbank.decode(), against the dump at its offset. Prints one line per sound and a total."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aw_sbank  # noqa: E402

resdir, k, dump = sys.argv[1], int(sys.argv[2]), open(sys.argv[3], 'rb').read()
pid, ids = aw_sbank.part_sounds(resdir)[k]
off, bad = 0, 0
for i in ids:
    ln, lp, smp = aw_sbank._sound(resdir, i)
    want = aw_sbank.decode(aw_sbank.encode([b - 256 if b > 127 else b for b in smp]), len(smp))
    got = dump[off:off + len(want)]
    diff = sum(1 for a, b in zip(want, got) if a != b) + abs(len(want) - len(got))
    bad += diff
    print('0x%02x at +%6d: %6d samples, %d differ' % (i, off, len(want), diff))
    off += (ln + lp + 3) & ~3
print('part 0x%04x: %d sounds, %d bytes, %d differ' % (pid, len(ids), off, bad))
