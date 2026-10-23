#!/usr/bin/env python3
"""make_awdisk.py RESDIR OUTDIR -- the game files for the KN5000 converter and the table that finds them.

RESDIR holds resource-0xNN.bin as kn7000/tools/aw_extract.py writes them from the MS-DOS release
(MEMLIST.BIN + BANK01..0D). Writes:
  OUTDIR/files/AWNN.BIN   each resource the KN5000 VM uses (every part's palette, bytecode and
                          polygons, the shared polygons 0x11, the twelve screens), unchanged
  OUTDIR/awfiles.inc      for aw_cnv.asm: CNV_SIZES (a 32-bit size for every id 0x00..0x91, 0 = not
                          on the disk), CNV_PARTS (palette, bytecode, video1, video2 ids per part,
                          video2 0 = none) and the largest size of each kind, to size the buffers;
                          CNV_SND, the voice that plays each sound resource (tools/aw_sound_map5.py);
                          and, for the DSP sound, CNV_SLEN, CNV_SPARTS and CNV_SBANK_MAX (tools/aw_sbank.py)
  OUTDIR/files/AWSND.BIN  every sound some part plays, as IMA ADPCM (tools/aw_sbank.py), for the DSP sound
The music modules go on the disk too: the sound reads them when the game starts one.
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aw_sbank  # noqa: E402
import aw_sound_map5  # noqa: E402

# (palette, bytecode, video1, video2) per part, 0x3E80..0x3E89 -- the VM's PART_RESOURCE_TABLE
PARTS = [
    (0x14, 0x15, 0x16, 0x00),   # 0 protection
    (0x17, 0x18, 0x19, 0x00),   # 1 intro
    (0x1A, 0x1B, 0x1C, 0x11),   # 2 water
    (0x1D, 0x1E, 0x1F, 0x11),   # 3 jail
    (0x20, 0x21, 0x22, 0x11),   # 4 citadel
    (0x23, 0x24, 0x25, 0x00),   # 5 battlechar
    (0x26, 0x27, 0x28, 0x11),   # 6 arena
    (0x29, 0x2A, 0x2B, 0x11),   # 7 final
    (0x7D, 0x7E, 0x7F, 0x00),   # 8 password
    (0x7D, 0x7E, 0x7F, 0x00),   # 9 password (same)
]
# the screens LOAD can name (aw_hle.cpp screen_resource_indexes[])
SCREENS = [0x12, 0x13, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x53, 0x90, 0x91]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    resdir, out = sys.argv[1], sys.argv[2]
    files = os.path.join(out, 'files')
    os.makedirs(files, exist_ok=True)
    rows = [line.split('\t') for line in open(os.path.join(resdir, 'memlist.tsv')).read().split('\n')[1:] if line]
    types = [r[1] for r in rows]
    music = [i for i, t in enumerate(types) if t == 'music']
    ids = sorted({r for p in PARTS for r in p if r} | set(SCREENS) | set(music))
    sizes = {}
    for r in ids:
        src = os.path.join(resdir, f'resource-0x{r:02x}.bin')
        sizes[r] = os.path.getsize(src)
        shutil.copyfile(src, os.path.join(files, f'AW{r:02X}.BIN'))
    for r in SCREENS:
        if sizes[r] != 32000:
            sys.exit(f'make_awdisk: screen 0x{r:02x} is {sizes[r]} bytes, not 32000')
    most = {k: max(sizes[p[i]] for p in PARTS) for i, k in enumerate(('PALETTE', 'BYTECODE', 'VIDEO1'))}
    with open(os.path.join(out, 'awfiles.inc'), 'w') as f:
        f.write('; awfiles.inc -- written by kn5000cnv/tools/make_awdisk.py; do not edit\n\n')
        for k, v in most.items():
            f.write(f'CNV_MAX_{k}\tEQU {v}\n')
        f.write(f'CNV_SIZE_VIDEO2\tEQU {sizes[0x11]}\n')
        f.write(f'CNV_MAX_MUSIC\tEQU {max(sizes[m] for m in music)}\n\n')
        f.write('; CNV_SIZES: the byte count of AWnn.BIN for each resource id 0x00..0x91 (0 = not on the disk)\n')
        f.write('CNV_SIZES:\n')
        for r in range(0x92):
            f.write(f'\tdd {sizes.get(r, 0)}\t; 0x{r:02x}\n')
        f.write('\n; CNV_PARTS: palette, bytecode, video1, video2 ids for parts 0x3E80..0x3E89 (video2 0 = none)\n')
        f.write('CNV_PARTS:\n')
        for p in PARTS:
            f.write('\tdb ' + ', '.join(f'0{r:02X}h' for r in p) + '\n')
        snd, _ = aw_sound_map5.table(types, lambda i: open(os.path.join(resdir, f'resource-0x{i:02x}.bin'), 'rb').read(4))
        f.write('\n; CNV_SND: the voice of each sound resource 0x00..0x91, 8 bytes each (tools/aw_sound_map5.py)\n')
        f.write('CNV_SND:\n')
        for i in range(0, len(snd), 8):
            f.write('\tdb ' + ', '.join(f'0{b:02X}h' for b in snd[i:i + 8]) + f'\t; 0x{i // 8:02x}\n')
        f.write('\n')
        f.write(aw_sbank.table(resdir))
    coded = aw_sbank.files(resdir)
    for name, data in coded.items():
        with open(os.path.join(files, name), 'wb') as g:
            g.write(data)
    total = sum(sizes.values())
    print(f'{out}: {len(ids)} files, {total} bytes, and {", ".join(coded)}, {sum(len(v) for v in coded.values())} '
          f'bytes coded; largest palette {most["PALETTE"]}, '
          f'bytecode {most["BYTECODE"]}, video1 {most["VIDEO1"]}, video2 {sizes[0x11]}')


if __name__ == '__main__':
    main()
