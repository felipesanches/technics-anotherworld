#!/bin/bash
# run_dsnd.sh OUT FLOPPY.img [SEQ] -- one KN5000 run for the DSP sound: the IC311 build of the emulator
# (BIN, default ~/compartilhado/kn5000dsp_build/kn7000: ARCHOPTS=-DKN5000_ENABLE_DSP1=1), the insert switched on
# (kn7000_mame notes/kn5000-dsp-mixer/dspcfg.lua) and its presentation words counted as decoded
# (UPD6383_PRESENT_ASIS, without which every frame of the mixer is discarded), the floppy started from STYLE CONVERT (seq.lua), dsnd.lua
# reporting the streamer. OUT (scratch) gets run.log (DSND/CNV/SEQ lines), out.wav (-wavwrite: three channels,
# the last two the speakers), nv/, cfg/, snap/.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
E="${EMU:-$HOME/compartilhado/kn7000-emulator}"
BIN="${BIN:-$HOME/compartilhado/kn5000dsp_build/kn7000}"
DSPCFG_LUA="${DSPCFG_LUA:-$HOME/compartilhado/kn7000_mame/notes/kn5000-dsp-mixer/dspcfg.lua}"
O="$(mkdir -p "${1:?usage: run_dsnd.sh OUT FLOPPY [SEQ]}" && cd "$1" && pwd)"
F="$(cd "$(dirname "${2:?}")" && pwd)/$(basename "$2")"
rm -rf -- "${O:?}/nv" "${O:?}/cfg" "${O:?}/snap"; mkdir -p "$O/nv" "$O/cfg" "$O/snap"
[ -d "$E/nvram/kn5000" ] && cp -r "$E/nvram/kn5000" "$O/nv/"
cp "$F" "$O/disk.img"
( cd "$E" && SEQ="${3:-25:DISK;28:L3;33:R4;45:snap;70:quit}" SUBSYM="$HERE/../build/awsub.sym" MAINSYM="$HERE/../build/aw_cnv.sym" DSPCFG_VALUE=1 UPD6383_PRESENT_ASIS=1 \
    PROBES="$HERE/seq.lua $DSPCFG_LUA $HERE/dsnd.lua" DISPLAY="${DISPLAY:-:0}" timeout -k 5 "${TIMEOUT:-900}" \
    "$BIN" kn5000 -rompath ./roms -pluginspath ./plugins -skip_gameinfo -window -nomaximize -nothrottle \
    -wavwrite "$O/out.wav" -flop "$O/disk.img" -nvram_directory "$O/nv" -cfg_directory "$O/cfg" \
    -snapshot_directory "$O/snap" -snapname '%i' -autoboot_script "$HERE/multi.lua" ) > "$O/run.log" 2>&1
grep -E "^(CNV|SEQ|DSND|DSPCFG)" "$O/run.log"
