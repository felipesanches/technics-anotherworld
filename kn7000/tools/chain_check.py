#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# chain_check.py CHAIN_S MENU_INC TRAMP_SYMS -- does src/chain.s still use the program menu's own addresses? Its copies
# of STAGE, T_CODE, T_DATA and the TD_* offsets (CH_*) must equal kn7menu/menu.inc's, and T_CODE the trampoline's
# T_LAUNCH (tramp_syms.inc, from its map): chain.s starts the menu through that trampoline, which runs at T_CODE and
# reads its data at T_DATA. Prints "chain_check: ok" or what differs, and fails the build then.
import re
import sys


def equs(path):
    out = {}
    for line in open(path):
        m = re.match(r"\s*\.equ\s+(\w+),\s*(0x[0-9A-Fa-f]+|\d+)", line)
        if m:
            out[m.group(1)] = int(m.group(2), 0)
    return out


chain, menu, syms = equs(sys.argv[1]), equs(sys.argv[2]), equs(sys.argv[3])
pairs = [("CH_STAGE", "STAGE"), ("CH_T_CODE", "T_CODE"), ("CH_T_DATA", "T_DATA"), ("CH_TD_RETSP", "TD_RETSP"),
         ("CH_TD_SIZE", "TD_SIZE"), ("CH_TD_MS", "TD_MS"), ("CH_TD_FG", "TD_FG"), ("CH_TD_BG", "TD_BG"),
         ("CH_TD_MSG", "TD_MSG"), ("CH_TD_LEN", "TD_LEN")]
bad = [f"{a} {chain.get(a)} != menu.inc {b} {menu.get(b)}" for a, b in pairs if chain.get(a) != menu.get(b)]
if chain.get("CH_T_CODE") != syms.get("T_LAUNCH"):
    bad.append(f"CH_T_CODE {chain.get('CH_T_CODE')} != tramp_syms.inc T_LAUNCH {syms.get('T_LAUNCH')}")
if bad:
    print("chain_check: DIFFERENT: " + "; ".join(bad))
    sys.exit(1)
print("chain_check: ok")
