#!/bin/bash
# build.sh VARIANT [DIR] -- clones rustyworld at the base commit, applies one of this folder's diffs, builds it in release.
# VARIANT: reference (refcksum/replayawr/replaycksum/replaywatch/dumpres, the parts' checks), events (+ the VAR/THR event
# log the LED probes read), vclock (+ the music-timing virtual clock, AW_VMODEL; what probes/musictiming.sh runs).
# DIR defaults to ~/compartilhado/tmp/rustyworld-VARIANT; the tools land in DIR/target/release/.
set -euo pipefail
V="${1:?variant: reference, events or vclock}"
DIR="${2:-$HOME/compartilhado/tmp/rustyworld-$V}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE=2e9a5ab
[ -d "$DIR/.git" ] || git clone -q https://github.com/EdMcBane/rustyworld.git "$DIR"
git -C "$DIR" checkout -q "$BASE"
git -C "$DIR" apply "$HERE/rustyworld-kn7000-$V.diff"
(cd "$DIR" && cargo build --release -q)
ls "$DIR/target/release/" | grep -E '^(refcksum|replayawr|replaycksum|replaywatch|dumpres)$'
