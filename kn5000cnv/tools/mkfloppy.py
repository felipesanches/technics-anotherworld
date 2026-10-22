#!/usr/bin/env python3
"""mkfloppy.py OUT.img LABEL FILE [FILE ...] -- a DOS FAT12 1.44 MB floppy image holding FILEs.

The KN5000 reads 3.5" HD diskettes formatted by DOS. Each file goes in the root directory under its
8.3 name (upper-cased), stored in consecutive clusters, in the order given. Timestamps are zero and
the volume serial is fixed, so the same inputs always give the same image. No dependencies.
"""
import os
import sys

SECTOR = 512
SECTORS = 2880           # 80 tracks x 2 heads x 18 sectors
FAT_SECTORS = 9
ROOT_ENTRIES = 224
ROOT_SECTORS = ROOT_ENTRIES * 32 // SECTOR
DATA_START = 1 + 2 * FAT_SECTORS + ROOT_SECTORS          # first sector of cluster 2
CLUSTERS = SECTORS - DATA_START


def name83(path):
    base = os.path.basename(path).upper()
    stem, _, ext = base.partition('.')
    if not stem or len(stem) > 8 or len(ext) > 3 or '.' in ext:
        sys.exit(f'mkfloppy: {base} is not an 8.3 name')
    return stem.ljust(8).encode('ascii') + ext.ljust(3).encode('ascii')


def boot_sector(label):
    b = bytearray(SECTOR)
    b[0:3] = b'\xeb\x3c\x90'
    b[3:11] = b'MSDOS5.0'
    b[11:13] = SECTOR.to_bytes(2, 'little')
    b[13] = 1                                            # sectors per cluster
    b[14:16] = (1).to_bytes(2, 'little')                 # reserved sectors
    b[16] = 2                                            # FATs
    b[17:19] = ROOT_ENTRIES.to_bytes(2, 'little')
    b[19:21] = SECTORS.to_bytes(2, 'little')
    b[21] = 0xF0                                         # media: 3.5" 1.44 MB
    b[22:24] = FAT_SECTORS.to_bytes(2, 'little')
    b[24:26] = (18).to_bytes(2, 'little')                # sectors per track
    b[26:28] = (2).to_bytes(2, 'little')                 # heads
    b[36] = 0x00                                         # drive number
    b[38] = 0x29                                         # extended boot signature
    b[39:43] = (0x4B4E3530).to_bytes(4, 'little')        # fixed volume serial
    b[43:54] = label.upper().ljust(11)[:11].encode('ascii')
    b[54:62] = b'FAT12   '
    b[510:512] = b'\x55\xaa'
    return b


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    out, label, files = sys.argv[1], sys.argv[2], sys.argv[3:]
    if len(files) > ROOT_ENTRIES - 1:
        sys.exit('mkfloppy: too many files for the root directory')
    img = bytearray(SECTORS * SECTOR)
    img[0:SECTOR] = boot_sector(label)
    fat = [0] * (CLUSTERS + 2)
    fat[0], fat[1] = 0xFF0, 0xFFF
    root = bytearray(ROOT_SECTORS * SECTOR)
    vol = label.upper().ljust(11)[:11].encode('ascii')
    root[0:11] = vol
    root[11] = 0x08                                      # volume label entry
    nxt = 2
    for i, path in enumerate(files, start=1):
        data = open(path, 'rb').read()
        n = (len(data) + SECTOR - 1) // SECTOR
        if nxt + n > CLUSTERS + 2:
            sys.exit(f'mkfloppy: {path} does not fit ({len(data)} bytes)')
        first = nxt if n else 0
        for k in range(n):
            fat[nxt + k] = nxt + k + 1 if k < n - 1 else 0xFFF
        off = (DATA_START + (nxt - 2)) * SECTOR
        img[off:off + len(data)] = data
        nxt += n
        e = 32 * i
        root[e:e + 11] = name83(path)
        root[e + 11] = 0x20                              # archive
        root[e + 26:e + 28] = first.to_bytes(2, 'little')
        root[e + 28:e + 32] = len(data).to_bytes(4, 'little')
    packed = bytearray(FAT_SECTORS * SECTOR)
    for c in range(0, len(fat) - 1, 2):
        a, b = fat[c], fat[c + 1] if c + 1 < len(fat) else 0
        packed[c * 3 // 2:c * 3 // 2 + 3] = bytes((a & 0xFF, (a >> 8) | ((b & 0xF) << 4), b >> 4))
    for f in range(2):
        s = (1 + f * FAT_SECTORS) * SECTOR
        img[s:s + len(packed)] = packed
    r = (1 + 2 * FAT_SECTORS) * SECTOR
    img[r:r + len(root)] = root
    open(out, 'wb').write(img)
    used = (nxt - 2) * SECTOR
    print(f'{out}: {len(files)} file(s), {used} of {CLUSTERS * SECTOR} data bytes used')


if __name__ == '__main__':
    main()
