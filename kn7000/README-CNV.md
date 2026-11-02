# Another World on a stock KN7000, through the SD loader (no SP7001)

The same Another World VM as the SP7001 build ([README.md](README.md)), started a different way, the
one the owner's KN7000 runs all custom code with: **`KN7LOAD.CNV`**, the generic loader on his
existing write-protected floppy, loads an application, **`KN7APP.BIN`**, from the SD card. The game
is such an application. Nothing new goes on the floppy: the game and its files go on the SD card.

The loader is the ROM dumper's (technics-roms-disasm `kn7000/tools/cnv_romdump`), unchanged since
its release on 2026-10-19 (`KN7LOAD.CNV` SHA-1 `6b81f382fd29b9bc5a025854af0e20a194e68bec`). The
KN7000's DISK MENU > STYLE CONVERT runs it like any style converter. It finds the firmware's SD file
routines, reads `KN7APP.BIN` from the card's root folder, checks it and calls it on every converter
call. The game finds the rest of what it needs in the firmware by itself, so the same card serves
every program build we know: **893** (v1.3, the owner's), 935, **941** (v1.6) and 942.

> **Status (2026-10-20): runs in MAME on program 893 (`-bios v13`) and program 941 (`-bios v16`)
> through the owner's loader floppy, and leaves the instrument's stored data and the loader alone.**
> The game lives only in the work RAM STYLE CONVERT leaves to a converter, above the loader, loads
> each part's files from the SD card when the part starts, and refuses any write outside its own
> RAM. In the overlay emulator, which models IC23 (the battery-backed panel memories), a whole
> session ending with POWER OFF leaves IC23 and the user-memory pools byte-identical to a session
> that ran a do-nothing application instead, the next boot accepts them, and nothing but the loader
> wrote the loader's memory. Results and evidence: "How it was checked". **It ran on the owner's KN7000
> on 2026-10-20, very slowly**; the build here blits only what changed, paints the border once and
> measures its own speed on the instrument ("Speed").

Contents: [What goes where](#what-goes-where) · [Building](#building) · [Before the first run on the
instrument](#before-the-first-run-on-the-instrument) · [Playing it](#playing-it) · [Replaying a session](#replaying-a-session) · [How it works](#how-it-works) ·
[Sound](#sound) · [Speed](#speed) · [The screen](#the-screen) · [The firmware's screen](#the-firmwares-screen) · [Memory](#memory) · [How it was checked](#how-it-was-checked) · [What MAME cannot
settle](#what-mame-cannot-settle) · [Limits](#limits) · [History](#history-the-awcnv-floppy-retired)

## What goes where

**The floppy: the one you already have.** It holds `KN7LOAD.CNV` alone, as released on 2026-10-19
(technics-roms-disasm `kn7000/tools/cnv_romdump/releases/2026-10-19/floppy/`: `KN7LOAD.CNV` SHA-1
`6b81f382fd29b9bc5a025854af0e20a194e68bec`, the image `kn7load_floppy.img` SHA-1
`b7a67de602694fd2257d59ce4509ca154b0b3064`). Nothing is added to it or changed on it; keep its
write-protect tab at PROTECTED. Every MAME test below runs this very image.

**The SD card: everything in `build/sdcard/`, copied to the card's root folder.** `make sdcard`
writes exactly these 62 files there and nothing else (their sizes and SHA-1s: `build/sdcard.txt`):

| file(s)                              | bytes   | what                                                                                                                  |
|--------------------------------------|---------|-----------------------------------------------------------------------------------------------------------------------|
| `KN7APP.BIN`                         | 40,620  | the game: application header, platform layer, firmware search, VM, unpacker, speed measurement, sound, settings, LEDs |
| `AWFONT.AW`                          | 768     | the 8x8 font (the KN5000 port's)                                                                                      |
| `AWSTRIDX.AW`, `AWSTRDAT.AW`         | 6,144   | the string tables (the KN5000 port's)                                                                                 |
| `AWSND.AW`                           | 584     | each sound's KN7000 program, note and length, for the tone generator mode ("Sound"; `tools/aw_sound_map.py`)          |
| `AWBANK.AW`                          | 2,952   | where each sound of the DSP's sample bank is in its SDRAM, the bank's id and checksum ("Sound"; `aw_extract.py`)      |
| `AWR07.AW` ... `AWR91.AW` (42 files) | 566,944 | each resource the game draws, runs or plays as music, as `MEMLIST.BIN` finds it in `BANKxx`                           |
| `AWSB0.AW` ... `AWSBD.AW` (14 files) | 431,724 | the DSP's sample bank, the 93 sounds the game plays, Rice-coded for the DSP to decode (`tools/dsp_bank.py`)           |

1,044,172 bytes in all (`build/sdcard.txt` lists every name, size and SHA-1), well within the 126.5 MB free on
the owner's card.
Each `AWRxx.AW` holds the exact bytes the original MS-DOS release's `MEMLIST.BIN` points at in its
`BANKxx` file, ByteKiller-packed or stored, for every palette, bytecode, polygon set and bitmap and the
two music modules (`AWR07.AW` the intro's, `AWR8A.AW` the final part's). The 93 sounds the game plays
(its sample bank: "Sound") are in the `AWSBn.AW` files since 2026-10-21, coded as the DSP decodes them;
before that they were 93 more `AWRxx.AW` files (`AWR01.AW` ... `AWR8E.AW`, 574,084 bytes), which the
card no longer needs: delete them when you copy this build over an older one. Everything is made from
your own copy of the game by `make sdcard` (`tools/aw_extract.py --parts`), and the part tables inside
`KN7APP.BIN` and `AWBANK.AW` are generated from the same `MEMLIST.BIN`, so the card must carry the files
the same build wrote.
`KN7APP.BIN`'s SHA-1 for the build in this repository and the MS-DOS release in `../../MSDOS/`:
`964e245addd985700168433cc461e6c56aa0c193` (the LCD at 8 bits a pixel through its look-up table, the ambilight
around the window: "The screen"; `build/sdcard.txt` lists it with the rest). Before it: `ccf024e4...` (384x240 pages
drawn at that resolution by default, PAGE DOWN 320x200, PAGE UP 384x240), `9a2f2db4...` (the 320x200
picture enlarged to 384x240 by repeating pixels; the overlay and the old blit gone), `cddfe76b...` (the screen
black while a part loads, the firmware's drawing off: "The firmware's screen"), `7b07e0f1...` (SHR shifts logically, found
by replaying Felipe's first input log), `6f58c18f...` (the input log, played on Felipe's KN7000 on
2026-11-01), `94910f68...` (round 3, `7f8ed09a...`: the coded bank, the keybed-only controls, the keybed-sound key;
then UP moved to A♭5 or B♭5). The builds before those that ran on Felipe's KN7000: `a2fbbaa6...`
(the DSP sound) and `97fbd9e6...` (the first sound build, tone generator only).

**With the program menu (2026-10-20): the game in a folder of its own, `AW\`.** The card's root
`KN7APP.BIN` can be the program menu (technics-roms-disasm `kn7000/tools/kn7menu`), which lists the
programs in the card's folders and starts the one picked as the loader would have. Its `make card`
puts this game in `AW\` (all 47 files of `build/sdcard/`, with a `MANIFEST.TXT` and an `ICON.BMP`)
beside the ROM dumper's passes 5 to 9, each in its folder, so nothing has to be swapped on the card any
more: copy the whole of kn7menu's `build/card/` to the card's root once. "Continue Next?" YES then
brings the menu back instead of a new game.

The game reads its files from the folder it was started from. The menu leaves a launch block at
`0x502E7F00` (the loader's contract, `kn7cnv.inc` `LB_*`) with the folder's 8.3 name; on its first call
the game copies the block's prefix, `AW\`, into `AW_PREFIX` (`cnv_main.s` `LaunchFolder`), and opens
every file as that prefix and its name (`AppPath`: `AW\AWR11.AW`), through the loader's `SV_OPEN` as
before. The loader zeroes the whole application area, the block included, before it loads anything,
so **the game still runs from the root without the menu**: the prefix stays empty and the names are the
old ones (below). Opening a file in a folder is the one thing this adds: the firmware's FAT library
walks the path, as it does for its own SD screens; from a converter that has run only in MAME so far
(probes/cnv/README.md, "Through the program menu").

**Without the menu: the root.** `KN7APP.BIN` and the game's files in the card's root, as before. The
card's root `KN7APP.BIN` is then the game; copy the one there first if it is something else. Only one
application is in the root at a time, since the loader always loads `C:\KN7APP.BIN`.

**Why the root was the first choice.** The loader empties the SD card's current folder around every
call, so names are looked up in `C:\`, and the root is where the loader itself reads `KN7APP.BIN` on the
owner's unit: the one way of reading the card that had already run on that instrument. The menu's
launch block now gives the game its folder without the optional `sdfmpath` service: a prefix in the
name needs nothing the loader may not have found.

## Building

As for the SD build (README.md: the MS-DOS release in `../../MSDOS/` and the KN5000 port's font and
string tables), with technics-roms-disasm beside this repository (`DISASM_REPO`: the assembler,
`sd_addfile.py`, and the loader's `tools/cnv_romdump`):

    make sdcard     # build/sdcard/ (also `make`): KN7APP.BIN and the 46 game files; build/sdcard.txt
    make app        # build/KN7APP.BIN alone: leafcheck, ic23_guard --loader ("clean"), assemble,
                    #   cnv_layout, then the loader's mkapp.py (header size and CRC-32)
    make kn7run     # the overlay emulator with the owner's loader floppy and a copy of the real
                    #   KN7000's SD card with build/sdcard/ added (BIOS=v13, the default: program 893;
                    #   BIOS=v16: 941); then DISK MENU, STYLE CONVERT, OK
    make fwfind     # tools/aw_find_fw.py: the game's firmware search over every program build

The build also checks that the loader it is laid out around is the owner's: `build/loader.ok`
compares `KN7LOAD.CNV` and its floppy image with the SHA-1s above. `tools/leafcheck.py` stops the
build when a routine entered with `call X, 0, 0` calls another before making a frame of its own; on
the MN10300 that nested call overwrites the return address.

## Before the first run on the instrument

These were the safeguards for the first run on the owner's unit (2026-10-20; it ran). MAME runs the
owner's own program 893 and the very floppy image above, but not the real chip's timing nor the real
card. The speed build adds one thing the earlier one never did: at each quit it writes a new
`AWPERFn.TXT` to the card's root, so back the card up first as in step 1. So the first run is made with a record of IC23 (the
panel memories and settings) before and after, taken by the ROM dumper's SURVEY2 pass, which already
ran on the unit (technics-roms-disasm `kn7000/tools/cnv_romdump/releases/2026-10-20-survey2/`):

1. Back up the whole SD card on the computer as an image, as before the dumper's passes
   (`sudo dd if=/dev/sdX of=kn7000-sdcard-backup.img bs=1M status=progress`; check the device).
2. Copy the card's present `KN7APP.BIN` to the computer (above). Save the panel memories the usual
   way too.
3. **SURVEY2 before:** copy `sdcard-pass5-SURVEY2/KN7APP.BIN` (SHA-1 `24bdc35d...`) to the card's root
   as `KN7APP.BIN`; run it (DISK MENU > STYLE CONVERT > `KN7LOAD.CNV` > OK, as before); copy the
   files it writes (`R*.BIN`, `DUMPLIST.TXT`, 56 MB) into a folder `before/` on the computer and delete
   them from the card.
4. Copy everything in `build/sdcard/` to the card's root (this replaces `KN7APP.BIN` with the game's).
5. Play (next section): into at least one part switch, open HELP, quit with EXIT held and **NO**.
   Then switch the instrument off and on.
6. **SURVEY2 after:** put SURVEY2's `KN7APP.BIN` back in the root, run it, copy its files into
   `after/`.
7. Compare IC23, on the computer, from this repository's `kn7000/`:

       head -c 262144 before/R8400000.BIN > before-ic23.bin
       head -c 262144 after/R8400000.BIN > after-ic23.bin
       python3 -I probes/cnv/ic23_diff.py before-ic23.bin after-ic23.bin
       python3 -I probes/cnv/ic23_file.py after-ic23.bin

   The PANEL MEMORY store `0x824`-`0x30173` must show 0 differing bytes, and `ic23_file.py` must say
   `match=True` (the header checksum the firmware stamped at power-off). Bytes in the header (the live
   settings) may differ where a setting was changed: R1/R2 OCTAVE + / - and SUSTAIN keep doing their
   own job while the game runs (below). `cmp before/R5018000.BIN after/R5018000.BIN` compares the
   user-memory pools the same way; report any difference rather than judge it, since the firmware
   may change live data there between two power-ons.

If anything looks wrong, write the card image from step 1 back and restore the panel memories.

## Playing it

1. Switch on and wait for the main screen. Insert the floppy and the SD card.
2. **DISK MENU**, then **STYLE CONVERT** (left button 3). The list shows `KN7LOAD.CNV`. Press **OK**
   (right button 4).
3. The loader's screen flashes by. As soon as the game is first called, the whole LCD goes black and
   "Loading... NN%" counts up in its middle: the firmware search, the font, the strings, the sound tables and
   the shared polygons, then, the first time after the instrument was switched on, the game's samples going
   into the effects DSP ("Sound"; in MAME 11.6 s; HELP's first page shows how long it took on your unit), the
   sound's settling and the first part. At 100% the splash starts. Whenever the game moves to another part,
   the screen goes black for a moment while the part's files are read from the card.
4. The controls (the HELP screen shows them too, with the level codes). **The game is played on the keybed
   only** (or over MIDI IN 1, channels 1-3); since 2026-10-21 no panel button moves the player:

| game   | keybed (or MIDI IN 1, channels 1-3) |
|--------|-------------------------------------|
| up     | A♭5 or B♭5                          |
| down   | A5                                  |
| left   | F5                                  |
| right  | C6                                  |
| action | C4 or any key below                 |

   The panel's buttons are the port's own controls:

| what         | panel                                                                   |
|--------------|-------------------------------------------------------------------------|
| codes        | OTHER PART & FR: the level code screen                                  |
| help         | HELP; PAGE UP / PAGE DOWN turn pages; EXIT, HELP or any key returns     |
| settings     | HELP, then PAGE DOWN three times ("Settings", below)                    |
| sound        | PART SELECT RIGHT 2: the game's sound, DSP / TG / off (in the help too) |
| keybed sound | PART SELECT RIGHT 1: the instrument's own notes for your keys on / off  |
| screen       | PAGE UP: 384x240, high resolution (the default); PAGE DOWN: 320x200     |
| quit         | hold EXIT for 1.5 s                                                     |

   **The screen.** The game starts in its high-resolution mode: it draws at 384x240, the LCD's whole height,
   centred with black strips at the sides, in the original's proportions (6/5 of 320x200 both ways). The
   polygons are computed and filled at that resolution, not enlarged afterwards; the text keeps its 8x8 glyphs,
   pixel for pixel, each where the game puts it; the background bitmaps, which exist at 320x200 only, are
   enlarged (in every 5 pixels and rows one is doubled). PAGE DOWN switches to the original resolution, 320x200
   in the middle of the LCD, PAGE UP back; the pages are converted on the spot, so what was drawn before the
   switch keeps the other resolution's look until the game draws it again ("The screen", below).
   A♭5 and B♭5 are both UP, the black keys either side of A5 (DOWN); B5 is no control (Felipe,
   2026-10-21). With three keys down (an action key, a direction and up: run and jump) the keybed's
   scan matrix can lose either of them (`src/vm.inc`, `KBD_UP_NOTE_*`).

   **The keybed's own sound** (PART SELECT RIGHT 1). The instrument plays its own voice for every key
   you press to steer the game. RIGHT 1 mutes those notes and brings them back; the game's own sound
   (RIGHT 2) is separate. Every game starts with them on. The game mutes them with expression (MIDI
   CC 11) 0 on channels 1-3 (RIGHT 1, RIGHT 2, LEFT) through the firmware's MIDI IN path, and puts 127
   back when it leaves (EXIT held, the stop screen's EXIT, the firmware ending the converter) and at a
   new game. Expression is a live controller, not a panel setting: nothing is stored, and a power cycle
   resets it anyway. If an expression pedal is connected, moving it brings the sound back. The help
   screen's first page shows "KEYBED SOUND: ON" or "OFF".

   R1/R2 OCTAVE + / - and SUSTAIN no longer do anything in the game, but the firmware still does their
   own job while the game runs: OCTAVE + / - shift the R1/R2 octave, SUSTAIN switches sustain on and
   off. Those are ordinary setting changes, kept at power-off like any other (measured in MAME:
   `probes/cnv/awcnv_panelsettings.lua`); press them back afterwards if they matter. PART SELECT LEFT,
   RIGHT 1, RIGHT 2, HELP, OTHER PART & FR, PAGE UP, PAGE DOWN and EXIT changed no setting in the tests,
   and the firmware drew nothing on the LCD for them. **Do not press DISPLAY HOLD**: once in MAME it
   made the firmware repaint its screen and stop calling the game for good, so that EXIT could no
   longer end it (`probes/cnv/README.md`, "Speed").
5. **To quit, hold EXIT for 1.5 seconds.** The game writes its speed figures to a new file in the
   card's root (`AWPERF0.TXT`, then `AWPERF1.TXT`, ...: "Speed"), and the rest of its input log
   (`AWIN00.BIN` ...: "Replaying a session"). Started from the program menu (the game in its `AW\` folder),
   it goes straight back to the menu: it reads `C:\KN7APP.BIN`, checks it as the loader does, and starts it
   through the menu's own trampoline (`src/chain.s`), so no firmware message and no "Continue Next?" come
   between them (in MAME the menu was back 5.5 s after EXIT went down, the 1.5 s hold included). Started by
   the loader from the card's root, or if the menu cannot be read or is damaged, it ends as before: the
   firmware shows a message box; press EXIT, and it asks **Continue Next?** **NO** (right button 4)
   returns to the main screen. **YES** (right button 3) makes the loader read `KN7APP.BIN` again and
   starts a new game from the beginning, firmware search included. A short EXIT press still closes the
   help screen.
6. **The game's end.** After the credits the game's last words scroll up ("Now Go Out Of This World") and
   the picture stops for good, as in the original. Then any key of the keybed (or MIDI IN 1) starts the
   intro again, and so do 3 seconds of the still picture (`src/interp.s` EndCheck: part 0x3E87's string
   0x265, then 100 frames of scrolling).
7. If the firmware is one the game does not recognise, or a game file is missing or damaged, the
   screen says so ("AW: UNKNOWN FIRMWARE, STEP n", "AW: A GAME FILE IS MISSING OR BAD") and EXIT ends
   it; nothing has been written outside the game's RAM. Step 2 of the search is the loader's service
   table: "STEP 2" means the floppy's loader is not the one the game was built for. If `KN7APP.BIN`
   itself is missing or damaged, the loader says so on its own screen and ends after about 15 s.

## Settings

The help screen's fourth page (HELP, then PAGE DOWN three times; "SETTINGS 4/4") holds five settings. They are
chosen and changed on the keybed, with the game's own direction keys: **UP** (A♭5 or B♭5) and **DOWN** (A5)
choose a row, **LEFT** (F5) and **RIGHT** (C6) change it. A change applies at once, behind the page:

| setting       | values                         | default | what it does                                                           |
|---------------|--------------------------------|---------|------------------------------------------------------------------------|
| resolution    | 384x240, 320x200               | 384x240 | the display mode the game starts in (PAGE UP / PAGE DOWN still switch) |
| ambilight     | on, off                        | on      | the glow the picture casts into the black strips at the LCD's sides    |
| light scatter | short, medium, long, very long | long    | how far that glow reaches into the strips                              |
| keybed sound  | on, off                        | on      | the instrument's own notes for the keys that steer the game (RIGHT 1)  |
| LED effects   | on, off                        | on      | the panel LEDs following the game ("The panel's LEDs")                 |

The KN7APP.BIN build keeps them on the SD card, in `AWPREFS.CFG` in its root (16 bytes: "AWP1", then one byte
a setting in the order above, then zeros; `src/prefs.s`). The game reads it at the start, before the first
part, and writes it, over the old one, at the first converter call after a change with no panel button down
(while no part is loading), and at the quit if a change is still unsaved. A missing or unreadable file means the
defaults; a write that fails is counted (not retried) and the next change writes the file again. Checked in MAME by `probes/cnv/run_prefs.sh` (two runs: the
settings changed on the page, then read back from the card on the next start).

## The panel's LEDs

With the LED effects on (the default), every LED of the panel goes dark once the firmware search is done (while
"Loading..." still counts), and from then on only the game lights them (`src/leds.s`):

| moment                                          | LEDs                                                                       |
|-------------------------------------------------|----------------------------------------------------------------------------|
| a guard's laser shot                            | every red LED on for 150 ms                                                |
| Lester's laser shot                             | the red LEDs on the half of the instrument he shoots towards, 150 ms       |
| Lester's gun charging (a shield or a big blast) | the eight PANEL MEMORY LEDs pulse (200 ms on, 200 off)                     |
| the charge grown to the big energy blob         | the same, twice as fast                                                    |
| the big blast                                   | every LED on while the blast shows (the beam and its impact, about 0.9 s)  |
| the gun recharging at a station                 | every green LED on for the 1.4 s the station's sparkles last               |
| by the waterfall (the caves)                    | LEDs at random every 50 ms: half on its two screens, an eighth beside them |
| the intro's lightning                           | every LED on for 150 ms at each flash                                      |
| the intro's thunder                             | every LED on for 100 ms at each loud clap                                  |
| the lightning striking the lab                  | every LED blinks three times                                               |

At the quit the LEDs go back to what the firmware has them showing; with the LED effects turned off in the
settings, at once (and the game leaves them to the firmware from then on).

The moments are recognised in the game's own bytecode as it runs, the way the reference VM's event log showed them
(research-scratch `kn7000-aw-reference/fingerprints`): a sound and which thread plays it (lasers, the charge, the
waterfall's loop, sound 0x6A, whose volume on its channel gives the share of LEDs lit), a variable (the blast,
var 0x88; the recharge, var 0x06 set to 1000; Lester's facing, var 0x04), a palette (the intro). The red LEDs'
halves are split at the middle of the instrument by where each LED is on the panel (the MAME layout), their colour
by the service manual's parts list (`probes/ledmasks.py`). The game writes the firmware's own LED shadow, so the
firmware's 24 ms flush carries the pattern; any LED the firmware changed meanwhile keeps the change when its LEDs
come back, and the game asks the firmware to redraw the LEDs of its
own state, all its refresh groups but the one that re-applies the LED freeze: that routine zeroes the firmware's
record of what the panel shows, and run before the flush had sent the restore it left the LEDs set back to off
still lit (seen in MAME: `probes/cnv/README.md`, "The panel's LEDs"). The shadow's address is known for programs
893, 935, 941 and 942; on any other build, or with the LED effects off, the game leaves the LEDs alone.

Checked in MAME by replaying sessions with an LED log (`probes/cnv/awcnv_inplog.lua`, `AW_LEDLOG`) and comparing
it with the reference VM's events of the same sessions (`probes/ledcheck.py`): every laser (each of Lester's on his
side), charge, blast, flash, clap and strike lit its pattern, the LEDs were dark in every frame without an effect,
the recharge and the waterfall lit theirs, and MAME's panel followed (`probes/cnv/README.md`, "The panel's LEDs,
second round"). The LEDs on the instrument itself have been seen with the first round's effects only.

## Replaying a session

Every game keeps an **input log** (`src/inplog.s`): everything the VM was given from outside, frame by frame, so that
what was played on the instrument can be played again exactly in MAME and in the reference VM, and the two compared
frame by frame to find where the port's VM goes wrong. The VM is otherwise deterministic (GameReset fixes the random
seed), so the log holds:

| record   | what                                                                                                                                                                                                             |
|----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `I`      | the input ReadInput applied, from that frame on: the mask it wrote to var 0xFE, and its mode (in the intro only var 0xFA and 0xFE are written; elsewhere the six hero variables, which all follow from the mask) |
| `M`      | a sync mark of the music (var 0xF4), and the first thread that saw it: the module player writes them on the kernel's clock, between two threads or in the yield at a frame's end, and the intro waits for them   |
| `R`      | the part the panel asked for (OTHER PART & FR, the code screen)                                                                                                                                                  |
| `P`      | a part switch (to check that a replay keeps step)                                                                                                                                                                |
| `H`, `E` | each file's header (the session, the file's number); the end (records lost for want of room)                                                                                                                     |

The game writes the log to the SD card's root folder as it fills, 1,008 records at a time, as `AWIN00.BIN`,
`AWIN01.BIN`, ... (8 KB each; 2,032 records and 16 KB until 2026-11-02), between part loads and while no panel button is down, and the rest when you quit
(EXIT held). A record is 8 bytes; inputs change a few times a second, so a file holds several minutes. A new game
writes over the last one's files; quit before switching off, or the last few minutes are lost. KN7000
`update_sdcard.sh` brings the files back with the card's other root files.

To replay and compare (`probes/cnv/README.md`):

    python3 tools/aw_inplog.py FOLDER -o session.awr          # the AWIN*.BIN files as one text file
    probes/cnv/run_inplog.sh OUT replay session.awr           # MAME: the session replayed, its pages (OUT/pages.log)
    replayawr session.awr ref.log                             # rustyworld (research-scratch kn7000-aw-reference/replay-mods)
    python3 probes/compare_frames.py OUT/pages.log ref.log    # the first frame where they differ, and the rest
    REF_VARS=ref.vars replayawr session.awr ref.log           # rustyworld, with its 256 variables at every frame
    python3 probes/varsdiff.py OUT/vars.bin ref.vars          # the first variable to differ, and when
    python3 probes/pagediff.py OUT/pages.bin REF.bin FRAME -o DIR  # both pages side by side, the difference in red
                                                              # (REF_BIN=REF.bin replayawr ... writes rustyworld's)

`awcnv_inplog.lua` gives MAME's game what the log says, where the log says it: the input at ReadInput's last write,
the marks when NextThread picks the thread that saw them first, or at the frame's end when no later thread runs (the
module player's own are undone), the requests after ReadInput. `replayawr` does the same in rustyworld (`Vm::run_awr`), starting with the port's splash.
`run_inplog.sh OUT record` plays a scripted session in MAME and logs it, for testing the log itself.

## How it works

Traced in the firmware (technics-roms-disasm `kn7000/notes/style-converter.md`), in the loader's
source (`kn7000/tools/cnv_romdump/loader.s`, `kn7cnv.inc`) and measured in MAME (`probes/cnv/`):

- **STYLE CONVERT** zeroes `0x30000` bytes at `0x502B8000`, reads the chosen `.CNV` there whole, and
  calls its first byte (`calls (a0)`) on the firmware's **main task** (941 `0x48479929`, 893
  `0x48479766`). When the converter returns, the firmware reads a request from the mailbox at
  `0x5031BC00`, serves it, writes `0xFF` and calls again.
- **The loader** (`KN7LOAD.CNV`, 6,064 bytes) is that converter. On its first call it finds the
  firmware's SD file routines by searching the program flash (on the owner's 893 it found the fmm
  dispatch tables and called the SD backends directly), fills its **service table** at `0x502B9E00`,
  zeroes `0x502BA000`-`0x502E7FFF`, reads `C:\KN7APP.BIN` to `0x502BA000` in 16 KB pieces and checks its
  header (magic, loader ABI, link address, size, entry) and its CRC-32. From then on **every converter
  call goes through the loader to the application's entry**, with the SD card's current folder
  emptied around it (names are relative to `C:\`); the application sets the mailbox request itself.
  When it answers `0xFE` and "Continue Next?" is answered YES, the next call loads `KN7APP.BIN` afresh.
  The loader stays resident below `0x502BA000` all along: its code, its line buffer, its variables and
  the service table.
- **One step per call.** Every call of the game does one step and answers **request 5**, "show this
  text" (`LOADING ANOTHER WORLD`, then `HOLD EXIT TO QUIT`). The firmware keeps calling, about 20
  times a second, which parks the user interface on the converter: the firmware doesn't repaint the
  screen under the game and ignores EXIT, while the main task goes on decoding the panel and passing
  the keybed's notes to MIDI OUT, the two inputs the game reads (probe 2 in `probes/cnv/README.md`).
- **Finding the firmware** (`src/fwfind.s`, the first eight calls). `KN7APP.BIN` carries no firmware
  address. It searches the program flash and the kernel library in RAM by code signatures, the way the
  loader does, and accepts a find only when it is unambiguous and cross-checked:

| step | what                                          | found by                                                                                                                     |
|------|-----------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| 0    | the panel switch bitmaps                      | the panel decoder's two sites, which must agree (CPL = CPR + 0x30)                                                           |
| 1    | the firmware's yield, the millisecond counter | the yield routine in the library and the tick handler, which must agree, and agree with the loader's own find of the counter |
| 2    | SD open, read, close, the drive switch        | the loader's service table: magic `KN7S`, loader ABI 1, file access found                                                    |
| 3    | `cre_tsk`, `sta_tsk`                          | the firmware's own "cre_tsk then sta_tsk(N, 0)" call sites: all must agree                                                   |
| 4    | `exd_tsk`                                     | the firmware's tasks that end themselves: all must agree, a kernel stub                                                      |
| 5    | the MIDI IN 1 and MIDI OUT 1 rings            | the library's per-port ring wrappers                                                                                         |
| 6, 7 | the effects DSP's host-port routines          | DSPTONE's search, one signature a call (`src/dsp.s` DspFind); not found: the game goes on with the tone generator ("Sound")  |

  `tools/aw_find_fw.py` runs the same searches (all but step 2) over every program image we have; the
  loader's `find_fw.py` runs the loader's:

| what         | 893 (v1.3)   | 935 (v1.5)   | 941 (v1.6)   | 942 (SP7001) |
|--------------|--------------|--------------|--------------|--------------|
| cre_tsk      | `0x4C03D0B5` | `0x4C03D0C8` | `0x4C03D0C8` | `0x4C03D46B` |
| sta_tsk      | `0x4C03D898` | `0x4C03D8AB` | `0x4C03D8AB` | `0x4C03DCD3` |
| dly_tsk      | `0x4C03DD5C` | `0x4C03DD6F` | `0x4C03DD6F` | `0x4C03E295` |
| exd_tsk      | `0x4C03D58E` | `0x4C03D5A1` | `0x4C03D5A1` | `0x4C03D944` |
| kernel_ms    | `0x500C53F8` | `0x500C541C` | `0x500D3C58` | `0x500D3C68` |
| panel_cpr    | `0x5006BE4C` | `0x5006BE50` | `0x5006BE50` | `0x5006BE60` |
| panel_cpl    | `0x5006BE7C` | `0x5006BE80` | `0x5006BE80` | `0x5006BE90` |
| midiin1_rxq  | `0x5001F020` | `0x5001F024` | `0x5001F050` | `0x5001F060` |
| midiout1_txq | `0x5001F834` | `0x5001F838` | `0x5001F864` | `0x5001F874` |

  Step 2 takes the SD routines the loader found: on 893 its service table hands over the SD backends
  themselves (open `0x48564A88`, read `0x48564D70`, close `0x48564B4F`; the drive switch is the loader's
  no-op), the same `open` the loader reported on the owner's unit. The loader's `find_fw.py` finds
  the same kind of table in 935, 941 and 942.

  The 941 and 942 columns equal the addresses measured in MAME before; in MAME, the game's own search
  gives the 893 and 941 columns exactly (the session test prints them).
- **The global files** (the next six calls): the font, the string tables, the two sound tables
  (`AWSND.AW`, `AWBANK.AW`) and the shared polygons (resource 0x11), one file per call. Then, when the
  effects DSP's routines were found, its mixer and the sample bank ("Sound"). Then the game starts a task
  of its own (`cre_tsk` / `sta_tsk`, ids 10 then 9, priority 3) that runs the VM.
- **Parts on demand.** Like the original engine, the game holds one part at a time. At a part switch
  the game task asks for the new part (`EnsurePart`) and yields until it is there. Each converter call
  then reads one of the part's files from the card's root into the part area, with the loader's
  routines (the drive switch to the SD card and back around it, a no-op where the loader calls the SD
  backends directly) and in 16 KB pieces, as the loader reads `KN7APP.BIN`, and unpacks it in place,
  as the original engine does (`tools/aw_extract.py` checks at build time that every such resource
  unpacks right in place). The bitmaps a part's bytecode LOADs stay packed until LOAD draws one; they
  are unpacked into a buffer of their own (`BitmapData`). A part's loads start only once no panel
  button is down (or after about 5 s), so that a button's release never arrives while the main task
  is busy in a file read; a file that fails to load is tried again on the next call, up to three
  times, before the game stops and says so.
- **Quitting.** The entry watches EXIT. Once it has been held for 1.5 s, the game task ends itself at
  its next yield (`exd_tsk`), and the next call answers **0xFE**, which ends the conversion; the
  loader notes it. The firmware shows its message box, then "Continue Next?". YES makes the loader
  read `KN7APP.BIN` again, which starts a new game from the firmware search on. NO goes back to the
  main screen.

## Sound

The sound has three modes, and **PART SELECT RIGHT 2** cycles through them: **DSP samples** (the game's own
sounds, played by the instrument's effects DSP), **tone generator** (the KN7000's own voices over MIDI, the first
iteration) and **off**: DSP, then tone generator, then off, then DSP again (off goes to the tone generator when
the DSP cannot be used). RIGHT 2 works in the HELP screen too, and its first page shows the mode at once:
"NOW: DSP SAMPLES", "NOW: TONE GENERATOR" or "NOW: OFF", with "NO DSP n" after it when the DSP was given up (n
below); under it "KEYBED SOUND: ON" or "OFF" (PART SELECT RIGHT 1, "Playing it"), and on the right how long the
sample bank took ("SENT IN 11.4 S", "CHECKED IN 0.3 S" when it was already there, or "NOT LOADED"). The game
starts in the DSP mode when it could set the DSP up, else in the tone generator's. In every mode the module
player runs and writes its sync marks into var 0xF4 as before, so the intro keeps its timing.

**The volume.** The DSP mixer's output gain is 2 since 2026-11-02 (MIX = the voices' sum x 2; it was 128), the
ProTracker port's value: there, on the owner's unit, 128 gave a comfortable level only at the bottom of MAIN
VOLUME's travel (kn5000_homebrew 26bd920). 2 is 36 dB below 128. `make DSP_GAIN=n` builds another (1 to 128, each
doubling 6 dB louder; `tools/dsp_mixer.py --gain`). This game's level at 2 has not been measured, in MAME or on the
unit; the 36 dB is the gain ratio.

### The DSP mode (iteration 2, 2026-10-21): the game's own samples

**On the instrument (2026-10-21, Felipe's report, `KN7APP.BIN` `a2fbbaa6...`, program 893):** the sounds play
perfectly, with REVERB on and with REVERB off (on is a little louder); the game's level is close to a piano note's;
nothing garbled or stuck; no "NO DSP" shown; reverb and chorus both came back after quitting. The bank's first
load felt slow (26 s in MAME; not timed on the unit): since round 3 (2026-10-21, `7f8ed09a...`) it is coded and
decoded by the DSP, 11.6 s in MAME (below).

The KN7000's tone generators play only their wave ROMs, so sound of the game's own has to come from the effects
DSP (IC306, an ADSP-21065L with 1M words of SDRAM), which the firmware host-boots and keeps running its own
effects kernel. Iteration 1, DSPTONE (technics-roms-disasm `kn7000/tools/dsptone`), put a program of ours into
it through the firmware's own host-port routines, as one effect unit of that kernel, and it played on Felipe's
KN7000 on 2026-10-21 (a 440 Hz tone and a PCM sweep from SDRAM; heartbeat 44,087 frames a second; the reverb
back after STOP). The game does the same with a sample mixer (`tools/dsp_mixer.py` builds it, `src/dsp.s` drives
it):

- **The bank, once.** Every sound the game plays (PLAY_SOUND, LOAD, or a music instrument): 93 of the release's
  sound resources, 684,980 samples. Four 8-bit samples go in a word: 171,576 words of SDRAM from `0x70000` (the
  kernel's delay rings end at `0x69D3F`; DSPTONE's PCM at `0x70000` played on the unit), each sound from a word
  that is a multiple of 8 past the first, with `AWBANK.AW` saying where each one is. The host port moves one
  16-bit half per DSP frame (the firmware's handshake: 44,100 a second, 22.68 us on the unit), so the bank is sent
  as little as possible:
  - **Coded** (`tools/dsp_bank.py`, since 2026-10-21): the SDRAM image is cut into 837 blocks of at most 128 DM
    words and Rice-coded, losslessly: each sample against the one before it, a k for every 64 samples, an escape
    after 12 zeros. 686,304 bytes become 431,724, 14 card files `AWSB0.AW` ... `AWSBD.AW`. The build decodes every
    block with a Python copy of the DSP's decoder and stops unless it gives the bank word for word. (A 4-bit
    ADPCM would halve it, lossy, for little more: not used.)
  - **Sent and decoded**: at the start, after the global files, the converter reads one `AWSBn.AW` per call into
    `PART_AREA`, checks each block (its length, inside the file, inside the bank) and uploads it into one of two
    128-word staging buffers in the DSP's internal memory, while the mixer's decoder (unit 0) turns the block in
    the other one into SDRAM, 20 bits of the stream a frame; a block is handed over (MSGR5 the buffer, MSGR4 = 1)
    once the decoder has finished the one before (MSGR4 reads 0). "LOADING ANOTHER WORLD: SOUNDS" and the load bar
    meanwhile, 400 ms of it per converter call.
  - **Checked**: then the DSP computes a checksum of the 171,576 words it wrote, read back from SDRAM (rotate left
    by one, xor the word: MSGR4 = 2, the answer in MSGR5, 16 words a frame, 0.24 s), and the bank is used only when
    it equals the one in `AWBANK.AW`; otherwise "NO DSP 13" and the tone generator. (Before 2026-10-21 nothing of
    the bank was read back; the mixer and its variables still are, word for word, before the hook.)
  - **Once per power-on**: the mixer's marker in DSP memory ("AWS2" and the bank's id, a CRC-32 of its layout and
    samples) tells a later run (YES at "Continue Next?", or the game started again from the menu) that the bank
    is there; that run only asks for the checksum, and sends the bank again if it differs.

  Where the time goes, in MAME (`probes/cnv/awcnv_round3.lua`, `AWR_MODE=bank`, program 893, through the menu):

| part                                   | before (`a2fbbaa6...`, 93 `AWRxx.AW`) | now (`7f8ed09a...`, 14 `AWSBn.AW`) |
|----------------------------------------|---------------------------------------|------------------------------------|
| reading the card                       | 10.19 s (574,084 bytes, 93 files)     | 3.88 s (431,724 bytes, 14 files)   |
| ByteKiller unpacking                   | 1.74 s                                | none                               |
| host-port traffic and our own work     | 12.26 s                               | 7.52 s                             |
| handshakes (one DSP frame each)        | 359,792                               | 238,642                            |
| between converter calls                | 1.68 s (97 calls)                     | 0.22 s (29 calls)                  |
| in all, from the DSP setup to the game | 25.87 s                               | 11.62 s                            |

  On the unit the handshakes take one DSP frame each (pass 8: 96.8 % of the firmware's accesses), 8.16 s before
  and 5.41 s now; MAME's took 34 and 31.5 us each. If the card and the CPU go as in MAME, the unit should take
  about 9.5 s where it took about 22; the HELP screen's first page shows the time it took ("SENT IN ...").
  The whole bank rather than a part's sounds at each part switch: one wait, no pause added to the part
  switches, and no list of which part needs which sound.
- **The mixer.** 303 SHARC instructions at PM `0x8140` (the bank's decoder and checksum included), eight voices: PLAY_SOUND's four channels on voices 0-3
  and the music's four on 4-7, as rawgl's mixer and module player keep them apart (the tone generator mode does
  the same with its note slots). Per voice: a start in SDRAM, a 16.16 position and step (PLAY_SOUND's
  frequency, `freqTable`, or the module's Amiga period, 7,159,092 / (2 x period) Hz, over 44,100 frames a
  second), the end, the loop (a sound plays its first part once and repeats its loop part, as the original's
  mixer) and the volume (0-63). The nearest sample, no interpolation; the sum times 128, so one voice at full
  volume peaks at -18 dBFS. It costs at most about 650 of the 1,360 instruction cycles a frame has (all eight
  voices sounding, a command and a copy step in one frame; 10 a silent voice, 39 a sounding one), less than the
  reverb and the chorus it stands in for.
- **Commands.** The game task fills a five-word record per voice (start, step, end, loop, volume) and a mask
  (start, change step and volume, stop) in RAM; at every poll (each VM thread switch and every 4 ms of a yield)
  it waits until the mixer has taken the last mask (MSGR6 reads 0), uploads the records that changed into DSP
  memory and writes the mask to MSGR6. The mixer applies it at its next frame and writes MSGR6 = 0. A sound
  effect or a row's notes so cost 20 to 100 DSP frames of host traffic (0.5-2.3 ms).
- **Where it is heard.** The mixer sits in two of the kernel's unit slots: unit 0 (PM `0x8080`, normally the
  panel REVERB), whose return is unit 0's input plus the mix, and unit 9 (PM `0x80A0`, normally the CHORUS),
  whose return is the mix alone. The tone generator mixes unit 0's return into the DAC only while REVERB is on
  (the crossfade `0x803A`; DSPTONE needed REVERB on). The CHORUS has no return register (kn7000_mame
  `notes/effect-return-routing.md`: its button moves only its send), so unit 9's return should be heard whatever
  REVERB and CHORUS are: that is the path for REVERB off. **Heard on the unit (2026-10-21):** Felipe hears the game
  properly with REVERB and CHORUS both off, and a little louder with REVERB on, when both paths carry the mix. The reverb and
  the chorus are off while the game's sound is on the DSP (their programs are not run; the keybed's notes go
  through dry). MAME mixes unit 9's return only while the CHORUS is on, so the MAME check below hears unit 0's.
- **Putting it back.** Leaving the DSP mode with RIGHT 2, quitting (before the game answers 0xFE), a failure
  while it is being set up, and the firmware ending the converter some other way (the game task notices that
  the converter has not been called for 5 s) all stop the voices and put both slots back as they were found,
  each read back, with MSGR4-MSGR7 at 0 and the external port's channel 8 as found: the firmware's reverb and
  chorus run again at once (their programs were never touched). The help screen, a part switch and LOAD 0 only
  stop the voices. Coming back to the DSP mode hooks the slots again. The keybed's own sound (PART SELECT RIGHT
  1) is put back on (expression 127 on channels 1-3) at every quit, at the watchdog and at a new game.
- **Safety, as DSPTONE.** Only the firmware's own host-port routines (found by DSPTONE's search, two more steps
  of the game's firmware search: 8 in all), with their lock, their per-frame handshake and their "DSP dead"
  guard: `tools/ic23_guard.py` now also refuses any reference to the port's addresses (`0x98000000`,
  `0x9C000000`). Before it touches anything: the dead flag, the kernel downloaded, SYSCON, channel 8, both slots
  read back as the kernel's "CALL (0x8xxx) (DB)" (a slot an earlier program of ours left pointing at PM
  `0x8100`-`0x82FF` is put back first). The mixer and its variables are read back and compared before the
  hook. No M0-M7 (the 893 and 941 kernels set them differently). The dead flag is checked at every step; if the
  firmware ever sets it, the game goes on with the tone generator ("NO DSP 10" or "12").

**Trying it on the instrument** (the first DSP build, `a2fbbaa6...`, ran on Felipe's unit as reported above; round 3,
`7f8ed09a...`, has run only in MAME):

1. Before starting: **REVERB on** (its lamp lit), MAIN VOLUME low to moderate, and a few notes played to hear
   the reverb and the chorus as they are.
2. Start the game from the menu. The first time after switching on, "LOADING ANOTHER WORLD: SOUNDS" and the
   bar stay a while (11.6 s in MAME, 25.9 s with the build before; the card and the chip decide here). Later
   starts only have the DSP check the bank (a fraction of a second).
3. In the intro you should hear the original game's own sounds: its music and its effects, not the instrument's
   voices. HELP's first page shows "NOW: DSP SAMPLES"; "NO DSP n" there means the DSP was not used (n above):
   note n. On its right, "SENT IN n S": how long the bank took on your unit (photograph it).
4. Then with **REVERB off**: quit, switch REVERB off on the main screen, start the game again (quick now). Is it
   heard, and how loud against REVERB on? That decides which of the two paths the instrument mixes.
5. PART SELECT RIGHT 2: the tone generator (the first iteration's GM sound), again: off, again: the DSP. The same
   inside HELP: its "NOW:" line changes at once.
6. Quit (EXIT held), then play a few notes: the reverb and the chorus should be as before the game.

What to report: whether the game's own sounds were heard with REVERB on and with it off; how loud against your
notes; anything garbled, clicking or stuck (a sound that keeps playing after the help screen, a part switch, RIGHT
2 or the quit); the help line ("NO DSP n"); how long the sounds took to load (HELP's "SENT IN n S"); whether the
reverb and the chorus
were back after quitting. **If anything goes wrong, switch the instrument off and on**: the firmware resets and
reloads the DSP at every power-on, and nothing of this outlives that (no IC23, no user memory, no card writes
but `AWPERFn.TXT`).

The `n` of "NO DSP n" (`src/dsp.inc`, `DF_*`): 1 the routines not found, 2 the DSP was already marked dead, 3 its
kernel never downloaded, 4 SYSCON or channel 8 not as the firmware leaves them, 5 a slot unreadable or not the
kernel's form, 6 the mixer read back different, 7 a hooked slot read back different, 8 a sound file missing or
damaged (an `AWSBn.AW`, or a block in it), 9 the decoder stopped taking the bank's blocks, 10 the DSP marked dead
while the bank was sent, 11 the firmware stopped calling the game (the slots were put back), 12 the DSP marked dead
while playing, 13 the DSP's checksum of the bank in SDRAM not the one in `AWBANK.AW` (the bank is not used).

### The tone generator mode (iteration 1, 2026-10-20)

The first iteration: sound effects and music, played by the KN7000's own tone generator, unchanged but for the
mode switch. **On the instrument (2026-10-21):** Felipe ran this build (`KN7APP.BIN` `97fbd9e6...`, from the menu's `AW\`)
on his KN7000 (program 893) and reported that the sound plays properly; no further detail was recorded.
The game never outputs a sample. It becomes a MIDI source inside the instrument (`src/audio.s`), and
the firmware plays its notes by its normal path, the one an external sequencer on MIDI IN uses.

- **The way in: the MIDI IN 1 receive ring.** The firmware's MIDI 1 receive ISR (941 `0x484B1E86`)
  takes each byte from the serial port and enqueues it into a byte ring in work RAM (lib `0x4C0249C5`,
  the enqueue `0x4C024CBC`: the byte at `wr`, `wr` + 1 wrapping at `last`, `free` - 1, nothing when
  `free` is 0); a firmware task dequeues and parses the bytes. The game's `MidiMsg` writes each whole
  message the same way, with interrupts masked (PSW IE off), so that neither the ISR nor a task switch
  can come in the middle; it never touches the read pointer. The ring is the one `fwfind.s` already
  finds for MIDI IN input (step 5; 893 `0x5001F020`, 941 `0x5001F050`). A full ring drops the message.
- **Which parts.** The KN7000's MIDI receive routing as initialised (owner's manual p.190): channels
  1-3 are RIGHT 1, RIGHT 2 and LEFT, the panel's voices; channels 4-16 are PART 4-16, the parts "for SMF
  playback or MIDI receive". The game sends only on channels 4-7 (the sound effects, one per AW mixer
  channel), 10 (the drums of both) and 11-14 (the music, one per module channel): **it never touches
  the panel's parts.** On those channels it sends reset all controllers and volume 100 at the start,
  then GM2 bank select (121/0, drums 120/0) and a program change whenever a channel needs another
  sound, and notes.
- **The sound effects** (opcode 0x18 PLAY_SOUND). Each sound resource has a GM program and the note it
  sounds at 8363 Hz, or a GM drum key: `tools/aw_sound_map.py`, a hand-made table from each sample's
  analysis (length, noise or tone, pitch), loaded at the start from the card file `AWSND.AW`. The
  frequency index moves the note by semitones, the volume is the velocity, the note lasts as long as the
  sample would at that rate (held while a looping sample plays); volume 0 stops the channel.
- **The music** (opcode 0x1A PLAY_MUSIC): rawgl's module player, on the kernel's millisecond counter.
  Each row, each of the four channels may start a note (an Amiga period, played as the nearest
  semitone, on the instrument's program), stop, change the volume, or set the **sync mark var 0xF4**.
  The marks are written as the original does, whether the sound is on or off: the intro reads them to
  time its scenes, and with them it follows the music (it reached the lake by itself in MAME, below).
  The module is loaded with its part's files (`AWR07.AW` with the intro, `AWR8A.AW` with the final
  part) into `MUSIC_BUF`.
- **When.** `AudioPoll` runs at every switch of VM thread and between 4 ms slices of every yield
  (`DLY_TSK`): the rows that are due, the notes whose time is up, the sound button. A part switch and
  LOAD 0 stop everything (as rawgl's `restartAt` and `stopAll`); the help screen sends all notes off
  and freezes the music; **quitting sends all notes off, all sound off and reset all controllers on
  every channel the game used**, before the game task ends.
- **PART SELECT RIGHT 2 takes the sound on to OFF** (all notes off, all sound off, nothing more is sent),
  and from OFF to the DSP; coming into this mode (from the DSP, or from OFF when the DSP cannot be used) sets
  the channels up again. The music player keeps running in every mode, so the intro's timing does not depend
  on the button.
- **MIDI IN as input now means channels 1-3.** The game's own notes go into the same ring as MIDI IN,
  so its note trackers count only channels 1-3 there (`MIDI_IN_CHANNELS`); the keybed is unaffected.

What was asked of the instrument for this mode: whether the intro's music and the effects sound at all;
which effects sound wrong or too loud (the resource ids are in `aw_sound_map.py`); whether any note keeps
sounding after the help screen, a part switch, the sound button or quitting; whether RIGHT 1, RIGHT 2 and LEFT
still have your voices afterwards.

## Speed

**Why it was slow on the instrument.** Every VM tick the old `KN7APP.BIN` (`b952c2aa...`) blitted the
front page to the LCD twice (the bytecode's own blit, then once more at the end of every frame) and
repainted the whole black border with each blit: 128,000 16-bit and 89,600 32-bit stores into the LCD
frame per tick, whatever had changed (counted in MAME: `probes/cnv/awcnv_perf.lua`). The LCD frame at
`0x9CE00000` sits on a 16-bit bus behind four wait states (the firmware leaves MEMCTR3 at `0x0424`):
on the owner's unit a 16-bit store there takes 439 ns, a 32-bit one 888 ns, a 16-bit load 694 ns,
where work RAM answers in one 15.6 ns cycle of the 64 MHz core from its cache (the ROM dumper's pass 9,
technics-roms-disasm `cnv_romdump`, 2026-10-20). So those stores alone took about 136 ms per tick, a
ceiling of 7 frames per second where the gameplay asks for 25 or 50. MAME gives the LCD no wait
states, so it showed none of it.

**What changed (2026-10-20).** One `KN7APP.BIN` that is faster and measures itself:

- **The blit writes only what changed** (`src/display.s` `BlitPage`; since 2026-11-02 `SHADOW` holds 4 bits a
  pixel and the comparison packs the page's pixels to match, eight at a time). `SHADOW`, a copy in RAM of the
  colour indices the LCD's window shows, is compared with the page eight pixels at a time; a group
  of four pixels that differs is written as two 32-bit stores of two pixels each, from a table of the
  RGB565 of every pair of indices that is rebuilt only when the palette changes. The LCD is never read
  back for this. A blit of the page the LCD already shows, when nothing has drawn on that page since
  (the end-of-frame blit, mostly), is skipped. A new palette rewrites the whole window.
- **The border is painted once**, and everything again only when something may have drawn over it:
  the first blit, a part's load and 5 and 30 frames after it, a switch of the display mode, the stop
  screen, every 500 frames, and whenever one of 47 sentinel pixels of the LCD (45 at 384x240: the
  border, a grid in the window), read after each yield to the
  firmware, no longer holds what the game drew there: about 33 us of LCD loads per frame. The firmware
  repaints its own text screen over the whole LCD now and then: in MAME, twice while the intro hands
  over to the lake, and once after DISPLAY HOLD. Before, every blit painted over it.
- **Spans, page fills and page copies** store 32 bits at a time (`src/vm.s`, `src/interp.s`): the same
  bytes, a quarter of the stores into work RAM.
- **A frame that has overrun its time yields 2 ms** to the firmware, no longer 8: the firmware's tasks
  get the CPU when they are ready whatever the yield asks; a longer yield only spins.
- **The measurement** (`src/perf.s`), below. Until 2026-11-02 PAGE DOWN also switched to the old blit
  (every pixel 16 bits at a time, the whole border on every blit, twice a frame, and the 8 ms yield) and
  PAGE UP showed the figures in the left border, so that one run on the instrument measured both;
  both are gone, and PAGE UP / PAGE DOWN now choose the display mode (384x240 / 320x200).

In MAME (`KN7APP.BIN` `26aabecb...`, the intro, ticks 1-300, mean per tick): the stores into the LCD
frame fell from 217,600 (about 136 ms at the unit's times) to 2,036 32-bit ones and 47 sentinel loads
(1.84 ms; most ticks a few hundred stores, the two full repaints after the intro's load 76,800 each);
the game's loads from the pages, from 141,694 to 45,931. In MAME's own time (no wait states, but the
instructions counted) the intro ran at 25.0 frames per second with the new blit and 8.7 with the old
one (`probes/cnv/README.md`, "Speed"). The picture is the same: the intro's 2,612 frames are identical
to the reference VM's; the whole LCD frame, checked at every one of 3,601 ticks of the intro and the
lake against what the old blit made of the same VM state (`probes/cnv/awcnv_lcd.lua`), was that picture
but at one tick, when the firmware was repainting its text screen and the next tick put it right; and
its snapshots every 100 ticks are byte-identical to the old build's.

**What else was looked at.** The code, the VM pages and `SHADOW` lie in work RAM's cached view
(`0x50...`; pass 9 read `CHCTR` `0x008F` on the unit: instruction and data caches on); only the LCD frame
is reached uncached (`0x9CE00000`), as it must be. The old pacing yielded at least 8 ms even after a
frame that had overrun; the yield (the firmware's, found at run time) rotates the ready queue until
the millisecond counter has advanced that far, so any ready firmware task runs whatever it asks and
a longer yield only spins: now 2 ms. In MAME the yield took what it asked (31.1 ms for 31.5 asked,
7.5 for 8.0 with the old blit): the firmware's tasks took little there; YIELD against ASKED on the
speed page says what they take on the unit. The rasterizer still keeps its per-scanline state in
variables in (cached) RAM and calls a span routine per scanline; in MAME's time polygons took about
1 ms per frame of the intro, the blit 8 (the comparison: 128 KB of loads a frame), so the unit's
figures should decide what comes next.

**Where the time goes, on the instrument.** The game times itself with the clock pass 8 of the ROM
dumper proved on the owner's unit: the kernel's millisecond counter and timer 4's down-counter
(`TM4BC`, 2001 counts per ms). Every frame is split into phases, summed over one-second windows, per
part and over the whole game, separately for each display mode (384x240, 320x200; until 2026-11-02 the
new and the old blit):

| phase    | what                                                                             |
|----------|----------------------------------------------------------------------------------|
| VM       | the interpreter, input, everything not below                                     |
| polygons | the polygon and string ops (`0x80`, `0x40`, DRAW_STRING)                         |
| page ops | page fill, page copy, a bitmap drawn                                             |
| blit     | the page to the LCD                                                              |
| border   | the border fill                                                                  |
| yield    | the end-of-frame yield to the firmware: the pacing, and the firmware's own tasks |
| (load)   | waiting for a part's files: not part of a frame                                  |
| (pause)  | the help screens, the stop screen: not part of a frame                           |

Before the game starts, a benchmark of a few milliseconds measures, on that instrument, the ns per
access of a register add, 16- and 32-bit stores and 16-bit loads to the LCD frame (in the top border
rows, which the game paints black anyway), 8- and 32-bit stores and loads to work RAM through the cache
and 32-bit loads through its uncached view; and the game reads the bus controller's registers
(MEMCTR0-7, `0x32000040`, `0x32000042`), the cache control (`CHCTR`), timer 4's mode and base.

The figures go to the SD card (the help screen's speed page gave way to the settings, 2026-11-02):

- **`AWPERFn.TXT`** on the SD card: at each quit, the game writes the speed page, the figures per
  part and per display mode, the counters, the benchmark and the registers in full to a new file in the
  card's root, `AWPERF0.TXT`, then `AWPERF1.TXT` ... `AWPERF9.TXT` (it never writes over a file; with
  all ten there it writes nothing). It uses the loader's routines as the ROM dumper does for its
  files on the owner's unit: drive switch, open, one write, close.

**On the instrument: what to do, photograph and send.** With the card files of this build
(`make sdcard`; the floppy as it is):

1. Start the game as usual. The benchmark runs during the loading screen (well under a second).
2. Let the splash and the intro play with no input for a minute or so (384x240), then press
   **PAGE DOWN** and let it go on a minute at 320x200. Skip to the lake with C4 and play a little in
   each mode (PAGE UP, PAGE DOWN).
3. Quit as usual (hold EXIT, EXIT, **NO**). On the way out the game writes `AWPERF0.TXT` (or the next
   free number) to the card's root. Send that file; it can be deleted from the card afterwards.

How to read the figures (all in ms per VM frame unless said otherwise; "last 1 s" is the last
one-second window):

| figure                 | meaning                                                                                       |
|------------------------|-----------------------------------------------------------------------------------------------|
| FPS, frames/s          | VM frames per second, loads and pauses left out                                               |
| FRAME, frame           | the time of a frame: the sum of the six lines below it                                        |
| LONGEST, longest       | the longest frame                                                                             |
| VM ... YIELD           | the phases (table above)                                                                      |
| ASKED, yield asked     | the yield the pacing asked for: var[0xFF] x 20 ms less the frame's work, at least 2 ms        |
| LOAD/S                 | ms of the last second spent waiting for a part's files                                        |
| PIXELS, LCD pixels     | the page's pixels the blits wrote to the LCD per frame                                        |
| REPAINT, repaints      | full repaints of border and window so far                                                     |
| ns per access          | the benchmark: ALU (one add), LCD w16 / w32 / r16, RAM w8 / w32 / r8 / r32, uncached r32      |
| bus 20-2E, 40 42 CHCTR | MEMCTR0-7, `0x32000040`, `0x32000042`, the cache control and TM4MD, as the firmware left them |

A frame should take what the bytecode asks (var[0xFF] x 20 ms, set scene by scene; in MAME the intro
ran at 25 frames per second, 40 ms a frame). When FRAME is longer, the phases say why; when YIELD is
much longer than ASKED, the firmware's own tasks took the CPU in the yield.

## The screen

**Two resolutions** (since 2026-11-02; Felipe asked for a true higher resolution in place of the enlarged picture
of the day before). The game's VM draws on four pages, and their size is the display mode's (`vm.inc` PG_W, PG_H):

| mode                      | pages   | window on the LCD       | button    |
|---------------------------|---------|-------------------------|-----------|
| high resolution (default) | 384x240 | x 128-511, all 240 rows | PAGE UP   |
| original                  | 320x200 | x 160-479, y 20-219     | PAGE DOWN |

At 384x240 everything the game computes in its 320x200 coordinates is placed at 6/5 of it and drawn at the page's
own resolution (`src/vm.s`, `src/interp.s`):

- **Polygons**: the zoom scaling of every bounding box, vertex and hierarchy offset is `byte * zoom * 6 / 320` (in
  place of `byte * zoom / 64`), and the polygon's centre `floor(6x / 5)`, `floor(6y / 5)` (`Scale`, `ToPgSigned`); the
  edges are walked and the spans filled on the 384x240 page, clipped to it. Whether a polygon is a single point is
  decided on its 320x200 values, as the original does.
- **Text**: each 8x8 glyph is drawn pixel for pixel, its top-left corner at 6/5 of the game's position
  (`DrawChar`, `ToPg`): the glyphs are not scaled, so they are as crisp as at 320x200; the gaps between letters are
  1 or 2 pixels (8 pixels of the game are 9.6 of the page).
- **Page copies with a vertical scroll** move the page by 6/5 of the scroll, in whole rows.
- **Bitmaps** (the background pictures some scenes load) exist at 320x200 only: they are drawn at that size and
  enlarged to the page (`display.s` PageUp: every 5 pixels and rows become 6, the first of each doubled).
- **The help screens and the stop screen** keep their 8x8 font the same way.

**Memory.** Four 384x240 pages take 368,640 bytes, which fill `0x50320000`-`0x50379FFF` exactly: `SHADOW` (what the
LCD's window shows, which the blit compares with) now keeps 4 bits a pixel, 46,080 bytes at `0x502C8000`, and the help
and stop screens are drawn in it rather than in a page of their own; a bitmap's 32,000 bytes of planes are unpacked
there too (the next blit then repaints everything); the input log moved to the 16 KB after the mailbox page
(`0x5031C000`), in 8 KB files. Nothing outside the game's RAM is used, on any program build.

**Switching** converts the four pages in place (`display.s` DisplayConvert: PageUp, PageDown, a few ms each): what
was drawn before the switch keeps the other resolution's look until the game draws it again, mostly at the next
scene. The game's logic does not see the switch: its variables never depend on the pages.

**How it was checked** (MAME, program 893; `probes/cnv/README.md`, "384x240 pages"):

- at 320x200 the pages are those of before: Felipe's session replayed (`run_inplog.sh`) matches rustyworld on all
  1346 frames and all 256 variables at every frame;
- the LCD shows the page, pixel for pixel, in both modes: every one of 3,601 ticks of the intro and the lake, with
  PAGE DOWN and PAGE UP twice each (`awcnv_lcd.lua`);
- at 384x240, the whole intro replayed with its sync marks (`run_inplog.sh`, `AW_HIRES=1`): all 256 variables equal
  rustyworld's at every one of its 3,218 frames (the resolution changes nothing the game computes), and each page
  brought down to 320x200 the way PageDown does it agrees with rustyworld's on 89.9 to 100% of the pixels, 96.0% at
  the median (`probes/hires_vs_ref.py`): the same scenes, the edges where the higher resolution puts them;
- the acceptance tests pass on programs 893 and 941, the display modes' check included.

**Speed.** In MAME's time, a tick of the intro (ticks 10-300, `awcnv_perf.lua`) took 61.3 ms at 384x240 and 48.8 at
320x200 (48.6 before these pages): 1.44 times the pixels to fill, copy and compare. On the instrument the polygons,
page operations and blit phases will grow about as much; the speed page and `AWPERFn.TXT` keep the two modes'
figures apart.

**The LCD at 8 bits a pixel, and the ambilight** (since 2026-11-02, `src/lcd8.s`; Felipe asked for the black sides to
glow with the picture's colours, by palette changes alone). The LCD controller (an S1D13806) can show its display
memory at 8 bits a pixel through a 256-entry look-up table of 4 bits a channel, the original game's own colour depth;
Pinball Fantasies runs that way on the owner's KN7000 (its `screen.cpp`, probes PFT14 and PFT15), and kn7000_mame
models it. From the game task's start the game's frame is its own, `FB8`, at display memory `0x50000` (640 x 240
bytes, past the firmware's 16-bit frame, which is left as it was): the firmware's REG[040h], [042h]-[044h] and
[046h]-[047h] are saved, the controller set to 8 bits a pixel and lines of 640 bytes, and its start address to FB8's
last word (written outside the vertical non-display period, interrupts off, as Pinball does). At the quit, or when
the firmware stops calling the game, the registers go back and the firmware's own screen shows again.

- **The window**: each byte is the page's colour index, so the palette is entries 0-15 of the look-up table: a palette
  change is 16 entries written, not a window repainted, and a store into FB8 carries 4 pixels (2 at 16 bits).
  A new palette goes into the table only once the page's pixels are written (`src/display.s` BlitPage): written
  first, it showed the old picture in the new colours while the pixels changed, about two LCD frames for a whole
  window (Felipe saw that flash at the splash's cuts, 2026-11-02; MAME showed the Interplay logo in Delphine's
  colours, `probes/cnv/awcnv_flash.lua`). When the page differs from what the window shows in more than a quarter of
  it (counted on every fourth row: PageCut), the game's 16 entries go black while the pixels are written; the
  splash fades to black before each cut, so nothing of it shows.
- **The border** (the 128-pixel strips beside the 384x240 window; the 160-pixel strips and the 20-row bands around
  the 320x200 one) holds entries 16-255, drawn once for each window size and never again: 2 sides x 8 bands of rows x
  15 levels. A pixel's level is its distance from the window in fifteenths of the border's width, plus a random -1
  to +2 levels; its band its row, plus a random offset of up to a whole band either way; above and below the window
  it takes the right side's colours with a chance that grows from 0 to 1 across the window's width (no seam in the
  middle: Felipe, 2026-11-02). The randomness is a dither: the levels, the bands and the sides mix, along and across.
- **Each page shown**: for each side and band, the window's quarter on that side in those rows (every 4th pixel of
  every 2nd row) is counted by colour; the average colour, taken half way from the last one (smoothing), gives the
  band's 15 entries, 0.9 of it beside the window falling off as the square of the distance to black at the far edge;
  only entries that change are written.
- **A part's load** makes every entry black: the screen goes black at once and nothing is redrawn.
- Nothing the firmware draws reaches FB8; the controller's mode and start address are checked after each yield (in
  place of the 47 sentinel pixels of the 16-bit frame) and set again if anything changed them.

In MAME (`probes/cnv/README.md`, "The ambilight"): at every one of 3,601 ticks of the intro and the lake, through
PAGE DOWN and PAGE UP twice each, FB8's window held the page, its border what the last of its 5 drawings left
(ambilight entries only), the controller its settings, and the look-up table what the game had written (the palette
loaded, the ambilight's entries); part loads were black; after the quit the controller held the firmware's settings
again; the acceptance tests pass on programs 893 and 941. Per tick
of the intro the game now makes 607 stores into display memory at 384x240 (2,186 before) and 435 at 320x200
(1,624), at 888 ns each on the unit; in MAME's own time a tick took 63.9 and 50.3 ms (61.3 and 48.8 before: the
ambilight's counting and entries).

## The firmware's screen

**While a part loads the screen is black** (since 2026-11-02). Before, the firmware's STYLE CONVERT screen showed
through during every part's load (Felipe on the instrument): its title bar and text box over the game's last
picture, or, at the first part, the whole screen with "LOADING ANOTHER WORLD". Every converter call answers request
5, and program 893 answers each with a new text title and a repaint of its screen; while the game draws every frame
that never shows, but during a load the game task only waits. In MAME each load got one whole repaint, 305,920
stores into the LCD.

Now, as Pinball Fantasies does it (`src/fwdraw.s`; Pinball `kn7000/src/app/fwdraw.c` traces the firmware's side):

- once the game task has started, ScreenProc's record in the firmware's view class table is pointed at a copy in
  the game's RAM (`FWDRAW_AT`) whose procedure answers the paint event without the 150 KB wallpaper copy;
- at every yield of the game task the firmware's drawing is turned off (DrawEnable `0x5002A018` and `0x5002A01C`
  at 0) once no wallpaper copy is under way;
- a part's load paints the whole LCD black first (`display.s` LcdBlack) and draws no load bar; the first frame
  after it repaints everything;
- at the quit, before "Continue Next?", the table and DrawEnable are put back; also when the firmware stops calling
  the converter for 5 s (DISPLAY HOLD).

The hook is made only when the class table holds program 893's records (`0x48724914`, 0x6B of them, ScreenProc
`0x484177CE` in record 0x41); with any other program nothing changes. In MAME (`probes/cnv/awcnv_loadblack.lua`;
`probes/cnv/README.md`, "The screen during loads"), the intro's and the lake's loads were black at every frame, with
no store from the firmware, and took 0.58 and 0.53 s instead of 0.98 and 0.93; the converter is called 70 times a
second instead of 13.

## Memory

Everything the game writes is in **`0x502BA000`-`0x50379FFF`**: the work RAM STYLE CONVERT leaves to a
converter, less the loader's resident area below it and the mailbox page; and, on program 893 only, three words
of the firmware's own ("The firmware's screen"): group 4's records pointer in the view class table
(`0x5011FAD4`) and the two DrawEnable words (`0x5002A018`, `0x5002A01C`), all put back at the quit. That range was measured
untouched by the firmware on program 893 in MAME through boot, idle, DISK MENU and a converter run
(research-scratch `aw-memory-plan/taps893_ranges.out`), and the acceptance tests below measure it
again while the game runs through the loader and reads the SD card. `src/platformcnv.inc` holds the
map, laid out around the loader's contract `kn7cnv.inc` (which the game includes);
`tools/cnv_layout.py` prints and checks it at every build:

| range                     | what                                                                                             |
|---------------------------|--------------------------------------------------------------------------------------------------|
| `0x502B8000`-`0x502B97AF` | KN7LOAD.CNV: the loader's image (6,064 bytes, SHA-1 6b81f382...)                                 |
| `0x502B9C00`-`0x502B9C7F` | LV_STR: the loader's line buffer                                                                 |
| `0x502B9D00`-`0x502B9DFF` | LOADER_VARS: the loader's variables and the saved SD folder                                      |
| `0x502B9E00`-`0x502B9E6B` | SVC: the loader's service table (the game reads it)                                              |
| `0x502BA000`-`0x502C7FFF` | KN7APP.BIN: header, code and tables (40,620 bytes, to 0x502C3EAC)                                |
| `0x502C8000`-`0x502D33FF` | SHADOW: the window as the LCD shows it, 4 bits a pixel; help and stop screens, a bitmap's planes |
| `0x502D4000`-`0x502D5FFF` | REPORT_BUF: the text of AWPERF.TXT                                                               |
| `0x502D8000`-`0x502D82FF` | AW_FONT: the 8x8 font, from AWFONT.AW                                                            |
| `0x502D8300`-`0x502D8AFF` | AW_STRIDX: string index, from AWSTRIDX.AW                                                        |
| `0x502D8B00`-`0x502D9AFF` | AW_STRDAT: strings, from AWSTRDAT.AW                                                             |
| `0x502DA000`-`0x502DA1FF` | AUDIO_VARS: audio.s: MIDI producer, music player, note slots                                     |
| `0x502DA200`-`0x502DA5FF` | SND_TAB: each sound's program, note, length, from AWSND.AW                                       |
| `0x502DA600`-`0x502DA9FF` | DSP_HOST: dsp.s: the effects DSP's routines, state, commands, readback                           |
| `0x502DAA00`-`0x502DACFF` | LCD8_VARS: lcd8.s: the LCD's, the ambilight's and the loading screen's state                     |
| `0x502DAD00`-`0x502DADFF` | LED_VARS: leds.s: the LED effects' state                                                         |
| `0x502DB000`-`0x502DEFFF` | MUSIC_BUF: the current part's music module                                                       |
| `0x502DF000`-`0x502DF3FF` | CNV_VARS: the entry's and the part loader's variables                                            |
| `0x502DF400`-`0x502DF4FF` | FW_VARS: what fwfind.s found, and its scratch                                                    |
| `0x502DF800`-`0x502DF83F` | AW_PATHS: the game's folder, from the menu's launch block                                        |
| `0x502DF900`-`0x502DF95F` | PREFS_AT: prefs.s: the settings (AWPREFS.CFG) and the settings page                              |
| `0x502E0000`-`0x502E01FF` | VM_POLY_BASE: rasterizer scratch                                                                 |
| `0x502E0400`-`0x502E0E47` | FWDRAW_AT: fwdraw.s: the firmware's view records, ours                                           |
| `0x502E1000`-`0x502E20FF` | VM_INTERP_BASE: VM variables, threads, call stack                                                |
| `0x502E3000`-`0x502E43FF` | VM_MISC_BASE: input, help, guard, note trackers                                                  |
| `0x502E5000`-`0x502E5247` | RES_TAB: where each resource is now                                                              |
| `0x502E6000`-`0x502E6FFF` | VM_PERF_BASE: speed figures, the blit's palette and pixel pairs                                  |
| `0x502E7000`-`0x502E7EFF` | DSP_BANKTAB: the DSP's sample bank: where each sound goes, from AWBANK.AW                        |
| `0x502E7F00`-`0x502E7FFF` | LB_ADDR: the program menu's launch block (kn7cnv.inc): read, never ours                          |
| `0x502E8000`-`0x502EE3FF` | VIDEO2_AT: the shared polygons (0x11)                                                            |
| `0x502EE400`-`0x5031AFFF` | PART_AREA: the current part's files                                                              |
| `0x5031B000`-`0x5031BFFF` | the firmware's mailbox page (0x5031BC00..): never written by the game but the request            |
| `0x5031C000`-`0x5031FFFF` | INPLOG_AT: the input log: its variables and two halves (inplog.s)                                |
| `0x50320000`-`0x503367FF` | PAGE_BITMAP_0: VM page 0: 384x240, or 320x200 at its start                                       |
| `0x50336800`-`0x5034CFFF` | PAGE_BITMAP_1: VM page 1: 384x240, or 320x200 at its start                                       |
| `0x5034D000`-`0x503637FF` | PAGE_BITMAP_2: VM page 2: 384x240, or 320x200 at its start                                       |
| `0x50363800`-`0x50379FFF` | PAGE_BITMAP_3: VM page 3: 384x240, or 320x200 at its start                                       |

At the quit back to the program menu (`src/chain.s`), once the game task has ended, the menu's file is read into
`0x502E8000` (the menu's STAGE: the shared polygons and the start of PART_AREA, no longer needed) and the menu's
trampoline and its data go to `0x50368000` and `0x50369800` (its T_CODE and T_DATA, inside page 3);
`tools/chain_check.py` checks at every build that these are still the menu's addresses.

What the game must never touch, and how that is checked:

- **IC23**, the 256 KB battery-backed SRAM with the panel settings and the 104 PANEL MEMORY records,
  is chip select CS1: `0x44000000`-`0x47FFFFFF`, and its uncached view `0x84000000`-`0x87FFFFFF`. It
  repeats every 256 KB through the whole chip select (A1-A17 only; confirmed on the owner's unit on
  2026-10-20), so any address there is the panel memories. The firmware writes it at any time and
  stamps a checksum over its header only at power-off: damage done during a session would be stamped
  valid (kn7000_mame `notes/ic23-nvram-2026-10-20`).
- **The user-memory pools**, `0x50180000`-`0x50297FFF` (and `0x90180000`-...): COMPOSER styles, pads
  and the other user data the firmware never clears and keeps across power-off.
- **The loader**, `0x502B8000`-`0x502B9FFF` (and `0x902B8000`-...): its code runs on every converter
  call, and its variables and service table must survive the game. The game only reads the service
  table.
- **Boot data** from `0x5037A000`, and 941's zlib arena `0x503B1000`-`0x503FFFFF`.

Three checks keep the game inside its range:

1. **At build time**, `tools/ic23_guard.py --loader` assembles the game with the toolchain's own
   assembler and records every value any expression produces (operands, data, constants, labels):
   none may lie in CS1 or the pools, and none in the loader's area but loads `mov (SVC + SV_x), reg`
   from its service table (11 of them: the table check of steps 1 and 2, with the write routine and
   the program build). `make app` stops unless it
   says "clean"; `probes/cnv/guard_loader_selftest.s` proves the guard finds a store, an address taken,
   a byte load, the loader's variables or code, an address as data and an IC23 address.
   `tools/cnv_layout.py` checks the map above: every region inside `0x502BA000`-`0x50379FFF`, off the
   mailbox page and the loader's area, no overlaps, every `vm.inc` field inside its block, the image
   starting at `APP_BASE` with its header and ending below `IMAGE_END_MAX` (`0x502C0000`), `AW_LO` equal to the loader's
   `APP_BASE`, and the loader's own image (the owner's `KN7LOAD.CNV`), line buffer, variables and
   service table below `APP_BASE`.
2. **At run time**, every load destination is checked before the file is read (`GuardRange`: inside
   `0x502BA000`-`0x50379FFF`, clear of the mailbox page), every page the VM draws or copies on must be
   one of the four pages (`GuardPage`), and the VM's call stack must stay in its 512 bytes. A refused
   write is skipped, and the game stops at once with "ANOTHER WORLD STOPPED", the reason and the
   address on the LCD; EXIT then ends it as usual. The rasterizer already clips every span and point
   to the page; variables and threads are indexed with masks.
3. **In MAME**, write taps over CS1, the pools, the loader's area and the game's own RAM, through whole
   sessions on 893 and 941 (below).

The task's stack is the kernel's: `cre_tsk` allocates it and `exd_tsk` frees it.

Outside its RAM the game writes only the mailbox's request, the LCD frame, at each quit one new file in
the SD card's root (`AWPERF0.TXT` .. `AWPERF9.TXT`, the first name that does not exist: "Speed"), through
the loader's file routines, and, through the firmware's own host-port routines, the effects DSP's memory
("Sound"): its mixer at PM `0x8140`-`0x826E`, its variables, voices, command records, decoder state, two
staging buffers and marker at DM `0x9D00`-`0x9EFF` (never written by the firmware: the ROM dumper's pass 7), the sample bank
at SDRAM `0x70000`-`0x99E37` (above the kernel's delay rings), MSGR4-MSGR7, and the CALL slots of units 0
and 9, which it puts back as it found them. All of that is the DSP's, which the firmware resets and
reloads at every power-on.

## How it was checked

All in the overlay emulator (`kn7000-emulator`, binary md5 `2a8e2fce...`), which models IC23 as 256 KB
of NVRAM repeating through CS1 and runs the firmware's power-down from its POWER OFF input. `-bios v13`
is the owner's program 893 / table 80, from the owner's own dumps; `-bios v16` is program 941. Every
run boots with the owner's loader floppy image (`b7a67de6...`) and a copy of the real KN7000's SD card
with `build/sdcard/` added to its root. The commands, the scripts and what each check reads are in
`probes/cnv/README.md`; every number below comes from `probes/cnv/run_cnv_tests.sh`, run on the speed
build (`KN7APP.BIN` `26aabecb...`; the build before, `b952c2aa...`, passed the same with 16 session
checks).

| check        | question                                                                      | 893, blank IC23           | 893, the owner's IC23     | 941, blank IC23           |
|--------------|-------------------------------------------------------------------------------|---------------------------|---------------------------|---------------------------|
| (a) guard    | does the game name any address in CS1, the pools or the loader? map in range? | clean; map ok             | (same build)              | (same build)              |
| (b) session  | a whole session (18 checks, below)                                            | 18 of 18                  | 18 of 18                  | 18 of 18                  |
| (b) report   | `AWPERF0.TXT` at the first quit, `AWPERF1.TXT` at the second, nothing more?   | both, as built            | both, as built            | both, as built            |
| (c) ic23w    | any write into CS1 from the converter area, or past IC23's 256 KB?            | none, none                | none, none                | none, none                |
| (d) same     | IC23 after the game and POWER OFF = IC23 after a control run and POWER OFF?   | identical, checksum valid | identical, checksum valid | identical, checksum valid |
| (d) accepted | does the next boot find it valid, PANEL MEMORY store as it was?               | valid, store kept         | valid, store kept         | valid, store kept         |
| (e) pools    | `0x50180000`-`0x50297FFF` identical at POWER OFF, and no write there?         | identical, none           | identical, none           | identical, none           |
| (f) area     | any foreign write into the game's RAM while it runs?                          | none                      | none                      | none                      |
| (g) loader   | any write into the loader's area but the loader's own?                        | none                      | none                      | none                      |

**Again on 2026-11-02**, with the firmware's drawing off (`KN7APP.BIN` `cddfe76b...`, emulator md5 `8b9865bd...`;
893 and 941 with a blank IC23, the owner's IC23 not run): every check above passed in both, the 18 session checks
included. (f) had found 431,724 foreign writes in both: the firmware's SD read filling PART_AREA with the DSP's
sample bank (dsp.s BankRead, since the DSP build), which only the part loader's reads were recognised as. BankRead
now sets `LD_IN_READ` to 2 while it reads, and the test counts those writes with the game's SD reads (914,072).

The session's 18 checks: the loader ran the game, having found all seven of its services (`0x7F`),
and the game's firmware search found everything (on 893: from the loader's table SD open
`0x48564A88`, read `0x48564D70`, close `0x48564B4F`, the drive switch the loader's no-op `0x502B85BE`;
`cre_tsk` `0x4C03D0B5`, `sta_tsk` `0x4C03D898`, the yield `0x4C03DD5C`, `exd_tsk` `0x4C03D58E`, ms
counter `0x500C53F8`, panel `0x5006BE4C`, MIDI rings `0x5001F020` / `0x5001F834`: the `aw_find_fw.py`
column); the splash, the intro, a key skipping it to the lake; the panel's five game buttons and the
keybed's action; HELP (the VM pauses, PAGE DOWN turns the page, EXIT returns); the speed figures (the
fourth help page; since 2026-11-02 the two display modes, before that the overlay and the old blit); the level codes HTDC
(the prison) and CLLD (the city, the largest part); quitting, "Continue Next?" YES (the loader reads
`KN7APP.BIN` again: a new game), quitting again and NO; no guard refusal and no load error; and each
part's resources, every time one became resident (8 times, 46 resources), byte for byte the
reference unpack; and the two speed reports on the card, the second the text the game built. No
panel press was lost and no file read failed in any of the three. The saved IC23s are byte for byte
those of the build before and of the control runs.

How long a part's files take to load in MAME (emulated time, from the sessions' `LD_MS`; one file
per converter call, about 20 calls a second; a real card's speed is not known), from the SD card
through the loader, and, for comparison, from the floppy with the retired `AW.CNV` (893):

| what                                     | files | bytes read | SD card: 893 blank / owner, 941 | floppy (AW.CNV) |
|------------------------------------------|-------|------------|---------------------------------|-----------------|
| font, string tables, shared polygons     | 4     | 25,776     | 831 ms (the intro run)          | 5.2 s           |
| the splash part (0x3E80, with 4 bitmaps) | 7     | 30,060     | 584 / 580, 584 ms               | 6.3-6.5 s       |
| the intro (0x3E81)                       | 3     | 64,176     | 836 / 827, 920 ms               | 5.6 s           |
| the lake (0x3E82)                        | 3     | 60,108     | 872 / 880, 884 ms               | 4.7 s           |
| the prison (0x3E83, with 2 bitmaps)      | 5     | 93,464     | 1,264 / 1,264, 1,264 ms         | 9.8 s           |
| the city (0x3E84, with 4 bitmaps)        | 7     | 129,892    | 1,624 / 1,624, 1,628 ms         | 13.2 s          |

- **The writes.** In the game runs, the firmware's own IC23 writes are the boot's and a few from its
  library (893 `0x4C01F310`-`0x4C01F39C`, 941 `0x4C01F325`-`0x4C01F3B1`: the settings OCTAVE and
  SUSTAIN change); none from the converter area. The game's RAM saw only the firmware zeroing the
  converter area when it loaded the loader (893 pc `0x48478E7D`, 941 `0x48479040`), the loader zeroing
  the application area (`0x502B8187`, at the start and after YES), and the SD reads of `KN7APP.BIN`
  and of the files the game asked for (893 `0x4854BA0D` and `0x4C003031`, 941 `0x4854C0E0` and
  `0x4C003046`), each inside its destination. The loader's area saw the firmware load `KN7LOAD.CNV`
  and then only the loader's own code, in the control runs as in the game runs. The stack pointer seen
  while the game's code runs (the game task's, and the main task's during converter calls) stays in
  `0x5038DD2C`-`0x503AD844`, the kernel's, outside the game's range. In the game runs nothing touched
  the pools after boot. (In the control runs, after NO, the firmware's own code (893 `0x48455812` and
  a copy at `0x4C003031`, 941 `0x484558DB` and `0x4C003046`) rewrote part of `0x501A5000`-`0x501A6FFF`;
  the pools still ended byte-identical to the game runs'. With `AW.CNV` as the control, it did not.)
- **The saved IC23s** are the same as with `AW.CNV` (SHA-1 prefixes `eb26c67b...` for 893 blank,
  `14f82423...` for the owner's, `bc2305dd...` for 941 blank): the route to the game changes nothing
  that is kept.
- **The intro, frame by frame**, on 893 through the loader: `probes/cnv/awcnv_cksum.lua` captures the
  displayed page at every VM tick; compared with rustyworld as for the SP7001 build
  (`probes/CHECKSUM-COMPARISON.md`): "captured 2613 frames (last tick 2612); part loads 3, load errors
  0, guard 0", and 2612 of 2612 frames identical to the reference, as with `AW.CNV`. The font, the
  strings and the shared polygons loaded in 831 ms there.
- **The firmware search on the instrument's own data.** `tools/aw_find_fw.py` finds the same 893
  addresses in the owner's program dump, and, with `--real-lib893`, in the library RAM the ROM
  dumper read from the instrument (equal to the boot's copy of the flash over its whole length).
- **The panel buttons.** While the game runs, the firmware still acts on R1/R2 OCTAVE + / - (the octave
  setting) and SUSTAIN (sustain on/off), the game's UP, DOWN and FIRE until 2026-10-21 (`probes/cnv/awcnv_panelsettings.lua`,
  with `AW.CNV`; the session's `settings` check sees the same through the loader: FIRE changes header
  byte `0x03A`, UP and DOWN `0x6EA`); PART SELECT LEFT, RIGHT 1, RIGHT 2 and DISPLAY HOLD change
  nothing. The session therefore presses those in pairs that cancel, and checks that the settings end
  as they began.
- **What the tests found and fixed** (with `AW.CNV`, none of it a write outside the game's RAM, all of
  the fixes in `KN7APP.BIN` too): `probes/cnv/README.md`. The loader route needed no fix.

**The sound (2026-10-20, `KN7APP.BIN` `15f5c57e...` and `97fbd9e6...`; `probes/cnv/README.md`,
"Sound").** Only short runs, as asked: no acceptance suite was rerun for the sound build.

- `awcnv_sound.lua` (893, `15f5c57e...`, the build before the last change, which only keeps the
  sound quiet until the game has set it up): the whole intro with no input, recorded. The game put
  1,704 messages into the ring, dropped none, and the firmware read every one (its read pointer equal
  to the write pointer at every one-second sample). The module player played 951 rows; all 24 of the
  intro module's sync marks reached var 0xF4 in order (1, 4, 8, 12, 1, 16, 20, 33 .. 49), the intro
  stopped the music at mark 49, as its bytecode does, and went on to the lake by itself (at VM tick
  about 2,660; 2,612 before, without marks). 211 PLAY_SOUNDs sounded. The recording is silent before
  the game and between -27 and -49 dBFS through the intro, its pitches the module's (the bass's E2 at
  82 Hz, the melody's E4, G4, D4). PART SELECT RIGHT 2 stopped the game's output for the six seconds
  it was off. At the quit the ring's last bytes were all notes off, all sound off and reset all
  controllers on channels 10 to 14 (and before them 4 to 7), all read by the firmware.
- `awcnv_noteoff.lua` (893, `97fbd9e6...`, the game's own sound muted): the same notes put into the
  ring by the script, as `MidiMsg` does, and sent through the MIDI IN port from an SMF behave alike: a
  square lead (GM 80) falls by about 40 dB within a second of its note-off either way; a piano (GM 0)
  rings on after its note-off either way, which is the overlay's tone generator, not the path.

### The DSP sound (2026-10-21)

Light, as asked: one MAME session through the program menu, as Felipe runs it (`probes/cnv/run_dsp.sh`,
`awcnv_dsp.lua`, `dsp_report.py`; program 893, the owner's loader floppy, a copy of the real card with the menu as
the root `KN7APP.BIN` and the game in `AW\`), and the build's guards (`leafcheck` 0 unsafe calls, `ic23_guard`
clean with the DSP host port now forbidden too, `cnv_layout` ok, every word of the mixer checked against MAME's
SHARC disassembler). On `KN7APP.BIN` `a2fbbaa6...`, 11 of 11 checks (`probes/cnv/README.md`, "Sound on the
effects DSP"; the run's files: `probes/cnv/dsp-results-2026-10-21/`): the firmware's dead flag 0 throughout; the
whole bank sent in 25.9 s; both slots hooked and both units' counts at 44,100 a second through the intro; all
eight voices sounding, the music's alone audible in the recording (-52 to -43 dBFS); no MIDI sent in the DSP
mode; RIGHT 2 to the tone generator put both slots back, and back to the DSP hooked them again; after each quit
both slots as found, MSGR4-MSGR7 0, the reverb running again; a second game from the menu found the bank by its
marker and did not send it again. Not run: the acceptance suite (`run_cnv_tests.sh`, `run_menu_route.sh`),
program 941, the help screen's mode line, the watchdog.

### Round 3 (2026-10-21)

Light, as asked: the build's guards (`leafcheck` 0 unsafe calls, `ic23_guard` clean, `cnv_layout` ok, all 303 of
the mixer's words checked against MAME's SHARC disassembler, every one of the bank's 837 blocks decoded by the
build and equal to the bank) and two MAME sessions through the program menu on program 893
(`probes/cnv/run_round3.sh`, `awcnv_round3.lua`; `probes/cnv/README.md`, "Round 3"; the files:
`probes/cnv/round3-results-2026-10-21/`), on `KN7APP.BIN` `7f8ed09a...` (the second; the first on `59629a40...`,
the same but for the help screen's dot), and one bank-only session on the build before:

- **The bank**: 25.87 s before (`a2fbbaa6...`), 11.62 s now, all 171,576 words decoded and the DSP's checksum equal
  to `AWBANK.AW`'s; the second start, by the marker and the checksum alone, 0.43 s (its help line "CHECKED IN 0.2 S").
  The table in "Sound" says where the time went.
- **The sound**: the intro on the DSP (voices 0-5 sounding, the mix up to 915,072, the dead flag 0 throughout);
  after each quit both slots as at boot and MSGR4-MSGR7 0.
- **UP**: B♭5 alone and B5 alone each set var 0xE5 to -1 and var 0xFD to 8 in the lake.
- **The panel**: R1/R2 OCTAVE + and - (twice each), PART SELECT LEFT, RIGHT 1 (twice) and SUSTAIN (twice), each
  held in the lake, left every hero variable 0.
- **HELP**: RIGHT 2 three times inside it went TONE GENERATOR (slots back), OFF, DSP SAMPLES (hooked again), the
  help screen up all along and its line redrawn each time; RIGHT 1 twice "KEYBED SOUND: OFF", "ON".
- **The URL page** (snapshot): "github.com/felipesanches/" over "technics-anotherworld", the period a solid dot.
- **The keybed's sound**: RIGHT 1 set the firmware's expression for channel 1 (`0x5000B36B`) to 0 and back to
  0x7F; IC23 had not one word changed by it; the quit with the sound off put it back (0x7F). **It cannot be heard
  in MAME**: the overlay's tone generator ignores the voices' level word, which is where the firmware puts
  expression (for a keybed C4 it writes 0x0000 there instead of 0x0BE8 / 0x0BA4, `probes/cnv/awcnv_keymute.lua`),
  so the recording is the same muted or not.

Not run: the acceptance suites (`run_cnv_tests.sh`, `run_menu_route.sh`; their panel check now expects the panel
not to move the player), program 941, a part switch, the watchdog.

## What MAME cannot settle

- **Everything rests on the emulation of program 893.** The `-bios v13` program and table images are
  the owner's own dumps (cnv_romdump passes 1 and 2, checked byte for byte), and the kernel library
  the search reads in RAM is the boot's copy of that flash, so the firmware search's results should
  carry over unchanged; `tools/aw_find_fw.py` gives the same answers from the dump files alone, and
  with `--real-lib893` from the library RAM the SURVEY2 pass read on the instrument.
- **What has already run on the owner's unit:** the loader itself, unchanged (its search, its SD
  routines, reading `KN7APP.BIN` from the root in 16 KB pieces, calling an application on every
  converter call, request 1, ending the conversion with `0xFE`), in eight passes of the dumper.
- **What has not:** answering request 5 (the dumper parks with request 1), starting and ending a task
  of our own (`cre_tsk`, `sta_tsk`, `exd_tsk`), the firmware's yield routine, and reading more than
  one file per run from the card (one file per converter call, up to 55,476 bytes, the intro's
  polygons). MAME runs the same firmware code for all of them, but not the real chip's timing nor the
  real card's.
- **The card's speed.** How long a part's files take on the real card is unknown; in MAME see "How it
  was checked". Whether a panel event that comes in while the main task is in a file read is kept: in
  MAME one release was lost that way with the floppy, which is why loads wait for the panel to be let
  go.
- **The panel while parked.** Request 5 keeps the firmware on the converter's text screen, and the
  panel's switch bitmaps keep being updated. In MAME the firmware also acts on R1/R2 OCTAVE + / - and
  SUSTAIN there (above); other buttons may do the same on the instrument, which a changed setting
  after a session would show.
- **The speed.** MAME gives the LCD frame no wait states, so its frame times say nothing of the
  instrument's; it counts the accesses (before and after: "Speed") and checks the picture. On the unit
  the speed page and `AWPERFn.TXT` say where the time goes, in both display modes.
- **The firmware's painting on the instrument.** In MAME the firmware repainted its text screen
  around the intro's last load and once after DISPLAY HOLD; on the unit it did at every part's load
  (Felipe, 2026-11-02), which program 893's drawing switched off now prevents ("The firmware's screen");
  with another program, or after DISPLAY HOLD, it may still. The sentinels, read after each yield, and the repaints after each load put it right within a
  frame or two where MAME saw it; a painting that misses all 47 sentinels and comes long after a load
  stays until the game draws there again or the 500-frame repaint. A switch of the display mode
  (PAGE UP / PAGE DOWN) paints everything.
- **`AWPERFn.TXT`.** Writing a file through the loader's routines has run on the owner's unit many
  times (the ROM dumper's `DUMPLIST.TXT` and dump files); the game does it the same way, in the root,
  once per quit, and never opens an existing file for writing (it tries each name for reading first,
  which fails for a missing one as a missing game file's read does).
- **The sound on the instrument.** In MAME the notes the game sends are consumed and sound, and its
  note-offs are honoured as MIDI IN's are; but the overlay's tone generator keeps some voices sounding
  after their note-off (and after all notes off), so MAME cannot show that nothing hangs: listen after
  the help screen, the sound button, a part switch and the quit. The GM programs and drum keys are
  chosen without hearing the KN7000 play them. And the routing is the instrument's initial one: if
  PART 4-14 have been given other channels, NOTE ONLY or no program change in the MIDI menus, or MIDI IN
  is set to BASS PEDAL, the game may sound differently or not at all.
- **The DSP sound on the instrument.** What iteration 1 (DSPTONE) settled on the unit: the firmware's
  host-port routines, the upload and readback of a program, a unit slot hooked and put back, SDRAM from
  `0x70000` written and played, the heartbeat at 44,087 frames a second, unit 0's return heard with REVERB
  on. What is new here and has run only in MAME: SDRAM up to `0x99E37` (the bank's 171,576 words; DSPTONE's
  PCM reached `0x7AC44`), the multiply and the shifts by a register on the chip, unit 9's slot and its
  return (MAME mixes it only while the CHORUS is on; the instrument mixes it whatever REVERB and
  CHORUS are, as Felipe heard on 2026-10-21), host traffic from a task of ours rather than the firmware's main task,
  how long the bank takes, and the level. MAME runs the DSP at exactly 44,100 frames a second and moves
  the host's words straight into DSP memory; the chip moves them through the external port's FIFO and
  DMA, as the firmware's own uploads, which is why every upload is read back before the hook.
- **Round 3 on the instrument** (`7f8ed09a...`): the bank decoder and checksum on the chip (MAME runs the same
  instructions; the build checks the code, not the chip), how long the bank takes there (the help screen says),
  and whether PART SELECT RIGHT 1 really silences the keybed's notes: MAME's tone generator does not model the
  level word the firmware sets for it.
- **IC23, the pools and the loader are only measured in MAME.** The game names no address there and
  refuses any computed one outside its RAM, but the first run should still check the instrument's
  memory: "Before the first run on the instrument".

## Limits

- **Sound: the DSP's is a second iteration** ("Sound"). No interpolation between samples, and the level
  against the instrument's own sound is not set (one voice at full volume peaks at -18 dBFS at the DSP).
  While it plays, the instrument's REVERB and CHORUS are off (the keybed sounds dry). The bank takes a
  while to load after each power-on (11.6 s in MAME; the host port's one 16-bit half per DSP frame is the
  floor: 4.9 s for the coded bank's 214,188 halves). Faster would need more than one access per handshake,
  which the firmware's own uploads never make and which MAME cannot check: the game keeps to the firmware's
  routines. The tone generator mode is the first iteration's: GM sounds for the
  effects, the music's notes on GM instruments. The SP7001 build stays silent.
- **Load pauses** at each part switch, up to 130 KB of files (the city).
- **One card per build.** `KN7APP.BIN`'s part tables name the files of the build that wrote them:
  copy the whole of `build/sdcard/` each time, never `KN7APP.BIN` alone.
- **YES restarts from scratch.** The loader reloads `KN7APP.BIN` for "Continue Next?" YES, so a new
  game repeats the firmware search and the global files before the splash, and its speed figures
  start afresh (384x240).
- **Room in `KN7APP.BIN`.** The variables moved up on 2026-10-21 (they were right after the image, at
  `0x502C0000`); the image may now reach `0x502C8000` (`IMAGE_END_MAX`): 25,032 bytes are left.
- **Ten speed reports at most.** With `AWPERF0.TXT` .. `AWPERF9.TXT` all on the card, a quit writes no
  more; delete them after copying them off.

## History: the AW.CNV floppy (retired)

Until 2026-10-20 the game was its own style converter, `AW.CNV`, on a floppy of its own with the 43
game files beside it, loaded at `0x502B8000` by STYLE CONVERT directly, with the floppy's file
routines found by its own search (`OpenHere`, `fmmread`, `fmmclose`). It passed the same acceptance
tests in MAME (`probes/cnv/README.md`), but it never went to the instrument: all custom code on the
owner's unit is started by `KN7LOAD.CNV` from the one write-protected floppy, and no other `.CNV` goes
on a floppy for it. It is retired, not kept as a MAME-only target: the loader route runs in MAME just
as well, and a second route would need its own guards and tests. Its last state is commit `dbc7a2c`
(`make floppy`, `src/cnv_main.s` linked at `0x502B8000`, `tools/make_cnv_floppy.py`).
