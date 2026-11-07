# The modified rustyworld reference

The port's checks compare it with [rustyworld](https://github.com/EdMcBane/rustyworld) at commit `2e9a5ab`, with these
diffs applied. Until 2026-11-07 the modified clones lived only in scratch (`tmp/kn7000-aw-reference`,
`tmp/aw-leds2-world`, `tmp/aw-music`). Each diff below is the whole of one clone's changes, new files included.

| diff                               | taken from (2026-11-07)              | adds                                                                                                   | used by                                                                           |
|------------------------------------|--------------------------------------|--------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| `rustyworld-kn7000-reference.diff` | `tmp/kn7000-aw-reference/rustyworld` | `refcksum`, `replayawr`, `replaycksum`, `replaywatch`, `dumpres`; page checksums, `START_PART`         | `probes/awparts.sh`, `probes/cnv/run_inplog.sh` (the parts' and sessions' checks) |
| `rustyworld-kn7000-events.diff`    | `tmp/aw-leds2-world/rustyworld`      | the reference's tools, plus the VAR/THR event log (`AW_EVENTS`, `AW_EVENTS_THREADS`)                   | `probes/ledcheck.py` (replayawr `AW_EVENTS`)                                      |
| `rustyworld-kn7000-vclock.diff`    | `tmp/aw-music/rustyworld`            | the reference's tools, plus the virtual clock (`AW_VMODEL`, `AW_VMARKS`, `AW_VOUT`); not the event log | `probes/musictiming.sh` (its `RW`)                                                |

To rebuild one: `tools/rustyworld/build.sh vclock` (or `reference`, `events`). It makes
`~/compartilhado/tmp/rustyworld-<variant>/`, with the clone in `rustyworld/` (the tools in `rustyworld/target/release/`)
and `run/data/` linked to the MS-DOS release, the layout the probes' defaults expect.

Checked 2026-11-07: `build.sh vclock` from a fresh clone, then `replayawr` on `probes/sessions/2026-11-06-felipe-unit-2.awr`
as `probes/musictiming.sh` runs it, gave the same log, variables and events (sha256 `8e1e996e...`, `a02d7e46...`,
`ac2a1087...`) as the scratch clone's build.
