#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_inplog.sh OUT record                 -- a scripted session in MAME, its input log and its pages
# run_inplog.sh OUT replay SESSION.awr     -- that session (or one from the instrument) replayed, its pages
# run_inplog.sh OUT compare A B            -- two runs' pages compared frame by frame (A, B: run folders)
# The input log (src/inplog.s; README-CNV.md, "Replaying a session") with awcnv_inplog.lua. Each run boots with the
# owner's loader floppy and a copy of the real KN7000's card with build/sdcard/ added (run_cnv_tests.sh's way), -bios
# $BIOS (default v13, program 893, the owner's). A run leaves in OUT: run.log, pages.bin/.idx (the front page at every
# frame), vars.bin (the 256 VM variables at every frame, int16 LE), pages.log (their CRC-32s, cksum_pages.py), AWIN*.BIN (the game's log, from the card) and session.awr
# (tools/aw_inplog.py's text of it). A replay also checks its own log against the one replayed: the I, P and G
# records must be the same (input.txt); R records are not, as the replay sets the requested part itself, past the
# game's ReadInput, which is what logs them (a G record is logged where the start is made, so the replay's has it). OUT is scratch (~/compartilhado/tmp/..., never /tmp). Run `make sdcard`
# first. Env: EMU (default ~/compartilhado/kn7000-emulator), BIOS, CARDFILES (default build/sdcard), DISPLAY.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KN="$(cd "$HERE/../.." && pwd)"
EMU="${EMU:-$HOME/compartilhado/kn7000-emulator}"
DISASM_REPO="${DISASM_REPO:-$KN/../../technics-roms-disasm/kn7000}"
FLOPPY="$DISASM_REPO/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img"
CARDFILES="${CARDFILES:-$KN/build/sdcard}"
BIOS="${BIOS:-v13}"
O="$(mkdir -p "$1" && cd "$1" && pwd)"; MODE="$2"

if [ "$MODE" = compare ]; then
  python3 -I "$KN/probes/compare_frames.py" "$3/pages.log" "$4/pages.log"
  exit $?
fi

SESSION=""
[ "$MODE" = replay ] && SESSION="$(realpath "$3")"
mkdir -p "$O/snap"
cp "$EMU/sdcard_from_real_kn7000.img" "$O/sd.img"; chmod u+w "$O/sd.img"
args=()
for f in "$CARDFILES"/*; do args+=("$(basename "$f")" "$f"); done
python3 -I "$DISASM_REPO/tools/sd_addfile.py" "$O/sd.img" "${args[@]}" > "$O/card.log" || { cat "$O/card.log"; exit 1; }
cp "$FLOPPY" "$O/floppy.img"; chmod u+w "$O/floppy.img"
{ echo "KN7APP.BIN $(sha1sum < "$CARDFILES/KN7APP.BIN" | cut -c1-40), emulator $(md5sum < "$EMU/kn7000" | cut -c1-32), bios $BIOS"
  [ -n "$SESSION" ] && echo "replaying $SESSION $(sha1sum < "$SESSION" | cut -c1-40)"; } > "$O/versions.txt"
( cd "$EMU" && AWCK_BIN="$O/pages.bin" AWCK_IDX="$O/pages.idx" AWCK_VARS="$O/vars.bin" AW_MAP="$KN/build/kn7app.map" AW_REPLAY="$SESSION" \
  DISPLAY="${DISPLAY:-:0}" timeout -k 10 "${TIMEOUT:-5400}" ./kn7000 kn7000 -bios "$BIOS" -rompath ./roms -pluginspath ./plugins \
  -skip_gameinfo -window -nothrottle -harddisk "$O/sd.img" -flop "$O/floppy.img" -nvram_directory "$O/nv" \
  -cfg_directory "$O/cfg" -snapshot_directory "$O/snap" -autoboot_script "$HERE/awcnv_inplog.lua" ) > "$O/run.log" 2>&1
grep "awcnv_inplog:" "$O/run.log"
python3 -I "$KN/probes/cksum_pages.py" "$O/pages.bin" "$O/pages.idx" "$O/pages.log" > /dev/null
echo "pages: $(wc -l < "$O/pages.log") frames"
for n in $(seq -w 0 99); do
  python3 -I "$DISASM_REPO/tools/cnv_romdump/fatls.py" "$O/sd.img" "C:\\AWIN$n.BIN" "$O/AWIN$n.BIN" > /dev/null 2>&1 || { rm -f -- "$O/AWIN$n.BIN"; break; }
done
python3 -I "$KN/tools/aw_inplog.py" "$O" -o "$O/session.awr"
if [ -n "$SESSION" ]; then
  # the replay's own log: its inputs and parts as the replayed one's (up to where the replay quit)
  last=$(awk '$1=="E"{print $2}' "$O/session.awr")
  grep -E '^[IPG] ' "$SESSION" | awk -v L="$last" '$2 < L' > "$O/input.want"
  grep -E '^[IPG] ' "$O/session.awr" | awk -v L="$last" '$2 < L' > "$O/input.got"
  if cmp -s "$O/input.want" "$O/input.got"; then echo "input: the replay's I, P and G records are the replayed ones ($(wc -l < "$O/input.got") records)" | tee "$O/input.txt"
  else echo "input: DIFFERENT (diff $O/input.want $O/input.got)" | tee "$O/input.txt"; fi
fi
rm -f -- "$O/sd.img" "$O/floppy.img"
