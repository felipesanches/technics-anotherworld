# KN5000 programs as style converters (.CNV)

The KN5000's DISK MENU > STYLE CONVERT loads a `.CNV` file from the floppy and runs it on the main
CPU, with the stock firmware. This directory holds programs that use that door.

## The mechanism (v7 disassembly, `technics-roms-disasm/v7/maincpu/sequencer/accompaniment_engine.s`)

- STYLE CONVERT lists `*.CNV` on the floppy (STYLE TYPE SELECT); OK loads the chosen one.
- `StylCnvModl_OK_SelectItem` opens it, zeroes 192 KB at `0x80000`, reads the whole file there,
  clears the flag at `0xFFBFE`, writes `0xFF` to the mailbox byte `0xFFC00` and 0 to `0xFFC01`, and
  jumps to `0x80000` (`TableData_JumpToEntry`), with a return address on the stack.
- The converter returns with a request in `0xFFC00`. `FloppyState_Dispatch` serves it. Request 1
  copies the string at `0xFFC01`, writes `0xFF` and calls the converter again at once
  (`StylCnv_ClearAndFinalize`, `StylCnv_FinalizeAndCheckStatus`). Request `0xFE` ends the run: the
  firmware shows "Continue Next?" (title `0x16`). Requests 0, 2, 3, 4 and 5 are the converter
  services (store, names, file loading, file I/O, text); they are the KN7000's request codes.

A converter is TLCS-900/H code linked at `0x80000`, assembled with ASL (`cpu 96c141`).

## probes/hello: the smallest converter (2026-10-22)

`hello.asm` (80 bytes) counts its calls at `0xA0004`, writes `CNV5` at `0xA0000`, fills LCD rows
100-139 (VRAM `0x1A0000`, 320 bytes a row) with the count's low byte, and answers request 1 until the
600th call, then `0xFE`.

Measured in MAME (published `kn7000` binary, md5 `7f1205b746cde8c45781ba9eed5a2565`, machine
`kn5000`, default firmware): STYLE TYPE SELECT lists `HELLO.CNV`; after OK (right button 4) the
signature is there and the count climbs about 97 calls per second (20 at 1.0 s after OK, 310 at
4.0 s, 600 at 7.0 s), the band is drawn over the firmware's screen, and after the 600th call the
mailbox reads `0xFE` and the firmware shows "Continue Next?".

```sh
cd probes/hello
~/compartilhado/tools/asl/asl -q -w -L -olist hello.lst hello.asm -o hello.p
~/compartilhado/tools/asl/p2bin hello.p HELLO.CNV -r 0x80000-\$
python3 -I ../../tools/mkfloppy.py hello.img HELLO HELLO.CNV
cd .. && ./run.sh ~/compartilhado/tmp/kn5000cnv/run1 hello/hello.img \
    "25:DISK;28:L3;33:R4;34:snap;35:snap;37:snap;40:snap;45:snap;50:quit"
```

## Another World: `AW.CNV` on one floppy (2026-10-22)

The KN5000 VM of this repository (`../src/another_world_vm.asm`, built with `TARGET_CNV`) as a converter.
`make AW_DATA=<the MS-DOS release>` writes `build/aw5000.img`, a 1.44 MB floppy with `AW.CNV` (16,904 bytes)
and the game's 40 resources as `AWnn.BIN` (997,046 bytes; 1,022,464 of the disk's 1,457,664 used). The game
data comes from your own copy (`../kn7000/tools/aw_extract.py`) and is not in this repository.

To play: DISK MENU > STYLE CONVERT > `AW.CNV` > OK. Controls as in the standalone build (UP = PART SELECT
RIGHT 2, DOWN / LEFT / RIGHT = CONDUCTOR RIGHT 2 / LEFT / RIGHT 1, ACTION = VARIATION 4, HELP, OTHER PARTS/TR
for the codes). The keybed plays it too: F4 left, C5 right, A4 down, A♭4 or B♭4 up, any key from C3 down
action (the KN5000's own note names: middle C is C3; the help screen lists them); of two opposite directions held, the one in use stays until its key is released. Hold EXIT for 1.5 s to leave; the firmware then shows "ERROR!" and "Continue Next?", as it
does after any converter that ends; NO returns to the main screen. The sound effects and the music play on the instrument's own voices ("Sound" below).

### How it runs beside the firmware

- **Inside the first call.** The VM runs in the firmware's first call to the converter and returns only
  when the game ends.
- **The firmware's file routines.** `FileIO_OpenWithMode`, `_ReadBlock`, `_SeekAndReadBlock` and
  `_CloseHandle` read `A:\AWnn.BIN`. Their addresses differ between v5, v6, v7 and v8-v10
  (`tools/find_fileio.py`); `cnv_platform.asm` carries all four sets and checks each routine's opening
  bytes before it trusts a set, so another firmware gets a message, not a crash.
- **Memory.** The 192 KB the firmware zeroes at `0x80000` holds the program and the part buffers. The four
  page buffers, the shared polygons and the screen buffer go in the sequencer's song memory
  (`0xB0000`-`0xFDFFF`), used only when it holds no song: all 0 (v5, v6 after boot) or exactly the block
  chain v7-v10 build at boot (`0x4D8` blocks of 256 bytes; the model is in `cnv_platform.asm`). Otherwise
  it shows "AW: SAVE SONGS, SWITCH OFF+ON" and ends; on leaving it writes back the state it found. The help
  screen draws in VRAM past the visible 320x240 (`0x1B3000`).
- **Input.** The firmware runs the panel link by interrupt (INTA, INTRX1, INTTX1), but decodes it in its
  main loop, which does not run meanwhile. The game masks those three, turns SC1's pins on as the
  firmware's own transmit path does (`PFFC`/`PFCR` | `0x50`), and polls the panels itself. A reply is used
  only if its header names the segment asked for, since the panels also push changes on their own.
- **Keybed.** The sub CPU sends each key as note and velocity (0 = released); the firmware's interrupt
  path writes the pair into a 256-byte ring, which its main loop would read. The game reads that ring
  instead and keeps the keys held. The ring's address is found as `tools/find_noterng.py` finds it, from
  the sequencer's dispatch table (`0x202CB` in v5-v10). A part loading from floppy (about 5 s) reads no
  keys; those pressed meanwhile are read when it ends.
- **Timing.** The firmware's Timer 1 counter at `0x0409` (the same INTT1 handler in v5-v10; 488 Hz in MAME):
  one 20 ms frame slice is 10 ticks.
- **Leaving.** `INTEAB`, `INTES1`, `SC1MOD`, `SC1CR`, `BR1CR`, `PFCR` and `PFFC` (from the firmware's RAM
  copies) and DAC colours 0-15 are put back.

### Measured in MAME

Published `kn7000` binary md5 `3e9ee312330a64cbec3a0c458caec32c` (with the KN5000 panel fixes these runs
led to, kn7000_mame `802d189`, `b2e0e3e`: `notes/kn5000-panel-race-2026-10-22/`); the keybed rows on
`44828eab2e95a2d3b6b3bd33baacf074`, which adds the port A fix (`0d0649e`). The key names are the KN5000's
(kn7000_mame `89fcd6b`, binary `345965464b9431f7f9c307420a85b388`, on which the keybed row was re-run with
the `KEYS` line below); earlier binaries named every key an octave higher.

| check                                                                                          | result                                                                                                                                   |
|------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| start, v5 v6 v7 v10 (`ex_*` runs)                                                              | each finds its own routines (open `0xF883B8`, `0xF886C5`, `0xF887BA`, `0xF88BC7`) and runs the intro                                     |
| loading                                                                                        | the intro's three files (77 KB) about 7 s after OK; the water part's four (105 KB) about 10 s                                            |
| the intro to the water part (v10, no input)                                                    | the part switches at about 292 s, 250 s after the intro starts (the standalone ROM build: at about 240 s from boot); "ACCESS CODE: LDKD" |
| controls (`vmvars.lua`)                                                                        | UP: up/down -1, mask `0x08`; RIGHT: left/right 1, mask `0x01`; LEFT: -1, `0x02`; ACTION: action 1, mask `0x80`; HELP opens help          |
| play (`START_PART=03E82h` build)                                                               | UP held through the fall: Lester surfaces, climbs out, the beast appears, RIGHT walks him right                                          |
| keybed (`keys.lua`, `vmvars.lua`, `notering.lua`)                                              | C5: left/right 1; F4: -1; A4: up/down 1; G#4, A#4: -1; C1, C2, C3: action; C5 held, then F4 too: right until C5 is released, then left   |
| ACTION or C2 in the intro                                                                      | the water part (`3E82`) starts: about 5 s of loading, then the game; the keys pressed meanwhile arrive together                          |
| HELP, page 1                                                                                   | a KEYBED column beside the buttons: G#4/A#4, A4, F4, C5, C1-C3                                                                           |
| out of the lake (UP 56.5-70.5 s), then C5 or F4 with C3 held, A#4 at 73.6 s (`jumpR`, `jumpL`) | a running jump to the right, and the same to the left (to the cliff); the VM's inputs `0x89` / `0x8A`                                    |
| EXIT held 1.5 s, then NO, then DISK                                                            | "Continue Next?", the main screen, the DISK MENU: the panel works again                                                                  |
| song memory after leaving (`songsame.lua`, v5 v6 v7 v10)                                       | byte-identical to before OK in all four                                                                                                  |
| a song in memory (`poke.lua` changes one byte)                                                 | "AW: SAVE SONGS, SWITCH OFF+ON" for 4 s, then "Continue Next?"; the memory untouched                                                     |

Not checked: the real instrument; the game past the beast's first chase on a converter build.

### Sound: the instrument's voices (2026-10-23)

As the KN7000 port's first sound mode (`../kn7000/src/audio.s`, the tone generator mode): no sample of the game is
played; each PLAY_SOUND and each row of the music module becomes a note of one of the KN5000's voices
(`src/cnv_sound.asm`).

- **To the sub CPU directly.** The firmware's main loop, which turns MIDI and the keybed into the sub CPU's records,
  does not run while the game does, so the game sends the records itself over the inter-CPU latch, with its own copy
  of the firmware's send (v10 `InterCPU_Send_Data_Block`, 0xEF3345: the handshake on port Z): `90 part note velocity`,
  `B0 part control value`, `C0 part program selector 0`. The records were read off the latch (`probes/latch.lua`,
  `tools/latch_decode.py`) while the firmware played: C3 on the keybed sends `90 00 3C 64`, BRASS `C0 00 38 00 00`
  ("Bigband Brass" is selector 0 program 56 in the tone database), the boot gives every part its settings.
- **Parts 3-6** play PLAY_SOUND's channels 0-3 and **parts 7-10** the music's (MIDI receive parts of channels 4-11,
  piano at power-on, idle while no song is loaded, which the game requires); on leaving they get the boot's piano,
  volume 100, expression 127 and pan back. The module (resources 0x07, 0x89, 0x8A, now on the floppy) is read when
  the game starts it, into `MUSIC_BUF`; rows are timed on the firmware's 488 Hz counter, polled through every frame
  pause; its sync marks go into var 0xF4 as the original's.
- **The voices** (`tools/aw_sound_map5.py`): the KN7000 table's choice per sound, moved to KN5000 voices that MAME
  plays. MAME has only one of the four wave ROMs dumped, and many voices are silent there; every drum kit is (so the
  drums are melodic voices at a fixed note). The instrument plays them all, so the table is one to retune on the
  unit. Measured with the `SND_TEST=1` build (`make SND_TEST=1 ...`: 82 notes before the game, 0.75 s apart) and
  `tools/sndtest_levels.py RUN.log OUT.wav 33` (MAME `-wavwrite`; the latch probe's log):

  | heard in MAME (C3, velocity 100)                                                                                                                                                                                                                                                                                                                        | silent                                                                                                                                                                                                                                                       |
  |---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
  | Piano, Bright Piano, Mellow Piano -34..-36 dBFS; Electric Bass -45; Mute Bass -31; Glockenspiel -45; Steel Drum -49; Sleigh Bell -40; Halo Pad -55; Sine Lead -42; Dream -51; Goblins -63; Kalimba -47; Agogo -31; Wood Block -33; Taiko -26; Synth Drum -30; Seashore -46; Gun Shot -32; Full and Chapel Organ -40, -46 (the organs' notes do not end) | Vibraphone, Tubular Bells, Marimba, Xylophone, Celesta, Music Box, every bass synth, every string and pad but Halo, every brass, the leads but Sine, the E.Pianos, voices, Harp, Trumpet; drum keys on the rhythm part 0x14 and on part 0x0F with either kit |

- **Checked in MAME (v10):** the intro sends 436 notes and program changes in 230 s and sounds at -17 to -40 dBFS
  through it; the water part (`START_PART=03E82h`, UP held) at -14 to -32 dBFS, its looping water held quietly
  (Dream, -67 dBFS) while it lasts (`probes/sndstate.lua`, `tools/wavlevel.py`). Not heard by a person yet, and not
  tried on the unit.

### A DSP mixer of ours in IC311 (2026-10-23): runs in the emulator, test builds only

The KN7000 port plays the game's own samples with a mixer of ours in its effects DSP (`../kn7000/README-CNV.md`,
"Sound"). The KN5000 now has the same, in three pieces, all in a `DSND_TEST=1` build so far:

| piece                | where it runs                             | what it does                                                                                                                                                                                                                                          |
|----------------------|-------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `src/cnv_dspsnd.asm` | main CPU, in AW.CNV                       | puts the streamer into the sub CPU's DRAM at `0xF8000` with E1 transfers, as the boot sends the sub program, and points two of the sub program's RAM trampolines at it: INTT1 (the audio tick) and INTT5 (timer 4, unused); puts both back at the end |
| `src/awsub.asm`      | sub CPU, from its audio tick              | once, loads the mixer into IC311 and starts timer 4 at 4000 Hz; on each timer 4 tick, steps four channels over 8-bit samples in sub DRAM and writes the four current samples and any changed volume to IC311                                          |
| `tools/dspmix.py`    | IC311 (uPD6383GF), 44,100 frames a second | DO1 = the sum of the four samples times their volumes; 92 I-RAM words, only decoded forms but the output stage's presentation word                                                                                                                    |

The trampolines' original targets differ between sub programs (v1.40/1.41 on firmware v5-v8, v1.42 on v9/v10),
and the main CPU cannot read the sub CPU's memory, so AW.CNV recognises the sub program by its first literal bytes
in IC19 flash (the compressed copy the boot sends, `0x3E000C`) and takes the targets from a table; on any other
sub program it leaves the sub CPU alone. The mixer's layout (where the CALL, the presentation word, the samples
and the output level go) is what the MAME core's model of the chip required, each item measured:
kn7000_mame `notes/kn5000-dsp-mixer/README.md`.

**Measured (run `e4`, firmware v10, `probes/run_dsnd.sh`):** AW.CNV found sub program v1.42, the streamer's
magic and both trampolines are in place, timer 4 ticks at 4000 per second of emulated time (`SUB_TICKS`), and
the DSND_TEST sine on channel 0 (256 samples, 4 per tick: 62.5 Hz) is on the speakers from the moment AW.CNV
starts (36-44 s: rms 4454, peak 6819, strongest bins 62.1-62.8 Hz), and stays under the intro's music. It needs
the IC311 build of the emulator (`KN5000_ENABLE_DSP1=1`), the insert switched on (DSPCFG bit 0) and
`UPD6383_PRESENT_ASIS=1`, which `run_dsnd.sh` sets; and kn7000_mame `38ee146`, without which the DSP saw the
samples about 90 times a second instead of 4000.

**The game's sound effects (`make DSND=1`).** `tools/aw_sbank.py` codes every sound the parts play as IMA
ADPCM into one file, `AWSND.BIN` (93 sounds, 342,490 bytes; the floppy then holds 1,408,512 of 1,457,664
bytes). When a part loads, `CNV_SBANK_LOAD` reads its sounds (seek and read per sound, into the screen
buffer, which nothing uses while a part loads), decodes them on the main CPU and sends the samples to the sub
CPU's DRAM from `0xA0000` (the largest part, 219,012 bytes). PLAY_SOUND then sets one of the four channels:
start, end, loop, the step for its frequency at 4000 ticks a second, its volume. Measured (`probes/dsnd.lua`
with `DS_WATCH=1`, runs `e9`-`e11`):

| how the sounds are read            | the intro's 22 sounds (141 KB of samples)                |
|------------------------------------|----------------------------------------------------------|
| one file per sound, 4 KB a read    | over 35 s                                                |
| one file per sound, read whole     | about 1.5 s a sound, nearly all of it the file's opening |
| `AWSND.BIN`: one open, seek + read | 14 s (41.0 - 55.0 s)                                     |

and the intro then plays with its own sound effects (levels 58-110 s: rms up to 3309, peak 10483, nothing
clipped). The music stays on the instrument's voices for now.

Open: the music on the four channels, as on the Amiga; a faster load (decoding and E1 take about half the
14 s); a higher tick rate than 4000 Hz, whose 2 kHz bandwidth dulls the sounds; IC311's own effect program
back when the game ends; and the real instrument, where none of this has run. The core's model reads the
CALL, its D-RAM rebase and the output level from the shipped kernel; the chip may differ. The research plan is
on the technics-docs site: `kn5000-dsp-sample-playback-research.md`.

### Speed (2026-10-23)

Frames took about 1.5 times what the script asks for (`var[0xFF]` slices of 20 ms), in emulated time:

- **Pacing.** The VM showed the page, then paused, and timed the next frame from the end of the thread loop, so
  the work after the pause never counted. As the reference does, `BLIT_FRAMEBUFFER` now pauses, stamps the
  time, then shows the page (and sets `var[0xF7]` = 0). The end of each frame also copied the page to VRAM a
  second time; the reference does not, and the help screen redraws the game itself.
- **Copies and fills.** `COPY_VIDEO_PAGE` (both forms) is one `LDIRW` (7 states a word, against 22 for each
  dword of the old loop); `FILL_VIDEO_PAGE` stores 4 bytes at a time; `drawLineN` stores 4 bytes at a time on
  spans of 8 pixels or more; `drawLineP` is one `LDIR` (7 states a byte, against 18). Cycle costs are those of
  MAME's TLCS-900/H tables (`900htbl.hxx`), which match the datasheet for `LDIRW`.

Mean frame length against the script's request (v10, binary `34596546`; `probes/frametime.lua`, `tools/ftsum.py`;
the same input: ACTION in the intro, UP out of the lake, a running jump):

| frames                   | asked | before   | pacing fixed | and copies/fills |
|--------------------------|-------|----------|--------------|------------------|
| intro, 3 slices          | 60 ms | 104.7 ms | 72.9 ms      | 64.0 ms          |
| intro, 4 slices          | 80 ms | 120.8 ms | 81.8 ms      | 81.9 ms          |
| lake and chase, 4 slices | 80 ms | 124.3 ms | 86.4 ms      | 85.0 ms          |

The pause polls a 488 Hz tick, so a frame of 4 slices is at least 82 ms. Before the copy changes, a profile of
the chase (`probes/profile.lua`, one PC sample a video frame) gave the page copy 24.8 % of the main CPU, the
VRAM copy 16.8 %, the pause 24.0 %, polygon drawing about 20 %.

**Same pictures.** `probes/pagehash.lua` hashes every page shown; `tools/pagehash_cmp.py` compares two runs'
sequences, repeats dropped. Against the build before these changes (`1310a76`): the intro with no input, 566
pages identical (the new build showed 859 in the same 77 s); a `START_PART=03E82h` build with no input, 104
pages identical.

**MAME's own speed** is the larger limit on this machine: unthrottled, the KN5000 emulation runs at about 63 % of
real time here (no probes, during the game), so a frame of 80 ms emulated takes about 127 ms of yours. That is
in the emulator, not the game.

The standalone ROM builds change too (maincpu `a2a7bb2b`, extension `428b8d3b`); they assemble, and have not been
run.

### The lake froze the game (fixed 2026-10-22)

From the intro, at the lake, the game froze when Lester died (a black screen) and when he climbed out
(the lake in the next scene's colours). Both run bytecode that was no longer the part's own:

- **Cause.** `CHECK_THREAD_REQUESTS` (`../src/another_world_vm.asm`) walks the 64 threads with `LD A, 0` and
  indexes the thread table with `WA`. On the frame a part switch runs, `W` still held `0x4A` from the
  palette pointer `initForPart` leaves in `XWA` (`PALETTE_BUF`, `0x84A00`). That frame's 64 thread updates
  went to `THREADS_DATA + 0x2800` (the index wraps at 16 bits): the new part's bytecode, offsets
  `0x1A08`-`0x1B07` for the water part, the code for dying and leaving the lake. Drawing from the broken
  code recursed without end until the stack ran into the firmware's memory. The `START_PART` builds never
  switch parts, so they did not show it. Fix: `LD WA, 0`.
- **The standalone ROM builds** have the same bug (their writes land elsewhere in DRAM); the fix changes one
  byte in each: maincpu `0b2b6ca2` -> `0c1f2d21`, extension `2f4ac1cb` -> `ba0f8582`.

| check (v10, ACTION in the intro, binary `34596546`)                 | before the fix                                                                                                       | after                                                                                                    |
|---------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------|
| the water part's bytecode in RAM against `AW1B.BIN` (`bcwatch.lua`) | 243 bytes differ from `0x1A09`, from 53.05 s, written by `_dont_delete_this_thread` (`0x3608`, `0xFFFF` at `0x1A08`) | identical at 57, 100 and 150 s                                                                           |
| no input (`frames.lua`, `cpupc.lua`)                                | at 66.2 s, VM PC `0x1AF9`: the stack grows past `0x1A9A8`, the CPU ends in the firmware at `0xEF086A`                | Lester dies; "PRESS BUTTON OR RETURN TO CONTINUE", "ACCESS CODE: LDKD"; ACTION restarts the lake (twice) |
| UP (A#4) held from 56.5 s for 30 s                                  | not run: the pre-fix run held UP from 66 s and froze first; the freeze on climbing out was seen by hand              | Lester surfaces, climbs out, the beast comes; it catches him; the continue screen                        |

```sh
# the bytecode check and the run on (the KN5000 emulator folder; P = kn5000cnv/probes, R = a new scratch folder)
SYM=$P/../build/aw_cnv.sym PROBES="$P/seq.lua $P/keys.lua $P/awstate.lua $P/bcwatch.lua" BC_FILE=$P/../build/files/AW1B.BIN \
    BW_CHECK=57,100,150 PERIOD=8 AS_FROM=56 KEYS="45:C2*0.5" SEQ="25:DISK;28:L3;33:R4;80:snap;158:quit" DISPLAY=:0 \
    ./kn7000 kn5000 -rompath ./roms -pluginspath ./plugins -skip_gameinfo -window -nothrottle -sound none \
    -flop $R/disk.img -nvram_directory $R/nv -cfg_directory $R/cfg -snapshot_directory $R/snap -autoboot_script $P/multi.lua
# who writes there: add BW_LO=1a08 BW_HI=1a0b BW_FROM=44 (on a floppy built before the fix)
```

### After any converter

STYLE CONVERT itself zeroes the 192 KB at `0x80000` before it loads a converter. The main screen used to show
"Sound Name Error" for the parts afterwards, and the keybed played nothing: the emulator held the sub CPU in
reset from the moment STYLE CONVERT opened (a port A read-back fault in MAME's TMP94C241, fixed in kn7000_mame,
`notes/kn5000-subcpu-reset-porta-2026-10-22/`). With the fix, leaving the game (EXIT held, then NO) shows the
parts' names again: Piano, Bigband Brass, Modern E.P.1 (v10).

```sh
make AW_DATA=~/compartilhado/MSDOS ASL_DIR=~/compartilhado/tools/asl DISASM_REPO=~/compartilhado/technics-roms-disasm
probes/run.sh ~/compartilhado/tmp/kn5000cnv/play build/aw5000.img "25:DISK;28:L3;33:R4;60:snap;90:quit"
# the keybed rows: seq.lua, keys.lua and vmvars.lua in one session (multi.lua), from the emulator folder
R=~/compartilhado/tmp/kn5000cnv/keys; H=$PWD/probes; mkdir -p $R/nv $R/cfg; cp build/aw5000.img $R/disk.img
(cd ~/compartilhado/kn7000-emulator && SYM=$H/../build/aw_cnv.sym PROBES="$H/seq.lua $H/keys.lua $H/vmvars.lua" \
    KEYS="45:C5*1;47:F4*1;49:A4*1;51:G#4*1;53:A#4*1;55:C3*1" VV_FROM=45.5 VV_PERIOD=2 SEQ="25:DISK;28:L3;33:R4;58:quit" \
    DISPLAY=:0 ./kn7000 kn5000 -rompath ./roms -pluginspath ./plugins -skip_gameinfo -window -nothrottle -sound none \
    -flop $R/disk.img -nvram_directory $R/nv -cfg_directory $R/cfg -autoboot_script $H/multi.lua 2>&1 | grep -E "^KEY|VMVARS")
```

## Tools

| file                                               | what it does                                                                                                   |
|----------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| `tools/mkfloppy.py`                                | `mkfloppy.py OUT.img LABEL FILE...`: a FAT12 1.44 MB image, files contiguous in the root, reproducible         |
| `probes/seq.lua`                                   | presses panel buttons on a schedule (`SEQ="t:button;t:snap;t:quit"`), reports the converter's state            |
| `probes/run.sh`                                    | `run.sh OUT FLOPPY SEQ`: one KN5000 run in the published emulator with that floppy                             |
| `tools/make_awdisk.py`                             | the game's resources as `AWnn.BIN` and `awfiles.inc` (sizes, the parts' resource lists)                        |
| `tools/find_fileio.py`                             | the four FileIO routines in each firmware version (`kn5000_v*_program.rom`)                                    |
| `tools/lst2sym.py`                                 | an ASL listing's symbols as `NAME HEX` lines, for the probes                                                   |
| `probes/multi.lua`                                 | runs several probes in one session (`PROBES="a.lua b.lua"`)                                                    |
| `probes/awstate.lua`                               | AW.CNV's state: part loaded and running, last file read, VM PC, firmware matched, mailbox                      |
| `probes/vmvars.lua`                                | the VM's input variables                                                                                       |
| `probes/songsame.lua`                              | the song memory before OK against after leaving                                                                |
| `probes/songcheck.lua`                             | the song memory against the v7-v10 boot chain                                                                  |
| `probes/poke.lua`                                  | writes one byte at a time (to fake a song in memory)                                                           |
| `probes/qheaders.lua`                              | the panel reply headers the VM's queries receive                                                               |
| `probes/clobber.lua`, `statewatch.lua`             | foreign writes to AW.CNV's variables; writes to its state byte; machine resets                                 |
| `probes/ramuse.lua`, `dumpram.lua`, `tickrate.lua` | which DRAM/VRAM the firmware writes by phase; high DRAM after boot and its writers; the Timer 1 counter's rate |
| `probes/partwatch.lua`                             | the VM's part and PC (also for the standalone ROM build)                                                       |
| `probes/keys.lua`                                  | holds keybed keys on a schedule (`KEYS="t:C3*0.5"`, MAME's key names)                                          |
| `probes/notering.lua`                              | the keybed note ring: each byte written, its indices, AW.CNV's held-key map                                    |
| `probes/subpkt.lua`                                | the sub CPU's packets to the main CPU (header and payload)                                                     |
| `tools/find_noterng.py`                            | the keybed note ring's address in each firmware version, found as AW.CNV finds it                              |
| `probes/bcwatch.lua`                               | the part's bytecode in RAM against its file at given times; writes to a range of it, with PC                   |
| `probes/bcread.lua`                                | the VM's bytecode reads (offset, byte) in a time window: the instructions it ran                               |
| `probes/foreign.lua`                               | writes into AW.CNV's memory and buffers from code outside AW.CNV                                               |
| `probes/cpupc.lua`, `frames.lua`                   | the main CPU's PC by AW.CNV symbol every few seconds; every frame with the stack pointer and VM PC             |
| `probes/hostkeys.lua`                              | which PC keys MAME sees held, on every change: does the keyboard report a combination at all?                  |
| `probes/latch.lua`, `tools/latch_decode.py`        | every byte the main CPU writes to the sub CPU (and MIDI IN bytes); cut into packets, the MIDI-ring records     |
| `probes/sndstate.lua`                              | the sound's state: ready, module, the notes sounding                                                           |
| `tools/sndtest_levels.py`, `tools/wavlevel.py`     | each note of a run and how loud it was in the recording; a recording's level per second                        |
| `tools/mkmid.py`                                   | a MIDI file of GM program changes and notes, for MAME's `-midiin1`                                             |
| `tools/aw_sound_map5.py`                           | the KN5000 voice of each sound resource (`CNV_SND`)                                                            |
| `probes/frametime.lua`, `tools/ftsum.py`           | each VM frame's pause request, length and overrun; summarised per part and request                             |
| `probes/pagehash.lua`, `tools/pagehash_cmp.py`     | a hash of every page shown; do two builds show the same pages in the same order?                               |
| `probes/profile.lua`                               | the main CPU's PC once a video frame, counted by AW.CNV routine                                                |
| `probes/run_dsnd.sh`, `probes/dsnd.lua`            | one run for the DSP sound (IC311 build, insert on, `-wavwrite`); the streamer's state in the sub CPU           |
| `tools/dspmix.py`, `tools/upd6383_asm.py`          | the IC311 mixer program (`build/dspmix.inc`) and its test version for the MAME core's harness                  |
| `tools/aw_sbank.py`                                | the game's sounds as IMA ADPCM, and each part's sound table (not yet used by the build)                        |
