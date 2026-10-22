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
`make AW_DATA=<the MS-DOS release>` writes `build/aw5000.img`, a 1.44 MB floppy with `AW.CNV` (16,771 bytes)
and the game's 40 resources as `AWnn.BIN` (997,046 bytes; 1,022,464 of the disk's 1,457,664 used). The game
data comes from your own copy (`../kn7000/tools/aw_extract.py`) and is not in this repository.

To play: DISK MENU > STYLE CONVERT > `AW.CNV` > OK. Controls as in the standalone build (UP = PART SELECT
RIGHT 2, DOWN / LEFT / RIGHT = CONDUCTOR RIGHT 2 / LEFT / RIGHT 1, ACTION = VARIATION 4, HELP, OTHER PARTS/TR
for the codes). The keybed plays it too: F5 left, C6 right, A5 down, A♭5 or B♭5 up, any key from C4 down
action; of two opposite directions held, the one in use stays until its key is released. Hold EXIT for 1.5 s to leave; the firmware then shows "ERROR!" and "Continue Next?", as it
does after any converter that ends; NO returns to the main screen. There is no sound.

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
`44828eab2e95a2d3b6b3bd33baacf074`, which adds the port A fix (`0d0649e`).

| check                                                    | result                                                                                                                                   |
|----------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| start, v5 v6 v7 v10 (`ex_*` runs)                        | each finds its own routines (open `0xF883B8`, `0xF886C5`, `0xF887BA`, `0xF88BC7`) and runs the intro                                     |
| loading                                                  | the intro's three files (77 KB) about 7 s after OK; the water part's four (105 KB) about 10 s                                            |
| the intro to the water part (v10, no input)              | the part switches at about 292 s, 250 s after the intro starts (the standalone ROM build: at about 240 s from boot); "ACCESS CODE: LDKD" |
| controls (`vmvars.lua`)                                  | UP: up/down -1, mask `0x08`; RIGHT: left/right 1, mask `0x01`; LEFT: -1, `0x02`; ACTION: action 1, mask `0x80`; HELP opens help          |
| play (`START_PART=03E82h` build)                         | UP held through the fall: Lester surfaces, climbs out, the beast appears, RIGHT walks him right                                          |
| keybed (`keys.lua`, `vmvars.lua`, `notering.lua`)        | C6: left/right 1; F5: -1; A5: up/down 1; G#5, A#5: -1; C2, C3: action; C6 held, then F5 too: right until C6 is released, then left       |
| ACTION or C3 in the intro                                | the water part (`3E82`) starts: about 5 s of loading, then the game; the keys pressed meanwhile arrive together                          |
| EXIT held 1.5 s, then NO, then DISK                      | "Continue Next?", the main screen, the DISK MENU: the panel works again                                                                  |
| song memory after leaving (`songsame.lua`, v5 v6 v7 v10) | byte-identical to before OK in all four                                                                                                  |
| a song in memory (`poke.lua` changes one byte)           | "AW: SAVE SONGS, SWITCH OFF+ON" for 4 s, then "Continue Next?"; the memory untouched                                                     |

Not checked: the real instrument; the game past the water part's opening on a converter build (it is the
same VM and data as the standalone build).

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
    KEYS="45:C6*1;47:F5*1;49:A5*1;51:G#5*1;53:A#5*1;55:C3*1" VV_FROM=44.6 VV_PERIOD=0.5 SEQ="25:DISK;28:L3;33:R4;58:quit" \
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
| `probes/keys.lua`                                  | holds keybed keys on a schedule (`KEYS="t:C4*0.5"`, MAME's key names)                                          |
| `probes/notering.lua`                              | the keybed note ring: each byte written, its indices, AW.CNV's held-key map                                    |
| `probes/subpkt.lua`                                | the sub CPU's packets to the main CPU (header and payload)                                                     |
| `tools/find_noterng.py`                            | the keybed note ring's address in each firmware version, found as AW.CNV finds it                              |
