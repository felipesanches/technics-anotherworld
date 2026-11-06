#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# musictiming.sh OUT [MAME_NAME=TIMELOG ...] -- the intro's music against its picture (probes/MUSIC-TIMING.md):
#   1. rustyworld with the virtual clock (probes/music-timing/rustyworld-vclock.diff) plays the intro with no input
#      once per engine's row period (the picture takes no CPU time: what rawgl, Sanglard and rustyworld do on a PC);
#      then again with the picture uniformly 5-20% slower than it asks (a 21-24 ms slice), the music unchanged;
#   2. rustyworld replays the owner's unit sessions of 2026-11-06 (their marks where the unit had them) for var 0xFF
#      at every tick, and logs the PLAY_MUSIC calls;
#   3. probes/musictiming.py report puts them, and the MAME runs' AW_TIMELOGs given, in OUT/summary.md.
# Env: RW (replayawr built with rustyworld-vclock.diff; default ~/compartilhado/tmp/aw-music/rustyworld/target/release/
# replayawr), RWRUN (a folder with data/MEMLIST.BIN + data/BANK0*: the MS-DOS release; default
# ~/compartilhado/tmp/kn7000-aw-reference/run), DATA (the same files for musictiming.py; default ~/compartilhado/MSDOS).
# OUT is scratch (~/compartilhado/tmp/...).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RW="${RW:-$HOME/compartilhado/tmp/aw-music/rustyworld/target/release/replayawr}"
RWRUN="${RWRUN:-$HOME/compartilhado/tmp/kn7000-aw-reference/run}"
DATA="${DATA:-$HOME/compartilhado/MSDOS}"
O="$(mkdir -p "$1" && cd "$1" && pwd)"; shift
MARKS="$(python3 -I "$HERE/musictiming.py" marks "$DATA")"
printf '# the splash and the intro, no input (musictiming.sh)\nP 0 0x3E80\nE 3400 0\n' > "$O/intro-noinput.awr"
args=()
for m in amiga_pal dos rawgl sanglard ours ours_pal; do
  ( cd "$RWRUN" && AW_VMODEL=$m AW_VMARKS="$MARKS" AW_VOUT="$O/sim-$m.txt" "$RW" "$O/intro-noinput.awr" "$O/sim-$m.log" ) \
    > "$O/sim-$m.err" 2>&1
  args+=(--sim "sim $m=$O/sim-$m.txt")
done
# the same, the picture uniformly slower: a slice of 21 .. 24 ms against the music's own tempo (AW_VSLICE)
for m in amiga_pal ours; do
  for sl in 21.0 21.5 22.0 22.5 23.0 23.5 24.0; do
    ( cd "$RWRUN" && AW_VSLICE=$sl AW_VMODEL=$m AW_VMARKS="$MARKS" AW_VOUT="$O/slow-$m-$sl.txt" "$RW" "$O/intro-noinput.awr" \
      "$O/slow-$m-$sl.log" ) > "$O/slow-$m-$sl.err" 2>&1
    args+=(--sim "sim $m slice $sl ms=$O/slow-$m-$sl.txt")
  done
done
for n in 2026-11-06-felipe-unit-2 2026-11-06-felipe-unit-1; do
  ( cd "$RWRUN" && AW_VMODEL=ours AW_VMARKS="" AW_VOUT="$O/$n.ev" REF_VARS="$O/$n.vars" "$RW" "$HERE/sessions/$n.awr" \
    "$O/$n.log" ) > "$O/$n.err" 2>&1
done
for k in 2 1; do
  n=2026-11-06-felipe-unit-$k
  args+=(--unit "unit 2026-11-06-$k=$HERE/sessions/$n.awr:$O/$n.vars:$O/$n.ev")
done
for mm in "$@"; do args+=(--mame "$mm"); done
python3 -I "$HERE/musictiming.py" report "$DATA" "${args[@]}" > "$O/summary.md"
echo "musictiming: $O/summary.md"
grep '^P ' "$O/2026-11-06-felipe-unit-2.ev" | sed 's/^/unit-2 PLAY_MUSIC (tick res delay pos): /'
