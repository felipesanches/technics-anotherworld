# The KN7APP.BIN build: probes and acceptance tests

Measurements behind [README-CNV.md](../../README-CNV.md), the Another World build that a stock KN7000
runs through its SD loader: STYLE CONVERT runs `KN7LOAD.CNV` from the owner's floppy, and the loader
loads and calls `KN7APP.BIN` from the SD card. They run in the published overlay MAME build
(`kn7000-emulator`, which models IC23 as 256 KB of NVRAM repeating through CS1 and has a POWER OFF
input), with the owner's loader floppy and a copy of the real KN7000's SD card. The acceptance tests
(2026-10-20) come first; the probes that established the platform (2026-10-18, program 941, with
`AW.CNV`, the floppy-only predecessor that kept its data in the `0x44000000` window) follow.

**Addresses.** On 2026-10-21 (the DSP sound build, commit `f87fc55`) the game's variables moved up as one
block, from `0x502C0000`-`0x502C7FFF` to `0x502DF000`-`0x502E6FFF` (`src/platformcnv.inc`), and the image may
now reach `0x502C8000`. The Lua probes here name the new addresses, so they run against that build and later;
the results below for earlier builds were measured with the old ones (the git history has those scripts).

## Acceptance tests (2026-10-20): through the loader, program 893 and 941

`run_cnv_tests.sh OUT CASE...` runs them, after `make sdcard`; `OUT` is a scratch directory. Each
prints `run_cnv_tests: <case> PASS|FAIL detail` and appends it to `OUT/summary.txt`. Every MAME run
boots with the loader floppy exactly as released (technics-roms-disasm
`kn7000/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img`, SHA-1 `b7a67de6...`, holding
`KN7LOAD.CNV` `6b81f382...`) and a fresh copy of the real KN7000's SD card (`sdcard_from_real_kn7000.img`)
with the 44 files of `build/sdcard/` added to its root by `sd_addfile.py`; the copy is deleted when
the run ends.

| file                      | what it is                                                                                             |
|---------------------------|--------------------------------------------------------------------------------------------------------|
| `run_cnv_tests.sh`        | the runner: the cases below, each MAME run in its own directory with fresh cfg and NVRAM               |
| `awcnv_test.lua`          | the MAME side: the whole game session (or the control, or a plain boot) and every tap                  |
| `noop_app.s`              | the control application: a `KN7APP.BIN` that ends the conversion on its first call                     |
| `guard_loader_selftest.s` | what `ic23_guard.py --loader` must find: 7 planted references, and the 2 loads it must allow           |
| `ic23_file.py`            | a saved IC23's stored and computed header checksum (copied from kn7000_mame)                           |
| `ic23_diff.py`            | which regions of two IC23 images differ (copied from kn7000_mame)                                      |
| `awcnv_cksum.lua`         | the intro frame by frame, for the pixel comparison with the reference VM                               |
| `awcnv_inplog.lua`        | the input log (`src/inplog.s`): a scripted session recorded, or a session replayed; every frame's page |
| `run_inplog.sh`           | its runner: `OUT record`, `OUT replay SESSION.awr`, `OUT compare A B`                                  |

The questions, and how each is answered:

| case / check          | question                                                                                        | how                                                                                                                                                                                                                                                                 |
|-----------------------|-------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `guard`               | (a) does KN7APP.BIN name any address in CS1, the user pools or the loader? is the map in range? | `tools/ic23_guard.py --loader` must say "clean" for `src/cnv_main.s`, find exactly the 7 planted hits of `guard_loader_selftest.s` and the SP7001 build's references; `tools/cnv_layout.py` must accept the memory map                                              |
| `blank-v13`, `-v16`   | a realistic empty baseline                                                                      | boot with no IC23 file, POWER OFF at 40 s: the firmware initialises IC23 and stamps it                                                                                                                                                                              |
| `ic23` ... `session`  | (b) does a whole session work?                                                                  | `awcnv_test.lua` drives DISK MENU > STYLE CONVERT > OK (the loader), the splash, the intro, a key to skip it, the panel and keybed controls, HELP, two level codes, quitting, YES (the loader reloads the game), quitting, NO; 16 checks                            |
| `ic23` ... `ic23w`    | (c) does anything of the converter area write into CS1?                                         | a write tap over all of CS1 (both views), per PC: none from `0x502B8000`-`0x502E7FFF` (the loader's code or the game's), none past IC23's first 256 KB                                                                                                              |
| `ic23` ... `same`     | (d) is IC23 exactly as it would have been without the game?                                     | the same baseline, a control run (the same floppy, card and menus, `noop_app.s` as `KN7APP.BIN`, NO) and the game run, both ending with POWER OFF: the saved IC23s must be byte-identical, checksum valid                                                           |
| `ic23` ... `accepted` | (d) does the next boot accept it?                                                               | each saved IC23 booted once more: the firmware's own verdict byte (893 `0x5006CC7C`, 941 `0x5006CC80`) must be 0, and the PANEL MEMORY store must come out as it went in (no factory reset)                                                                         |
| `ic23` ... `pools`    | (e) are the user-memory pools untouched?                                                        | `0x50180000`-`0x50297FFF` dumped just before POWER OFF in both runs: identical; and a write tap: none from the converter area                                                                                                                                       |
| `ic23` ... `area`     | (f) does anything else write into the game's RAM while it runs?                                 | a write tap over `0x502BA000`-`0x50379FFF` (and its `0x90` view) but the mailbox page: every write not from the game's code, classified: the firmware's and the loader's loads, the SD reads the game asked for (into the current file's destination), or "foreign" |
| `ic23` ... `loader`   | (g) is the loader left alone?                                                                   | a write tap over the loader's resident area `0x502B8000`-`0x502B9FFF` (and its `0x90` view), in both runs: no write from the game's code, and none but the loader's own once it has filled in its service table                                                     |

The session's `resources` check compares, each time a part has become resident, every resource in
`RES_TAB` with the reference unpack (`build/res/resource-0xNN.bin`, or the card file
`build/res/sdfiles/AWRxx.AW` for a bitmap kept packed).

Commands, from `kn7000/` after `make sdcard` (`T` is a scratch directory; the owner's IC23 is private
and used only from a copy, deleted afterwards):

    T=~/compartilhado/tmp/aw-kn7load-tests    # EMU=... to run another copy of the overlay emulator
    probes/cnv/run_cnv_tests.sh $T guard blank-v13 blank-v16
    probes/cnv/run_cnv_tests.sh $T ic23 v13 $T/blank-v13/ic23 blank
    probes/cnv/run_cnv_tests.sh $T ic23 v16 $T/blank-v16/ic23 blank
    head -c 262144 ~/compartilhado/technics_roms/roms/kn7000/real_dump_v1.3_b893/pass5-run1/R8400000.BIN > $T/owner-ic23.bin
    probes/cnv/run_cnv_tests.sh $T ic23 v13 $T/owner-ic23.bin owner
    rm -f -- $T/owner-ic23.bin

**Results for the speed build (2026-10-20, `KN7APP.BIN` `26aabecb...`, the loader floppy `b7a67de6...`,
overlay binary md5 `2a8e2fce...`; a copy of the emulator, `EMU`):**

| case                 | session  | report                        | ic23w | same                      | accepted          | pools               | area  | loader |
|----------------------|----------|-------------------------------|-------|---------------------------|-------------------|---------------------|-------|--------|
| `ic23 v13 ... blank` | 18 of 18 | AWPERF0, AWPERF1 (2335, 1801) | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v13 ... owner` | 18 of 18 | AWPERF0, AWPERF1 (2335, 1801) | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v16 ... blank` | 18 of 18 | AWPERF0, AWPERF1 (2335, 1801) | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |

`guard`: clean with "11 load(s) from the loader's service table" (the write routine and the program
build added); "src/main.s: 798 reference(s)"; `cnv_layout: ok`. The saved game IC23s are the same as
before, SHA-1 prefixes `eb26c67b...` (893 blank), `14f82423...` (893 owner), `bc2305dd...` (941 blank),
equal to the control runs'; so writing `AWPERF0.TXT` and `AWPERF1.TXT` to the card changed nothing that
is kept in IC23 or the pools. The `speed` check in all three: the speed page shown, the overlay on and
off, the old blit and back with the VM running on, IC23's live settings unchanged by PAGE UP and PAGE
DOWN. The game's RAM saw "loads 326936, SD reads 474104" foreign-but-expected writes (the loader zeroing
and loading a larger `KN7APP.BIN`), none foreign. The summaries: research-scratch
`sessions/2026-10-20_aw-perf/acceptance_summary_26aabecb.txt` and `session_*.txt`.

**Results for the build before (2026-10-20, through the loader: `KN7APP.BIN` `b952c2aa...`, the loader
floppy `b7a67de6...`, overlay binary md5 `2a8e2fce...`):**

| case                 | session  | ic23w | same                      | accepted          | pools               | area  | loader |
|----------------------|----------|-------|---------------------------|-------------------|---------------------|-------|--------|
| `ic23 v13 ... blank` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v13 ... owner` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v16 ... blank` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |

`guard`: "ic23_guard: src/cnv_main.s: clean" with "9 load(s) from the loader's service table
0x502B9E00-0x502B9E6B allowed, nothing else in 0x502B8000-0x502B9FFF"; the self-test "7 reference(s)";
"src/main.s: 670 reference(s)"; "cnv_layout: ok -- everything in 0x502BA000-0x50379FFF, off the
mailbox page and the loader's 0x502B8000-0x502B9FFF, no overlaps".

In all three sessions: the loader found all seven of its services (`0x7F`); the game's search printed
the `aw_find_fw.py` column of its build, and took from the loader's table the SD backends (893: open
`0x48564A88`, read `0x48564D70`, close `0x48564B4F`; 941: `0x4856580E`, `0x48565AF6`, `0x485658D5`) and
its no-op drive switch `0x502B85BE`; no panel press lost, no failed file read, 8 parts made resident with
46 resources compared to the reference unpack, 0 differing. The saved game IC23s' SHA-1 (prefix) equal
the controls', and the ones `AW.CNV` gave: `eb26c67b...` (893 blank), `14f82423...` (893 owner),
`bc2305dd...` (941 blank). The tap reports, per writer: the game's RAM saw the boot, the firmware
zeroing the converter area when it loaded the loader (893 pc `0x48478E7D`, 941 `0x48479040`), the
loader zeroing the application area (`0x502B8187`, twice: at the start and after YES) and the SD reads
(893 `0x4854BA0D`, `0x4C003031`; 941 `0x4854C0E0`, `0x4C003046`), of `KN7APP.BIN` and, into each record's
destination, of the game's files: "loads 313144, SD reads 474104" writes, no foreign one. The loader's
area saw the firmware load `KN7LOAD.CNV` (14,256 writes) and then only the loader's code, in the
control runs too. The firmware's own IC23 writes during the game are the OCTAVE and SUSTAIN settings'
(893 `0x4C01F310`-`0x4C01F39C`, 941 `0x4C01F325`-`0x4C01F3B1`). The pools saw no write after boot in the
game runs; in the control runs, after NO, the firmware itself (893 `0x48455812` and a copy at
`0x4C003031`, 941 `0x484558DB`, `0x4C003046`) rewrote part of `0x501A5000`-`0x501A6FFF`, ending with the
same bytes (the pools are identical at POWER OFF), which it did not with `AW.CNV` as the control. The
stack pointer seen while the game's code runs stays in `0x5038DD2C`-`0x503AD844`, the kernel's.
Load times per part are in README-CNV.md, "How it was checked"; the loader route needed no fix.

What each run printed is in `OUT/summary.txt` and `OUT/<bios>-<name>/session.txt`; the tap reports
are `ic23.txt`, `pools.txt`, `awarea.txt` and `loader.txt` in each run's directory.

### Through the program menu (2026-10-20, branch `launcher-folders`)

The same tests with the game in `AW\` of the program menu's card (technics-roms-disasm
`kn7000/tools/kn7menu`, `make card` there: the menu as the root's `KN7APP.BIN`, this game in `AW\`,
the ROM dumper's passes 5 to 9 in their folders). `run_menu_route.sh` is `run_cnv_tests.sh` with that
card (copied into the image by kn7menu's `fatimg.py`) and `awmenu_test.lua` is `awcnv_test.lua` with
the menu in front: the session picks "Another World" in the menu's list and presses RUN, and after
"Continue Next?" YES (which now brings the menu back) does so again. The control run is the same card
with `noop_app.s` as the root's `KN7APP.BIN`. The taps count the menu's and the trampoline's code as
the converter's, and allow a firmware write into the converter RAM while the menu runs only as a sector
read the menu asked for, into its destination.

| file                | what it is                                                                                         |
|---------------------|----------------------------------------------------------------------------------------------------|
| `run_menu_route.sh` | the runner: `blank-v13`, `ic23 BIOS BASE NAME` as in `run_cnv_tests.sh`, through the menu          |
| `awmenu_test.lua`   | the session through the menu: `menu`, `launch`, the 16 checks, `menu-again`, `menu-again-run`, ... |

    T=~/compartilhado/tmp/aw-menu-tests     # EMU=a copy of kn7000-emulator; CARDTREE=kn7menu's build/card
    make -C ../../technics-roms-disasm/kn7000/tools/kn7menu card
    probes/cnv/run_menu_route.sh $T blank-v13
    probes/cnv/run_menu_route.sh $T ic23 v13 $T/blank-v13/ic23 blank
    head -c 262144 ~/compartilhado/technics_roms/roms/kn7000/real_dump_v1.3_b893/pass5-run1/R8400000.BIN > $T/owner-ic23.bin
    probes/cnv/run_menu_route.sh $T ic23 v13 $T/owner-ic23.bin owner
    rm -f -- $T/owner-ic23.bin

**Results (2026-10-20, branch `launcher-folders`: the game `KN7APP.BIN` `b80b0205...` in `AW\`, the menu
`0566fba3...`, the loader floppy `b7a67de6...`, overlay binary md5 `5dfebca3...`, `-bios v13`):**

| case                       | session  | ic23w | same                      | accepted          | pools               | area  | loader |
|----------------------------|----------|-------|---------------------------|-------------------|---------------------|-------|--------|
| `ic23 v13 ... blank`, menu | 20 of 20 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v13 ... owner`, menu | 20 of 20 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v13 ... blank`, root | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |

The last row is `run_cnv_tests.sh` as it is, on this branch's build in the card's root, without the menu:
the game still runs as before when the loader starts it directly. Through the menu the session's 20
checks are the 16, plus the menu listing the six programs of its card, the launch (the launch block's
folder `AW`, prefix `AW\`, the game's `AW_PREFIX` `AW\`), and the same two after "Continue Next?" YES
brought the menu back. The saved IC23s equal the controls' and the ones every earlier route gave
(SHA-1 prefixes `eb26c67b...` blank, `14f82423...` owner); the pools `dde3dd9c...`. Every file the game
read came from `AW\` (474,104 bytes of SD reads into the record's destination, as from the root);
the area tap also counts the menu's sector reads (541,696 bytes, each inside the destination it asked
for) and the trampoline's writes (94,338), and no foreign write. The owner's IC23 copy and every image
derived from it were deleted after the run.

### Before the loader: AW.CNV from its own floppy (2026-10-20, retired)

The same tests ran first on `AW.CNV`, the game as a style converter of its own on a floppy with its
files (README-CNV.md, "History"; harness and build at commit `dbc7a2c`). They passed on the overlay
binary of that day (md5 `ed41d01b...`, AW.CNV `7aab745c...`, floppy `b7214529...`), and again,
unchanged, as the baseline for this work on the binary the loader route was tested on (md5
`2a8e2fce...`, which takes the 1 kHz tick from timer 4, gives the DSP handshake once per DSP frame
and lets the DSP read MSGR back):

| case                 | binary        | session  | ic23w | same                      | accepted          | pools               | area  |
|----------------------|---------------|----------|-------|---------------------------|-------------------|---------------------|-------|
| `ic23 v13 ... blank` | `ed41d01b...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |
| `ic23 v13 ... owner` | `ed41d01b...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |
| `ic23 v16 ... blank` | `ed41d01b...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |
| `ic23 v13 ... blank` | `2a8e2fce...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |
| `ic23 v13 ... owner` | `2a8e2fce...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |
| `ic23 v16 ... blank` | `2a8e2fce...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |

In all six, the saved game IC23 equals the control's, and their SHA-1s (prefix) are the same on both
binaries: `eb26c67b...` (893 blank), `14f82423...` (893 owner), `bc2305dd...` (941 blank). The
baseline's `guard` and blank boots also matched (the same stamped checksum `6e1e9dd0` for both blank
IC23s); its full output: research-scratch `aw-kn7load-2026-10-20/baseline-summary.txt`.

In those sessions the floppy's loads took (emulated): the splash 6.5 s, the intro 5.6 s, the lake
4.7 s, the prison 9.8 s, the city 13.3 s (`session.txt` of each run), against well under 2 s each
from the SD card through the loader (above).

**How the runs went wrong before they went right** (AW.CNV, each fixed in its own commit, 2026-10-20;
the fixes are all in `KN7APP.BIN` too):

- the load guard refused the city's last bitmap: it measured a packed bitmap by its unpacked size;
- a failed part list was retried on every call, and YES could not start a new game;
- the firmware still acts on OCTAVE and SUSTAIN while the game runs (`awcnv_panelsettings.lua`): the
  session now presses them in pairs that cancel and checks the settings end as they began;
- with the session driven by `emu.register_periodic`, OK on STYLE TYPE SELECT was lost in every run
  with the owner's IC23 and with a stamped one on 941; driven by the emulated frame and confirming
  each press in the firmware's bitmap, no press was lost in those runs;
- with the owner's IC23, OTHER PART & FR's release was lost while the main task was in a part's first
  file read, the bitmap kept the button down and the emulated panel delivered nothing more (36
  presses lost; the bitmap dump on each lost press showed CPC_SEG5 `0x01` stuck while the converter
  kept being called). AW.CNV now starts a part's loads only once the panel is let go;
- once, the intro's polygons failed to load and loaded on a rerun; a failed file is now retried.

**The panel buttons while AW.CNV runs** (`awcnv_panelsettings.lua`, -bios v13, AW.CNV `61fb4601`,
presses each button once while the game runs and lists the IC23 header bytes each press changed):

| button (game control)             | header bytes changed                              |
|-----------------------------------|---------------------------------------------------|
| PART SELECT RIGHT 1 (RIGHT)       | none                                              |
| PART SELECT LEFT (LEFT)           | none                                              |
| R1/R2 OCTAVE + (UP)               | `0x6EA`: `0x40` -> `0x4C`                         |
| R1/R2 OCTAVE - (DOWN)             | `0x6EA`: `0x4C` -> `0x40`                         |
| SUSTAIN (FIRE)                    | `0xCE`: `0x25` -> `0x2D`                          |
| SUSTAIN again                     | written with the next panel event, back to `0x25` |
| PART SELECT RIGHT 2, DISPLAY HOLD | none                                              |

(In the session, where SUSTAIN comes before any PART SELECT, it changes `0x03A` instead: the sustain
of whichever part is selected.)

Commands for these two, through the loader as the acceptance tests run (`$T` a scratch directory; the
card copy is 121 MB and `pages.bin` 167 MB: delete both afterwards):

    K=$PWD; E=../../kn7000-emulator; R=$T/panelset; mkdir -p $R/nv/kn7000_4 && cp $T/blank-v13/ic23 $R/nv/kn7000_4/
    F=../../technics-roms-disasm/kn7000/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img
    cp $F $R/floppy.img; cp $E/sdcard_from_real_kn7000.img $R/sd.img; chmod u+w $R/sd.img $R/floppy.img
    python3 -I ../../technics-roms-disasm/kn7000/tools/sd_addfile.py $R/sd.img \
      $(cd build/sdcard && for f in *; do printf '%s build/sdcard/%s ' $f $f; done)
    (cd $E && ./kn7000 kn7000 -bios v13 -rompath ./roms -skip_gameinfo -window -nothrottle \
      -harddisk $R/sd.img -flop $R/floppy.img -nvram_directory $R/nv \
      -autoboot_script $K/probes/cnv/awcnv_panelsettings.lua)
    # the intro frame by frame
    (cd $E && AWCK_BIN=$T/pages.bin AWCK_IDX=$T/pages.idx ./kn7000 kn7000 -bios v13 \
      -rompath ./roms -skip_gameinfo -window -nothrottle -harddisk $R/sd.img \
      -flop $R/floppy.img -nvram_directory $R/nv2 -autoboot_script $K/probes/cnv/awcnv_cksum.lua)
    python3 -I probes/cksum_pages.py $T/pages.bin $T/pages.idx $T/cnv_checksums.log
    python3 -I probes/compare_frames.py $T/cnv_checksums.log \
      ~/compartilhado/research-scratch/kn7000-aw-reference/ref_checksums.log

The intro on 893 through the loader (`KN7APP.BIN` `b952c2aa...`): "first frame at t=63.2 s; global
files loaded in 831 ms, load errors 0, task 10", "captured 2613 frames (last tick 2612); part loads 3,
load errors 0, guard 0", and `compare_frames.py`: 2612 of 2612 frames identical to the reference
(the checksum log: research-scratch `aw-kn7load-2026-10-20/intro_checksums_kn7app.log`). With `AW.CNV` and its floppy (`b7214529...`) the same check
gave "captured 2613 frames (last tick 2612); part loads 3, load errors 0, guard 0", and 2612 of 2612
frames identical.

## Round 3 (2026-10-21): the bank's speed, the keybed-only controls, the keybed-sound key, the help screen

Felipe's requests after the DSP build ran on his unit (README-CNV.md): a faster sample bank, the right URL on the help
screen, the sound mode selectable in HELP, B and B♭ as UP, no game control on the panel; and a panel key that mutes
the instrument's own notes for the keys that steer the game. Light, as asked: the build's guards and two MAME
sessions on the final build (the first on `59629a40...`, the build before the help screen's dot; the second on
`7f8ed09a...`), plus one bank-only session on the build before (`a2fbbaa6...`).

| file                         | what it is                                                                                                                     |
|------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| `run_round3.sh OUT [MODE]`   | the runner, as `run_dsp.sh` (the menu card, program 893); MODE `full` (default) or `bank`; `SDDIR=` an older build's `sdcard/` |
| `awcnv_round3.lua`           | the session (its header says every step and what it reads); `bank`: the bank load alone, timed and taken apart                 |
| `round3_report.py OUT`       | the bank timings (`bank.txt`, `bank2.txt`) and the recording's level in each "keys window"                                     |
| `awcnv_keymute.lua`          | no game: which MIDI message mutes the keybed's notes, and how the firmware takes CC 11 (its header)                            |
| `round3-results-2026-10-21/` | the runs' text files: `before/` (bank only, `a2fbbaa6...`), `after/` (`7f8ed09a...`), `keymute/`                               |

    probes/cnv/run_round3.sh ~/compartilhado/tmp/aw-round3/run full      # from kn7000/; DISPLAY=:0; about 8 minutes
    SDDIR=<an older build's sdcard/> probes/cnv/run_round3.sh ~/compartilhado/tmp/aw-round3/before bank

**Where the bank's time went, and goes** (`bank.txt`; time from the DSP setup, state 5, to the game task, state 3;
"card" is inside `BankRead` until the unpacker starts, "unpack" the ByteKiller unpacker, "fw" from our answer to the
next converter call, "dsp" the rest of the calls; the handshakes are writes of 1 to G17ICR `0x3400015C`):

| figure                        | before, `a2fbbaa6...` | after, `7f8ed09a...` |
|-------------------------------|-----------------------|----------------------|
| total                         | 25.87 s               | 11.62 s              |
| card                          | 10.19 s (93 files)    | 3.89 s (14 files)    |
| unpack                        | 1.74 s                | 0                    |
| fw (between calls)            | 1.68 s (97 calls)     | 0.22 s (29 calls)    |
| dsp (host port, our work)     | 12.26 s               | 7.51 s               |
| handshakes                    | 359,792               | 238,656              |
| ... upload halves             | 343,892               | 215,375              |
| ... register halves           | 10,246                | 11,944               |
| ... MSGR4 reads (polls)       | 4,322                 | 9,250                |
| ... other reads               | 1,332                 | 2,087                |
| handshakes at 22.68 us (unit) | 8.16 s                | 5.41 s               |

MAME's handshakes took 34.1 and 31.5 us on average (the firmware's own code between two accesses often misses a
frame there); on the unit pass 8 found 96.8 % of the firmware's accesses one frame apart. The second start (YES,
the menu, RUN) found the bank by its marker and only had the DSP checksum it: 0.43 s (`bank2.txt`; its counters
are the two starts' sums, the session did not reset them then; it does now).

**What the full session showed** (`after/events.txt`, `after/report.txt`):

| check             | result                                                                                                                          |
|-------------------|---------------------------------------------------------------------------------------------------------------------------------|
| bank              | all 171,576 words, the DSP's checksum equal to `AWBANK.AW`'s (DV_BK_SENT 1), slots hooked at `0x8140` / `0x8257`                |
| DSP sound         | 15 s of the intro: voices 0-5 seen sounding, the mix up to 915,072, the dead flag 0                                             |
| B♭5, B5 (UP)      | each held alone: var 0xE5 = -1, var 0xFD = 8; A5: +1 and 4                                                                      |
| the panel         | R1/R2 OCTAVE + and - (twice each), PART SELECT LEFT, RIGHT 1 (twice), SUSTAIN (twice), each held: vars 0xFC, 0xE5, 0xFA, 0xFD 0 |
| keybed sound      | RIGHT 1: the firmware's expression for channel 1 (`0x5000B36B`) 0x7F, 0x00, 0x7F; IC23 0 of 65,536 words changed; no MIDI drop  |
| HELP, RIGHT 2     | three presses in HELP: TONE GENERATOR (slots back), OFF, DSP SAMPLES (hooked again); the help stayed up, the line redrawn       |
| HELP, RIGHT 1     | two presses: "KEYBED SOUND: OFF", "ON"                                                                                          |
| HELP lines        | "NOW: DSP SAMPLES", "KEYBED SOUND: ON", "SENT IN 11.4 S"; at the second start "CHECKED IN 0.2 S"                                |
| page 3 (snapshot) | "github.com/felipesanches/" over "technics-anotherworld", the period a solid dot                                                |
| quit              | muted before it; after it AU_KEYSENT 0 and the expression 0x7F; both slots as at boot, MSGR4-7 0; again after the second game   |

**The keybed's sound in MAME cannot be heard to change.** The recording's level is the same in every window (-46.4
to -47.0 dBFS, `report.txt`), muted or not, and the same for CC 7 = 0 and for notes sent as MIDI IN
(`keymute/levels-report.txt`): the overlay's tone generator ignores the voice level word (class 0x3000) where the
firmware puts expression. The firmware's side is plain: CC 11 = 0 on channel 1 sets `0x5000B36B` from 0x7F to 0
and back (`keymute/ramdiff-events.txt`), and a keybed C4's tone-generator writes differ in one register only, the
level word of its two voices, 0x0BE8 / 0x0BA4 at 127, 0x0000 at 0, the same again at 127 (`keymute/tg.txt`, one
column per case; mask the voice number, bits 4-7 of the address, and drop the 0xFCxx polling). Felipe's ears decide.

## Sound on the effects DSP (2026-10-21): the game's own samples

The DSP build (README-CNV.md, "Sound": `src/dsp.s`, `tools/dsp_mixer.py`) in one MAME session through the program
menu, as Felipe runs it. Light, as asked for this iteration: one session, no sweeps.

| file            | what it is                                                                                                 |
|-----------------|------------------------------------------------------------------------------------------------------------|
| `run_dsp.sh`    | the runner: builds the card (the menu as the root `KN7APP.BIN`, `build/sdcard/` as `AW\`), runs MAME       |
| `awcnv_dsp.lua` | the session (below) and a tap of the game's and the DSP's state every 0.25 s (`OUT/tap.txt`, `events.txt`) |
| `dsp_report.py` | the verdict: one line per check (its docstring says what each reads), "dsp_report: N of M checks"          |

    probes/cnv/run_dsp.sh ~/compartilhado/tmp/aw-dsp/run    # from kn7000/; DISPLAY=:0; about 10 minutes

The session (program 893, `-bios v13`; the owner's loader floppy as released; a fresh copy of the real card): DISK
MENU, STYLE CONVERT, OK; the menu; "Another World", RUN; the firmware search, the global files, the DSP set up and
the whole bank sent; the splash skipped (`NO_SPLASH`, as `awcnv_cksum.lua`); the intro with no input; PART SELECT
RIGHT 2 at intro + 25 s (tone generator), + 35 s (off), + 45 s (DSP again); EXIT held 2 s at intro + 60 s; EXIT;
"Continue Next?" YES; the menu, RUN again (the bank must not be sent again); 15 s of the game; EXIT held; EXIT; NO;
a C4 on the keybed. The recording (`OUT/run.wav`) is the game's own music: never commit it.

What it showed, for `KN7APP.BIN` `a2fbbaa6...` (the run's files: `dsp-results-2026-10-21/`; the published overlay,
md5 `3077b137...`; the menu `0566fba3...`), `dsp_report: 11 of 11 checks`:

| check      | result                                                                                                                                                  |
|------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| `dead`     | the firmware's dead flag 0 at all 771 samples after the boot (20-212.5 s)                                                                               |
| `setup`    | the 8-step firmware search 6.8 s from RUN (DSP routines found: `1F`); the mixer loaded, read back, hooked; the whole bank, 171,576 words, in 25.9 s     |
| `hooked`   | through the intro in DSP mode PM `0x8080` = `06BE04008200`, PM `0x80A0` = `06BE04008296`; MSGR7 and unit 9's count both 44,100 a second                 |
| `voices`   | all eight voices sounded (the music's in 63, the effects' in 46 of 93 quarter-seconds); unit 0's and unit 9's returns carried the mix, peak 1,224,576   |
| `midi`     | MIDI messages sent: 0 in the DSP mode, 76 in the tone generator's, 0 when off, 0 in the DSP mode again                                                  |
| `modes`    | TG: both slots back as at boot, nothing hooked (35 samples); DSP again: both hooked (54 samples)                                                        |
| `restored` | after each quit both slots as at boot, MSGR4-MSGR7 0; DM `0xC003` (the reverb's store of I6) 1 value while hooked, 16 in the 4 s after: the reverb runs |
| `again`    | YES, the menu, RUN: the bank found in SDRAM by its marker, not sent again (the DSP setup 0.1 s)                                                         |
| `sound`    | the recording: -240 dBFS before the game; the intro on the DSP -61.9 to -38.4 dBFS a second, every second more than 20 dB above that                    |
| `music`    | the 47 quarter-seconds in which only the music's voices sounded: -52.1 to -43.4 dBFS, all of them audible                                               |

The tone generator's notes in MAME ring on after their note-off (the overlay's tone generator, as in "Sound" below),
so after the TG interval the recording and unit 0's input stay loud (-29 to -28 dBFS) through OFF and later: that
is not the DSP. MAME mixes unit 9's return only while the CHORUS is on (its bridge), so the recording heard the mix
through unit 0's return (REVERB on, the default); the tap shows unit 9's return carrying the same mix. In MAME the
DSP's sound is about 10 dB below the tone generator's for the same intro: MAME's return level is not calibrated.
Not checked here: the help screen's mode line, a part switch, the watchdog (the firmware stopping the calls), a
program build other than 893.

## Sound (2026-10-20): the game as a MIDI source on the firmware's receive ring

`src/audio.s` (README-CNV.md, "Sound") writes MIDI into the MIDI IN 1 receive ring as the RX ISR does.
These answer whether the firmware takes it, and whether the intro still runs with the music's sync
marks. All on program 893 (`-bios v13`) through the owner's loader floppy, each one MAME run with
`-wavwrite` (the commands below; `$F` a scratch directory holding a card copy with `build/sdcard/`
added, the loader floppy image and, for the last, the SMF; never `/tmp`).

| file                  | question                                                                                                                         |
|-----------------------|----------------------------------------------------------------------------------------------------------------------------------|
| `awcnv_midiprog.lua`  | before audio.s: are bytes written into the ring consumed and played? do program change and bank select work on PART 4 and 10?    |
| `midiprog_spectra.py` | its reading: flatness, peaks, level and C4's harmonics per segment                                                               |
| `awcnv_sound.lua`     | the sound build's intro with no input: messages sent / dropped, ring rd vs wr, rows, PLAY_SOUNDs, var 0xF4, the toggle, the quit |
| `wavrms.py`           | level (dBFS) and dominant frequency per window of a recording                                                                    |
| `awcnv_noteoff.lua`   | are the game's note-offs honoured as MIDI IN's are? the same notes through the ring and through the port                         |
| `gen_noteoff_mid.py`  | the SMF for awcnv_noteoff.lua's MIDI IN half (`-midiin1`)                                                                        |
| `noteoff_levels.py`   | its reading: each note's level from note-on to 2.5 s after its note-off                                                          |

What they showed:

| probe                | KN7APP.BIN    | result                                                                                                                                                                                                                                                                                                                                                                                                                             |
|----------------------|---------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `awcnv_midiprog.lua` | `e3ee3a40...` | every byte consumed; program 80 alone and with bank 121/0 make PART 4 a square wave (C4's even harmonics 49-58 dB down), program 48 sawtooth-like strings, program 0 piano; channel 10 is a drum part as it is and after bank 120/0 (a 57 Hz thump on key 36, 216 Hz on 38)                                                                                                                                                        |
| `awcnv_sound.lua`    | `15f5c57e...` | 1,704 messages, 0 dropped, rd = wr at every sample; 951 rows; the 24 marks of module 0x07 in order into var 0xF4; the intro stops the music at mark 49 and reaches the lake by itself (tick about 2,660); 211 PLAY_SOUNDs; silent before the game, -27 to -49 dBFS in the intro; nothing sent while RIGHT 2 had the sound off; the quit's all notes off / all sound off / reset all controllers on channels 4-7 and 10-14 consumed |
| `awcnv_noteoff.lua`  | `97fbd9e6...` | ring and MIDI IN port alike: GM 80 falls about 40 dB within 1 s of its note-off (C4 132 -> 89 dB, G4 128 -> 91), GM 0 rings on either way (E4 92 -> 90, A4 110 -> 108): the overlay's tone generator, not the path                                                                                                                                                                                                                 |

In MAME notes of some voice classes ring on after their note-off whatever sends them (kn7000_mame
`notes/tg-envelope-implementation-plan.md`: the overlay releases them only on a keybed key-up), so the
recordings cannot show that every note ends; the unit can.

    K=$PWD; E=../../kn7000-emulator; F=~/compartilhado/tmp/aw-sound/feas      # from kn7000/
    cp $E/sdcard_from_real_kn7000.img $F/sd.img; chmod u+w $F/sd.img
    python3 -I ../../technics-roms-disasm/kn7000/tools/sd_addfile.py $F/sd.img \
      $(cd build/sdcard && for f in *; do printf '%s build/sdcard/%s ' "$f" "$f"; done)
    cp ../../technics-roms-disasm/kn7000/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img $F/floppy.img
    cd $E && AWS_OUT=$F/sound.log DISPLAY=:0 ./kn7000 kn7000 -bios v13 -rompath ./roms -pluginspath ./plugins \
      -skip_gameinfo -window -nothrottle -harddisk $F/sd.img -flop $F/floppy.img -nvram_directory $F/nv \
      -cfg_directory $F/cfg -wavwrite $F/sound.wav -autoboot_script $K/probes/cnv/awcnv_sound.lua
    python3 $K/probes/cnv/wavrms.py $F/sound.wav 60 246 1.0
    # awcnv_noteoff.lua: the same, with AWN_OUT, a fresh card copy, the SMF and its reading:
    python3 $K/probes/cnv/gen_noteoff_mid.py $F/noteoff.mid      # then add -midiin1 $F/noteoff.mid
    python3 $K/probes/cnv/noteoff_levels.py $F/noteoff.wav

The recordings are of the game's own music: regenerate them, never commit them. The card copy is
121 MB: delete it afterwards.

## Speed (2026-10-20): where a frame's time goes

On the owner's KN7000 the game ran, but its frame rate was very low. MAME gives every memory access the
same cost, with no wait states, so it cannot show why; what it can do is count the accesses the game
makes per VM tick in each region, and check that a faster blit leaves the LCD as it was. The probes
run through the loader exactly as the acceptance tests do (`run_perf.sh`: the owner's floppy, a copy
of the real card with `CARDFILES` added, fresh NVRAM, program 893; the game's `AWPERFn.TXT` files are
copied off the card before it is deleted):

| file                  | question                                                                                                                                                                              |
|-----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `run_perf.sh`         | the runner: one MAME run with a given autoboot script and card files; the card copy is deleted after                                                                                  |
| `awcnv_perf.lua`      | per VM tick: the game's stores into the LCD frame (by size), its loads from it, its accesses to the pages and to the rest of its RAM; the firmware's LCD stores; the emulated time    |
| `awcnv_fwlcd.lua`     | while the game runs, when and where does the firmware draw on the LCD? 10 s with no input, then each panel button and a key, 4 s each; or (`AWL_INTRO=1`) through the intro           |
| `awcnv_lcd8.lua`      | since the 8-bit LCD: FB8's window and border, the controller, the look-up table at every tick (`src/lcd8.s`)                                                                          |
| `awcnv_loadblack.lua` | is the screen black while a part loads, and does the firmware draw nothing while the game runs? the intro into the lake, then the quit (`src/fwdraw.s`)                               |
| `lcd_cost.py`         | what the counted LCD accesses cost at the unit's measured times (pass 9), or at others given                                                                                          |
| `awcnv_lcd.lua`       | at every VM tick of the intro and the lake: is the whole LCD frame the picture of the front page for the display mode in use? (`AWL_PRESS`: PAGE UP / DOWN at given ticks); snapshots |
| `awcnv_speed.lua`     | the owner's run on the instrument, in MAME: the overlay, the old blit and back, the speed page, quitting; what the game measures in MAME's time; `AWPERF0.TXT`                        |

**Why it was slow.** Before (`KN7APP.BIN` `b952c2aa...`, the intro, ticks 1-300, mean per tick):

| region              | accesses per tick                                |
|---------------------|--------------------------------------------------|
| LCD frame, 16-bit   | 128,000 stores: the window, 64,000 pixels, twice |
| LCD frame, 32-bit   | 89,600 stores: the black border, 44,800, twice   |
| VM pages            | 141,694 loads, 21,231 stores                     |
| the rest of its RAM | 6,470 loads, 2,188 stores                        |
| the firmware's LCD  | 0 stores                                         |

Every tick blitted the front page twice (the bytecode's own blit, then `NextThread`'s at the end of
every frame) and repainted the whole border with each blit: 217,600 stores, about 614 KB, into the LCD
frame per tick, whatever changed. The ROM dumper's pass 9 measured the costs on the owner's unit
(technics-roms-disasm `cnv_romdump`, 2026-10-20, run by the main session): the core runs at 64 MHz, a
cached work-RAM access takes one 15.6 ns cycle (a new 16-byte line 389 ns to load), and the LCD frame
is on a 16-bit bus with four wait states (MEMCTR3 `0x0424`, which also covers the DSP's ports): a
16-bit store 439 ns, a 32-bit store 888 ns (two accesses), a 16-bit load 694 ns. At those times
`lcd_cost.py` puts the old build's LCD stores at **136 ms per tick**, a ceiling of 7 frames per second
before any other work, where the gameplay asks for 25 or 50. (Before pass 9 a model from the bus
set-up, 4 or 7 waits on a 16-bit bus at a guessed 16 MHz, gave 115 or 173 ms: `lcd_cost.py --model`.)

**The firmware's own drawing.** The firmware drew on the LCD before the first VM frame (its text
screen, 458,880 stores from `0x48414F92`), and with the game running it drew nothing in 10 s with no
input or after R1/R2 OCTAVE + / -, SUSTAIN (twice), PART SELECT RIGHT 1 / LEFT, PAGE UP (twice), PAGE DOWN,
HELP, EXIT, OTHER PART & FR or a keybed key. But through the intro (`AWL_INTRO=1`) it repainted its whole
text screen twice (305,920 stores, `0x48414F92`) between ticks 2600 and 2800, when the intro hands over
to the lake and the lake's files load; in a traced run of the new build (`AWL_TRACE`) that painting was
split around one of the game's frames (301,406 stores before the frame's check, 4,514 after it), so it is
not confined to one yield of the game and may land at any moment. The old blit painted over it at every
blit. **DISPLAY HOLD**: in the first run, pressed in the intro, the firmware repainted the
whole screen (152,960 stores) and stopped calling the converter for the rest of the run (so EXIT could
no longer end the game); in the second, pressed on the level-code screen, it did nothing. Do not press
DISPLAY HOLD while the game runs.

**After** (`KN7APP.BIN` `26aabecb...`, the same ticks): **2,036 32-bit stores into the LCD frame per tick**
(most ticks a few hundred; 76,800 for each of the two full repaints that follow the intro's load) and
the 47 sentinel loads, **1.84 ms per tick** at the unit's times (from 135.84); the pages' loads 45,931,
their stores 16,718; the rest of the RAM 8,358 loads and 2,271 stores (the measuring). In MAME's own
time a tick of the intro took 45.9 ms on average, from 122.7 (the bytecode asks for 40).

| check                                  | before (`b952c2aa`) | after (`26aabecb`)                                                |
|----------------------------------------|---------------------|-------------------------------------------------------------------|
| LCD stores per tick (16 / 32-bit)      | 128,000 / 89,600    | 0 / 2,036                                                         |
| LCD time per tick at pass 9's costs    | 135.84 ms           | 1.84 ms                                                           |
| the intro's pages against rustyworld   | 2612 of 2612        | 2612 of 2612                                                      |
| LCD = the old blit's picture, per tick | 3601 of 3601        | 3600 of 3601: tick 2612, the firmware painting, put right at 2613 |
| LCD snapshots every 100 ticks          | -                   | 37 of 37 byte-identical to the old build's                        |

The intro's page checksums of the new build: research-scratch
`sessions/2026-10-20_aw-perf/intro_checksums_kn7app_26aabecb.log` (`awcnv_cksum.lua` through
`run_perf.sh`, then `cksum_pages.py` and `compare_frames.py` as above). The one tick: while the firmware
was repainting its text screen (above), 5,347 pixels showed its
painting at the check; one sentinel pixel caught it after the next yield and the next blit repainted
everything. An earlier version with 16 sentinels and no repaints after a load (`c1fd72bc`) missed the
same painting in the border for 500 ticks, until the periodic repaint; hence the 47 sentinels read
after each yield and the repaints 5 and 30 frames after each load.

**The game's own figures in MAME** (`awcnv_speed.lua`, `26aabecb`, MAME's time, no wait states; the
intro): new blit 25.1 frames per second, 39.8 ms a frame (blit 7.9 ms, yield 31.1); old blit (PAGE
DOWN) 8.7 frames per second, 114.1 ms a frame (blit 97.1, border 9.1); over the run 25.0 and 8.7
frames per second. The speed page and the overlay in their snapshots fit their places; `AWPERF0.TXT`,
1,979 bytes, holds the same page, the figures per part and blit, the benchmark and the registers.
(MAME reads 0 from the bus controller's registers and gives every access the same 43 ns; the unit's
figures will say what matters.)

    T=~/compartilhado/tmp/aw-perf    # EMU=a copy of kn7000-emulator; CARDFILES=the build's card files
    probes/cnv/run_perf.sh $T/base-perf probes/cnv/awcnv_perf.lua           # AWP_MAX=300
    probes/cnv/run_perf.sh $T/base-fwlcd2 probes/cnv/awcnv_fwlcd.lua         # DISPLAY HOLD last
    AWL_HOLD_EARLY=1 probes/cnv/run_perf.sh $T/base-fwlcd probes/cnv/awcnv_fwlcd.lua   # ... as the first run
    AWL_INTRO=1 probes/cnv/run_perf.sh $T/base-fwintro probes/cnv/awcnv_fwlcd.lua
    python3 -I probes/cnv/lcd_cost.py $T/base-perf/perf.tsv $T/fin-perf/perf.tsv [--model]
    AWL_PAL=0x$(grep ' palette$' build/kn7app.map | cut -c3-10) AWL_TRACE=2605-2650 \
      probes/cnv/run_perf.sh $T/fin-lcd probes/cnv/awcnv_lcd.lua           # the same for the old build
    for f in $T/fin-lcd/lcd_*.bin; do cmp $f $T/base-lcd/$(basename $f); done
    probes/cnv/run_perf.sh $T/fin-speed probes/cnv/awcnv_speed.lua
    AWCK_BIN=$T/fin-ck/pages.bin AWCK_IDX=$T/fin-ck/pages.idx probes/cnv/run_perf.sh $T/fin-ck probes/cnv/awcnv_cksum.lua

The acceptance tests (above) gained two checks for this build: `speed` (the speed page, the overlay on
and off, the old blit and back with the VM running, IC23's header unchanged) and `report` (the first
quit leaves `AWPERF0.TXT`, the second `AWPERF1.TXT` beside it, the text the game built).

## The screen during loads (2026-11-02)

Felipe saw the firmware's screen during part loads on the instrument. `awcnv_loadblack.lua` (through `run_perf.sh`,
program 893, the intro from tick 0 into the lake, then EXIT held) counts, at every MAME frame while a part loads,
the LCD frame's pixels that are not black, and all along the stores into the LCD frame from outside KN7APP.BIN's
code. The build on the card then (`7b07e0f1`) against the one with `src/fwdraw.s` (`1fc493e5`):

| check                                       | `7b07e0f1`                         | `1fc493e5`                              |
|---------------------------------------------|------------------------------------|-----------------------------------------|
| the intro's load (0x3E81): non-black pixels | max 50,195, mean 45,341 of 153,600 | 0 at all 35 frames                      |
| the lake's load (0x3E82): non-black pixels  | max 67,744, mean 56,232            | 0 at all 32 frames                      |
| firmware stores into the LCD, each load     | 305,920                            | 0                                       |
| the loads' time                             | 0.98 s, 0.93 s                     | 0.58 s, 0.53 s                          |
| converter calls a second, the intro         | 13.4                               | 69.7                                    |
| firmware stores while the VM runs           | -                                  | 0                                       |
| ScreenProc paints skipped, to the lake      | -                                  | 12,296; drawing turned on again 0 times |
| after the quit: table, DrawEnable, its copy | `0x48724914`, 1, 1                 | `0x48724914`, 1, 1                      |

The new build's other firmware stores: 152,960 between the game task's start and its first load (the firmware's
text screen as the answered text changes to HOLD EXIT TO QUIT, before the hook takes hold; the load's black covers
it), and 141,061 after EXIT (the firmware's own screen and "Continue Next?"). Snapshots in the middle of each load:
the old build shows the STYLE CONVERT screen with "LOADING ANOTHER WORLD: SOUNDS", then its title bar and the load
bar over the game; the new one black.

The final build (`cddfe76b`: the same, and BankRead's `LD_IN_READ` flag for the acceptance test's area check) gave
the same: both loads black at all 35 and 33 frames, 0.58 and 0.55 s, no firmware store during loads or play, 69.8
converter calls a second, the table and DrawEnable back after the quit; 142,716 firmware stores before the first load
and 152,960 after EXIT (the split between the two moves with the timing of the firmware's repaints).

    T=~/compartilhado/tmp/aw-loadblack
    AWLB_OUT=$T/new probes/cnv/run_perf.sh $T/new probes/cnv/awcnv_loadblack.lua
    AWLB_OUT=$T/old CARDFILES=$T/oldcard probes/cnv/run_perf.sh $T/old probes/cnv/awcnv_loadblack.lua   # build/sdcard, the old KN7APP.BIN

## Two display modes (2026-11-02)

The overlay (PAGE UP) and the old blit (PAGE DOWN) are gone; PAGE UP shows the picture enlarged to 384x240 (the
default: `display.s` BlitBig, 6/5 both ways, the middle pixel and row of every 5 doubled), PAGE DOWN at the original
320x200. (Replaced the same day by true 384x240 pages: "384x240 pages", below. The results in this section are
`KN7APP.BIN` `9a2f2db4`'s.) `awcnv_lcd.lua` now reads the mode at every tick and checks the whole LCD frame against that mode's
picture of the front page; `AWL_PRESS` presses the buttons. Program 893, the intro from tick 0 into the lake, ticks
0-3600, PAGE DOWN at 800, UP at 1600, DOWN at 2700, UP at 3000 (and, as it happened, presses of Felipe's in the
MAME window during the intro):

| ticks checked                  | enlarged | 320x200 | differ | mode switches |
|--------------------------------|----------|---------|--------|---------------|
| 3601 (`KN7APP.BIN` `9a2f2db4`) | 1705     | 1896    | 0      | 4             |

No firmware store into the LCD after tick 0 (the screen it left before the game). The cost, `awcnv_perf.lua` over the intro's ticks
10-300 (`AWP_ORIGINAL=1` holds PAGE DOWN from the start), mean per tick:

| mode     | LCD 32-bit stores | LCD loads (sentinels) | page loads | at the unit's 888 ns a store |
|----------|-------------------|-----------------------|------------|------------------------------|
| enlarged | 2,273.7           | 45                    | 49,968     | 2.0 ms                       |
| 320x200  | 1,623.5           | 47                    | 45,874     | 1.4 ms                       |

A full repaint is 76,800 stores in both (window and border cover the whole LCD). The acceptance tests (`run_cnv_tests.sh
ic23`, blank IC23, 893 and 941) pass all checks with this build; `speed` now checks the modes: enlarged at the start,
PAGE DOWN twice 320x200, PAGE UP twice enlarged, two switches, the VM running in both. `awcnv_speed.lua` drives the
overlay and the old blit, and so serves only builds before this one.

    T=~/compartilhado/tmp/aw-bigscreen
    AWL_OUT=$T/lcd AWL_PAL=0x$(grep ' palette$' build/kn7app.map | cut -c3-10) AWL_MAX=3600 \
      AWL_PRESS="800:DOWN,1600:UP,2700:DOWN,3000:UP" probes/cnv/run_perf.sh $T/lcd probes/cnv/awcnv_lcd.lua
    AWP_OUT=$T/perf-big AWP_FROM=10 AWP_MAX=300 probes/cnv/run_perf.sh $T/perf-big probes/cnv/awcnv_perf.lua
    AWP_OUT=$T/perf-orig AWP_ORIGINAL=1 AWP_FROM=10 AWP_MAX=300 probes/cnv/run_perf.sh $T/perf-orig probes/cnv/awcnv_perf.lua

## 384x240 pages (2026-11-02)

Felipe asked for a true higher resolution in place of the enlarged picture (its repeated rows distorted the text):
the VM's pages are 384x240 in the default mode, the polygons drawn at that resolution, the text in 8x8 glyphs where
the game puts it (README-CNV.md, "The screen"). PAGE DOWN gives 320x200 pages, PAGE UP 384x240 again. Program 893,
`KN7APP.BIN` `ccf024e4`:

| check                                                                  | result                                               |
|------------------------------------------------------------------------|------------------------------------------------------|
| Felipe's session replayed at 320x200 (`run_inplog.sh`), rustyworld     | 1346/1346 pages; all 256 variables at every frame    |
| the whole intro (rec2) replayed at 384x240 (`AW_HIRES=1`)              | all 256 variables = rustyworld's at all 3218 frames  |
| ... its pages brought to 320x200 as PageDown does (`hires_vs_ref.py`)  | 89.9-100% of the pixels = rustyworld's, median 96.0% |
| the LCD against the page, intro and lake, 4 switches (`awcnv_lcd.lua`) | 3601/3601 ticks: 2502 at 384x240, 1099 at 320x200    |
| acceptance tests (`run_cnv_tests.sh ic23`, blank IC23)                 | all checks pass on 893 and 941                       |
| a tick of the intro, ticks 10-300, MAME's time (`awcnv_perf.lua`)      | 61.3 ms at 384x240, 48.8 at 320x200 (48.6 before)    |

The agreement can't be 100%: the polygons' edges fall where the higher resolution puts them. A wrong scene would
stand out (an unreplayed intro, whose music marks came at other frames, showed scenes cut early at 0-60%: that is
why the comparison replays the logged marks). The lowest frames, around 2713, are the lab's console scene with
many small polygons. The LCD check found, on the way, that inverting SHADOW to force a full write left a group
unwritten whenever its new word was the inverse of the old one (tick 851, four pixels): `BlitAll` writes everything
without comparing. Per tick at 384x240: 2,186 LCD stores (1,624 at 320x200), page loads 42,327 and stores 22,259
(29,396, 15,666).

    T=~/compartilhado/tmp/aw-hires/fin
    probes/cnv/run_inplog.sh $T/urep replay SESSION.awr                       # 320x200, then compare_frames.py, varsdiff.py
    AW_HIRES=1 probes/cnv/run_inplog.sh $T/rep2hi replay rec2/session.awr      # 384x240
    REF_BIN=ref.bin REF_IDX=ref.idx replayawr rec2/session.awr ref.log        # rustyworld's pages (REF_VARS: variables)
    python3 probes/hires_vs_ref.py $T/rep2hi/pages.bin $T/rep2hi/pages.idx ref.bin ref.idx [-o DIR FRAME...]
    AWL_OUT=$T/lcd AWL_PAL=0x... AWL_MAX=3600 AWL_PRESS="800:DOWN,1600:UP,2700:DOWN,3000:UP" \
      probes/cnv/run_perf.sh $T/lcd probes/cnv/awcnv_lcd.lua                   # AWL_DUMPBAD=n: dumps of wrong ticks
    AWP_OUT=$T/perf-hi AWP_FROM=10 AWP_MAX=300 probes/cnv/run_perf.sh $T/perf-hi probes/cnv/awcnv_perf.lua  # AWP_ORIGINAL=1

## The ambilight (2026-11-02)

Felipe asked for the black sides to glow with the picture's colours, by palette changes alone, and then (watching a
run) for no seam in the middle of the bands above and below the 320x200 window and a wider dither. The game now
drives the LCD at 8 bits a pixel through its look-up table, in its own frame FB8 (README-CNV.md, "The screen";
`src/lcd8.s`). Program 893, `KN7APP.BIN` `964e245a`:

| check                                                              | result                                                                                            |
|--------------------------------------------------------------------|---------------------------------------------------------------------------------------------------|
| FB8's window = the page, every tick (`awcnv_lcd8.lua`)             | 3601/3601 ticks (2502 at 384x240, 1099 at 320x200, 4 switches)                                    |
| the border between its drawings (start and each switch)            | never written: 5 drawings, 0 changes; every byte an entry 16-255                                  |
| the controller (REG[040h] 8 bits a pixel, start 0x03ABFF)          | as set at all 3601 ticks                                                                          |
| the look-up table (a copy kept from every REG[1E2h], [1E4h] write) | = PF_PAL's palette and AMB_LUT's entries at all 3601 ticks                                        |
| part loads, MAME's screen (`awcnv_loadblack.lua`)                  | black from the second frame on (the first: the picture before)                                    |
| after the quit                                                     | REG[040h], [042h]-[044h], [046h]-[047h] the firmware's again                                      |
| acceptance tests (`run_cnv_tests.sh ic23`, blank IC23)             | all checks pass on 893 and 941                                                                    |
| a tick of the intro, ticks 10-300 (`awcnv_perf.lua`)               | 607 / 435 display-memory stores (2186 / 1624 before); 63.9 / 50.3 ms of MAME's time (61.3 / 48.8) |

Two of the probe's first ways were wrong and are recorded here so as not to be tried again: comparing MAME's screen as a
script reads it (`screen:pixels()`) with what the game had set differed now and then (4 of 145 samples; 44 of 96 when
waiting for a still display), because that is the screen bitmap being drawn into next (`screen_device::pixels`,
`m_bitmap[m_curbitmap]`), a frame or two behind; the table is therefore checked from its writes, and the screen only
dumped for the eye (`AWL_DUMPAT`). And the game's own check of the start address first compared 0xAC0F (a slip:
240639 is 0x3ABFF), which the probe caught as the controller "not as set" at every tick. On 941 the firmware wrote
IC23 952,175 times during the session (526,391 with the 16-bit builds; none from the game; the saved IC23 identical
to the control run's).

    T=~/compartilhado/tmp/aw-ambi/fin
    AWL_OUT=$T/lcd8 AWL_PAL=0x$(grep ' palette$' build/kn7app.map | cut -c3-10) AWL_MAX=3600 \
      AWL_PRESS="800:DOWN,1600:UP,2700:DOWN,3000:UP" AWL_DUMPAT="1200,2100" probes/cnv/run_perf.sh $T/lcd8 probes/cnv/awcnv_lcd8.lua
    AWLB_OUT=$T/lb probes/cnv/run_perf.sh $T/lb probes/cnv/awcnv_loadblack.lua
    python3 probes/screen2png.py $T/lcd8/screen_*.bin --sheet sheet.png      # the dumps, to look at

## Settings and loading screen (2026-11-02)

The settings page (help page 4) and `AWPREFS.CFG`, and the loading screen (README-CNV.md, "Settings"; `src/prefs.s`,
`src/lcd8.s`), checked with `run_prefs.sh` (`awcnv_prefs.lua`, two runs of program 893: a card without the file, then
one with the file the first run wrote). `KN7APP.BIN` SHA-1 `9bfd11f2`, 38,204 bytes:

| check     | what is read                                                          | result                                                                            |
|-----------|-----------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| `loading` | `LCD_OWNED`, `LOAD_PCT` and the controller's bpp, every frame from OK | LCD taken 9.3 s after OK, 8 bpp throughout, 57 percentages 0-100, none going back |
| `page`    | `HELP_PAGE`, `PR_SEL` after PAGE DOWN x3 and the keybed moves         | page 3 (the fourth), row 4                                                        |
| `apply`   | `PREFS_AT` +4..+8, `PG_W`, `AMB_LUT`, `AU_KEYWANT` after each change  | ambilight off and black, 320x200, scatter 2, keybed off, LEDs off                 |
| `saved`   | `PR_WROTE`, `PR_FAILS`, `PR_DIRTY` 5 s after EXIT                     | written 5, failed 0, dirty 0, the game running                                    |
| `read`    | `PR_STATUS` and `PREFS_AT` in the second run                          | status 1 (read), the same five values                                             |
| `effect`  | `PG_W`, `AMB_LUT`, `AU_KEYWANT` in the second run                     | 320 wide, ambilight black, keybed muted                                           |

The file the first run wrote: `41 57 50 31 01 00 02 00 00 00 00 00 00 00 00 00` ("AWP1", then resolution, ambilight,
scatter, keybed, LEDs).

The acceptance tests (`run_cnv_tests.sh`, above) on the same build: `ic23 v13 ... blank` and `ic23 v16 ... blank`
pass all eight checks (session 18 of 18; the saved IC23s `eb26c67b...` and `bc2305dd...` as before). At first the
`area` check found 16 foreign writes: the firmware's SD read (893 pc `0x4C003031`, 941 `0x4C003046`) putting
`AWPREFS.CFG` into `PR_BUF` (`0x502DF940`). That is the game's own read, so `PrefsRead` now sets `LD_IN_READ` = 3
during it, as `BankRead` sets 2, and `awcnv_test.lua` counts those writes as "prefread" with the SD reads.

    T=~/compartilhado/tmp/aw-prefs; probes/cnv/run_prefs.sh $T     # prints the "awpr:" lines; OUT/p1, OUT/p2

## The panel's LEDs (2026-11-02)

Felipe asked for the panel LEDs to follow the game: every red LED at a laser shot, the other LEDs pulsing while
Lester's gun charges (faster once the big blob forms), everything blinking at the blast and at the intro storm's key
moments, and a setting to turn it off (README-CNV.md, "The panel's LEDs"; `src/leds.s`). The moments were found in the
reference VM's event log (research-scratch `kn7000-aw-reference/fingerprints`, `awfp.py`); the firmware's LED
shadow, mirror, flush and refresh requests in research-scratch `kn7000-leds`.

Two sessions replayed in MAME (`run_inplog.sh`, program 893, `AW_LEDLOG`), each against the reference VM's events
of the same session (`../sessions/2026-11-02-*.fp`) with `../ledcheck.py`, and the pictures against the reference
VM's (`compare_frames.py`). `KN7APP.BIN` SHA-1 `edc5cb45`:

| check                                                      | the gun (`3e86-via-code-gun`, 1400 frames) | the intro (`intro-rec2`, 3218 frames) |
|------------------------------------------------------------|--------------------------------------------|---------------------------------------|
| lasers: every red LED bit set, and sent (the mirror)       | 10/10 (5 Lester's, 5 guards')              | -                                     |
| the charge starts / the big blob / the shield ends it      | 3/3, 1/1, 2/2                              | -                                     |
| the pulse: frames of a charge with the non-red LEDs lit    | 40/80                                      | -                                     |
| the blast: blinking                                        | 1/1                                        | -                                     |
| lightning flashes / thunder claps: every LED bit set, sent | -                                          | 3/3, 38/38                            |
| the strike: blinking                                       | -                                          | 1/1                                   |
| the panel (MAME's outputs) as the shadow, 3 frames' lag    | 1400/1400, the same at the end             | 3217/3218, the same at the end        |
| the LED bits after the last effect as before the first     | yes                                        | yes                                   |
| the pictures as the reference VM's                         | 1400/1400                                  | 3218/3218                             |

The one intro frame (2709) caught the firmware's flush halfway through a restore (registers 17-19 not yet sent; the
next frame is right). With the LED effects off (a card with `AWPREFS.CFG` byte +8 = 0) the gun session's shadow
held one value at all 1400 frames, 15 outputs lit (the firmware's own), and the pictures again matched 1400/1400.
On the final build (`9bfd11f2`, which only adds `PrefsRead`'s `LD_IN_READ` marker, see "Settings and loading
screen") the gun session gave the same counts but the pulse, 42/80, and the panel, 1399/1400: frame 1151 is again a
restore caught halfway (registers 17-19 still lit, right the next frame); the pictures 1400/1400.

Three faults the replays found, fixed before these results:

- **The pulse lit in 8 of 80 frames.** `mov a1, mdr` assembled silently as `mov d1, mdr` (the encoding has only a
  data register form), so the divide's high word was the period, not 0. Fixed in `leds.s`, and the encoder now
  refuses an address register there (technics-roms-disasm `c240d1c0b`); no other source used it.
- **After an effect, MAME's panel kept registers 2-10 lit** (44 outputs at the session's end instead of 15) while
  the shadow and the mirror said they were off. `AW_TXTRACE=1169,1173` (`awcnv_inplog.lua`: every write to SIO0's TX
  data, the TX FIFO's header and the shadow/mirror, with the PC) showed why: the restore wrote the shadow, then,
  before the 24 ms flush, the refresh routines the game had requested ran, and one of them, the fourth mask's bit
  0x10 (893 `func_484B086A`), re-applies the LED freeze state and zeroes the mirror (`func_484AE493`). The flush then
  sends only registers that differ from 0, so the ones set back to 0 were never sent. That is the firmware's logic,
  so the instrument would do the same; `LedEnd` now leaves that bit out (it is the same routine on 935, 941 and 942).
- **The checks:** a 100 ms thunder flash can end within one game frame (about 75 ms here), so `ledcheck.py` asks for
  the lit bits within 4 frames, not for the effect's timer.

    T=~/compartilhado/tmp/aw-leds; S=probes/sessions
    AW_LEDLOG=$T/gun.led probes/cnv/run_inplog.sh $T/gun replay $S/2026-11-02-3e86-via-code-gun.awr
    python3 -I probes/ledcheck.py $T/gun.led $S/2026-11-02-3e86-via-code-gun.fp
    python3 -I probes/compare_frames.py $T/gun/pages.log <rustyworld replayawr's log of the same session>
    (the same with 2026-11-02-intro-rec2; the .fp files: research-scratch kn7000-aw-reference/fingerprints
    run_all.sh's `one`, replayawr AW_EVENTS then awfp.py EV 3E80)

## The panel's LEDs, second round; the splash's flash; the end; the quit to the menu (2026-11-02)

Felipe's second list: the LEDs dark but for the effects, the charge pulsing the PANEL MEMORY ring only, every LED with
the blast, Lester's shots lighting the red LEDs on his side, the recharge station the green ones, the waterfall
blinking them at random (fainter beside it), a flash of the previous picture at the splash's cuts, the game's end
starting the intro again, and the quit going back to the menu with no firmware message. The game's signals were found
in the reference VM (research-scratch `kn7000-aw-reference/fingerprints`: `run_gun.sh`, `gunsig.py`,
`waterfall_probe.sh`, `end_probe.sh`, and the README's findings). The LED groups: `../ledmasks.py` (the MAME layout
and the service manual's colours: 71 red, 32 on the left half, 39 on the right, 22 green, 8 PANEL MEMORY).

Six sessions replayed in MAME (`run_inplog.sh`, program 893, `AW_LEDLOG`; `../ledcheck.py`). The three that start in
a part at a checkpoint were made from the reference VM's with `../jump_session.py` (the splash and the intro as
always, then at frame 300 the code screen's var 0x00 and part request, as `V` and `R` records, which
`awcnv_inplog.lua` now replays). `KN7APP.BIN` SHA-1 `d5c54c1e` (the LED, end and palette changes) for the first,
third and fourth, `2623ff2c` (with the quit's chain) for the other two:

| session                            | what                                                                                                                                                                                                                                 |
|------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `3e86-via-code-gun` (1400 frames)  | dark 1283/1283; guards' lasers 5/5, Lester's 5/5 (all to the left); charge 3/3, blob 1/1, shield 2/2, blast 1/1; the ring lit in 41 of 77 charge frames, another LED in 0; panel 1400/1400; pictures 1400/1400 as the reference VM's |
| `3e86-via-code-turn-fire` (1330)   | dark 1305/1305; guards' 4/4; Lester's to the left 3/3, to the right 1/1 (each half alone); panel 1330/1330                                                                                                                           |
| `3e84-cp31-recharge` (jump, 501)   | the recharge at frame 349 (48 frames into the part, as the reference VM's tick 48): every green LED in 17 of its 18 frames (the first is logged before the next yield writes it); dark 481/481                                       |
| `3e84-waterfall-48-4a` (jump, 901) | beside the waterfall (volume 16, chance 32/256): 222 frames, 13% of the LEDs lit on average; on it (64, 128/256): 31 frames, 48%; dark 646/646                                                                                       |
| `3e87-end` (jump, 2301)            | the last words at frame 1763, the picture still from 1863 (100 frames on), the intro asked for at 1930 (3.1 s later, by the kernel ms in the LED log); its first picture as frame 0's; LEDs dark 2300/2300                           |

The splash's flash: `awcnv_flash.lua` saves every MAME frame that differs from the one before, `../flashfind.py` lists
the short ones between longer ones. Before (`KN7APP.BIN` `9bfd11f2`): VM frame 50, the Interplay logo (faded to
black) showing in Delphine's colours for a frame, then half overwritten; VM frame 161, part of the Out of This World
logo in the next screen's colours. Cause: BlitPage loaded a new palette into the look-up table before writing the
page's pixels. After (`2623ff2c`, the palette after the pixels, the game's 16 entries black first on a cut): neither
is there; what is left between two pictures is the blit writing one top-down (a mix of the two) and, at VM frame 288,
a frame the game itself makes (the intro's palette over a page still all colour 0, dark grey, before its bitmap).

The quit to the menu (`src/chain.s`; technics-roms-disasm `kn7000/tools/kn7menu/test/run_menu_tests.sh leave`, the
staged card with this build in `AW\`): RUN on "Another World", then EXIT held in the game: the menu back 5.5 s after
the press (`KN7APP.BIN` `2623ff2c`), the firmware's titles 0x46 and 0x4A only (the STYLE CONVERT titles a request-5
converter has; never "Continue Next?", 0x4C, nor the message, 0x03). Its snapshots showed the firmware's STYLE CONVERT
screen behind the menu while the menu drew its first screen, so the firmware's frame is now made black before the LCD
is handed back (`FwFrameBlack`). With it (`fafbe3d9`): the menu back 5.7 s after the press, the same two titles; the
first snapshot after the menu is up (0.2 s) still shows the firmware's own STYLE CONVERT text screen with the menu's
"KN7000 PROGRAM MENU": the firmware paints it at the menu's first request-5 answer, as whenever the loader starts the
menu, before the menu draws over it (the menu's own start, not the game's quit).

On the final build (`fafbe3d9`): the acceptance tests above, `ic23 v13 ... blank` and `ic23 v16 ... blank`, pass all
eight checks (the saved IC23s `eb26c67b...`, `bc2305dd...` as before; area clean); `run_prefs.sh` passes all seven,
"defaults" among them (light scatter 2, long, with no AWPREFS.CFG).

Leaving the menu itself stays the firmware's: its message, then "Continue Next?". Tried and dropped: the menu calling
the firmware's ChangeMode(1, 0) (what "Continue Next?" NO calls, 893 `loc_484796EC`) on its last call: the main screen
came (title 0x01, 2.7 s after EXIT), but the firmware's dispatcher then opened "Continue Next?" over it (0x4C at 2.82 s,
the message 0x03 at 2.87 s): every request a converter can end a call with makes the dispatcher post a title after the
call returns (0xFE: 0x4C; 0: 0x49; 5: 0x4A; others: 0x46; 893 `func_48479934`), so it always comes after the mode
change. ChangeModeEZ (synchronous, `MT_SetHold` first) left the firmware on title 0x4A and no longer calling. (ChangeMode
is findable by its first 14 bytes in all four builds: `cfe0f8feecf1e682fccf00000e00`, 893/935 `0x4842B301`, 941
`0x4842B343`, 942 `0x4842B345`: research-scratch `kn7000-aw-exit/changemode_sig.py`.)

    T=~/compartilhado/tmp/aw-leds2; S=probes/sessions
    AW_LEDLOG=$T/gun.led probes/cnv/run_inplog.sh $T/gun replay $S/2026-11-02-3e86-via-code-gun.awr
    python3 -I probes/ledcheck.py $T/gun.led $S/2026-11-02-3e86-via-code-gun.fp      # (turn-fire the same, with its .fp)
    AW_LEDLOG=$T/rch.led probes/cnv/run_inplog.sh $T/rch replay $S/2026-11-02-3e84-cp31-recharge.awr
    python3 -I probes/ledcheck.py $T/rch.led                                         # (waterfall, end the same)
    AWF_OUT=$T/flash probes/cnv/run_perf.sh $T/flash probes/cnv/awcnv_flash.lua; python3 -I probes/flashfind.py $T/flash
    TREE=<card tree, root KN7APP.BIN = the menu> MT_PROGRAM="Another World" MT_GAME_UP="0x502DF000=3" \
      ~/compartilhado/technics-roms-disasm/kn7000/tools/kn7menu/test/run_menu_tests.sh $T/menu leave

## The panel's LEDs, third round; the help screen (2026-11-03)

Felipe's third list. The signals: research-scratch `kn7000-aw-reference/fingerprints`, "Fourth pass" (the tank:
`tanksig.py`, `tank_probe.sh`) and "Fifth pass" (the lift, the skeletons, the guard's light: `lift_probe.sh`,
`hit_probe.sh`). Replays in MAME (`run_inplog.sh`, program 893), the jump sessions made with `../jump_session.py`
from the reference VM's:

| session (frames)               | check                                                                                                                                                                                                                                                                                                                              |
|--------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `3e86-via-code-gun` (1400)     | dark 1280/1280; the small ball: the ring in 13 of 24 frames, nothing else; the big ball: the ring with every green LED together in 51 of 52, nothing else; 2 shields, 2 different red sets (34%, and one with a guard's shot at the same moment: every red LED); blast, lasers as before; pictures 1400/1400 as the reference VM's |
| `3e84-waterfall-48-4a` (901)   | beside the waterfall (chance 8/256): 3% of the LEDs lit on average; on it (128/256): 48%                                                                                                                                                                                                                                           |
| `3e85-tank-panel-solve` (933)  | `../tankcheck.py`: from the press of cell 0x0B (frame 461) to the eject, each rule 64/64; the white button 8/8 (from frame 521)                                                                                                                                                                                                    |
| `3e85-tank-panel-hold` (721)   | to the tank's destruction (the panel gone at frame 598): each rule 132/132, the white button 44/44                                                                                                                                                                                                                                 |
| `3e86-cp66-guard-kill` (jump)  | every green LED at frames 427-428: the reference VM's explosion at the part's tick 125 = frame 426                                                                                                                                                                                                                                 |
| `3e84-cp41-room109-lift` (631) | `../liftcheck.py`: the lead's path 0134673201367653013465320, at most 3 lit; at rest on the left, the lead alone                                                                                                                                                                                                                   |
| `3e84-cp41-room79-lift` (501)  | the lead's path sweeping 0-7-0 over and over, at most 3 lit                                                                                                                                                                                                                                                                        |

The guard's blinking light is a candidate only (part 0x3E83, room 68, thread 2's polygon): no session reaches it.
`run_prefs.sh` (`awcnv_prefs.lua`): "order" (the settings page's resolution change: the window redrawn at MAME frame 8,
the border at 10) and "codes" (OTHER PART & FR on the help screen in the intro: part 0x3E81 to 0x3E88) pass, with the
rest (7 and 2 checks).

    T=~/compartilhado/tmp/aw-leds3; S=probes/sessions
    AW_LEDLOG=$T/tank.led probes/cnv/run_inplog.sh $T/tank replay $S/2026-11-03-3e85-tank-panel-solve.awr
    python3 -I probes/tankcheck.py $T/tank.led $T/tank/vars.bin
    AW_LEDLOG=$T/l109.led probes/cnv/run_inplog.sh $T/l109 replay $S/2026-11-03-3e84-cp41-room109-lift.awr
    python3 -I probes/liftcheck.py $T/l109.led

## The panel's LEDs, fourth round; the help screen's bank time (2026-11-03)

Felipe's fourth list: the recharge's green LEDs blinking fast at random, every green LED flashing at the lake's
explosion (Lester's arrival, part 0x3E82: the reference VM loads palette 0x02 from thread 3 at pc 0x3BCD, the part's
tick 25), the lift's ring with no dimming and at most two LEDs lit, and the help screen without the bank's time
("SENT IN 11.4 S", whose last letter wrapped). Build `2ff75e4c...`; replays in MAME (`run_inplog.sh`, program 893):

| session (frames)               | check                                                                                                                                                                              |
|--------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `3e84-cp31-recharge` (501)     | `../ledcheck.py`: dark 481/481; the recharge, frames 349-366: 50% of the green LEDs lit on average, 18 different sets in 18 frames, nothing else                                   |
| `3e84-cp41-room109-lift` (631) | `../liftcheck.py`: the lead's path 0134675320134675320134675320 (the thread's frames, `lift109`), at most 2 lit                                                                    |
| `intro-rec2` (3218)            | every green LED, nothing else, at frames 2923-2925, 3069-3071 and 3187-3189: the lake's explosion each time the session shows it (its pages: the splash seen from under the water) |

    T=~/compartilhado/tmp/aw-leds4; S=probes/sessions
    AW_LEDLOG=$T/rch.led probes/cnv/run_inplog.sh $T/rch replay $S/2026-11-02-3e84-cp31-recharge.awr
    python3 -I probes/ledcheck.py $T/rch.led
    AW_LEDLOG=$T/l109.led probes/cnv/run_inplog.sh $T/l109 replay $S/2026-11-03-3e84-cp41-room109-lift.awr
    python3 -I probes/liftcheck.py $T/l109.led
    AW_LEDLOG=$T/intro.led probes/cnv/run_inplog.sh $T/intro replay $S/2026-11-02-intro-rec2.awr
    python3 -I probes/greenframes.py $T/intro.led

## The panel's LEDs, fifth round (2026-11-03)

Felipe's fifth list: the PANEL MEMORY ring is green on the instrument (the parts list says amber), so the recharge,
the lake's explosion and a skeleton's explosion light it with the other green LEDs; the lift's chase as a line
2-1-8-7-6-5-4-3, bouncing, and nothing left lit once the light is gone; every green LED when a lamp holder Lester
shot down bursts; the guard's red lamp at code TXHF (one screen left). The two new signals: research-scratch
`kn7000-aw-reference/fingerprints`, "Sixth pass" ((a) `guardlamp.py`: part 0x3E86, room 170, thread 4's pc
0x0FAF-0x0FB9; (b) `lampsig.py`: part 0x3E84, room 107, 0x5B at pc 0xD050 and 0xD057). A thread's pc between ticks
is the one after its yield: the lift's resting pc is 0x089B (the earlier rule tested 0x089A, the draw's, which
never matched, so its last LED stayed lit). Replays in MAME (program 893); `AW_LEDFINE` logs the shadow at every MAME
frame (60 a second; `AW_LEDFINE_THREAD=n` adds thread n's pc), fine enough to see each step of the chase:

| session (frames)               | check                                                                                                                                           |
|--------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| `3e84-cp31-recharge` (501)     | `../ledcheck.py`: the recharge, frames 349-366: 49% of the 30 green LEDs lit on average (49% of the ring's), 18 sets in 18 frames, nothing else |
| `3e84-cp41-room79-lift` (501)  | `../liftcheck.py --fine`: the lead 0123456754321 over and over, one step a tick (the light's period, 14 ticks), at most 2 lit                   |
| `3e84-cp41-room109-lift` (631) | the lead 0123456754321 (14 steps in the light's 11 ticks); the ring dark from frame 513, the light waiting (thread 1 at 0x089B)                 |
| `intro-rec2` (3218)            | `../greenframes.py`: every green LED, the ring's too, at frames 2923-2925, 3069-3071, 3187-3189 (the lake's explosion)                          |
| `3e84-lamp-fall` (501)         | every green LED at frames 376-378 (the reference VM's bursts at its ticks 74 and 75 = frames 375, 376)                                          |
| `3e86-txhf-guard-lamp` (761)   | SPLIT POINT G2 lit 3 frames, dark 2, 61 times over (frames 395-739; the lamp from frame 390)                                                    |

    T=~/compartilhado/tmp/aw-leds9; S=probes/sessions
    AW_LEDFINE=$T/l79.fine AW_LEDFINE_THREAD=5 AW_LEDLOG=$T/l79.led probes/cnv/run_inplog.sh $T/l79 replay \
        $S/2026-11-03-3e84-cp41-room79-lift.awr
    python3 -I probes/liftcheck.py --fine $T/l79.fine
    AW_LEDLOG=$T/lamp.led probes/cnv/run_inplog.sh $T/lamp replay $S/2026-11-03-3e84-lamp-fall.awr
    python3 -I probes/greenframes.py $T/lamp.led

## The bitmap filter (2026-11-03)

`src/smooth.s` (README-CNV.md, "Settings"). Replays at 384x240 (program 893), each twice: the filter on (the
default) and off (`AW_SMOOTH=0`, a nearest-pixel baseline). `../smoothcheck.py` reads the 320x200 picture back from
the baseline's page and enlarges it as smooth.s does, in a palette of the part's palette resource, and counts the
pixels where the filtered replay differs; the frame time is the LED log's kernel ms (`AW_LEDLOG`), next frame minus
this one. Build `5023cd80...`:

| session, frame                      | check                                                                                                                 |
|-------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| `intro-rec2` 60 (the Delphine logo) | 0 pixels differ from the model in palette 0x16 (the glint's fade one step before its end), 933 from the baseline      |
| `intro-rec2` 100, 150 (the title)   | 0 differ from the model in palette 0x09 (its fade's last step), 7659 from the baseline                                |
| `intro-rec2` 1-49 (bitmap 0x12)     | 0 differ from the baseline: drawn on at once, its palette still black                                                 |
| `intro-rec2` frame times            | frame 51 380 ms (61 off), frame 75 576 ms (63 off); the fades' steps as with the filter off (60-70 ms)                |
| `3e84-waterfall-48-4a` 589-616      | smoothed (the model cannot say: Lester is drawn over the bitmap); the room change 1432 ms (756 off)                   |
| both, every frame                   | the same pages as the build before the copy's dedupe (`SM_SAME`) and the one before the row ring: 3218 and 901 frames |

    T=~/compartilhado/tmp/aw-bilin; S=probes/sessions
    AW_HIRES=1 AW_LEDLOG=$T/in.led probes/cnv/run_inplog.sh $T/in replay $S/2026-11-02-intro-rec2.awr
    AW_HIRES=1 AW_SMOOTH=0 probes/cnv/run_inplog.sh $T/in0 replay $S/2026-11-02-intro-rec2.awr
    python3 -I probes/smoothcheck.py $T/in0/pages.bin $T/in/pages.bin 100 build/res/resource-0x14.bin 0x09 -o $T/cmp.png

`run_prefs.sh`: 7 and 2 checks pass, the bitmap filter's row among them (default bilinear, turned off, saved, read
back).

## What the platform does with a converter

Three small converters, each alone on a floppy, ask what a converter may do on 941. They answer
the questions the port's design rests on. `build_probe.sh` assembles one into `AW.CNV` on a blank
disk the KN7000 formatted; `run_probe.sh` boots with it and runs a command file for
`tools/rigs/remote.lua` (kn7000_mame). The command files walk DISK MENU > STYLE CONVERT > OK and
then print the probe's variables. Rebuilt from these sources, the three converters are
byte-identical to the ones measured.

| probe (`.s` + `.cmd`)                         | question                                                                                              | result                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
|-----------------------------------------------|-------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `probe1_noreturn`                             | Does a converter that never returns (it yields with `dly_tsk`) keep the instrument usable?            | **No.** Its loop runs, 62.5 passes per second (`hb` 304 → 429 in 2 s). But a PART SELECT press never reaches the switch bitmap (no `52:01` in `seen`), and a keybed note never reaches the MIDI OUT 1 ring (`mout` stays `0x5001F064`). Both are the main task's work, and the converter is holding the main task.                                                                                                                                                                                      |
| `probe2_task`                                 | If the converter starts a task of its own and answers request 5 on every call, does input still work? | **Yes.** `cre_tsk(10)` and `sta_tsk(10, 0)` return 0, and the task runs at 62.5 passes per second. The firmware calls the converter 20 times a second (`entries` 77 → 117 in 2 s), with the main task's title on `0x4A` (`_TT_STYLCNVTXT`). PART SELECT sets `0x5006BE52` bit `0x01`. One keybed note (on + off) moves the MIDI OUT 1 write pointer by 6 bytes (`0x5001F064` → `0x5001F06A`). EXIT shows up at `0x5006BE8B` bit `0x80`, and the firmware keeps calling: EXIT does not leave the screen. |
| `probe3_quit`                                 | Can the converter end itself and the conversion?                                                      | **Yes.** On EXIT the task records `quit` and calls `exd_tsk`, and its heartbeat stops (243 → 243 over 3 s). The next call answers `0xFE`, and the firmware stops calling (`entries` 79 → 79). Each call finds `0xFF` in mailbox byte 0 (`mb` = `4F4E41FF`: `0xFF`, then the "ANO" left there by the text request).                                                                                                                                                                                      |
| `ram44.cmd` (with probe3's disk)              | Which part of the `0x44000000` window does the firmware write?                                        | Only `0x44000000`–`0x4403FFFF`: 64 KB blocks `00`–`03`, with 243,011, 242,062, 242,060 and 225,037 writes, through boot (40 s) and the same counts after STYLE CONVERT ran the probe. That is the 256 KB battery-backed SRAM (see below).                                                                                                                                                                                                                                                               |
| `taskprobe.cmd` (with the Style Convert Disk) | Which task calls a converter, and which decodes the panel? Where are 941's MIDI rings?                | Both are the **main task**. Breakpoint `0x48479929` (`calls (a0)`) hit 3 times, with the current TCB (`*0x5038002C`) = `0x50381470` = the main task's TCB. `PanelFrameDecode` `0x484AD116`: 395 of 395 hits on `0x50381470`. Ring headers: MIDI IN 1 at `0x5001F050` (buffer `0x5001EC50`–`0x5001F04F`); MIDI OUT 1 at `0x5001F864` (buffer `0x5001F064`–`0x5001F863`, write pointer `0x5001F06A` after one note). That is 942's addresses minus `0x10`.                                                |

How to read the `PROBE` lines (`probe1`/`probe2`):

- `hb` is the probe's heartbeat at `0x502E0000`, one per pass. A pass ends in `dly_tsk(16)`.
- `entries` is how many times the firmware has called the converter (`0x502E0020`).
- `mout` and `min` are the MIDI OUT 1 and MIDI IN 1 ring write pointers (`0x5001F870`,
  `0x5001F05C`).
- `ms` is the kernel millisecond counter (`0x500D3C58`).
- `title` is the title table's two words (`0x5000099C`, `0x500009A0`): `0xF0000 + title`.
- `seen` is every bit seen set since the start in the switch bitmaps `0x5006BE40`–`0x5006BEBF`,
  as `offset:bits` (`52:01` is `0x5006BE52` bit `0x01`).

taskprobe needs MAME's debugger for its breakpoints (`DEBUG=1`). It also needs the rebuilt floppy
set: with the older `scd7000` image, the STYLE CONVERT screen shows an empty box and no
converter is called. The MIDI-OUT watchpoint and
enqueue breakpoint in its second half never fired. The ring header dump answered the question
instead.

    probes/cnv/build_probe.sh probes/cnv/probe2_task.s $T/probe2.img
    probes/cnv/run_probe.sh probes/cnv/probe2_task.cmd $T/probe2.img $T/run2
    probes/cnv/run_probe.sh probes/cnv/ram44.cmd $T/probe3.img $T/runram
    R=~/compartilhado/technics_romsets/floppy-rebuild-2026-10-18
    DEBUG=1 probes/cnv/run_probe.sh probes/cnv/taskprobe.cmd scd7000 $T/runtask \
      -rompath "$R/roms;./roms" -hashpath "$R/hash;hash"

`T` is any scratch directory. The converters' SHA-1s are probe1 `94df8164…`, probe2 `4c88cbcb…`
and probe3 `d471e36e…`.

**The `0x44000000` window on a real instrument** is chip select CS1, which is IC23 alone: the
KN7000's **256 KB battery-backed SRAM** (also at `0x84000000`, uncached), holding the panel settings
and the 104 PANEL MEMORY records. It has address pins A1-A17 only, so it **repeats every 256 KB through
the whole window**; the owner's unit confirmed it on 2026-10-20 (SURVEY2 dump: 7 of 7 copies equal).
`ram44.cmd` above measured MAME's 16 MB placeholder RAM, so "nothing above `0x4403FFFF`" says what
the firmware addresses, not that the rest is free: on an instrument every address there is the panel
memories. The 2026-10-18 AW.CNV kept its data at `0x44050000`-`0x4480CFFF`; the current one names
no address in CS1 at all (README-CNV.md, "Memory"), which `tools/ic23_guard.py` checks at every
build and the acceptance tests above measure.

## Firmware addresses for 941 (2026-10-18)

AW.CNV no longer carries these: it finds them, and every other build's, by search
(`src/fwfind.s`, `tools/aw_find_fw.py`; table in README-CNV.md). The values found for 941 equal the
ones below.

- **RAM.** The ring headers, switch bitmaps and millisecond counter come from the probes above.
- **Task services.** The 941 entry stubs are paired with 942's exports by the kernel routine each
  one enters (kn7000_disassembly `tools/itron_stubs.py`):
  - `cre_tsk` `0x4C03D0C8`
  - `sta_tsk` `0x4C03D8AB`
  - `exd_tsk` `0x4C03D5A1`

  The disassembly's ported symbol file had `0x4C03D8AB` as `ext_tsk` until 2026-10-18. probe2
  measured what it does: it returns 0 and starts the dormant task.
- **`dly_tsk`.** `addrmap.py` matches 942's `dly_tsk` `0x4C03E295` against the 941 image, with
  absolute operands masked, and finds one 941 candidate, `0x4C03DD6F`. It does not settle the
  other stubs: their first bytes are alike, so a short match is ambiguous and a long one fails.
- **File routines.** `open` in the current folder `0x48531AC5`, `fmmread` `0x48532463` and
  `fmmclose` `0x485323BC` are in kn7000_disassembly's symbol files.

## Does the game run right? (2026-10-18, the earlier AW.CNV, program 941)

These ran the earlier AW.CNV, which loaded the whole game into the `0x44000000` window at start.
`awcnv_resdump.lua`, `resverify.py` and `awcnv_session.lua` read that layout; they are superseded by
`awcnv_test.lua` and are in git history (`97a9cd9`). `awcnv_cksum.lua` follows the current layout.

| probe                                                            | question                                                                           | result                                                                                                                                                                                                                                 |
|------------------------------------------------------------------|------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `awcnv_resdump.lua` + `resverify.py`                             | Are the resources AW.CNV unpacked on the instrument the bytes the SD build loads?  | **Yes.** All 1,730,376 bytes from `0x44200000` are identical to `build/res/AWP*.bin` laid end to end (SHA-1 `7a707a66…`), and so are the font and both string tables. The loader reported 0 errors and a 76,445 ms load (emulated).    |
| `awcnv_cksum.lua` + `../cksum_pages.py` + `../compare_frames.py` | Does the intro play pixel-identically to the reference VM (rustyworld)?            | **Yes.** 2612 of 2612 frames (floppy SHA-1 `b0d07c4e…`) are identical to rustyworld's `ref_checksums.log` (research-scratch `kn7000-aw-reference/`), as for the SP7001 build ([../CHECKSUM-COMPARISON.md](../CHECKSUM-COMPARISON.md)). |
| `awcnv_session.lua`                                              | Does a whole session work: start, input, quit, play again, leave, run again?       | **9 of 9 PASS**, listed below.                                                                                                                                                                                                         |
| `../../tools/leafcheck.py` (run by `make cnv`)                   | Does any routine entered with `call X, 0, 0` call something before making a frame? | **No.** 51 call targets checked, none unsafe. The first unpacker did this (`GetBits` called `ReadBE`): the nested call overwrote its return address, and the load hung.                                                                |

The session results (`awcnv_session.lua`, floppy SHA-1 `b0d07c4e…`):

    start    PASS  frame 51 at t=123 s; load 76846 ms, errors 0, task 10
    skip     PASS  part 0x3E82 at frame 52
    panel    PASS  var[0xFC] reached 1
    keybed   PASS  var[0xFA] reached 1
    quit     PASS  TASK_DONE=1 QUIT_REQ=1
    menus    PASS  frame stayed 117 after quitting; snapshot: Continue Next? YES/NO
    again    PASS  YES restarted the game (frame 11, task 10)
    leave    PASS  second quit, NO; snapshot shows the main screen
    rerun    PASS  reloaded AW.CNV runs at once: load 0 ms (data still in RAM)

Its snapshots show:

1. the intro;
2. the lake after the skip;
3. the firmware's message box after quitting;
4. "Continue Next?" with YES/NO;
5. the game again after YES;
6. the main screen after NO;
7. the game once more after running AW.CNV again.

How to run them, from `kn7000/` after `make floppy`:

    E=../../kn7000-emulator; cp $E/sdcard_from_real_kn7000.img $T/sd.img; chmod u+w $T/sd.img
    # resources, font and strings
    AWDUMP_DIR=$T $E/run.sh kn7000 -window -nothrottle -harddisk $T/sd.img \
      -flop $PWD/build/another_floppy.img -autoboot_script $PWD/probes/cnv/awcnv_resdump.lua
    python3 -I probes/cnv/resverify.py $T build/res ../../custom-kn5000-roms/anotherworld/src/hardcoded_data
    # the intro, frame by frame
    AWCK_BIN=$T/pages.bin AWCK_IDX=$T/pages.idx $E/run.sh kn7000 -window -nothrottle \
      -harddisk $T/sd.img -flop $PWD/build/another_floppy.img \
      -autoboot_script $PWD/probes/cnv/awcnv_cksum.lua
    python3 -I probes/cksum_pages.py $T/pages.bin $T/pages.idx $T/cnv_checksums.log
    python3 -I probes/compare_frames.py $T/cnv_checksums.log \
      ~/compartilhado/research-scratch/kn7000-aw-reference/ref_checksums.log
    # a whole session
    $E/run.sh kn7000 -window -nothrottle -harddisk $T/sd.img \
      -flop $PWD/build/another_floppy.img -snapshot_directory $T/snap \
      -autoboot_script $PWD/probes/cnv/awcnv_session.lua

`pages.bin` is 167 MB; it is regenerated, not kept.

## The input log (2026-11-01)

`run_inplog.sh` (README-CNV.md, "Replaying a session"). Results, program 893 (`-bios v13`), KN7APP.BIN 6f58c18f
(technics-anotherworld 5ea5e2c), the published emulator; `compare_frames.py` over the CRC-32 of the front page at every
frame (pages.log), rustyworld's `replayawr` (research-scratch kn7000-aw-reference/replay-mods) from its run folder:

| run                                                  | frames | sync marks | result                                                                                  |
|------------------------------------------------------|--------|------------|-----------------------------------------------------------------------------------------|
| `rec1`: splash, 300 intro frames, C4, the moves      | 797    | 1          | rustyworld's replay of its log: 797/797 identical                                       |
| `rep1`: `rec1`'s log replayed in MAME                | 817    | 1          | `rec1`'s pages 797/797; rustyworld's 817/817; its own I, P, R records = the replayed 19 |
| `rec2`: splash, the whole intro, the lake, the moves | 3198   | 24         | rustyworld's replay of its log: 3198/3198 identical                                     |

In `rep1` the module player wrote 5 marks of its own, which the replay undid: the music does not keep the same time
against the VM's frames from one run to the next, so the marks must come from the log.

**Felipe's first session on the instrument (2026-11-01; `probes/sessions/2026-11-01-felipe-unit-aw.awr`, from
`2026-11-01-felipe-unit-AWIN00.BIN`):** 1346 frames: the splash, the intro (2 marks), the code screen, a code, part
0x3E86 played until the hero died. Replayed in MAME with KN7APP.BIN 6f58c18f, the build it was played on, against
rustyworld's replay: frames 0-1142 identical, 1143-1291 different (149), the rest identical. A black bar was drawn in
the upper room instead of the lower one, and rustyworld's death screen came a frame earlier. `varsdiff.py` named var
0x4B first, at frame 1142: -436 against 588, 1024 apart; rustyworld's opcode trace (`WATCH_VAR=4b DUMP_TICK=1142`)
showed thread 63 at pc 44067 doing SHR 6 on 0x8000. The port shifted arithmetically (0xFE00), rawgl's `op_shr` and
rustyworld shift logically (0x0200). With SHR fixed in both ports (technics-anotherworld aeeeb5c, KN7APP.BIN 7b07e0f1):

| run                                   | frames | sync marks | MAME's replay against rustyworld's                                |
|---------------------------------------|--------|------------|-------------------------------------------------------------------|
| Felipe's session, the build it played | 1346   | 2          | pages 1197/1346; first variable to differ 0x4B at frame 1142      |
| Felipe's session, SHR fixed           | 1346   | 2          | pages 1346/1346; all 256 variables equal at every frame           |
| `rec2`'s log, SHR fixed               | 3218   | 24         | pages 3218/3218 (and `rec2`'s own 3198/3198); all variables equal |

The variables are compared at each frame's end (`vars.bin`, written beside the pages; rustyworld's `REF_VARS`). For
them to compare equal, both replays now write a mark that no later thread of its frame sees at the frame's end: the
MAME replay at NextThread's end-of-frame thread 0 write, rustyworld after its last chan (research-scratch 5a61c1d).
Before that change, var 0xF4 differed at the end of 13 frames of these two sessions, all frames whose logged mark came
after the last thread that ran, while the pages all agreed. The replay's own log has no R record, as the replay sets
the requested part itself, past ReadInput, which logs them; `run_inplog.sh` checks the I and P records.
