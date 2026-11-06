# The intro's music against its picture

Felipe, playing `KN7APP.BIN` `7c2d2c06` on the unit (2026-11-06): the music seems to play slightly fast; in the
intro it reaches its "wait loop" a few seconds before the countdown to the experiment does, where it used to be in
step with the countdown's end. This note says what the intro's bytecode does there, how each engine times its
music and its frames, what the unit and MAME measured, and what changed.

Every measured number below is in `music-timing/summary.md`, which `musictiming.sh` makes, but the replay check's
(`compare_frames.py`, `varsdiff.py`); the commands are at the end.

## What the bytecode does around the countdown

The intro (part 0x3E81) starts its module (resource 0x07) at once, `PLAY_MUSIC 0x0007, delay 0x3D54, order 0`,
and retimes it to delay 0x3E1C in the biometric scene, some 57 s in. The module plays 1024 rows; 24 of its events
are sync marks (period 0xFFFD), which the player writes to var 0xF4 (`musictiming.py marks`). The bytecode reads
them in few places (the MS-DOS release's intro, `another-world-source-reconstruction` `src/levels/dos_1992/INTRO.asm`):

| where                                              | reads                 | does                                                                |
|----------------------------------------------------|-----------------------|---------------------------------------------------------------------|
| the lab door closing (`LAB_DOOR_LEAVES_SHUT_LOOP`) | mark 0x10 (row 415)   | ends the scene early                                                |
| RESULT, "Practical verification Y/N ?"             | mark > 0x20 (row 831) | ends the texts early, starts the countdown                          |
| countdown "20", "19"                               | marks 0x22, 0x23      | each digit until its mark, or 10 frames at var 0xFF = 5 (1 s)       |
| "18", "17"                                         | -                     | 10 frames, then the soda                                            |
| the soda's last pose                               | mark 0x2B (row 895)   | held until the mark, or 18 frames at var 0xFF = 9 (3.2 s)           |
| countdown "5" to "1"                               | marks 0x2C to 0x30    | each digit until its mark, or 11 frames (1.1 s)                     |
| "0"                                                | mark 0x31 (row 948)   | waits up to 39 frames at var 0xFF = 4 (3.1 s); 0x31 stops the music |

So the picture never waits for the music: it can only leave a scene early when the music is ahead, and every wait
has a frame-count timeout. From 0x21 to 0x31 the module has a mark every 8 rows (1.06 s at 0x3D54), one per second
of the countdown. Only when the music arrives at each mark before the picture's timeout do the digits follow the
music and "0" fall on mark 0x30, with the music stopping at 0x31 1.6 s later.

## How each engine times the music and the frames

The row period, from the code:

- **Amiga original** (`another-world-archive` `amiga-archive-org/Another_World_Disk1.adf`, offsets into the image;
  68000 code, `unidasm -arch m68000`): PLAY_MUSIC stores the delay (or the module's own, its first word) at `$52A0`
  (0x916A4, 0x916D6, 0x916E4); 0x917DC writes it into CIA-A timer A (`$BFE401`, `$BFE501`, started at `$BFEE01`);
  the timer's interrupt, added through the CIA resource (0x9174C, 0x91764), runs 0x9186E, which counts `$5298` to 6
  and then plays a row (0x919E2), the other five calls sliding the channels' periods. A row is 6 x delay counts of
  the E clock, 709,379 Hz on a PAL Amiga: **132.79 ms** at 0x3D54. The VM's pause slice is a PAL frame, 20 ms.
- **MS-DOS original** (`~/compartilhado/MSDOS/ANOTHER.EXE`, file offsets, `objdump -m i8086`): 0x4083 computes the
  timer-interrupt count of a row, `delay x 600 / 7050` (x 300 in the other modes); the timer interrupt (0x911) plays the
  row (0x933, calling 0x40A1) when its counter passes that count, so a row is count + 1 ticks of the PIT at 1193182 / 119 Hz
  (0x0077 at data `0x1A0`, 10000 at `0x1A2`): **133.34 ms**. The same interrupt counts a VM slice every
  10000 / 50 = 200 ticks (0x93C; `[0x5A6A]`), 19.95 ms; the blit waits for var 0xFF slices since the last blit
  (0x2658: `[0x5C8A]` is var 0xFF), then sets var 0xF7 to the count and clears it.
- **rawgl** (`049e4ad`, `sfxplayer.cpp:109`): `_delay * 60 * 1000 / kPaulaFreq` with `kPaulaFreq = 7159092`, the
  NTSC clock (commit `82327ea`, "Use Amiga CIA timer as base frequency"), whole ms, then whole samples: 131.0 ms.
  Before `82327ea` rawgl had the MS-DOS release's `delay * 60 / 7050`.
- **Sanglard** (`fabiensanglard/Another-World-Bytecode-Interpreter` `170b7d4`, `sfxplayer.cpp:42,67`):
  `delay * 60 / 7050` whole ms on an SDL timer: 133 ms. Frames: `vm.cpp:280-290`, var 0xFF x 20 ms less the time
  since the last blit.
- **rustyworld** (`2e9a5ab`, `music.rs:36,64`): `delay * 60 / 7050` ms, 133. Its `load_module` reads the default
  delay from offset 0x3E (the order count) instead of 0: the intro passes its delay, so it does not matter here.
  Frames: `vm.rs:759-768`, var 0xFF x 20 ms on a running deadline (a late frame makes the next ones shorter).
- **The port** until this branch (`src/audio.s` MusicPeriod): rawgl's formula without the rounding, 131.61 ms, on
  the kernel's 1 ms counter. Frames (`src/interp.s` NextThread): var 0xFF x 20 ms less the frame's work, at least
  2 ms, once a tick; every intro tick runs exactly one BLIT_FRAMEBUFFER (`T` records of the virtual-clock runs), so
  that is the originals' once a blit.

Against the 20 ms slice the Amiga plays 6.64 slices a row, the MS-DOS release 6.69, the port 6.58: the port's
music ran 0.89% fast against the original's picture; rawgl's 1.35%; Sanglard's and rustyworld's are within 0.16%.

## What the instrument and MAME measured

**The music's tempo.** Against the picture's 20 ms slice the port played the Amiga's 6.64 slices a row as 6.58:
its music ran 0.89% fast, 0.98 s early by mark 0x21 (109.37 s against 110.35 s from PLAY_MUSIC at 0x3D54). That
is real but small. In MAME the player kept the kernel's clock: every mark written 0 to
56 ms after its row was due, none drifting (`K` records against `AU_NEXT`).

**The picture's speed.** On the unit (session `2026-11-06-felipe-unit-2`, from power-on: splash, intro, the lake)
the frames took longer than the bytecode asks, most of all from 8 to 38 s into the intro (rows 64-288), where the
frames ask 46 and 27 ms on average and took 67 and 43:

| stretch (rows) | frames | asked s | took s | took / asked | lag s  | asked ms a frame | took ms a frame |
|----------------|--------|---------|--------|--------------|--------|------------------|-----------------|
| 0-64           | 120    | 6.84    | 8.42   | 1.231        | +1.58  | 57.0             | 70.2            |
| 64-128         | 125    | 5.70    | 8.42   | 1.478        | +4.31  | 45.6             | 67.4            |
| 128-288        | 492    | 13.38   | 21.06  | 1.574        | +11.98 | 27.2             | 42.8            |
| 288-415        | 253    | 15.72   | 16.71  | 1.063        | +12.98 | 62.1             | 66.1            |
| 415-767        | 599    | 43.36   | 46.87  | 1.081        | +16.49 | 72.4             | 78.3            |
| 767-831        | 104    | 8.50    | 8.53   | 1.004        | +16.52 | 81.7             | 82.0            |

"took" is the music's time between the two marks (the module player runs on the kernel's millisecond counter, so
the marks arrived on time), "asked" var 0xFF x 20 ms over the frames between them (rustyworld's replay of the
session: the same frames). To the music's countdown the picture took 110.0 s for 93.5 s asked: 17.7% slower.
The first session of the day (`-1`) agrees to within 0.1 s up to row 415. MAME at 384x240 is slower still (21.8%
to row 831, 20.1 s behind at row 936; MAME's frame times are not the unit's), and there each frame's kernel-ms
length summed between two marks equals the music's time between them to within 0.6%: the player keeps time.

**What that does to the countdown.** Where the picture is when the music reaches row 831:

| run                                     | Phase 2 at row | countdown at row | lead s | RESULT, Y/N | soda pose | 5..1 | "0" at row | 0x31 stops it |
|-----------------------------------------|----------------|------------------|--------|-------------|-----------|------|------------|---------------|
| no CPU time, Amiga tempo                | 705.9          | 748.0            | -11.16 | 54          | 24        | 55   | 852.0      | no            |
| no CPU time, rawgl's tempo              | 712.9          | 755.4            | -10.06 | 54          | 24        | 55   | 862.5      | no            |
| no CPU time, Sanglard's / rustyworld's  | 704.9          | 746.9            | -11.36 | 54          | 24        | 55   | 849.8      | no            |
| picture 10% slower (22 ms), Amiga tempo | 766.4          | 818.8            | -1.64  | 54          | 24        | 54   | 936.7      | yes           |
| picture 12.5% slower (22.5 ms)          | 783.9          | 832.0            | +0.13  | 49          | 17        | 46   | 936.7      | yes           |
| picture 17.5% slower (23.5 ms)          | 820.1          | 848.9            | +2.41  | 20          | 7         | 39   | 936.7      | yes           |
| the unit, 7c2d2c06                      | 825.5          | 851.3            | +2.71  | 20          | 7         | 47   | 936.0      | yes           |
| MAME 384x240, 7c2d2c06                  | 849.5          | 876.0            | +5.31  | 20          | 24        | 55   | -          | no            |
| MAME 384x240, 3f0042c4 (this branch)    | 840.0          | 866.7            | +3.08  | 20          | 24        | 55   | -          | no            |

"lead": how long the music's countdown had been playing when the picture's began. Frames: RESULT and "Practical
verification" together (54 in full), the soda's held pose (24 in full), the digits 5 to 1 (55 in full).

- With the picture taking no CPU time, which is how rawgl, Sanglard's interpreter and rustyworld pace it on a PC
  (each frame var 0xFF x 20 ms exactly), the picture reaches the countdown 10.1 to 11.7 s before the music does,
  every digit and the soda run their full counts, "0" comes 74 to 91 rows before mark 0x30, the 39 frames after
  it time out, and the PLAY_MUSIC 0, 0 as the experiment starts (tick 2218) cuts the module off at rows 870 to 888. **So the
  references share the fault, in the other direction**, Sanglard's included: its tempo is the MS-DOS release's
  and its pacing rawgl's.
- The design (texts shown in full, the digits following the music, "0" on mark 0x30, the music stopped at 0x31)
  comes out with the picture 10 to 12.5% slower than it asks: then the music reaches its countdown 0 to 1.6 s
  before or after the picture does, and the soda's held pose absorbs the rest. That is what Felipe remembers.
- On the unit the picture is 17.7% slower: the music's countdown section, an 8-row figure with a mark at each
  repeat (pattern 12, rows 832-895: 55 of its rows repeat the notes 8 rows before), began 2.7 s before the picture's countdown
  appeared, while it still showed "Phase 2: EJECTION". The picture then caught up as the bytecode lets it: RESULT
  and "Practical verification" were cut from 54 frames to 20, the soda's pose from 24 to 7. "5" to "0" followed the
  music, "0" on mark 0x30 and the music stopped at 0x31. The music had reached its countdown loop "a few seconds
  early".
- MAME is slower again: the music led by 5.3 s, so far that the digits' exact-mark tests (`je`) missed their marks,
  the countdown ran on its own counts and 0x31 had passed before "0".

Why the original hardware ran its picture some 10% slower than it asks is not settled here: whether the Amiga 500's
frames overran (the intro's first scenes ask for 20-40 ms frames), or its blit waits in a way that adds to each
frame. The Amiga's vertical-blank server (image offset 0x8F726, added at 0x8F720 with AddIntServer, INTB_VERTB)
counts frames into a word; the blit that reads it was not traced. The MS-DOS release's blit (0x2658) waits until
var 0xFF slices have passed since the last blit and then for the VGA's retrace, the same model as rawgl's.

## What changed

`src/audio.s` MusicPeriod: a row lasts 6 x delay / 709379 s, the Amiga original's (`delay x 35476 / 16384` in
1/256 ms). `KN7APP.BIN` SHA-1 `3f0042c4fa039d3a8952317444078c404cbf574e`.

In MAME (the intro with its own music, 384x240, `AW_TIMELOG`, `music-timing/mame-*.timelog`) the player's schedule
went from 131.609 to 132.789 ms a row at 0x3D54 and from 133.287 to 134.486 at 0x3E1C (the formula's 132.792 and
134.484), and the music's lead at the countdown from 5.31 s to 3.08 s. On the unit the tempo alone is worth about
1 s at the countdown: with the picture 17.5% slow the virtual-clock runs put the lead at 2.41 s with the Amiga's
tempo and 3.33 s with the old one, and with the old one the digits' exact-mark tests already miss their marks
there (the countdown on its own counts, the music not stopped at 0x31), so the unit was close to MAME's failure.

What it does not change: the picture's 17.7% shortfall on the unit, which puts the music 2.4 s ahead at the
countdown even at the Amiga's tempo. The frame pacing is the originals' (var 0xFF slices since the last frame, no
catching up) and needs no change to be faithful; from 8 to 38 s into the intro the frames ask 27-46 ms and the unit
takes 43-67 ms (384x240). Making those frames cheaper, or measuring the Amiga 500's own shortfall and matching
it, is what would restore the sync.

The replays (`run_inplog.sh replay`) are unchanged by this: they undo the player's own marks and write the logged
ones. Felipe's first unit session (`2026-11-01-felipe-unit-aw.awr`) replayed on `3f0042c4` against rustyworld:
all
1346 pages equal (`compare_frames.py`) and all 256 variables at every frame (`varsdiff.py`), as before.

## Commands

    probes/musictiming.sh ~/compartilhado/tmp/aw-music/mt \
      "mame 7c2d2c06 384x240=probes/music-timing/mame-7c2d2c06-384x240.timelog" \
      "mame 3f0042c4 384x240=probes/music-timing/mame-3f0042c4-384x240.timelog"   # from kn7000/: summary.md
    AW_HIRES=1 AW_INTRO_FRAMES=2050 AW_TIMELOG=$T/live/time.log probes/cnv/run_inplog.sh $T/live record
                                                                                 # MAME: the intro with its own music
    probes/cnv/run_inplog.sh $T/rep replay probes/sessions/2026-11-01-felipe-unit-aw.awr   # the replay check
    REF_VARS=ref.vars replayawr probes/sessions/2026-11-01-felipe-unit-aw.awr ref.log     # (from the rustyworld run dir)
    python3 -I probes/compare_frames.py $T/rep/pages.log ref.log; python3 -I probes/varsdiff.py $T/rep/vars.bin ref.vars

`musictiming.sh` needs rustyworld's `replayawr` with `music-timing/rustyworld-vclock.diff` applied on the clone
research-scratch `kn7000-aw-reference/replay-mods` describes (rustyworld `2e9a5ab` + `rustyworld-kn7000-all.diff`):
`patch -p1 < rustyworld-vclock.diff; cargo build --release --no-default-features --bin replayawr`, and `RW=` its path.

| file                                  | question it answers                                                                                       |
|---------------------------------------|-----------------------------------------------------------------------------------------------------------|
| `musictiming.py marks DATA`           | which rows of the intro module carry sync marks, and their values                                         |
| `musictiming.py report DATA ...`      | each engine's row period; where the picture is when the music reaches the countdown; frames asked vs took |
| `musictiming.sh OUT`                  | runs the virtual-clock models and the unit sessions' replays through rustyworld, then the report          |
| `music-timing/rustyworld-vclock.diff` | rustyworld playing the music on a virtual clock: each blit advances it var 0xFF slices, the CPU free      |
| `cnv/awcnv_inplog.lua` `AW_TIMELOG`   | MAME: the kernel ms of every frame's end (var 0xFF, its blits) and of every mark the module player wrote  |
| `music-timing/mame-*.timelog`         | the two MAME runs' AW_TIMELOGs (the intro with its own music, 384x240, program 893)                       |
| `music-timing/summary.md`             | `musictiming.sh`'s output, every number of this note                                                      |

## Open

- The original hardware's frame times. The design needs the picture about 10% behind its asked pace by the
  countdown; measure the Amiga 500 (MAME `a500` or WinUAE, the ADF above: the frame at which each mark arrives,
  var 0xF4 against the VBL count) and the MS-DOS release on a period PC, and trace the Amiga's blit wait (the
  word the VBL server counts).
- Two things of the Amiga player the port does not do, seen in passing: the five ticks between rows slide the
  channels' periods (0x91892-0x918FC), and at the module's end it starts again from order 0 (0x91AB6-0x91AC6)
  where rawgl and the port stop. Neither touches the intro's countdown, which the bytecode stops at mark 0x31.
- The KN5000 port (`kn5000cnv/src/cnv_sound.asm` `_mus_period`) has the same NTSC tempo (`delay x 1073 / 1024`
  ticks / 256); the Amiga's would be `x 1083`. Not changed here.

