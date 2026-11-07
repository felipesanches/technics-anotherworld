#!/bin/bash
# build.sh VARIANT [DIR] -- the modified rustyworld the port's checks compare against (README.md here).
# Clones rustyworld into DIR/rustyworld at the base commit, applies rustyworld-kn7000-VARIANT.diff, builds it in release,
# and makes DIR/run/data: links to the MS-DOS release's MEMLIST.BIN and BANK0* (DATA, default ~/compartilhado/MSDOS),
# the folder the tools run in. VARIANT: reference, events or vclock. DIR defaults to ~/compartilhado/tmp/rustyworld-VARIANT.
# The probes' defaults: awparts.sh RUSTY_RUN=DIR/run (reference); musictiming.sh RW=DIR/rustyworld/target/release/
# replayawr and RWRUN=DIR/run (vclock).
set -euo pipefail
V="${1:?variant: reference, events or vclock}"
DIR="${2:-$HOME/compartilhado/tmp/rustyworld-$V}"
DATA="${DATA:-$HOME/compartilhado/MSDOS}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE=2e9a5ab
mkdir -p "$DIR/run/data"
[ -d "$DIR/rustyworld/.git" ] || git clone -q https://github.com/EdMcBane/rustyworld.git "$DIR/rustyworld"
P="$HERE/rustyworld-kn7000-$V.diff"
if ! git -C "$DIR/rustyworld" apply --reverse --check "$P" 2> /dev/null; then     # not applied yet (a rerun skips it)
    git -C "$DIR/rustyworld" checkout -q "$BASE"
    git -C "$DIR/rustyworld" apply "$P"
fi
(cd "$DIR/rustyworld" && cargo build --release --no-default-features -q --bin refcksum --bin replayawr --bin replaycksum --bin dumpres)
# replaywatch shows the picture: it needs the minifb window (the default features), which builds where a display is.
[ -n "${NO_WATCH:-}" ] || (cd "$DIR/rustyworld" && cargo build --release -q --bin replaywatch)
for f in MEMLIST.BIN BANK01 BANK02 BANK03 BANK04 BANK05 BANK06 BANK07 BANK08 BANK09 BANK0A BANK0B BANK0C BANK0D; do
    ln -sfn "$DATA/$f" "$DIR/run/data/$f"
done
ls "$DIR/rustyworld/target/release/" | grep -E '^(refcksum|replayawr|replaycksum|replaywatch|dumpres)$'
