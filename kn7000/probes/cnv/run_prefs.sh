#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_prefs.sh OUT -- the loading screen and the settings (awcnv_prefs.lua), in two runs through run_perf.sh: the
# first on the card without AWPREFS.CFG (the loading screen; every setting changed on the help screen's fourth page;
# the file written), the second on the card with the file the first one wrote (the settings read and in effect from
# the start). OUT/p1, OUT/p2: each run's run.log, screen dumps (*.bin: 640 x 240 32-bit pixels; probes/screen2png.py)
# and AWPREFS.CFG. OUT is scratch (~/compartilhado/tmp/..., never /tmp).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KN="$(cd "$HERE/../.." && pwd)"
O="$(mkdir -p "$1" && cd "$1" && pwd)"
AWPR_PHASE=1 AWPR_OUT="$O/p1" "$HERE/run_perf.sh" "$O/p1" "$HERE/awcnv_prefs.lua" > /dev/null
grep -h "^awpr:" "$O/p1/run.log"
if [ ! -f "$O/p1/AWPREFS.CFG" ]; then echo "run_prefs: no AWPREFS.CFG on the card after the first run"; exit 1; fi
od -A d -t x1 "$O/p1/AWPREFS.CFG"
mkdir -p "$O/card2"
cp "$KN/build/sdcard/"* "$O/card2/"
cp "$O/p1/AWPREFS.CFG" "$O/card2/"
AWPR_PHASE=2 AWPR_OUT="$O/p2" CARDFILES="$O/card2" "$HERE/run_perf.sh" "$O/p2" "$HERE/awcnv_prefs.lua" > /dev/null
grep -h "^awpr:" "$O/p2/run.log"
rm -rf -- "${O:?}/card2"
