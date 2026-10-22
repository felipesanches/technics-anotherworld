#!/usr/bin/env python3
"""find_fileio.py ROMDIR -- where the four FileIO routines a converter calls sit in each KN5000 program.

The addresses come from v10's symbols (technics-roms-disasm symbols/maincpu_v10_symbols_reference.txt).
Each routine's opening instructions in v10, with the bytes of absolute RAM addresses as wildcards
('..'), are searched for in every kn5000_v*_program.rom (loaded at 0xE00000); a routine must match
exactly once. Prints one line per version with the four addresses.
"""
import glob
import os
import re
import sys

# v10's opening bytes; '..' = an absolute RAM address that moves between versions
SIGS = {
    'open':  'bf8037 3e e98e e88a 45 ...... 00 bf0434 314000',   # lda xsp; push xiz; ...; ld xiy,path
    'read':  'bfee37 3e bf1260 bf04020000 e8a8 bf0660 e1 .... 20', # ...; ld xwa,(handle)
    'seek':  'e1 .... 22 eae2 6616 29 38 3a 1d',                 # ld xde,(handle); or; jr z; pushes; call
    'close': 'e1 .... 20 e8e0 660d 38 1d',                       # ld xwa,(handle); or; jr z; push; call
}
BASE = 0xE00000


def pattern(sig):
    hexs = sig.replace(' ', '')
    return re.compile(b''.join(b'.' if hexs[i:i + 2] == '..' else re.escape(bytes.fromhex(hexs[i:i + 2]))
                               for i in range(0, len(hexs), 2)), re.S)

romdir = sys.argv[1]
for path in sorted(glob.glob(os.path.join(romdir, 'kn5000_v*_program.rom')), key=lambda p: int(re.search(r'_v(\d+)_', p).group(1))):
    rom = open(path, 'rb').read()
    ver = re.search(r'_v(\d+)_', path).group(1)
    out = []
    for k in ('open', 'read', 'seek', 'close'):
        hits = [m.start() + BASE for m in pattern(SIGS[k]).finditer(rom)]
        out.append(f'{k}={hits[0]:06X}' if len(hits) == 1 else f'{k}=?({len(hits)} hits)')
    print(f'v{ver}: ' + ' '.join(out))
