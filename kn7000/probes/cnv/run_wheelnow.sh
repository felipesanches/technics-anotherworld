#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_wheelnow.sh OUT -- the code wheel setting applied at once (awcnv_wheelnow.lua), then the session's input log
# replayed (run_inplog.sh replay): the replay must give the same I, P and G records, so each restart the setting made
# is reproduced. OUT/rec: the scripted run (run.log, snap/*.png, AWIN*.BIN, session.awr); OUT/replay: the replay.
# OUT is scratch (~/compartilhado/tmp/..., never /tmp). Run `make sdcard` first. Env: EMU, BIOS (default v13), DISPLAY.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KN="$(cd "$HERE/../.." && pwd)"
EMU="${EMU:-$HOME/compartilhado/kn7000-emulator}"
DISASM_REPO="${DISASM_REPO:-$KN/../../technics-roms-disasm/kn7000}"
FLOPPY="$DISASM_REPO/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img"
BIOS="${BIOS:-v13}"
O="$(mkdir -p "$1/rec" && cd "$1" && pwd)"
R="$O/rec"
mkdir -p "$R/snap"
cp "$EMU/sdcard_from_real_kn7000.img" "$R/sd.img"; chmod u+w "$R/sd.img"
args=()
for f in "$KN/build/sdcard"/*; do args+=("$(basename "$f")" "$f"); done
python3 -I "$DISASM_REPO/tools/sd_addfile.py" "$R/sd.img" "${args[@]}" > "$R/card.log" || { cat "$R/card.log"; exit 1; }
cp "$FLOPPY" "$R/floppy.img"; chmod u+w "$R/floppy.img"
echo "run_wheelnow: KN7APP.BIN $(sha1sum < "$KN/build/sdcard/KN7APP.BIN" | cut -c1-16), bios $BIOS, emulator md5 $(md5sum < "$EMU/kn7000" | cut -c1-8)" | tee "$R/run.log"
( cd "$EMU" && AW_MAP="$KN/build/kn7app.map" DISPLAY="${DISPLAY:-:0}" timeout -k 10 1800 ./kn7000 kn7000 -bios "$BIOS" \
  -rompath ./roms -pluginspath ./plugins -skip_gameinfo -window -nothrottle -harddisk "$R/sd.img" \
  -flop "$R/floppy.img" -nvram_directory "$R/nv" -cfg_directory "$R/cfg" -snapshot_directory "$R/snap" \
  -autoboot_script "$HERE/awcnv_wheelnow.lua" ) >> "$R/run.log" 2>&1
grep -h "^awwn:" "$R/run.log"
for n in $(seq -w 0 99); do
  python3 -I "$DISASM_REPO/tools/cnv_romdump/fatls.py" "$R/sd.img" "C:\\AWIN$n.BIN" "$R/AWIN$n.BIN" > /dev/null 2>&1 || { rm -f -- "$R/AWIN$n.BIN"; break; }
done
rm -f -- "$R/sd.img" "$R/floppy.img"
python3 -I "$KN/tools/aw_inplog.py" "$R" -o "$R/session.awr" || exit 1
grep '^G ' "$R/session.awr"
"$HERE/run_inplog.sh" "$O/replay" replay "$R/session.awr" | grep -E '^(input|awcnv_inplog: replay)'
