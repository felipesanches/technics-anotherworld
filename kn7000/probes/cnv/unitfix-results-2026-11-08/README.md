# The zoomed code wheel page restarting the owner's KN7000 (2026-11-08)

On the unit, KN7APP `c707af6e` (the zoomed page) showed the page's frame and "Loading the wheel" for a while after HELP
at the code wheel's question, then the instrument restarted, with no log on the card. The first page, `aafd752e`, ran
there on 2026-11-06. MAME runs both through (15 of 15 checks, every picture exact).

## What was measured

| question                                                                 | answer                                                                                                                                                                                                       | file                                           |
|--------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------|
| does the new load keep the firmware's tasks from running longer?         | no: the longest gap of TickJobsTask's 96 ms bit-5 toggle while the page loads is 188 ms (the old page's: 144 ms); the game's own start has 850 ms gaps in both builds, which the unit has always run through | `tickgap-aafd752e.txt`, `tickgap-c707af6e.txt` |
| does the firmware use the LCD's ink layer (0x136000 up) here?            | not in MAME: REG[070h] and REG[071h] read 00 at the question                                                                                                                                                 | `tickgap-c707af6e.txt`                         |
| does a card read reach the user pools at 0x50180000 (the scratch's end)? | not in MAME: nothing written in 0x5017F000-0x50180FFF while the page loads                                                                                                                                   | `tickgap-c707af6e.txt`                         |
| does the new trail of steps reach the card at the next start?            | yes: after a quit and "Continue Next?" YES, `AWWHLOG.TXT` holds the 13 last steps (the page's load to its closing)                                                                                           | `crumb.txt`                                    |
| does a system-error NMI while the page shows reach the new NMI screen?   | yes (a build with `-D WHEEL_NMI_SELFTEST`): "NMI PC 502C3AEC", "PSW 00000F00", the trail's EE and EF; the instrument holds there                                                                             | `nmitest.txt`, `codewheel_nmi.png`             |

## The suspects, by reading the code that is new in `c707af6e`

1. **The LCD stores through an index register with a top byte of 0x4C.** WheelDraw stored each changed word with
   `mov d0, (d1, a2)`: a2 the RAM copy's word, d1 the LCD's address less it (0x9CE... - 0x501... = 0x4C...). The unit
   raises a system-error NMI for a (d32,An) operand whose displacement's top byte is not 0 (Pinball notes/session-
   2026-10-26: a CPU that keeps 24 bits of it would fit), and the firmware's NMI handler restarts the instrument. An
   index register added the same way would fail the same way; MAME models only the displacement. Nothing else in the
   game uses an index of that size (`d32_scan.py` lists every indexed operand now). It fits the timing: the first
   such store is the first word of the first picture, right after the load, before "Loading the wheel" is drawn over.
   **Fixed:** the address is added in a3 (`add d1, a3; mov d0, (a3)`).
2. **Display memory 0x136000-0x13FFFF** (the cache's end): the 8 KB pages Pinball's and the firmware's ink layer use
   (n = 5). Not seen enabled in MAME. **Moved:** the cache ends at 0x136000 and holds A only; B is read from the card at
   each showing (0.3 s).
3. **The read scratch ending at the user pools' first byte** (0x5017FFFF): a read that wrote past its count would
   reach them. Not seen in MAME. **Moved:** it ends at 0x5017EFFF.

## What the new build shows on the unit

- While the page loads, the left margin's foot shows the step, "Sss aaaaaa" in yellow (README-CNV.md, "The code wheel
  page": 10 a piece asked for, 40/41/42 its file opened, read, closed by the main task, 11 its size, 12 cached, 13
  unpacked, 20 the blob checked, 21 the frame drawn, 22 laid out, 23 the first picture, 24 shown).
- A system-error NMI while the page shows: "NMI PC pppppppp" and "PSW ssssssss" in yellow, and the instrument stays.
- The trail is in the input log's room (0x5031C0C0); the next start of Another World writes it to `C:\AWWHLOG.TXT`
  when the RAM kept it through the restart.

## Commands

    probes/cnv/run_tickgap.sh ~/compartilhado/tmp/aw-codewheel-zoom/tick-new2
    probes/cnv/run_tickgap.sh ~/compartilhado/tmp/aw-codewheel-zoom/tick-old <aafd752e's build/sdcard>
    probes/cnv/run_crumb.sh ~/compartilhado/tmp/aw-codewheel-zoom/crumb2
    (KN7APP.BIN with -D WHEEL_NMI_SELFTEST=1: xapasm as the Makefile's line, then mkapp.py, into a copy of build/sdcard)
    probes/cnv/run_nmitest.sh ~/compartilhado/tmp/aw-codewheel-zoom/nmirun <that card>
