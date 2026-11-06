#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_wheel.sh OUT -- the code wheel help page in MAME (awcnv_wheel.lua) on a card with build/sdcard/ and an AWPREFS.CFG
# with the code wheel on, through run_perf.sh (-bios $BIOS, default v13: program 893); then codewheel_check.py: every
# picture taken from the LCD against codewheel_render.py's render(). OUT/run.log, OUT/snap/*.png, OUT/pics/ (the
# pictures). OUT is scratch (~/compartilhado/tmp/..., never /tmp). Run `make sdcard` first.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KN="$(cd "$HERE/../.." && pwd)"
O="$(mkdir -p "$1/pics" "$1/card" && cd "$1" && pwd)"
cp "$KN/build/sdcard/"* "$O/card/"
# AWPREFS.CFG: "AWP1", 384x240, ambilight on, scatter long, keybed sound on, LED effects on, (9), code wheel on
printf 'AWP1\x00\x01\x02\x01\x01\x00\x01\x00\x00\x00\x00\x00' > "$O/card/AWPREFS.CFG"
AWWL_OUT="$O/pics" CARDFILES="$O/card" "$HERE/run_perf.sh" "$O" "$HERE/awcnv_wheel.lua" > /dev/null
grep -h "^awwl:" "$O/run.log"
python3 -I "$KN/probes/cnv/codewheel_check.py" "$O/pics" "$KN/build/wheel/wheel.bin"
cd "$O" && rm -rf -- card
