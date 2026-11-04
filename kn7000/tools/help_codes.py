#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# help_codes.py HELP.s RESOURCE-0x7e.bin -- is every access code the HELP screen lists (src/help.s, the strings
# hs_cN) one the game's code screen accepts? The code screen (part 0x3E88, its bytecode resource 0x7E) checks each
# code as four `if v1e..v21 != n jmp` (the letter n - 10, A = 0), then sets var 0x00 (the checkpoint) and loads the
# part (research-scratch kn7000-aw-reference/fingerprints/codetab.py). The build stops on a code it does not accept
# (XRJT was listed for XJRT until 2026-11-03), and when hs_c1, hs_c2, ... are not in the order the game reaches them
# (their checkpoints rising). Which scene each code starts: research-scratch kn7000-aw-reference/codes/codeshots.sh.
#   python3 -I tools/help_codes.py src/help.s build/res/resource-0x7e.bin
import re
import sys


def accepted(d):
    """{code: (checkpoint, part)} from the code screen's bytecode."""
    u16 = lambda p: d[p] << 8 | d[p + 1]
    out = {}
    pc = 0
    while pc < len(d) - 40:
        if all(d[pc + 6 * k] == 0x0A and d[pc + 6 * k + 1] == 0x01 and d[pc + 6 * k + 2] == 0x1E + k for k in range(4)) \
                and d[pc + 24] == 0x00 and d[pc + 25] == 0x00 and d[pc + 28] == 0x19:
            out["".join(chr(ord("A") + d[pc + 6 * k + 3] - 10) for k in range(4))] = (u16(pc + 26), u16(pc + 29))
            pc += 31
        else:
            pc += 1
    return out


def main():
    listed = re.findall(r'^(hs_c\d+):\s*\.asciz\s+"([^"]*)"', open(sys.argv[1]).read(), re.M)
    ok = accepted(open(sys.argv[2], "rb").read())
    if len(ok) < 20:
        sys.exit(f"help_codes: only {len(ok)} codes found in {sys.argv[2]}: not the code screen's bytecode?")
    bad = [f"{name} {code!r}" for name, code in listed if code not in ok]
    if bad:
        sys.exit(f"help_codes: the code screen does not accept: {', '.join(bad)}")
    listed.sort(key=lambda t: int(t[0][4:]))
    cps = [ok[code][0] for _, code in listed]
    if cps != sorted(cps):
        sys.exit("help_codes: not in the game's order: " + ", ".join(f"{c} {cp}" for (_, c), cp in zip(listed, cps)))
    print(f"help_codes: the {len(listed)} codes the HELP screen lists are among the {len(ok)} the code screen accepts, "
          f"in its order (checkpoints {' '.join(map(str, cps))})")


if __name__ == "__main__":
    main()
