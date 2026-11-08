#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_crumb.sh OUT [SDCARD_DIR] -- awcnv_crumb.lua (the code wheel page's trail of steps across a restart of the
# instrument, and its AWWHLOG.TXT at the next start) on a card with the files of SDCARD_DIR (default build/sdcard: another build's to compare) and an
# AWPREFS.CFG with the code wheel on, through run_perf.sh (-bios $BIOS, default v13). OUT is scratch
# (~/compartilhado/tmp/..., never /tmp).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KN="$(cd "$HERE/../.." && pwd)"
SRC="$(cd "${2:-$KN/build/sdcard}" && pwd)"
O="$(mkdir -p "$1/card" && cd "$1" && pwd)"
cp "$SRC/"* "$O/card/"
printf 'AWP1\x00\x01\x02\x01\x01\x00\x01\x00\x00\x00\x00\x00' > "$O/card/AWPREFS.CFG"
CARDFILES="$O/card" "$HERE/run_perf.sh" "$O" "$HERE/awcnv_crumb.lua" > /dev/null
grep -h "^awtc:" "$O/run.log"; echo "AWWHLOG.TXT:"; cat "$O/AWWHLOG.TXT" 2>/dev/null || echo "(none)"
cd "$O" && rm -rf -- card
