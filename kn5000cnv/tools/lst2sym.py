#!/usr/bin/env python3
"""lst2sym.py LISTING OUT -- the symbol table of an ASL listing as "NAME HEXVALUE" lines (probes read it)."""
import re
import sys

syms = {}
for line in open(sys.argv[1], encoding='latin-1'):
    for cell in line.split('|'):
        m = re.match(r'\s*\*?([A-Za-z_][\w.]*)\s*:\s*([0-9A-F]+)\s+[A-Z-]?\s*$', cell)
        if m:
            syms[m.group(1)] = int(m.group(2), 16)
with open(sys.argv[2], 'w') as f:
    for k in sorted(syms):
        f.write(f'{k} {syms[k]:X}\n')
print(f'{sys.argv[2]}: {len(syms)} symbols')
