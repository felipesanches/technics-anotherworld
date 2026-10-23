#!/usr/bin/env python3
"""aw_sbank.py -- the game's own sounds for the DSP sound (src/awsub.asm, src/cnv_dspsnd.asm).

Library for make_awdisk.py:
  files(resdir)  -> {name: bytes}: AWSnn.BIN, every sound some part plays, once, as 4-bit IMA ADPCM
  table(resdir)  -> the ASL text of CNV_SLEN (each sound's length and loop length, bytes), CNV_SPARTS (each
                    part's sounds: id and offset in that part's bank in sub DRAM, 0FFh-terminated) and
                    CNV_SBANK_MAX (the largest part's bank)

A sound resource is 8 bytes of header (length and loop length, in 16-bit words, big-endian) and signed 8-bit
samples: the first `length` play once, then the `loop length` after them repeat (rawgl). The floppy has no
room for them as 8-bit samples beside the rest (684,980 bytes), so they are coded: IMA ADPCM, two samples a
byte, low nibble first, on the samples taken as 16-bit (s << 8), the predictor starting at 0 with step index
0 for every sound. The decoder (src/cnv_dspsnd.asm CNV_ADPCM) must reproduce encode()'s own reconstruction,
which decode() here does; the build checks the two agree.

A part's sounds are those its bytecode plays or loads, and the instruments of the music it plays
(../kn7000/tools/aw_partinfo.py decodes the bytecode).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'kn7000', 'tools'))
import aw_partinfo  # noqa: E402

STEPS = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88,
         97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658,
         724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660,
         4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818,
         18500, 20350, 22385, 24623, 27086, 29794, 32767]
INDEX = [-1, -1, -1, -1, 2, 4, 6, 8]


def _step(pred, idx, code):
    st = STEPS[idx]
    d = st >> 3
    if code & 1:
        d += st >> 2
    if code & 2:
        d += st >> 1
    if code & 4:
        d += st
    pred = pred - d if code & 8 else pred + d
    pred = max(-32768, min(32767, pred))
    idx = max(0, min(88, idx + INDEX[code & 7]))
    return pred, idx


def encode(samples):
    """signed 8-bit samples -> ADPCM bytes"""
    pred, idx, nib = 0, 0, []
    for s in samples:
        diff = (s << 8) - pred
        code = 0
        if diff < 0:
            code, diff = 8, -diff
        st = STEPS[idx]
        if diff >= st:
            code |= 4; diff -= st
        if diff >= st >> 1:
            code |= 2; diff -= st >> 1
        if diff >= st >> 2:
            code |= 1
        pred, idx = _step(pred, idx, code)
        nib.append(code)
    if len(nib) & 1:
        nib.append(0)
    return bytes(nib[i] | (nib[i + 1] << 4) for i in range(0, len(nib), 2))


def decode(data, n):
    """ADPCM bytes -> n signed 8-bit samples (the predictor's top byte)"""
    pred, idx, out = 0, 0, []
    for b in data:
        for code in (b & 15, b >> 4):
            if len(out) == n:
                break
            pred, idx = _step(pred, idx, code)
            out.append((pred >> 8) & 0xFF)
    return bytes(out)


def _types(resdir):
    rows = [l.split('\t') for l in open(os.path.join(resdir, 'memlist.tsv')).read().split('\n')[1:] if l]
    return {int(r[0], 16): r[1] for r in rows}


def _sound(resdir, i):
    d = open(os.path.join(resdir, 'resource-0x%02x.bin' % i), 'rb').read()
    if len(d) < 8:
        return 0, 0, b''
    ln, lp = (d[0] << 8 | d[1]) * 2, (d[2] << 8 | d[3]) * 2
    return ln, lp, d[8:8 + ln + lp]


def part_sounds(resdir):
    """[(part id, [sound ids])] in aw_partinfo.PARTS order"""
    types = _types(resdir)
    out = []
    for pid, name, pal, cod, v1, v2 in aw_partinfo.PARTS:
        code = open(os.path.join(resdir, 'resource-0x%02x.bin' % cod), 'rb').read()
        ops, snd, mus, lds, bad, rd = aw_partinfo.decode(code)
        ids = {i for i in snd if types.get(i) == 'sound'} | {i for i in lds if i < 0x92 and types.get(i) == 'sound'}
        for m in set(mus) | {i for i in lds if i < 0x92 and types.get(i) == 'music'}:
            if types.get(m) != 'music':
                continue
            mod = open(os.path.join(resdir, 'resource-0x%02x.bin' % m), 'rb').read()
            for k in range(15):
                r = mod[2 + 4 * k] << 8 | mod[3 + 4 * k]
                if r and types.get(r) == 'sound':
                    ids.add(r)
        out.append((pid, sorted(i for i in ids if len(_sound(resdir, i)[2]) > 0)))
    return out


def files(resdir):
    out = {}
    for pid, ids in part_sounds(resdir):
        for i in ids:
            name = 'AWS%02X.BIN' % i
            if name in out:
                continue
            ln, lp, smp = _sound(resdir, i)
            data = encode([b - 256 if b > 127 else b for b in smp])
            back = decode(data, len(smp))
            if len(back) != len(smp):
                sys.exit('aw_sbank: sound 0x%02x decodes to the wrong length' % i)
            out[name] = data
    return out


def table(resdir):
    lines = ['; CNV_SLEN: each sound id 0x00..0x91: its length and loop length in bytes (0, 0: no DSP sound)', 'CNV_SLEN:']
    lens = {}
    parts = part_sounds(resdir)
    for pid, ids in parts:
        for i in ids:
            ln, lp, smp = _sound(resdir, i)
            lens[i] = (ln, lp)
    for i in range(0x92):
        ln, lp = lens.get(i, (0, 0))
        lines.append('\tdd %d, %d\t; 0x%02x' % (ln, lp, i))
    lines += ['', '; CNV_SPARTS: per part 0x3E80..0x3E89, a pointer to its list: (id byte, offset dd in the bank) ..., 0FFh',
              'CNV_SPARTS:']
    lines += ['\tdd CNV_SPART_%d' % k for k in range(len(parts))]
    biggest = 0
    for k, (pid, ids) in enumerate(parts):
        lines.append('CNV_SPART_%d:\t; 0x%04X' % (k, pid))
        off = 0
        for i in ids:
            ln, lp = lens[i]
            lines.append('\tdb 0%02Xh\n\tdd %d' % (i, off))
            off += (ln + lp + 3) & ~3
        lines.append('\tdb 0FFh')
        biggest = max(biggest, off)
    lines.append('CNV_SBANK_MAX\tEQU %d' % biggest)
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    for pid, ids in part_sounds(sys.argv[1]):
        print('%04X %2d sounds %7d bytes' % (pid, len(ids), sum(sum(_sound(sys.argv[1], i)[:2]) for i in ids)))
    f = files(sys.argv[1])
    print('%d files, %d bytes coded' % (len(f), sum(len(v) for v in f.values())))
