# The modified rustyworld reference

The port's checks compare it with [rustyworld](https://github.com/EdMcBane/rustyworld) at commit `2e9a5ab`, with these
diffs applied. Until 2026-11-07 the modified clones lived only in scratch (`tmp/kn7000-aw-reference`,
`tmp/aw-leds2-world`, `tmp/aw-music`). Each diff below is the whole of one clone's changes, new files included.

| diff                               | taken from (2026-11-07)              | adds                                                                                                   | used by                                                                           |
|------------------------------------|--------------------------------------|--------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| `rustyworld-kn7000-reference.diff` | `tmp/kn7000-aw-reference/rustyworld` | `refcksum`, `replayawr`, `replaycksum`, `replaywatch`, `dumpres`; page checksums, `START_PART`         | `probes/awparts.sh`, `probes/cnv/run_inplog.sh` (the parts' and sessions' checks) |
| `rustyworld-kn7000-events.diff`    | `tmp/aw-leds2-world/rustyworld`      | the reference's tools, plus the VAR/THR event log (`AW_EVENTS`, `AW_EVENTS_THREADS`)                   | `probes/ledcheck.py` (replayawr `AW_EVENTS`)                                      |
| `rustyworld-kn7000-vclock.diff`    | `tmp/aw-music/rustyworld`            | the reference's tools, plus the virtual clock (`AW_VMODEL`, `AW_VMARKS`, `AW_VOUT`); not the event log | `probes/musictiming.sh` (its `RW`)                                                |

To rebuild one: `tools/rustyworld/build.sh vclock` (or `reference`, `events`). The tools land in
`~/compartilhado/tmp/rustyworld-<variant>/target/release/`; point the probes' `RW` or `../rustyworld` at them.
