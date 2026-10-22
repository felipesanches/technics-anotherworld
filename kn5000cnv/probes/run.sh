#!/bin/bash
# run.sh OUT FLOPPY.img "SEQ" -- one KN5000 run in the published emulator with FLOPPY in the drive,
# driven by seq.lua. OUT (scratch) gets run.log, snap/, nv/, cfg/. The NVRAM starts from a copy of
# the published folder's.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
E="${EMU:-$HOME/compartilhado/kn7000-emulator}"
O="$(mkdir -p "${1:?usage: run.sh OUT FLOPPY SEQ}" && cd "$1" && pwd)"
F="$(cd "$(dirname "${2:?}")" && pwd)/$(basename "$2")"
rm -rf -- "${O:?}/nv" "${O:?}/cfg" "${O:?}/snap"; mkdir -p "$O/nv" "$O/cfg" "$O/snap"
[ -d "$E/nvram/kn5000" ] && cp -r "$E/nvram/kn5000" "$O/nv/"
cp "$F" "$O/disk.img"     # the drive may write to it; keep the input intact
( cd "$E" && SEQ="${3:?}" DISPLAY="${DISPLAY:-:0}" timeout -k 5 "${TIMEOUT:-600}" ./kn7000 kn5000 -rompath ./roms \
    -pluginspath ./plugins -skip_gameinfo -window -nomaximize -nothrottle -sound none -flop "$O/disk.img" \
    -nvram_directory "$O/nv" -cfg_directory "$O/cfg" -snapshot_directory "$O/snap" -snapname '%i' \
    -autoboot_script "$HERE/seq.lua" ) > "$O/run.log" 2>&1
grep -E "^(CNV|SEQ)" "$O/run.log"
