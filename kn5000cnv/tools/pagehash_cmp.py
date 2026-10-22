#!/usr/bin/env python3
"""pagehash_cmp.py A.log B.log -- do two runs show the same pages in the same order? Reads probes/pagehash.lua's
PAGEHASH lines, drops consecutive repeats (a build may show one page twice) and the first page (shown before the
game draws: whatever that memory held), and compares the two sequences over the shorter one's length. Prints the lengths, the number compared and the first difference, if any."""
import sys


def seq(path):
    out = []
    for line in open(path):
        if line.startswith('PAGEHASH '):
            h = line.split()[3]
            if not out or out[-1] != h:
                out.append(h)
    return out[1:]


a, b = seq(sys.argv[1]), seq(sys.argv[2])
n = min(len(a), len(b))
diff = next((i for i in range(n) if a[i] != b[i]), None)
print('distinct pages: %d and %d; compared %d; %s' % (len(a), len(b), n,
      'identical' if diff is None else 'first difference at %d (%s against %s)' % (diff, a[diff], b[diff])))
sys.exit(0 if diff is None else 1)
