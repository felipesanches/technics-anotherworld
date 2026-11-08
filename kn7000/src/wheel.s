# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# wheel.s -- the code wheel help page (README-CNV.md, "The code wheel page"): the original game's code wheel, from the
# owner's drawing of it (tools/codewheel_render.py), its upper disk turned by the TEMPO/PROGRAM wheel, a number a
# detent. The KN7APP.BIN build's (the SP7001 build has wheel_stub.s).
#
#   * Zoomed in (2026-11-08, Felipe: the symbols were too small on the unit): the wheel is drawn 480 pixels across,
#     twice the LCD's height, into a frame of 640 x 480 in the LCD's display memory (WD_TF: "the tall frame"), and the
#     LCD shows 240 of its rows, a region: TOP (rows 0-239), MIDDLE (120-359) or BOTTOM (240-479), chosen with the LCD's
#     soft buttons 1, 3 and 5 (either side; labelled on the right). A change scrolls the whole frame to the new region
#     by moving the controller's start address a frame at a time, easing out over 220 ms (320 ms TOP <-> BOTTOM). The
#     region is remembered while the game runs (WH_REGION; TOP at first).
#   * The pictures and tables (the blob: codewheel_render.py's W_* layout, WB_* here) come from the SD card, AWWH0.AW ..
#     AWWHD.AW, ByteKiller-packed pieces of 32 KB, the first time the page is shown in a game: the main task reads a
#     piece a converter call (WheelService) into the scratch (ARENA6), the game task unpacks it in its place
#     (cnv_main.s BkUnpack) and checks the whole (magic, version, sizes, words summing to 0). The packed pieces then stay
#     in the LCD's display memory (WD_CACHE: nothing shows it), and later showings unpack them from there.
#   * The blob is in three segments: A (TOP, the tables, the lower disk's first rows) in the VM's four pages (WRAM,
#     368,640 bytes, saved to display memory, WD_SAVE, while borrowed: the VM does not run while the help screen is up;
#     put back when it closes, WheelRestore); B (the lower disk's other rows) in SHADOW's room (the other help pages
#     redraw it, so B is unpacked again when the page comes back); C (the lower disk outside the upper one's reach,
#     which never changes) in ARENA5, read only to draw it into the tall frame once. The page's copy of what the tall
#     frame holds in the spans (WSHADOW: only the words that change are stored) is in ARENA5 and ARENA6 (free while a
#     converter runs on programs 893 and 941: Pinball Fantasies' canaries on the owner's unit; probes/cnv/
#     awcnv_areas.lua measures the firmware never writing them while the game runs).
#   * The tall frame stays in display memory between showings: a showing points the LCD at it at once (its colours
#     from WH_LUTC), then borrows the RAM and draws the region again at the arrow's number.
#   * The page takes the whole LCD: the wheel's 480 columns at x 80 (the pin in the LCD's middle), the text in the 80
#     columns left and right of it; look-up table entries 16-255 hold the wheel's 240 colours while it shows (the
#     ambilight's otherwise: WheelHide writes them back from AMB_LUT and points the LCD at FB8 again, untouched).
#   * The upper disk is drawn at any angle from its one picture, row by row over the spans it can reach (WheelDraw):
#     nearest texel while it turns, bilinear (in RGB, back to an entry through INV) when it comes to rest; only the
#     region's 240 rows while it turns. WT_ROWST keeps the angle each row of the tall frame was drawn at, so that rows
#     about to scroll into view are drawn first when they are stale, and the rows at rest are made bilinear once.
#     The angle of each number (ANGLES) and the arithmetic are codewheel_render.py's; its render() is this, pixel for
#     pixel.
#   * The TEMPO/PROGRAM wheel: each detent comes from the panel as a frame [0x17, step] into the firmware's panel
#     receive ring, which the firmware decodes on its main task and adds to the tempo. While the page shows, the
#     converter calls (the main task too: WheelService) look at the ring first: a wheel frame's step is counted
#     (WH_STEPS) and set to 0 in the ring while the firmware has not decoded it yet; one it decoded first (the tempo
#     moved) gets a frame of the opposite step put into the ring after it, so the tempo goes back. As the PDF viewer and
#     Pinball Fantasies do it (kn5000_homebrew demos/kn7000_pdf src/app/entry.c wheel_scan). Every firmware task and
#     ours run at the same priority without time slices, so nothing decodes the ring while WheelService runs.
#   * The LCD's soft buttons come the same way, a frame [segment, its switches] (LCDL 1-5: segment 0xC0 bits 0x02 0x08
#     0x20 0x01 0x04; LCDR 1, 2, 5: 0x05 bits 0x10 0x20 0x01; LCDR 4: 0x06 bit 0x01; LCDR 3: 0x07 bit 0x01, measured by
#     probes/cnv/awcnv_lcdkeys.lua). On the converter's screen the firmware acts on them (view records written, about
#     1,300 writes a press), so while the page shows their bits are cleared from the ring's frames before the firmware
#     decodes them; one it decoded first gets a frame without them put in after it (WH_SOFTLATE counts those).
#   * Each detent moves the target a number (accumulating while the disk is still turning) and starts a turn from
#     where the disk is to the target's angle, easing out (1 - (1 - t)^3) over 180 ms + 100 ms a number, at most 800
#     ms; frames are drawn as fast as they come (the help loop sleeps 2 ms between them).
# Convention as the rest of the port: d0, d1, a0, a1 scratch; d2, d3, a2, a3 kept; a routine that calls makes a frame
# first; locals from (0x14, sp) (the firmware's routines use the caller's sp + 4 .. + 0x10).

# ---- RAM (codewheel_render.py W_*: the same offsets) ----
.equ WRAM,          PAGE_BITMAP_0   # the VM's four pages, borrowed while the help screen is up
.equ WRAM_LEN,      4 * PAGE_STRIDE # 0x5A000
.equ ARENA5,        0x50123000      # free while a converter runs (programs 893, 941: Pinball Fantasies' ARENA5, 6)
.equ ARENA5_END,    0x50148000
.equ ARENA6,        0x50175000
.equ ARENA6_LAST,   0x5017FFFF      # (its end, 0x50180000, is the user pools' start: the guard refuses that value)
.equ TR0,           24              # TOP's rows kept: TR0 .. TR1 - 1, 512 bytes each
.equ TR1,           488
.equ WB_SEGA,       WRAM            # A: 11 pieces
.equ WB_SEGA_LEN,   0x58000
.equ WB_SEGB,       SHADOW          # B: 2 pieces (SHADOW and REPORT_BUF's room, to 0x502D7000, below AW_FONT)
.equ WB_SEGB_LEN,   0xF000
.equ WB_SEGC,       ARENA5          # C: 1 piece
.equ WB_SEGC_LEN,   0x8000
.equ WB_TOP,        WRAM + 0x00000  # TOP's rows TR0 .. TR1 - 1 (16-255 its colours; 0-15 its shadow over the lower)
.equ WB_TOPV,       WB_TOP - TR0 * 512  # texel (i, j) at WB_TOPV + j * 512 + i
.equ WB_SHADE_OFF,  TR1 * 512       # SHADE from WB_TOPV (16 x 256: an entry under each shadow level)
.equ WB_SHADE,      WB_TOPV + WB_SHADE_OFF
.equ WB_SIN,        WRAM + 0x3B000  # 4096 x s16: sin x 32767
.equ WB_LANES,      WRAM + 0x3D000  # 256 x u32: R << 20 | G << 10 | B, for the blend
.equ WB_INV,        WRAM + 0x3D400  # 4096: the entry nearest each 4-bit colour
.equ WB_LUT,        WRAM + 0x3E400  # 256 x u16: 0x0RGB of entries 16-255
.equ WB_SPANS,      WRAM + 0x3E600  # 480 x (u16 x0, u16 x1): what the upper disk can reach, each row
.equ WB_ANGLES,     WRAM + 0x3EE00  # 20 x u16: the upper disk's angle for each number, 1/65536 of a turn
.equ WB_BOTOFF,     WRAM + 0x3EE80  # 480 x u32: each row of the lower disk's spans, its offset in A then B
.equ WB_HDR,        WRAM + 0x3F600  # "AWWH", version, SEGA, SEGB, SEGC, the sum's word, C's sum
.equ WB_RING,       WB_SEGC         # 480 x (u16 xl, u16 xr), then the lower disk outside the spans, row after row
.equ WB_MAGIC,      0x48575741      # "AWWH"
.equ WB_VERSION,    2
.equ WB_PIECE,      0x8000
.equ WB_PIECES,     14              # A 0-10, B 11-12, C 13
.equ WB_CACHED_N,   11              # A is kept packed in display memory (B is read from the card at each showing)
.equ WB_SCRATCH,    ARENA6 + 0x1000 # a packed piece read from the card or the cache (to 0x5017EFFF: 4 KB short of
                                    #   the user pools at 0x50180000, should a read write a sector past its count)
.equ WB_SCRATCH_MAX, 0x9000
.equ WT_BOTROW,     WRAM + 0x58000  # 480 x u32: where each row of the lower disk's spans is
.equ WT_SHROW,      WRAM + 0x58800  # 480 x u32: where each row's copy of the tall frame's spans is (ARENA5, ARENA6)
.equ WT_ROWST,      WRAM + 0x59000  # 480 x u32: the angle a row was drawn at, | 0x10000 bilinear; -1 unknown
.equ WT_LINE,       WRAM + 0x59800  # a row being made bilinear (480 bytes)
# ---- display memory (nothing shows it; the firmware's frame is 0-0x4B4FF, FB8 0x50000-0x757FF; probes/cnv/
#      awcnv_areas.lua: the firmware writes none of it while the game runs) ----
.equ WD_TF_OFS,     0x76000         # the tall frame: 640 x 480, to 0xC1000
.equ WD_TF,         FB + WD_TF_OFS
.equ WD_SAVE,       FB + 0xC1000    # the VM's four pages while borrowed, to 0x11B000
.equ WD_CACHE,      FB + 0x11B000   # A's packed pieces, one after the other, to 0x136000: below the ink layer's
.equ WD_CACHE_END,  FB + 0x136000   #   memory there (n = 5, the 8 KB pages the firmware's ink and Pinball's use)
# ---- the page ----
.equ WHEEL_X0,      80              # the wheel's 480 columns in the tall frame
.equ WHEEL_W,       480
.equ WHEEL_NUMS,    20
.equ WHEEL_ROWS,    480
.equ REGION_ROWS,   240             # rows shown
.equ WH_SROWS,      12              # rows of the picture at rest a poll
.equ WH_SEG,        128             # nearest: a span in pieces of up to 128 pixels, each from U, V exact
.equ WH_REST_MS,    50              # a converter call looks at the panel's ring this long while the page shows
.equ WH_FRAME_WAIT, 6               # and waits this long for a frame's second byte
.equ PRING_LEN,     0x5C            # the panel's receive ring: 92 bytes, read index, write index before it
.equ WH_TURN_MS,    180             # a turn: 180 ms + 100 ms a number, at most WH_TURN_MAX
.equ WH_TURN_MAX,   800
.equ WH_SCROLL_MS,  220             # a scroll of 120 rows; 240 rows: WH_SCROLL_MS + 100
.equ WH_LOAD_MS,    15000           # a piece the main task has not read after this: the load fails
# ---- variables (WHEEL_VARS, 0x400 bytes; zeroed by the loader with the application area) ----
# WH_RXRD, WHEEL_VARS + 0x00: the panel ring's read index (platformcnv.inc; fwfind.s step 8; 0: not found), write
# index +2, ring +4
.equ WH_ON,         WHEEL_VARS + 0x04   # 1 while the page shows: the converter calls take the wheel's frames
.equ WH_SCAN,       WHEEL_VARS + 0x08   # main task: 1 once WH_AT follows the ring
.equ WH_AT,         WHEEL_VARS + 0x0C   # main task: the next frame to look at
.equ WH_STEPS,      WHEEL_VARS + 0x10   # main task: the detents so far, signed
.equ WH_TAKEN,      WHEEL_VARS + 0x14   # game task: the detents it has acted on
.equ WH_FRAMES,     WHEEL_VARS + 0x18   # wheel frames seen
.equ WH_LATE,       WHEEL_VARS + 0x1C   # of them, those the firmware had decoded first
.equ WH_UNDONE,     WHEEL_VARS + 0x20   # frames put into the ring after a late one (the wheel's and the soft buttons')
.equ WH_UNDO_N,     WHEEL_VARS + 0x24   # the ring positions of those not met yet: up to 8
.equ WH_UNDO_AT,    WHEEL_VARS + 0x28   #   (8 x u32, to +0x48)
.equ WH_BORROW,     WHEEL_VARS + 0x48   # 1 while the VM's pages are in WD_SAVE
.equ WH_INRAM,      WHEEL_VARS + 0x4C   # 1 while A holds the checked blob
.equ WH_CACHED,     WHEEL_VARS + 0x50   # 1 once WD_CACHE holds A and B (and the tall frame is drawn: WH_TFOK)
.equ WH_LOADREQ,    WHEEL_VARS + 0x54   # game task: piece n + 1 to read; the main task sets 0 when done
.equ WH_LOADRES,    WHEEL_VARS + 0x58   # main task: its bytes (-1: no file)
.equ WH_FAIL,       WHEEL_VARS + 0x5C   # why the blob could not be had: 0x10 + piece (read), 0x20 + piece (unpack),
                                        #   0x30 (check), 0x40 (the copy of the spans does not fit)
.equ WH_POS,        WHEEL_VARS + 0x60   # the number the arrow rests at, or turns to (0-19: 1-20)
.equ WH_ANG,        WHEEL_VARS + 0x64   # the angle drawn last (1/65536 turn)
.equ WH_FROM,       WHEEL_VARS + 0x68   # a turn: from this angle
.equ WH_DELTA,      WHEEL_VARS + 0x6C   #   by this much (signed)
.equ WH_T0,         WHEEL_VARS + 0x70   #   started at this ms
.equ WH_DUR,        WHEEL_VARS + 0x74   #   lasting this many ms
.equ WH_MOVING,     WHEEL_VARS + 0x78   # 1 while turning
.equ WH_SHOWN,      WHEEL_VARS + 0x7C   # 1 while the LCD shows the tall frame (WheelHide puts FB8 back)
.equ WH_SEQ,        WHEEL_VARS + 0x80   # + 2 at each picture finished (the probes' taps)
.equ WH_SMOOTH,     WHEEL_VARS + 0x84   # the last picture: 1 bilinear (at rest), 0 nearest (turning)
.equ WH_NFRAMES,    WHEEL_VARS + 0x88   # pictures drawn turning, so far
.equ WH_NREST,      WHEEL_VARS + 0x8C   # pictures drawn at rest
.equ WH_TURNF,      WHEEL_VARS + 0x90   # pictures drawn in the last turn
.equ WH_TLAST,      WHEEL_VARS + 0x94   # the last turning picture's time, in 1/2001 ms (perf.s Stamp)
.equ WH_TMAX,       WHEEL_VARS + 0x98   # the longest turning picture's
.equ WH_TREST,      WHEEL_VARS + 0x9C   # the last picture at rest's
.equ WH_POLLS,      WHEEL_VARS + 0xA0   # help polls on the page (the LCD checked every 16)
.equ WH_LOADMS,     WHEEL_VARS + 0xA4   # the last load from the card, ms
.equ WH_LOADS,      WHEEL_VARS + 0xA8   # loads from the card so far
.equ WH_SAVES,      WHEEL_VARS + 0xAC   # the VM's pages borrowed so far
.equ WH_BUSY,       WHEEL_VARS + 0xB0   # 1 while a picture is being made (the probes read the LCD when 0)
.equ WH_SROW,       WHEEL_VARS + 0xB4   # the next row of the region's picture at rest (WH_SROWS rows a poll); 240: none
.equ WH_R0,         WHEEL_VARS + 0xB8   # WheelDraw's rows: from
.equ WH_R1,         WHEEL_VARS + 0xBC   #   to
.equ WH_STORES,     WHEEL_VARS + 0xC0   # stores into the LCD in the last turning picture (the words that changed)
.equ WH_SSTORES,    WHEEL_VARS + 0xC4   # in the last picture at rest
.equ WH_NSTORE,     WHEEL_VARS + 0xC8   # (WheelDraw's count)
.equ WH_TACC,       WHEEL_VARS + 0xCC   # the picture at rest's time so far
.equ WH_REGION,     WHEEL_VARS + 0xD0   # the region shown, or scrolled to: 0 TOP, 1 MIDDLE, 2 BOTTOM
.equ WH_RREQ,       WHEEL_VARS + 0xD4   # main task: the region a soft button asked for
.equ WH_RSEQ,       WHEEL_VARS + 0xD8   # main task: + 1 at each such press
.equ WH_RSEEN,      WHEEL_VARS + 0xDC   # game task: the WH_RSEQ it has acted on
.equ WH_SCROLL,     WHEEL_VARS + 0xE0   # 1 while scrolling
.equ WH_SC_FROM,    WHEEL_VARS + 0xE4   #   from this first row
.equ WH_SC_TO,      WHEEL_VARS + 0xE8   #   to this one
.equ WH_SC_T0,      WHEEL_VARS + 0xEC   #   started at this ms
.equ WH_SC_DUR,     WHEEL_VARS + 0xF0   #   lasting this many ms
.equ WH_SC_ROW,     WHEEL_VARS + 0xF4   # the tall frame's first row the LCD shows now
.equ WH_SC_N,       WHEEL_VARS + 0xF8   # start addresses written in the last scroll
.equ WH_SCROLLS,    WHEEL_VARS + 0xFC   # scrolls so far
.equ WH_TFOK,       WHEEL_VARS + 0x100  # 1 once the tall frame holds the lower disk (C drawn) and the margins clear
.equ WH_INB,        WHEEL_VARS + 0x104  # 1 while B is in SHADOW's room
.equ WH_TROW,       WHEEL_VARS + 0x108  # the first row of the region the text is drawn for
.equ WH_SOFTN,      WHEEL_VARS + 0x10C  # soft button frames seen
.equ WH_SOFTLATE,   WHEEL_VARS + 0x110  # of them, those the firmware had decoded first
.equ WH_SOFTPREV,   WHEEL_VARS + 0x114  # 4 bytes: segments 0xC0, 0x05, 0x06, 0x07 as the panel last sent them
.equ WH_STALE,      WHEEL_VARS + 0x118  # rows drawn before the last scroll (stale at the angle)
.equ WH_SHOWMS,     WHEEL_VARS + 0x11C  # the last showing: ms from HELP's page to the region drawn
.equ WH_CNEXT,      WHEEL_VARS + 0x120  # the cache's next free byte
.equ WH_PC_AT,      WHEEL_VARS + 0x124  # 13 x u32: where each piece is in the cache (to +0x158)
.equ WH_PC_LEN,     WHEEL_VARS + 0x158  # 13 x u32: its packed size (to +0x18C)
.equ WH_NDRAWN,     WHEEL_VARS + 0x18C  # WheelDraw: rows drawn
.equ WH_NAME,       WHEEL_VARS + 0x190  # 16 bytes: "AWWHn.AW"
.equ WH_TEXT,       WHEEL_VARS + 0x1A0  # 64 bytes: a line being made
.equ WH_MARKS,      WHEEL_VARS + 0x3C0  # steps marked (WheelMark)
.equ WH_MTEXT,      WHEEL_VARS + 0x3C4  # 16 bytes: WheelMark's line
# ---- the trail of steps (WheelMark), kept across a restart of the instrument: in the input log's room, which the loader
#      does not zero; InpLogInit zeroes it at the next start, after WheelCrumbLog has written it to the card ----
.equ WH_CRUMB,      INPLOG_AT + 0xC0    # "WAWB", steps so far, the ms of the last, then 13 x (step << 24 | arg)
.equ WH_CRUMB_MAGIC, 0x42574157
.equ WH_CRUMB_N,    13
.equ WH_LUTC,       WHEEL_VARS + 0x1E0  # 240 x u16: entries 16-255 (WB_LUT's), for a showing before the blob is in RAM
                                        #   (to +0x3C0)

# =================================================================================
# The main task (cnv_main.s CnvEntry, every converter call while the game runs).
# WheelService: a piece the game task asked for, read from the card (then one look at the ring); while the page shows,
# the wheel's and the soft buttons' frames taken from the panel's ring: at once, then for up to WH_REST_MS (sleeping a ms at a time, so the game
# task draws meanwhile) until bytes come that the firmware must decode (a button: they are looked at first), then the
# second byte of a frame whose first has come (WH_FRAME_WAIT ms at most).
WheelService:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (WH_LOADREQ), d0
    cmp     0, d0
    beq     wsv_ring
    call    WheelReadPiece, 0, 0
    mov     (WH_ON), d0             # (a piece read: one look at the ring, no waiting, so the load goes on)
    cmp     0, d0
    beq     wsv_ret
    mov     (WH_RXRD), d0
    cmp     0, d0
    beq     wsv_ret
    call    WheelScanRing, 0, 0
    bra     wsv_ret
wsv_ring:
    mov     (WH_ON), d0
    cmp     0, d0
    bne     wsv_on
    clr     d0                      # not shown: the next showing follows the ring from where it then is
    mov     d0, (WH_SCAN)
    bra     wsv_ret
wsv_on:
    mov     (WH_RXRD), d0
    cmp     0, d0
    beq     wsv_ret
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d2                # d2 = start
wsv_rest:
    call    WheelScanRing, 0, 0
    mov     (WH_RXRD), a2
    movhu   (a2), d0                # bytes the firmware has still to decode: it decodes them when we return
    movhu   (2, a2), d1
    cmp     d1, d0
    bne     wsv_frame
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    sub     d2, d0
    cmp     WH_REST_MS, d0
    bcc     wsv_frame
    mov     1, d0
    mov     (FW_DLY), a0
    calls   (a0)
    bra     wsv_rest
wsv_frame:
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d2
wsv_half:
    call    WheelScanRing, 0, 0
    mov     (WH_RXRD), a2
    movhu   (2, a2), d1
    mov     (WH_AT), d0
    cmp     d1, d0
    beq     wsv_ret                 # every whole frame looked at
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    sub     d2, d0
    cmp     WH_FRAME_WAIT, d0
    bcc     wsv_ret
    mov     1, d0
    mov     (FW_DLY), a0
    calls   (a0)
    bra     wsv_half
wsv_ret:
    ret     [d2,d3,a2,a3], 0x30

# WheelScanRing: the ring's frames from WH_AT to the write index: a wheel frame [0x17, step] adds step to WH_STEPS;
# not yet decoded (between the read and the write index), its step becomes 0; decoded already, a frame of -step goes
# in after the panel's (WheelInject). A soft buttons' frame (WheelSoftMask) asks for a region at a press of 1, 3 or 5;
# not yet decoded, its soft buttons' bits are cleared; decoded already with any of them set, a frame without them goes
# in after it. A frame WheelInject put in is passed over. Frames are 2 bytes; a first byte whose second has not come
# waits for the next look.
# Locals: 0x14 frames left, 0x18 next, 0x1C step or mask, 0x20 the first byte, 0x24 the second's address, 0x28 slot.
WheelScanRing:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x30, sp
    mov     (WH_RXRD), a2           # a2 = the read index; +2 the write index; +4 the ring
    movhu   (a2), d2                # d2 = rd
    movhu   (2, a2), d3             # d3 = wr
    cmp     PRING_LEN, d2
    bcc     wsr_ret
    cmp     PRING_LEN, d3
    bcc     wsr_ret
    mov     (WH_SCAN), d0
    cmp     0, d0
    bne     wsr_go
    mov     1, d0
    mov     d0, (WH_SCAN)
    mov     d2, (WH_AT)
    clr     d0
    mov     d0, (WH_UNDO_N)
wsr_go:
    mov     PRING_LEN / 2, d0
    mov     d0, (0x14, sp)          # at most a ring's frames
wsr_frame:
    mov     (WH_AT), d0
    cmp     d3, d0
    beq     wsr_ret
    mov     d0, d1                  # next = at + 1, wrapping
    inc     d1
    cmp     PRING_LEN, d1
    bcs     wsr_nx
    clr     d1
wsr_nx:
    cmp     d3, d1
    beq     wsr_ret                 # (half a frame so far)
    mov     d1, (0x18, sp)          # next
    mov     a2, a0
    add     4, a0
    add     d1, a0
    mov     a0, (0x24, sp)          # the second byte's address
    mov     a2, a0
    add     4, a0
    add     d0, a0
    movbu   (a0), d0                # the frame's first byte
    mov     d0, (0x20, sp)
    mov     (WH_AT), d0             # one WheelInject wrote?
    call    WheelUndone, 0, 0
    cmp     0, d0
    bne     wsr_step
    mov     (0x20, sp), d0
    cmp     0x17, d0
    beq     wsr_wheel
    call    WheelSoftMask, 0, 0     # d0 = the soft buttons' bits, d1 = the slot
    cmp     0, d0
    beq     wsr_step
    mov     d0, (0x1C, sp)
    mov     d1, (0x28, sp)
    mov     (0x24, sp), a0
    movbu   (a0), d2                # d2 = the switches as sent (d2 is rd no more: read again below)
    mov     WH_SOFTPREV, a0
    add     d1, a0
    movbu   (a0), d0                # presses: now set, before not, a soft button's bit
    movbu   d2, (a0)
    not     d0
    and     d2, d0
    mov     (0x1C, sp), d1
    and     d1, d0
    beq     wsr_snone
    mov     (0x28, sp), d1
    call    WheelSoftRegion, 0, 0   # d0 = the region asked for, or -1
    cmp     0, d0
    blt     wsr_snone
    mov     d0, (WH_RREQ)
    mov     (WH_RSEQ), d0
    inc     d0
    mov     d0, (WH_RSEQ)
wsr_snone:
    mov     (WH_SOFTN), d0
    inc     d0
    mov     d0, (WH_SOFTN)
    mov     (0x1C, sp), d1          # none of the soft buttons' bits set: nothing to hide
    mov     d2, d0
    and     d1, d0
    beq     wsr_sret
    movhu   (a2), d2                # (rd again)
    call    wsr_ahead, 0, 0         # d0 = 1 still to be decoded
    cmp     0, d0
    beq     wsr_slate
    mov     (0x1C, sp), d1          # the firmware sees the frame without them
    not     d1
    mov     (0x24, sp), a0
    movbu   (a0), d0
    and     d1, d0
    movbu   d0, (a0)
    bra     wsr_step
wsr_slate:
    mov     (WH_SOFTLATE), d0
    inc     d0
    mov     d0, (WH_SOFTLATE)
    mov     (0x1C, sp), d1          # a frame without them after it
    not     d1
    mov     (0x24, sp), a0
    movbu   (a0), d0
    and     d0, d1
    mov     (0x20, sp), d0
    call    WheelInject, 0, 0
    bra     wsr_step
wsr_sret:
    movhu   (a2), d2
    bra     wsr_step
wsr_wheel:
    mov     (0x24, sp), a0          # the step
    movbu   (a0), d0                # (a signed byte)
    cmp     0x80, d0
    bcs     wsr_pos
    add     -0x100, d0
wsr_pos:
    mov     d0, (0x1C, sp)          # step
    mov     (WH_STEPS), d1
    add     d0, d1
    mov     d1, (WH_STEPS)
    mov     (WH_FRAMES), d1
    inc     d1
    mov     d1, (WH_FRAMES)
    call    wsr_ahead, 0, 0
    cmp     0, d0
    beq     wsr_late
    clr     d1                      # still to be decoded: the firmware sees no step
    mov     (0x24, sp), a0
    movbu   d1, (a0)
    bra     wsr_step
wsr_late:
    mov     (WH_LATE), d1
    inc     d1
    mov     d1, (WH_LATE)
    clr     d1                      # [0x17, -step]
    mov     (0x1C, sp), d0
    sub     d0, d1
    mov     0x17, d0
    call    WheelInject, 0, 0
wsr_step:
    mov     (WH_AT), d0
    add     2, d0
    cmp     PRING_LEN, d0
    bcs     wsr_st
    add     -PRING_LEN, d0
wsr_st:
    mov     d0, (WH_AT)
    mov     (0x14, sp), d0
    add     -1, d0
    mov     d0, (0x14, sp)
    bne     wsr_frame
wsr_ret:
    ret     [d2,d3,a2,a3], 0x40

# wsr_ahead(d2 = rd, d3 = wr) -> d0 = 1 when the frame at WH_AT is still to be decoded (ahead of the read index:
# (at - rd) mod len < (wr - rd) mod len), else 0. Leaf.
wsr_ahead:
    mov     (WH_AT), d0
    sub     d2, d0
    bge     wah_a
    add     PRING_LEN, d0
wah_a:
    mov     d3, d1
    sub     d2, d1
    bge     wah_f
    add     PRING_LEN, d1
wah_f:
    cmp     d1, d0
    bcc     wah_no
    mov     1, d0
    rets
wah_no:
    clr     d0
    rets

# WheelSoftMask(d0 = a frame's first byte) -> d0 = the soft buttons' bits in that segment (0: none), d1 = its slot in
# WH_SOFTPREV. Leaf.
WheelSoftMask:
    cmp     0xC0, d0
    bne     wsm_05
    clr     d1
    mov     0x2F, d0                # LCDL 4, 1, 5, 2, 3
    rets
wsm_05:
    cmp     0x05, d0
    bne     wsm_06
    mov     1, d1
    mov     0x31, d0                # LCDR 5, 1, 2
    rets
wsm_06:
    cmp     0x06, d0
    bne     wsm_07
    mov     2, d1
    mov     0x01, d0                # LCDR 4
    rets
wsm_07:
    cmp     0x07, d0
    bne     wsm_none
    mov     3, d1
    mov     0x01, d0                # LCDR 3
    rets
wsm_none:
    clr     d0
    rets

# WheelSoftRegion(d0 = presses, d1 = slot) -> d0 = the region the first of them asks for (0 TOP: LCDL 1, LCDR 1;
# 1 MIDDLE: LCDL 3, LCDR 3; 2 BOTTOM: LCDL 5, LCDR 5), or -1 (2 and 4 do nothing). Leaf.
WheelSoftRegion:
    cmp     0, d1
    bne     wsg_r
    btst    0x02, d0
    bne     wsg_top
    btst    0x20, d0
    bne     wsg_mid
    btst    0x04, d0
    bne     wsg_bot
    bra     wsg_none
wsg_r:
    cmp     1, d1
    bne     wsg_r3
    btst    0x10, d0
    bne     wsg_top
    btst    0x01, d0
    bne     wsg_bot
    bra     wsg_none
wsg_r3:
    cmp     3, d1
    beq     wsg_mid
wsg_none:
    mov     -1, d0
    rets
wsg_top:
    clr     d0
    rets
wsg_mid:
    mov     1, d0
    rets
wsg_bot:
    mov     2, d0
    rets

# WheelUndone(d0 = a ring position) -> d0 = 1 when WheelInject wrote the frame there (and it is forgotten), else 0.
# Leaf.
WheelUndone:
    mov     (WH_UNDO_N), d1
    mov     WH_UNDO_AT, a0
wud_loop:
    cmp     0, d1
    beq     wud_no
    mov     (a0), a1
    cmp     a1, d0
    beq     wud_yes
    add     4, a0
    add     -1, d1
    bra     wud_loop
wud_yes:
    mov     (WH_UNDO_N), d1         # the last one takes its place
    add     -1, d1
    mov     d1, (WH_UNDO_N)
    asl     2, d1
    mov     WH_UNDO_AT, a1
    add     d1, a1
    mov     (a1), d1
    mov     d1, (a0)
    mov     1, d0
    rets
wud_no:
    clr     d0
    rets

# WheelInject(d0 = first byte, d1 = second): a frame into the ring at its write index, as the panel's receive interrupt
# puts one (interrupts off meanwhile), when it fits; remembered so that WheelScanRing passes over it.
WheelInject:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2                  # d2 = the first byte << 8 | the second
    asl     8, d2
    and     0xFF, d1
    or      d1, d2
    mov     (WH_UNDO_N), d0
    cmp     8, d0
    bcc     win_ret
    mov     (WH_RXRD), a2
    mov     psw, d3                 # interrupts off
    and     0xF7FF, psw
    nop
    nop
    movhu   (2, a2), d0             # wr
    movhu   (a2), d1                # rd
    cmp     PRING_LEN, d0
    bcc     win_on
    btst    1, d0
    bne     win_on
    mov     d0, a1                  # filled = (wr - rd) mod len: room for 2 more, and one free byte
    sub     d1, d0
    bge     win_f
    add     PRING_LEN, d0
win_f:
    add     2, d0
    cmp     PRING_LEN, d0
    bcc     win_on
    mov     a1, d0                  # ring[wr], ring[wr + 1], wr += 2
    mov     a2, a0
    add     4, a0
    add     d0, a0
    mov     d2, d1
    lsr     8, d1
    movbu   d1, (a0)
    movbu   d2, (1, a0)             # (wr is even and len is even: wr + 1 needs no wrap)
    add     2, d0
    cmp     PRING_LEN, d0
    bcs     win_w
    clr     d0
win_w:
    movhu   d0, (2, a2)
    mov     (WH_UNDO_N), d0
    asl     2, d0
    mov     WH_UNDO_AT, a0
    add     d0, a0
    mov     a1, (a0)
    mov     (WH_UNDO_N), d0
    inc     d0
    mov     d0, (WH_UNDO_N)
    mov     (WH_UNDONE), d0
    inc     d0
    mov     d0, (WH_UNDONE)
win_on:
    mov     d3, psw
    nop
win_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelReadPiece: piece WH_LOADREQ - 1 (AWWHn.AW, n a hex digit, in the game's folder) into WB_SCRATCH (ARENA6), as
# LoadStep reads a file: the drive switch, open, FILE_PIECE at a time until a short read, close, the switch back.
# WH_LOADRES = its bytes (-1: it could not be opened; a file of WB_SCRATCH_MAX bytes or more is not one of ours: -1).
# Then WH_LOADREQ = 0.
WheelReadPiece:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     WH_NAME, a0             # "AWWHn.AW"
    mov     wh_name, a1
    call    StrPut, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     (WH_LOADREQ), d0
    add     -1, d0
    add     0x30, d0
    cmp     0x3A, d0
    bcs     wrp_digit
    add     7, d0                   # A-F
wrp_digit:
    movbu   d0, (WH_NAME + 4)
    mov     1, d0                   # the file layer to the SD card
    mov     (FW_SETEXT), a3
    calls   (a3)
    mov     WH_NAME, a0
    call    AppPath, 0, 0
    mov     mode_rb, a1
    mov     (FW_OPEN), a3
    calls   (a3)
    exth    d0
    cmp     0, d0
    blt     wrp_back
    mov     0x40, d0                # (step: the file opened)
    mov     (WH_LOADREQ), d1
    add     -1, d1
    call    WheelMark, 0, 0
    mov     4, d0                   # (the probes' taps: an SD read into the scratch in ARENA6)
    mov     d0, (LD_IN_READ)
    mov     WB_SCRATCH, a3          # a3: where the next piece goes
    clr     d3                      # d3: bytes read
wrp_piece:
    mov     FILE_PIECE, d0
    mov     d0, (0x14, sp)
    mov     a3, a0
    mov     (FW_READ), a1
    calls   (a1)                    # d0 = bytes read
    cmp     0, d0
    blt     wrp_end
    add     d0, d3
    add     d0, a3
    mov     (0x14, sp), d1
    cmp     d1, d0
    bne     wrp_end                 # short: the end of the file
    cmp     WB_SCRATCH_MAX - FILE_PIECE, d3
    bls     wrp_piece
    mov     -1, d3                  # (too long to be ours)
wrp_end:
    clr     d0
    mov     d0, (LD_IN_READ)
    mov     0x41, d0                # (step: read, the bytes)
    mov     d3, d1
    call    WheelMark, 0, 0
    mov     (FW_CLOSE), a3
    calls   (a3)
    mov     0x42, d0                # (step: closed)
    clr     d1
    call    WheelMark, 0, 0
    mov     (FW_RESETEXT), a3
    calls   (a3)
    mov     d3, (WH_LOADRES)
    bra     wrp_done
wrp_back:
    mov     (FW_RESETEXT), a3
    calls   (a3)
    mov     -1, d0
    mov     d0, (WH_LOADRES)
wrp_done:
    clr     d0
    mov     d0, (WH_LOADREQ)
    ret     [d2,d3,a2,a3], 0x30

# WheelMark(d0 = step, d1 = its argument): the page's progress (on either task), for a unit that restarts while the
# page loads (2026-11-08): into the trail WH_CRUMB (WheelCrumbLog writes it to the card at the next start) and, while
# the LCD shows the tall frame, as "Sss aaaaaa" (hex) at the left margin's foot in yellow. Steps: 01 the page asked
# for, 02 the LCD on the frame, 03 the VM's pages saved, 10 a piece asked of the main task (its number), 11 read (its
# bytes), 12 kept in the cache, 13 unpacked, 18 a piece from the cache, 20 the blob checked, 21 the frame drawn, 22 the
# rows laid out, 23 the first picture drawn, 24 the page shown, 2F hidden, 30 closing, 3F the VM's pages back; the main
# task's 40 a file opened (the piece), 41 read (bytes so far), 42 closed.
WheelMark:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    mov     d1, d3
    mov     WH_CRUMB_MAGIC, d0
    mov     d0, (WH_CRUMB)
    mov     (WH_CRUMB + 4), d0      # the entry: count mod 13
    mov     WH_CRUMB_N, d1
    call    Div, 0, 0
    asl     2, d1
    mov     WH_CRUMB + 12, a2
    add     d1, a2
    mov     d2, d0
    asl     24, d0
    mov     d3, d1
    and     0xFFFFFF, d1
    or      d1, d0
    mov     d0, (a2)
    mov     (WH_CRUMB + 4), d0
    inc     d0
    mov     d0, (WH_CRUMB + 4)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (WH_CRUMB + 8)
    mov     (WH_MARKS), d0
    inc     d0
    mov     d0, (WH_MARKS)
    mov     (WH_SHOWN), d0
    cmp     0, d0
    beq     wmk_ret
    mov     WH_MTEXT, a0            # "Sss aaaaaa"
    mov     0x53, d0
    movbu   d0, (a0)
    inc     a0
    mov     d2, d0
    mov     2, d1
    call    FmtHex, 0, 0
    mov     0x20, d0
    movbu   d0, (a0)
    inc     a0
    mov     d3, d0
    mov     6, d1
    call    FmtHex, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     WH_MTEXT, a0
    clr     d0
    mov     228, d1
    mov     3, d2
    call    WText, 0, 0
wmk_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelCrumbLog: at the game's start (the main task, inplog.s InpLogInit, before it zeroes the input log's room): when
# the trail of a session before is there, C:\AWWHLOG.TXT gets it, oldest step first, one a line ("ss aaaaaa"), after a
# line with the steps' count and the last one's ms; written as IlWriteFile writes AWINnn.BIN.
WheelCrumbLog:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (WH_CRUMB), d0
    mov     WH_CRUMB_MAGIC, d1
    cmp     d1, d0
    bne     wcl_ret
    mov     (FW_WRITE), d0
    cmp     0, d0
    beq     wcl_ret
    mov     REPORT_BUF, a0
    mov     wh_t_crumb, a1
    call    StrPut, 0, 0
    mov     (WH_CRUMB + 4), d0
    mov     8, d1
    call    FmtHex, 0, 0
    mov     0x20, d0
    movbu   d0, (a0)
    inc     a0
    mov     (WH_CRUMB + 8), d0
    mov     8, d1
    call    FmtHex, 0, 0
    call    wcl_eol, 0, 0
    mov     a0, a3                  # a3 = where the next line goes
    mov     (WH_CRUMB + 4), d2      # the entries, oldest first: from count - min(count, 13)
    mov     d2, d3
    cmp     WH_CRUMB_N, d3
    bls     wcl_n
    mov     WH_CRUMB_N, d3
wcl_n:
    sub     d3, d2                  # d2 = the first entry's number, d3 = entries
    cmp     0, d3
    beq     wcl_write
wcl_entry:
    mov     d2, d0
    mov     WH_CRUMB_N, d1
    call    Div, 0, 0
    asl     2, d1
    mov     WH_CRUMB + 12, a0
    add     d1, a0
    mov     (a0), d0
    mov     d0, a2                  # (the entry)
    lsr     24, d0
    mov     a3, a0
    mov     2, d1
    call    FmtHex, 0, 0
    mov     0x20, d0
    movbu   d0, (a0)
    inc     a0
    mov     a2, d0
    and     0xFFFFFF, d0
    mov     6, d1
    call    FmtHex, 0, 0
    call    wcl_eol, 0, 0
    mov     a0, a3
    inc     d2
    add     -1, d3
    bne     wcl_entry
wcl_write:
    mov     a3, d2                  # d2 = bytes
    mov     REPORT_BUF, d0
    sub     d0, d2
    mov     1, d0                   # the file layer to the SD card
    mov     (FW_SETEXT), a3
    calls   (a3)
    mov     wh_t_crumbname, a0
    mov     mode_wb, a1
    mov     (FW_OPEN), a3
    calls   (a3)
    exth    d0
    cmp     0, d0
    blt     wcl_back
    mov     REPORT_BUF, a0
    mov     d2, d0
    mov     (FW_WRITE), a3
    calls   (a3)
    mov     (FW_CLOSE), a3
    calls   (a3)
wcl_back:
    mov     (FW_RESETEXT), a3
    calls   (a3)
wcl_ret:
    ret     [d2,d3,a2,a3], 0x20

# wcl_eol(a0 = where) -> a0 past "\r\n". Leaf.
wcl_eol:
    mov     0x0D, d0
    movbu   d0, (a0)
    mov     0x0A, d0
    movbu   d0, (1, a0)
    add     2, a0
    rets

# =================================================================================
# The game task (help.s).
# WheelAtQuestion -> d0 = 1 while the game shows the code wheel's question (part 0x3E80, var 0xBC without the 0x10 a
# right answer, or the bypass, sets: the question, its ERROR page and the wait after it), else 0. Leaf.
WheelAtQuestion:
    clr     d0
    movhu   (CURRENT_PART_ID), d1
    cmp     PART_PROTECTION, d1
    bne     waq_ret
    movhu   (VM_VARIABLES + 2 * 0xBC), d1
    btst    0x10, d1
    bne     waq_ret
    mov     1, d0
waq_ret:
    rets

# WheelShow: the page (help.s HelpDrawPage). The LCD on the tall frame at the region at once (as it was left, in its
# colours, WH_LUTC; the first time: its rows cleared, the text and "Loading the wheel"); then the blob (WheelEnsure),
# the text, the region drawn at the number the arrow was left at (every row stored: WT_ROWST unknown), to be made
# bilinear a few rows a poll (WheelPoll). The converter calls take the wheel's and the soft buttons' frames as soon as
# the LCD shows the tall frame (WH_ON).
WheelShow:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    clr     d0
    mov     d0, (WH_ON)
    mov     d0, (WH_SCROLL)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (0x14, sp)          # (WH_SHOWMS)
    call    PalCheck, 0, 0          # entries 0-15: the help screen's colours (the text)
    mov     0x01, d0                # (step: the page asked for)
    clr     d1
    call    WheelMark, 0, 0
    mov     (WH_REGION), d0
    cmp     3, d0
    bcs     wsh_reg
    clr     d0
    mov     d0, (WH_REGION)
wsh_reg:
    mov     REGION_ROWS / 2, d1
    mulu    d1, d0
    mov     d0, (WH_TROW)
    mov     (WH_TFOK), d0
    cmp     0, d0
    bne     wsh_kept
    mov     (WH_TROW), d0           # the first time: the region's rows black, the text
    call    WheelClearRows, 0, 0
    call    WheelTexts, 0, 0
    bra     wsh_lcd
wsh_kept:
    mov     16, d2                  # the frame as it was left, in its colours
    mov     WH_LUTC, a2
wsh_lutc:
    movhu   (a2), d1
    mov     d2, d0
    call    LutSet, 0, 0
    add     2, a2
    inc     d2
    cmp     256, d2
    bne     wsh_lutc
wsh_lcd:
    mov     (WH_TROW), d0
    mov     d0, (WH_SC_ROW)
    call    WheelLcdSet, 0, 0
    mov     1, d0
    mov     d0, (WH_SHOWN)
    mov     0x02, d0                # (step: the LCD on the frame)
    mov     (WH_SC_ROW), d1
    call    WheelMark, 0, 0
    mov     1, d0
    mov     d0, (PF_DAMAGE)         # (FB8's window in full at the next page or blit; WheelHide makes sure)
    mov     (WH_STEPS), d0          # detents and presses from before the page: not for it; from now on they are
    mov     d0, (WH_TAKEN)          #   taken from the ring (the firmware does not see them while the blob comes)
    mov     (WH_RSEQ), d0           #   and acted on once the picture is drawn
    mov     d0, (WH_RSEEN)
    mov     1, d0
    mov     d0, (WH_ON)
    call    WheelEnsure, 0, 0
    cmp     0, d0
    beq     wsh_have
    clr     d0                      # no wheel: the ring left to the firmware; say why
    mov     d0, (WH_ON)
    mov     (WH_TROW), d0
    call    WheelClearRows, 0, 0
    call    WheelTexts, 0, 0
    mov     wh_t_missing, a0
    mov     WHEEL_X0 + 144, d0
    mov     112, d1
    mov     3, d2
    call    WText, 0, 0
    mov     WH_TEXT, a0
    mov     wh_t_code, a1
    call    StrPut, 0, 0
    mov     (WH_FAIL), d0
    mov     2, d1
    call    FmtHex, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     WH_TEXT, a0
    mov     WHEEL_X0 + 144, d0
    mov     124, d1
    mov     1, d2
    call    WText, 0, 0
    bra     wsh_ret
wsh_have:
    mov     16, d2                  # the wheel's colours
    mov     WB_LUT + 32, a2
wsh_lut:
    movhu   (a2), d1
    mov     d2, d0
    call    LutSet, 0, 0
    add     2, a2
    inc     d2
    cmp     256, d2
    bne     wsh_lut
    mov     WT_ROWST, a0            # every row's copy unknown: its first drawing stores it all
    mov     WHEEL_ROWS, d1
    mov     -1, d0
wsh_st:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     wsh_st
    mov     (WH_POS), d0            # the number it was left at (a turn under way: finished)
    cmp     WHEEL_NUMS, d0
    bcs     wsh_pos
    clr     d0
    mov     d0, (WH_POS)
wsh_pos:
    clr     d1
    mov     d1, (WH_MOVING)
    asl     1, d0
    mov     WB_ANGLES, a0
    add     d0, a0
    movhu   (a0), d0
    call    WheelPicture, 0, 0      # at once, nearest; then at rest, a few rows a poll (WheelPoll)
    mov     0x23, d0                # (step: the first picture drawn)
    mov     (WH_TLAST), d1
    call    WheelMark, 0, 0
    clr     d0
    mov     d0, (WH_SROW)
    call    WheelTexts, 0, 0
    mov     0x24, d0                # (step: shown; then the text's last line again over the step's)
    clr     d1
    call    WheelMark, 0, 0
    call    WheelTexts, 0, 0
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     (0x14, sp), d1
    sub     d1, d0
    mov     d0, (WH_SHOWMS)
wsh_ret:
    ret     [d2,d3,a2,a3], 0x30

# WheelHide: another page, or the help screen closing: the converter calls leave the ring alone, a turn or a scroll is
# finished (the arrow on its number, the region the one asked for), entries 16-255 hold the ambilight's colours again
# (AMB_LUT: what lcd8.s last wrote there, black where it is unknown), the LCD shows FB8 again (untouched by the page),
# FB8's window is drawn again by the next ShadowOut or blit (PF_DAMAGE), and B is no more in RAM (the other pages draw
# in SHADOW).
WheelHide:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d0
    mov     d0, (WH_ON)
    mov     d0, (WH_MOVING)
    mov     d0, (WH_SCROLL)
    mov     d0, (WH_BUSY)
    mov     d0, (WH_INB)
    mov     REGION_ROWS, d1
    mov     d1, (WH_SROW)
    mov     (WH_SHOWN), d1
    cmp     0, d1
    beq     whd_ret
    mov     d0, (WH_SHOWN)
    mov     16, d2
    mov     AMB_LUT, a2
whd_lut:
    movhu   (a2), d1
    cmp     0xFFFF, d1
    bne     whd_set
    clr     d1
whd_set:
    mov     d2, d0
    call    LutSet, 0, 0
    add     2, a2
    inc     d2
    cmp     256, d2
    bne     whd_lut
    call    LcdSet, 0, 0            # the LCD on FB8 (lcd8.s)
    mov     1, d0
    mov     d0, (PF_DAMAGE)
whd_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelRestore: the help screen closes (help.s): the page hidden, and the VM's pages back from display memory when
# they were borrowed.
WheelRestore:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    WheelHide, 0, 0
    mov     (WH_BORROW), d0
    cmp     0, d0
    beq     wrs_ret
    mov     0x30, d0                # (step: closing)
    clr     d1
    call    WheelMark, 0, 0
    mov     WD_SAVE, a0
    mov     WRAM, a1
    call    WheelCopyPages, 0, 0
    clr     d0
    mov     d0, (WH_BORROW)
    mov     d0, (WH_INRAM)
    mov     0x3F, d0                # (step: the VM's pages back)
    clr     d1
    call    WheelMark, 0, 0
wrs_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelCopy(a0 = from, a1 = to, d0 = words) -> d0 = the words' sum. Leaf.
WheelCopy:
    movm    [d2], (sp)
    mov     d0, d2
    clr     d1
    cmp     0, d2
    beq     wcp_end
wcp_loop:
    mov     (a0), d0
    mov     d0, (a1)
    add     d0, d1
    add     4, a0
    add     4, a1
    add     -1, d2
    bne     wcp_loop
wcp_end:
    mov     d1, d0
    ret     [d2], 4

# WheelCopyPages(a0 = from, a1 = to): the VM's four pages' room (WRAM_LEN), a page at a time, the firmware's tasks
# let run between them (WheelYield).
WheelCopyPages:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2
    mov     a1, a3
    mov     4, d2
wcg_page:
    mov     a2, a0
    mov     a3, a1
    mov     PAGE_STRIDE / 4, d0
    call    WheelCopy, 0, 0
    add     PAGE_STRIDE, a2
    add     PAGE_STRIDE, a3
    call    WheelYield, 0, 0
    add     -1, d2
    bne     wcg_page
    ret     [d2,d3,a2,a3], 0x20

# WheelYield: a millisecond to the firmware's tasks (cnv_main.s DLY_TSK), between long pieces of work.
WheelYield:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     1, d0
    mov     DLY_TSK, a1
    calls   (a1)
    ret     [d2,d3,a2,a3], 0x20

# WheelSum(a0 = from, d0 = words) -> d0 = the words' sum. Leaf.
WheelSum:
    mov     d0, d1
    clr     d0
wsu_loop:
    mov     (a0), a1
    add     a1, d0
    add     4, a0
    add     -1, d1
    bne     wsu_loop
    rets

# WheelPiece(d0 = piece) -> a0 = its place, d0 = its size: A 0-10 (32 KB each), B 11 (32 KB), 12 (28 KB), C 13.
# Leaf.
WheelPiece:
    cmp     11, d0
    bcc     wpi_b
    asl     15, d0
    mov     WB_SEGA, a0
    add     d0, a0
    mov     WB_PIECE, d0
    rets
wpi_b:
    cmp     11, d0
    bne     wpi_b2
    mov     WB_SEGB, a0
    mov     WB_PIECE, d0
    rets
wpi_b2:
    cmp     12, d0
    bne     wpi_c
    mov     WB_SEGB + WB_PIECE, a0
    mov     WB_SEGB_LEN - WB_PIECE, d0
    rets
wpi_c:
    mov     WB_SEGC, a0
    mov     WB_SEGC_LEN, d0
    rets

# WheelUnpack(d0 = piece, d1 = its packed size, in WB_SCRATCH) -> d0 = 0 when it unpacked into its place.
WheelUnpack:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d1, d2
    call    WheelPiece, 0, 0
    mov     a0, a1                  # BkUnpack(a0 = packed, d0 = its size, a1 = its place, d1 = the piece's size)
    mov     d0, d1
    mov     d2, d0
    mov     WB_SCRATCH, a0
    call    BkUnpack, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# WheelEnsure -> d0 = 0 when A and B hold the checked blob and WT_BOTROW, WT_SHROW are made (WheelLayout), else 1
# (WH_FAIL says why). The VM's pages are saved first. A from the cache (WD_CACHE) when it has it, else every piece
# from the card (the first time: C drawn into the tall frame, WheelFrameInit; A's packed pieces kept in the cache); B
# from the card whenever it is not in RAM (the other help pages draw where it is).
WheelEnsure:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (WH_BORROW), d0
    cmp     0, d0
    bne     wen_have
    mov     WRAM, a0                # the VM's pages into display memory
    mov     WD_SAVE, a1
    call    WheelCopyPages, 0, 0
    mov     1, d0
    mov     d0, (WH_BORROW)
    clr     d0
    mov     d0, (WH_INRAM)
    mov     (WH_SAVES), d0
    inc     d0
    mov     d0, (WH_SAVES)
    mov     0x03, d0                # (step: the VM's pages saved)
    clr     d1
    call    WheelMark, 0, 0
wen_have:
    mov     (WH_INRAM), d0
    cmp     0, d0
    bne     wen_b
    mov     (WH_CACHED), d0
    cmp     0, d0
    beq     wen_card
    clr     d2                      # A from the cache
wen_cpiece:
    mov     0x18, d0                # (step: a piece from the cache)
    mov     d2, d1
    call    WheelMark, 0, 0
    mov     d2, d0                  # the packed piece from display memory to the scratch, unpacked in its place
    asl     2, d0
    mov     WH_PC_AT, a0
    add     d0, a0
    mov     (a0), a0
    mov     WH_PC_LEN, a1
    add     d0, a1
    mov     (a1), d3
    mov     d3, d0
    add     3, d0
    lsr     2, d0
    mov     WB_SCRATCH, a1
    call    WheelCopy, 0, 0
    mov     d2, d0
    mov     d3, d1
    call    WheelUnpack, 0, 0
    cmp     0, d0
    bne     wen_recard
    call    WheelYield, 0, 0        # (the firmware's main task runs between pieces)
    inc     d2
    cmp     WB_CACHED_N, d2
    bne     wen_cpiece
    mov     1, d0
    mov     d0, (WH_INRAM)
    bra     wen_b
wen_recard:
    clr     d0                      # (not as it was left: from the card again)
    mov     d0, (WH_CACHED)
    mov     d0, (WH_TFOK)
wen_card:
    mov     wh_t_loading, a0        # every piece, from the card
    mov     WHEEL_X0 + 172, d0
    mov     116, d1
    mov     1, d2
    call    WText, 0, 0
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (0x14, sp)          # the load's start
    mov     WD_CACHE, d0
    mov     d0, (WH_CNEXT)
    clr     d2
wen_piece:
    mov     d2, d0
    call    WheelCardPiece, 0, 0
    cmp     0, d0
    bne     wen_fail
    inc     d2
    cmp     WB_PIECES, d2
    bne     wen_piece
    call    WheelValid, 0, 0
    cmp     0, d0
    bne     wen_bad
    mov     WB_SEGC, a0             # C: its words sum to what the header says
    mov     WB_SEGC_LEN / 4, d0
    call    WheelSum, 0, 0
    mov     (WB_HDR + 24), d1
    cmp     d1, d0
    beq     wen_good
wen_bad:
    mov     0x30, d0
    clr     d2
    bra     wen_fail
wen_good:
    mov     0x20, d0                # (step: the blob checked)
    clr     d1
    call    WheelMark, 0, 0
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     (0x14, sp), d1
    sub     d1, d0
    mov     d0, (WH_LOADMS)
    mov     (WH_LOADS), d0
    inc     d0
    mov     d0, (WH_LOADS)
    call    WheelFrameInit, 0, 0    # C into the tall frame, once
    mov     0x21, d0                # (step: the frame drawn)
    clr     d1
    call    WheelMark, 0, 0
    mov     1, d0
    mov     d0, (WH_TFOK)
    mov     (WH_CNEXT), d0          # every packed piece of A kept: the next showings unpack them from there
    mov     WD_CACHE_END, a0
    cmp     a0, d0
    bhi     wen_lutc
    mov     1, d0
    mov     d0, (WH_CACHED)
wen_lutc:
    mov     WB_LUT + 32, a0         # the colours, for a showing before the blob is in RAM
    mov     WH_LUTC, a1
    mov     2 * 240 / 4, d0
    call    WheelCopy, 0, 0
    mov     1, d0
    mov     d0, (WH_INRAM)
    mov     d0, (WH_INB)
wen_b:
    mov     (WH_INB), d0            # B, from the card
    cmp     0, d0
    bne     wen_layout
    mov     11, d2
wen_bpiece:
    mov     d2, d0
    call    WheelCardPiece, 0, 0
    cmp     0, d0
    bne     wen_fail
    inc     d2
    cmp     13, d2
    bne     wen_bpiece
    call    WheelValid, 0, 0
    cmp     0, d0
    bne     wen_bad
    mov     1, d0
    mov     d0, (WH_INB)
wen_layout:
    call    WheelLayout, 0, 0
    cmp     0, d0
    beq     wen_lay
    mov     0x40, d0
    clr     d2
    bra     wen_fail
wen_lay:
    mov     0x22, d0                # (step: the rows laid out)
    clr     d1
    call    WheelMark, 0, 0
    clr     d0
    bra     wen_ret
wen_fail:
    add     d2, d0
    mov     d0, (WH_FAIL)
    clr     d0
    mov     d0, (WH_INRAM)
    mov     d0, (WH_INB)
    mov     1, d0
wen_ret:
    ret     [d2,d3,a2,a3], 0x30

# WheelCardPiece(d0 = piece) -> d0 = 0 when it was read from the card (the main task, WheelService) and unpacked in
# its place, A's packed pieces kept in the cache while they fit; else 0x10 + piece (not read) or 0x20 + piece (not
# unpacked).
WheelCardPiece:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    mov     0x10, d0                # (step: a piece asked for)
    mov     d2, d1
    call    WheelMark, 0, 0
    mov     d2, d0
    inc     d0
    mov     d0, (WH_LOADREQ)        # the main task reads it (WheelService)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d3
wcp_wait:
    call    HelpSleep, 0, 0
    mov     (WH_LOADREQ), d0
    cmp     0, d0
    beq     wcp_read
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    sub     d3, d0
    cmp     WH_LOAD_MS, d0
    bcs     wcp_wait
    clr     d0
    mov     d0, (WH_LOADREQ)
    bra     wcp_rfail
wcp_read:
    mov     0x11, d0                # (step: a piece read, its size)
    mov     (WH_LOADRES), d1
    call    WheelMark, 0, 0
    mov     (WH_LOADRES), d0
    cmp     8, d0
    bgt     wcp_keep
wcp_rfail:
    mov     0x10, d0
    add     d2, d0
    bra     wcp_ret
wcp_keep:
    cmp     WB_CACHED_N, d2         # A's packed pieces into the cache, while they fit
    bcc     wcp_unpack
    mov     d2, d1
    asl     2, d1
    mov     WH_PC_LEN, a0
    add     d1, a0
    mov     d0, (a0)
    mov     (WH_CNEXT), a1          # a1 = where it goes
    mov     WH_PC_AT, a0
    add     d1, a0
    mov     a1, (a0)
    add     3, d0
    and     0xFFFFFFFC, d0
    mov     a1, d1
    add     d0, d1                  # d1 = its end
    mov     WD_CACHE_END, a0
    cmp     a0, d1
    bls     wcp_fits
    mov     WD_CACHE_END + 4, d1    # (it does not fit: the cache stays off, WH_CACHED 0)
    mov     d1, (WH_CNEXT)
    bra     wcp_unpack
wcp_fits:
    mov     d1, (WH_CNEXT)
    lsr     2, d0
    mov     WB_SCRATCH, a0
    call    WheelCopy, 0, 0
    mov     0x12, d0                # (step: kept in the cache)
    mov     d2, d1
    call    WheelMark, 0, 0
wcp_unpack:
    mov     d2, d0
    mov     (WH_LOADRES), d1
    call    WheelUnpack, 0, 0
    cmp     0, d0
    beq     wcp_ok
    mov     0x20, d0
    add     d2, d0
    bra     wcp_ret
wcp_ok:
    mov     0x13, d0                # (step: unpacked)
    mov     d2, d1
    call    WheelMark, 0, 0
    clr     d0
wcp_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelValid -> d0 = 0 when A and B hold a blob of this build's kind: "AWWH", version, the three sizes, A and B's words
# summing to 0.
WheelValid:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     1, d2
    mov     (WB_HDR), d0
    mov     WB_MAGIC, d1
    cmp     d1, d0
    bne     wvl_ret
    mov     (WB_HDR + 4), d0
    cmp     WB_VERSION, d0
    bne     wvl_ret
    mov     (WB_HDR + 8), d0
    cmp     WB_SEGA_LEN, d0
    bne     wvl_ret
    mov     (WB_HDR + 12), d0
    cmp     WB_SEGB_LEN, d0
    bne     wvl_ret
    mov     (WB_HDR + 16), d0
    cmp     WB_SEGC_LEN, d0
    bne     wvl_ret
    mov     WB_SEGA, a0
    mov     WB_SEGA_LEN / 4, d0
    call    WheelSum, 0, 0
    mov     d0, d3
    mov     WB_SEGB, a0
    mov     WB_SEGB_LEN / 4, d0
    call    WheelSum, 0, 0
    add     d3, d0
    cmp     0, d0
    bne     wvl_ret
    clr     d2
wvl_ret:
    mov     d2, d0
    ret     [d2,d3,a2,a3], 0x20

# WheelLayout -> d0 = 0 when made: WT_BOTROW, each row of the lower disk's spans in A or B (from WB_BOTOFF); WT_SHROW,
# each row's copy of the tall frame's spans, one after the other in ARENA5, then ARENA6 (codewheel_render.py
# shadow_rows), a row never straddling; 1 when they do not fit. Leaf.
WheelLayout:
    movm    [d2,d3,a2,a3], (sp)
    mov     WB_BOTOFF, a0
    mov     WT_BOTROW, a1
    mov     WHEEL_ROWS, d2
wly_bot:
    mov     (a0), d0
    cmp     WB_SEGA_LEN, d0
    bcc     wly_b
    add     WB_SEGA, d0
    bra     wly_set
wly_b:
    add     -WB_SEGA_LEN, d0
    add     WB_SEGB, d0
wly_set:
    mov     d0, (a1)
    add     4, a0
    add     4, a1
    add     -1, d2
    bne     wly_bot
    mov     WB_SPANS, a0
    mov     WT_SHROW, a1
    mov     ARENA5, a2              # a2 = the next free byte
    mov     ARENA5_END - 1, a3      # a3 = this room's last byte
    mov     WHEEL_ROWS, d2
wly_sh:
    movhu   (2, a0), d0             # x1 - x0
    movhu   (a0), d1
    sub     d1, d0
    bge     wly_len
    clr     d0
wly_len:
    mov     a2, d1                  # d1 = the row's last byte
    add     d0, d1
    add     -1, d1
    cmp     a3, d1
    bls     wly_fit
    mov     ARENA6_LAST, d1         # the next room
    cmp     d1, a3
    beq     wly_full
    mov     d1, a3
    mov     ARENA6, a2
    mov     a2, d1
    add     d0, d1
    add     -1, d1
    cmp     a3, d1
    bhi     wly_full
wly_fit:
    mov     a2, (a1)
    inc     d1
    mov     d1, a2
    add     4, a0
    add     4, a1
    add     -1, d2
    bne     wly_sh
    clr     d0
    ret     [d2,d3,a2,a3], 16
wly_full:
    mov     1, d0
    ret     [d2,d3,a2,a3], 16

# WheelFrameInit: the tall frame's rows outside the spans: entry 0 (the margins, the corners), and the lower disk
# outside the upper one's reach (C: each row's [xl, xr) less its span, which WheelDraw fills).
WheelFrameInit:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     WB_RING + 4 * WHEEL_ROWS, a2  # a2 = C's next byte
    clr     d2                      # d2 = y
wfi_row:
    mov     d2, d0
    mov     640, d1
    mulu    d1, d0
    mov     WD_TF, a3
    add     d0, a3                  # a3 = the row
    mov     d2, d0
    asl     2, d0
    mov     WB_RING, a0
    add     d0, a0
    movhu   (a0), d1
    mov     d1, (0x14, sp)          # xl
    movhu   (2, a0), d1
    mov     d1, (0x18, sp)          # xr
    mov     WB_SPANS, a0
    add     d0, a0
    movhu   (a0), d1
    mov     d1, (0x1C, sp)          # x0
    movhu   (2, a0), d1
    mov     d1, (0x20, sp)          # x1
    mov     (0x1C, sp), d0
    cmp     d0, d1
    bhi     wfi_span
    mov     (0x18, sp), d1          # no span: [xl, xr) whole
    mov     d1, (0x1C, sp)
    mov     d1, (0x20, sp)
wfi_span:
    clr     d0                      # [0, X0 + xl): 0
    mov     a3, a0
    mov     (0x14, sp), d1
    add     WHEEL_X0, d1
    call    wfi_zero, 0, 0
    mov     (0x14, sp), d0          # [xl, x0): C
    mov     (0x1C, sp), d1
    call    wfi_ring, 0, 0
    mov     (0x20, sp), d0          # [x1, xr): C
    mov     (0x18, sp), d1
    call    wfi_ring, 0, 0
    mov     (0x18, sp), d0          # [X0 + xr, 640): 0
    add     WHEEL_X0, d0
    mov     a3, a0
    mov     640, d1
    call    wfi_zero, 0, 0
    inc     d2
    cmp     WHEEL_ROWS, d2
    bne     wfi_row
    ret     [d2,d3,a2,a3], 0x30

# wfi_zero(a0 = the row, d0 = from, d1 = to: multiples of 4): entry 0 there. Leaf.
wfi_zero:
    add     d0, a0
    sub     d0, d1
    lsr     2, d1
    beq     wfz_ret
    clr     d0
wfz_loop:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     wfz_loop
wfz_ret:
    rets

# wfi_ring(d0 = from, d1 = to, wheel columns, multiples of 4; a2 = C's next byte, a3 = the row): C's bytes there, a2
# past them. Leaf.
wfi_ring:
    mov     a3, a0
    add     WHEEL_X0, a0
    add     d0, a0
    sub     d0, d1
    lsr     2, d1
    beq     wfr_ret
wfr_loop:
    mov     (a2), d0
    mov     d0, (a0)
    add     4, a2
    add     4, a0
    add     -1, d1
    bne     wfr_loop
wfr_ret:
    rets

# WheelClearRows(d0 = the first row): the region's 240 rows of the tall frame, every column, entry 0. Leaf.
WheelClearRows:
    mov     640, d1
    mulu    d1, d0
    mov     WD_TF, a0
    add     d0, a0
    mov     640 * REGION_ROWS / 4, d1
    clr     d0
wcr_loop:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     wcr_loop
    rets

# WheelClearMargins(d0 = the first row): the text's columns (0-79, 560-639) of the region's 240 rows, entry 0. Leaf.
WheelClearMargins:
    movm    [d2], (sp)
    mov     640, d1
    mulu    d1, d0
    mov     WD_TF, a0
    add     d0, a0
    mov     REGION_ROWS, d2
    clr     d0
wcm_row:
    mov     WHEEL_X0 / 4, d1
wcm_l:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     wcm_l
    add     WHEEL_W, a0
    mov     (640 - WHEEL_X0 - WHEEL_W) / 4, d1
wcm_r:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     wcm_r
    add     -1, d2
    bne     wcm_row
    ret     [d2], 4

# WheelStart(d0 = the tall frame's first row shown) -> d0 = the controller's start address for it (the bottom-right
# pixel's word: 180-degree SwivelView). Leaf.
WheelStart:
    add     REGION_ROWS - 1, d0
    mov     320, d1
    mulu    d1, d0
    add     WD_TF_OFS / 2 + 319, d0
    rets

# WheelLcdSet: the controller on the tall frame at row WH_SC_ROW: 8 bits a pixel, lines of 320 words (lcd8.s LcdSet's
# settings), its start address. Leaf (LcdStart's).
WheelLcdSet:
    mov     0x40, d0                # 320 words = 0x0140
    movbu   d0, (LCDC + 0x46)
    mov     0x01, d0
    movbu   d0, (LCDC + 0x47)
    movbu   (LCD_SAVE + 0), d0
    and     0xF8, d0
    or      3, d0
    movbu   d0, (LCDC + 0x40)
    mov     (WH_SC_ROW), d0         # (WheelStart's arithmetic: a leaf calls nothing)
    add     REGION_ROWS - 1, d0
    mov     320, d1
    mulu    d1, d0
    add     WD_TF_OFS / 2 + 319, d0
    bra     LcdStart

# WheelLcdCheck: is the controller still on the tall frame (8 bits a pixel, WH_SC_ROW's start)? If something else set
# it, set it back (lcd8.s LcdCheck, for the page). Leaf (WheelLcdSet's).
WheelLcdCheck:
    movbu   (LCDC + 0x40), d0
    and     7, d0
    cmp     3, d0
    bne     wlc_bad
    mov     (WH_SC_ROW), d0         # (WheelStart's arithmetic)
    add     REGION_ROWS - 1, d0
    mov     320, d1
    mulu    d1, d0
    add     WD_TF_OFS / 2 + 319, d0
    and     0xFFFF, d0
    movhu   (LCDC + 0x42), d1
    cmp     d1, d0
    bne     wlc_bad
    rets
wlc_bad:
    mov     (PF_SENT_BAD), d0
    inc     d0
    mov     d0, (PF_SENT_BAD)
    bra     WheelLcdSet

# WheelTexts: the page's text in the margins, for the region whose first row is WH_TROW: the fixed lines, the
# regions' labels (the one shown in yellow), "ARROW AT n", the drawing times.
WheelTexts:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     wh_items, a2
wtx_item:
    movhu   (a2), d0                # x (0xFFFF ends)
    cmp     0xFFFF, d0
    beq     wtx_more
    movhu   (2, a2), d1
    movhu   (4, a2), d2
    movhu   (6, a2), d3             # a region's label: 1 + the region
    cmp     0, d3
    beq     wtx_put
    add     -1, d3
    mov     (WH_REGION), a0
    cmp     a0, d3
    bne     wtx_put
    mov     3, d2                   # (the region shown)
wtx_put:
    mov     (8, a2), a0
    call    WText, 0, 0
    add     12, a2
    bra     wtx_item
wtx_more:
    mov     (WH_RXRD), d0           # no wheel found in this firmware: say so
    cmp     0, d0
    bne     wtx_arrow
    mov     wh_t_nowheel, a0
    mov     560, d0
    mov     196, d1
    mov     3, d2
    call    WText, 0, 0
wtx_arrow:
    call    WheelArrowText, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# WheelArrowText: "ARROW AT n" (the number turned to) and the drawing times, right of the wheel.
WheelArrowText:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     WH_TEXT, a0
    mov     (WH_POS), d0
    inc     d0
    mov     10, d1
    call    FmtNum, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     WH_TEXT, a0
    mov     560, d0
    mov     68, d1
    mov     1, d2
    call    WText, 0, 0
    call    WheelTimeText, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# WheelTimeText: how long the last picture took, turning and at rest, in ms (for the owner's unit: README-CNV.md).
WheelTimeText:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (WH_TLAST), d0
    mov     wh_t_turn, a1
    mov     162, d1
    call    wh_ms, 0, 0
    mov     (WH_TREST), d0
    mov     wh_t_rest, a1
    mov     174, d1
    call    wh_ms, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# wh_ms(d0 = 1/2001 ms counts, a1 = the label, d1 = y): "label nnnn" (whole ms, 10 characters) in the right margin.
wh_ms:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d1, d3
    mov     d0, d2
    mov     WH_TEXT, a0
    call    StrPut, 0, 0
    mov     a0, a2
    mov     d2, d0
    mov     2001, d1
    call    Div, 0, 0
    mov     a2, a0
    mov     6, d1
    call    FmtNum, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     WH_TEXT, a0
    mov     560, d0
    mov     d3, d1
    mov     1, d2
    call    WText, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# WText(a0 = NUL-terminated text, d0 = x (a multiple of 4), d1 = y in the region, d2 = entry): into the tall frame at
# row WH_TROW + y, 8x8 glyphs from AW_FONT, each cell written whole (its background entry 0), four pixels a store.
# Keeps d2.
WText:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, a2                  # a2 = text
    mov     (WH_TROW), d3
    add     d1, d3
    mov     640, d1
    mulu    d1, d3
    add     d0, d3
    mov     WD_TF, a3
    add     d3, a3                  # a3 = the cell's first pixel
    mov     d2, (0x14, sp)          # the entry
wtt_char:
    movbu   (a2), d0
    cmp     0, d0
    beq     wtt_ret
    inc     a2
    add     -0x20, d0
    asl     3, d0
    mov     AW_FONT, a0
    add     d0, a0                  # a0 = the glyph
    mov     a3, a1
    mov     8, d0
    mov     d0, (0x18, sp)          # rows
wtt_row:
    movbu   (a0), d3                # bits, bit 7 leftmost
    inc     a0
    mov     2, d0
    mov     d0, (0x1C, sp)          # two words a row
wtt_word:
    clr     d2                      # four pixels, the leftmost in the low byte
    mov     4, d1
wtt_px:
    lsr     8, d2
    btst    0x80, d3
    beq     wtt_off
    mov     (0x14, sp), d0
    asl     24, d0
    or      d0, d2
wtt_off:
    asl     1, d3
    add     -1, d1
    bne     wtt_px
    mov     d2, (a1)
    add     4, a1
    mov     (0x1C, sp), d0
    add     -1, d0
    mov     d0, (0x1C, sp)
    bne     wtt_word
    add     640 - 8, a1
    mov     (0x18, sp), d0
    add     -1, d0
    mov     d0, (0x18, sp)
    bne     wtt_row
    add     8, a3
    bra     wtt_char
wtt_ret:
    ret     [d2,d3,a2,a3], 0x30

# WheelSleepMs -> d0 = how long the help loop sleeps (help.s HelpSleep): 2 ms while the disk turns, the page scrolls,
# a region is asked for or the picture at rest is being made, else 30. Leaf.
WheelSleepMs:
    mov     2, d0
    mov     (WH_MOVING), d1
    cmp     0, d1
    bne     wsm_ret
    mov     (WH_SCROLL), d1
    cmp     0, d1
    bne     wsm_ret
    mov     (WH_SROW), d1
    cmp     REGION_ROWS, d1
    bcs     wsm_ret
    mov     (WH_ON), d1
    cmp     0, d1
    beq     wsm_long
    mov     (WH_RSEQ), d1
    mov     (WH_RSEEN), a0
    cmp     a0, d1
    bne     wsm_ret
wsm_long:
    mov     30, d0
wsm_ret:
    rets

# WheelPoll: the help loop on the page (help.s): the detents counted since the last look start a turn (WheelStep),
# but not while scrolling; a region asked for starts a scroll (WheelScrollStart), once no turn is under way; a turn or
# a scroll under way gets its next picture or start address; else the picture at rest, a few rows; every 16 looks the
# LCD's controller is checked (WheelLcdCheck). -> d0 = 1 while turning or scrolling.
WheelPoll:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (WH_ON), d0
    cmp     0, d0
    beq     wpl_ret
    mov     (WH_SCROLL), d0
    cmp     0, d0
    bne     wpl_region
    mov     (WH_STEPS), d0
    mov     (WH_TAKEN), d1
    cmp     d1, d0
    beq     wpl_region
    mov     d0, (WH_TAKEN)
    sub     d1, d0
    call    WheelStep, 0, 0
wpl_region:
    mov     (WH_MOVING), d0
    cmp     0, d0
    bne     wpl_turn
    mov     (WH_SCROLL), d0
    cmp     0, d0
    bne     wpl_scroll
    mov     (WH_RSEQ), d0
    mov     (WH_RSEEN), d1
    cmp     d1, d0
    beq     wpl_rest
    mov     d0, (WH_RSEEN)
    mov     (WH_RREQ), d0
    mov     (WH_REGION), d1
    cmp     d1, d0
    beq     wpl_rest
    call    WheelScrollStart, 0, 0
wpl_scroll:
    call    WheelScrollStep, 0, 0
    bra     wpl_check
wpl_turn:
    call    WheelTurn, 0, 0
    bra     wpl_check
wpl_rest:
    mov     (WH_SROW), d0           # the picture at rest, WH_SROWS rows a poll (a detent meanwhile stops it)
    cmp     REGION_ROWS, d0
    bcc     wpl_check
    call    WheelSmoothStep, 0, 0
wpl_check:
    mov     (WH_POLLS), d0
    inc     d0
    mov     d0, (WH_POLLS)
    and     15, d0
    bne     wpl_ret
    mov     (WH_SCROLL), d0         # (a scroll writes the start address itself)
    cmp     0, d0
    bne     wpl_ret
    call    WheelLcdCheck, 0, 0
wpl_ret:
    mov     (WH_MOVING), d0
    mov     (WH_SCROLL), d1
    or      d1, d0
    ret     [d2,d3,a2,a3], 0x20

# WheelScrollStart(d0 = the region asked for): the rows of its 240 not drawn at the angle the disk rests at are drawn
# now (nearest; WH_STALE counts them), the text moves to the new region (the old one's margins cleared), and the
# scroll starts from the row shown: 120 rows in WH_SCROLL_MS, 240 in 100 ms more.
WheelScrollStart:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    mov     (WH_REGION), d0         # d3 = the old first row
    mov     REGION_ROWS / 2, d1
    mulu    d1, d0
    mov     d0, d3
    mov     d2, (WH_REGION)
    mov     d2, d0
    mov     REGION_ROWS / 2, d1
    mulu    d1, d0
    mov     d0, d2                  # d2 = the new first row
    mov     d2, (WH_R0)
    add     REGION_ROWS, d0
    mov     d0, (WH_R1)
    mov     1, d0
    mov     d0, (WH_BUSY)
    clr     d0
    mov     d0, (WH_NSTORE)
    mov     (WH_ANG), d0
    mov     2, d1                   # nearest, rows drawn at this angle already passed over
    call    WheelDraw, 0, 0
    mov     (WH_NDRAWN), d0
    mov     d0, (WH_STALE)
    mov     d3, d0
    call    WheelClearMargins, 0, 0
    mov     d2, (WH_TROW)
    call    WheelTexts, 0, 0
    clr     d0
    mov     d0, (WH_BUSY)
    mov     d3, (WH_SC_FROM)
    mov     d2, (WH_SC_TO)
    mov     WH_SCROLL_MS, d0
    sub     d3, d2
    bge     wss_abs
    clr     d1
    sub     d2, d1
    mov     d1, d2
wss_abs:
    cmp     REGION_ROWS, d2
    bcs     wss_dur
    add     100, d0
wss_dur:
    mov     d0, (WH_SC_DUR)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (WH_SC_T0)
    mov     REGION_ROWS, d0         # (no picture at rest meanwhile)
    mov     d0, (WH_SROW)
    clr     d0
    mov     d0, (WH_SC_N)
    mov     1, d0
    mov     d0, (WH_SCROLL)
    mov     (WH_SCROLLS), d0
    inc     d0
    mov     d0, (WH_SCROLLS)
    ret     [d2,d3,a2,a3], 0x20

# WheelScrollStep: the scroll's row for now, from + (to - from) (1 - (1 - t)^3), into the controller's start address
# when it changed; at its end, the new region's row, and its picture at rest to be made (WH_SROW).
WheelScrollStep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     (WH_SC_T0), d1
    sub     d1, d0                  # d0 = ms gone
    mov     (WH_SC_DUR), d1
    cmp     d1, d0
    bcs     wst_mid
    mov     (WH_SC_TO), d2          # the end
    clr     d0
    mov     d0, (WH_SCROLL)
    mov     d0, (WH_SROW)
    bra     wst_set
wst_mid:
    asl     15, d0                  # u = t / dur, 15 bits
    call    Div, 0, 0
    mov     0x8000, d1              # p = 1 - (1 - u)^3, 15 bits
    sub     d0, d1
    mov     d1, d0
    mulu    d1, d0
    lsr     15, d0
    mulu    d1, d0
    lsr     15, d0
    mov     0x8000, d1
    sub     d0, d1                  # d1 = p
    mov     (WH_SC_TO), d0          # |to - from| * p >> 15, with its sign
    mov     (WH_SC_FROM), d2
    sub     d2, d0
    mov     d0, d3
    cmp     0, d3
    bge     wst_pos
    clr     d0
    sub     d3, d0
wst_pos:
    mulu    d1, d0
    lsr     15, d0
    cmp     0, d3
    bge     wst_add
    clr     d1
    sub     d0, d1
    mov     d1, d0
wst_add:
    add     d0, d2                  # d2 = the row now
wst_set:
    mov     (WH_SC_ROW), d0
    cmp     d0, d2
    beq     wst_ret
    mov     d2, (WH_SC_ROW)
    mov     (WH_SC_N), d0
    inc     d0
    mov     d0, (WH_SC_N)
    mov     d2, d0
    call    WheelStart, 0, 0
    call    LcdStart, 0, 0
wst_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelStep(d0 = detents, signed): the target that many numbers on, wrapping (clockwise for +, as the TEMPO wheel
# turned up); a turn from the angle drawn to the target's, the way the detents went (a whole turn when the target is
# where the disk is).
WheelStep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2                  # d2 = detents
    mov     (WH_POS), d0
    add     d2, d0
wsp_neg:
    cmp     0, d0
    bge     wsp_mod
    add     WHEEL_NUMS * 100, d0
    bra     wsp_neg
wsp_mod:
    mov     WHEEL_NUMS, d1
    call    Div, 0, 0
    mov     d1, (WH_POS)
    asl     1, d1
    mov     WB_ANGLES, a0
    add     d1, a0
    movhu   (a0), d3                # d3 = the target's angle
    mov     REGION_ROWS, d1         # (the picture at rest, if one was being made: not now)
    mov     d1, (WH_SROW)
    mov     (WH_ANG), d1            # from the angle drawn
    mov     d1, (WH_FROM)
    cmp     0, d2
    blt     wsp_back
    mov     d3, d0                  # forwards: (target - from) mod 2^16, 0 a whole turn
    sub     d1, d0
    and     0xFFFF, d0
    bne     wsp_set
    mov     0x10000, d0
    bra     wsp_set
wsp_back:
    mov     d1, d0                  # backwards: -((from - target) mod 2^16)
    sub     d3, d0
    and     0xFFFF, d0
    bne     wsp_bneg
    mov     0x10000, d0
wsp_bneg:
    clr     d1
    sub     d0, d1
    mov     d1, d0
wsp_set:
    mov     d0, (WH_DELTA)
    cmp     0, d0                   # the turn's time: WH_TURN_MS + 100 ms a number (3277 a number), at most WH_TURN_MAX
    bge     wsp_abs
    clr     d1
    sub     d0, d1
    mov     d1, d0
wsp_abs:
    mov     100, d1
    mulu    d1, d0
    mov     3277, d1
    call    Div, 0, 0
    add     WH_TURN_MS, d0
    cmp     WH_TURN_MAX, d0
    bls     wsp_dur
    mov     WH_TURN_MAX, d0
wsp_dur:
    mov     d0, (WH_DUR)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (WH_T0)
    clr     d0
    mov     d0, (WH_TURNF)
    mov     1, d0
    mov     d0, (WH_MOVING)
    call    WheelArrowText, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# WheelTurn: the turn's picture for now: angle = from + delta * (1 - (1 - t)^3), t the time gone in the turn; at its
# end, the target's angle (nearest), and its picture at rest to be made (WH_SROW).
WheelTurn:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     (WH_T0), d1
    sub     d1, d0                  # d0 = ms gone
    mov     (WH_DUR), d1
    cmp     d1, d0
    bcs     wtn_mid
    clr     d0                      # the end: the target, nearest at once, then at rest (WheelSmoothStep)
    mov     d0, (WH_MOVING)
    mov     (WH_POS), d0
    asl     1, d0
    mov     WB_ANGLES, a0
    add     d0, a0
    movhu   (a0), d0
    call    WheelPicture, 0, 0
    clr     d0
    mov     d0, (WH_SROW)
    bra     wtn_ret
wtn_mid:
    asl     15, d0                  # u = t / dur, 15 bits (0 <= u < 32768)
    call    Div, 0, 0
    mov     0x8000, d1              # v = 1 - u; p = 1 - v^3, all 15 bits (no product past 2^31)
    sub     d0, d1
    mov     d1, d0
    mulu    d1, d0
    lsr     15, d0
    mulu    d1, d0
    lsr     15, d0
    mov     0x8000, d1
    sub     d0, d1                  # d1 = p
    mov     (WH_DELTA), d0          # |delta| * p >> 15 (|delta| <= 65536: under 2^31), with delta's sign
    mov     d0, d2
    cmp     0, d2
    bge     wtn_dpos
    clr     d0
    sub     d2, d0
wtn_dpos:
    mulu    d1, d0
    lsr     15, d0
    cmp     0, d2
    bge     wtn_add
    clr     d1
    sub     d0, d1
    mov     d1, d0
wtn_add:
    mov     (WH_FROM), d1
    add     d1, d0
    and     0xFFFF, d0
    mov     (WH_ANG), d1
    cmp     d1, d0
    beq     wtn_ret                 # (no move since the last picture)
    call    WheelPicture, 0, 0
    mov     (WH_TURNF), d0
    inc     d0
    mov     d0, (WH_TURNF)
wtn_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelPicture(d0 = angle): the region's 240 rows at that angle, nearest (a turning picture): WH_ANG, WH_SMOOTH 0,
# WH_SEQ + 2, its time (WH_TLAST, WH_TMAX) and its stores into the LCD (WH_STORES).
WheelPicture:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, d2
    mov     1, d0
    mov     d0, (WH_BUSY)
    call    Stamp, 0, 0
    mov     d0, d3
    mov     (WH_REGION), d0
    mov     REGION_ROWS / 2, d1
    mulu    d1, d0
    mov     d0, (WH_R0)
    add     REGION_ROWS, d0
    mov     d0, (WH_R1)
    clr     d0
    mov     d0, (WH_NSTORE)
    mov     d2, d0
    clr     d1
    call    WheelDraw, 0, 0
    call    Stamp, 0, 0
    sub     d3, d0
    mov     d0, (WH_TLAST)
    mov     (WH_TMAX), d1
    cmp     d1, d0
    bls     wpc_max
    mov     d0, (WH_TMAX)
wpc_max:
    mov     (WH_NSTORE), d0
    mov     d0, (WH_STORES)
    mov     d2, (WH_ANG)
    clr     d0
    mov     d0, (WH_SMOOTH)
    mov     d0, (WH_TACC)
    mov     (WH_NFRAMES), d0
    inc     d0
    mov     d0, (WH_NFRAMES)
    clr     d0
    mov     d0, (WH_SSTORES)
    mov     d0, (WH_BUSY)
    mov     (WH_SEQ), d0
    add     2, d0
    mov     d0, (WH_SEQ)
    ret     [d2,d3,a2,a3], 0x30

# WheelSmoothStep: WH_SROWS more rows of the region's picture at rest (bilinear) at WH_ANG, from WH_SROW (rows already
# bilinear at that angle passed over); the last ones finish it: WH_SMOOTH 1, WH_SEQ + 2, its time (WH_TREST: the rows'
# times added up) and stores (WH_SSTORES); the drawing times shown.
WheelSmoothStep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     1, d0
    mov     d0, (WH_BUSY)
    call    Stamp, 0, 0
    mov     d0, d3
    mov     (WH_REGION), d0
    mov     REGION_ROWS / 2, d1
    mulu    d1, d0
    mov     d0, d2                  # d2 = the region's first row
    mov     (WH_SROW), d0
    add     d2, d0
    mov     d0, (WH_R0)
    mov     (WH_SROW), d0
    add     WH_SROWS, d0
    cmp     REGION_ROWS, d0
    bls     wss_r1
    mov     REGION_ROWS, d0
wss_r1:
    mov     d0, (WH_SROW)
    add     d2, d0
    mov     d0, (WH_R1)
    clr     d0
    mov     d0, (WH_NSTORE)
    mov     (WH_ANG), d0
    mov     1, d1
    call    WheelDraw, 0, 0
    call    Stamp, 0, 0
    sub     d3, d0
    mov     (WH_TACC), d1
    add     d0, d1
    mov     d1, (WH_TACC)
    mov     (WH_SSTORES), d0
    mov     (WH_NSTORE), d1
    add     d1, d0
    mov     d0, (WH_SSTORES)
    mov     (WH_SROW), d0
    cmp     REGION_ROWS, d0
    bcs     wss_ret
    mov     (WH_TACC), d0           # finished
    mov     d0, (WH_TREST)
    mov     1, d0
    mov     d0, (WH_SMOOTH)
    mov     (WH_NREST), d0
    inc     d0
    mov     d0, (WH_NREST)
    clr     d0
    mov     d0, (WH_BUSY)
    mov     (WH_SEQ), d0
    add     2, d0
    mov     d0, (WH_SEQ)
    call    WheelTimeText, 0, 0
wss_ret:
    ret     [d2,d3,a2,a3], 0x30

# =================================================================================
# WheelDraw(d0 = angle, 1/65536 turn; d1 = 1 bilinear (at rest), 0 nearest (turning), 2 nearest but only the rows not
# drawn at that angle): rows WH_R0 .. WH_R1 - 1 of the tall frame's wheel, the upper disk at that angle over the lower
# one (codewheel_render.py render_row()); a row already drawn so (WT_ROWST: the angle, | 0x10000 bilinear) is passed
# over. Into the LCD, four pixels a store, only the words that differ from the row's copy (WT_SHROW) but in a row whose
# copy is unknown (WT_ROWST -1: every word stored); WH_NSTORE counts the stores, WH_NDRAWN the rows drawn.
#   c = SIN[(angle >> 4) + 1024], s = SIN[angle >> 4];  dx2 = 2x + 1 - 480, dy2 = 2y + 1 - 480
#   U = (256 << 16) + c dx2 + s dy2;  V = (256 << 16) - s dx2 + c dy2   (16.16, at the span's first pixel)
#   nearest: the span in pieces of WH_SEG pixels; at a piece's start U and V to 9.7, rounded, in one word, V << 16 |
#     U, and so the step along the row, (dV << 16) + dU with dU = (2c + 256) >> 9, dV = (-2s + 256) >> 9: one add a
#     pixel; the texel's row is bits 23-31, its column bits 7-15: TOPV + (word >> 23 << 9 | word << 16 >> 23);
#     four pixels gathered in a3, compared with the copy (a2) and stored to the LCD at (row's LCD - row's copy, a2)
#   bilinear: 16.16, U and V each a stack variable, a pixel a turn into WT_LINE, then its words stored as above
# Locals: 0x14 dU (16.16), 0x18 dV, 0x1C the span's end (the lower disk's row), 0x20 y, 0x24 c, 0x28 s, 0x2C the
# mode, 0x30 smooth, 0x34 x0, 0x38 x1, 0x3C U, 0x40 V, 0x44 8 - fx, 0x48 fx, 0x4C 8 - fy, 0x50 fy, 0x54 the first
# row's sum, 0x58 where the pixel goes, 0x5C dUV (nearest), 0x60 force, 0x64 the LCD less the copy, 0x68 the piece's
# end, 0x6C angle, 0x70 the row's state to set.
WheelDraw:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x80, sp
    mov     d0, (0x6C, sp)
    mov     d1, (0x2C, sp)
    and     1, d1
    mov     d1, (0x30, sp)
    clr     d1
    mov     d1, (WH_NDRAWN)
    lsr     4, d0                   # s, c
    and     4095, d0
    mov     d0, d1
    asl     1, d0
    mov     WB_SIN, a0
    add     d0, a0
    movhu   (a0), d0
    exth    d0
    mov     d0, (0x28, sp)
    add     1024, d1
    and     4095, d1
    asl     1, d1
    mov     WB_SIN, a0
    add     d1, a0
    movhu   (a0), d0
    exth    d0
    mov     d0, (0x24, sp)
    asl     1, d0                   # dU = 2c, dV = -2s (16.16)
    mov     d0, (0x14, sp)
    mov     (0x28, sp), d0
    asl     1, d0
    clr     d1
    sub     d0, d1
    mov     d1, (0x18, sp)
    mov     (0x14, sp), d0          # dUV = (((dV + 256) >> 9) << 16) + ((dU + 256) >> 9)
    add     256, d0
    asr     9, d0
    mov     (0x18, sp), d1
    add     256, d1
    asr     9, d1
    asl     16, d1
    add     d1, d0
    mov     d0, (0x5C, sp)
    mov     (WH_R0), d0
    mov     d0, (0x20, sp)          # y
wd_row:
    mov     (0x20, sp), d0
    mov     (WH_R1), d1
    cmp     d1, d0
    bcc     wd_ret
    asl     2, d0                   # the row's state
    mov     WT_ROWST, a0
    add     d0, a0
    mov     (a0), d1
    clr     d2                      # force: unknown copy
    cmp     -1, d1
    bne     wd_known
    mov     1, d2
    bra     wd_go
wd_known:
    mov     (0x6C, sp), d0          # drawn at this angle already?
    mov     d1, d3
    and     0xFFFF, d3
    cmp     d0, d3
    bne     wd_go
    mov     (0x2C, sp), d0
    cmp     2, d0
    beq     wd_next                 # (any kind will do)
    lsr     16, d1
    cmp     d0, d1
    beq     wd_next
wd_go:
    mov     d2, (0x60, sp)
    mov     (0x30, sp), d0          # the state it will have
    asl     16, d0
    mov     (0x6C, sp), d1
    or      d1, d0
    mov     d0, (0x70, sp)
    mov     (WH_NDRAWN), d0
    inc     d0
    mov     d0, (WH_NDRAWN)
    mov     (0x20, sp), d0
    asl     2, d0
    mov     WB_SPANS, a0
    add     d0, a0
    movhu   (a0), d1
    mov     d1, (0x34, sp)          # x0
    movhu   (2, a0), d1
    mov     d1, (0x38, sp)          # x1
    mov     (0x34, sp), d0
    cmp     d1, d0
    bcc     wd_done                 # (no span)
    # U, V at x0
    mov     (0x34, sp), d2          # dx2 = 2 x0 + 1 - 480
    asl     1, d2
    add     1 - WHEEL_W, d2
    mov     (0x20, sp), d3          # dy2 = 2 y + 1 - 480
    asl     1, d3
    add     1 - WHEEL_ROWS, d3
    mov     (0x24, sp), d0          # U = (256 << 16) + c dx2 + s dy2
    mul     d2, d0
    mov     (0x28, sp), d1
    mul     d3, d1
    add     d1, d0
    add     256 << 16, d0
    mov     d0, (0x3C, sp)
    mov     (0x28, sp), d0          # V = (256 << 16) - s dx2 + c dy2
    mul     d2, d0
    mov     (0x24, sp), d1
    mul     d3, d1
    sub     d0, d1
    add     256 << 16, d1
    mov     d1, (0x40, sp)
    mov     (0x20, sp), d0          # a1 = the lower disk's row, a2 = its copy, the LCD less the copy
    asl     2, d0
    mov     WT_BOTROW, a0
    add     d0, a0
    mov     (a0), a1
    mov     WT_SHROW, a0
    add     d0, a0
    mov     (a0), a2
    mov     (0x20, sp), d0
    mov     640, d1
    mulu    d1, d0
    mov     (0x34, sp), d1
    add     d1, d0
    add     WD_TF + WHEEL_X0, d0
    mov     a2, d1
    sub     d1, d0
    mov     d0, (0x64, sp)
    mov     (0x38, sp), d0          # the span's end in the lower disk's row
    mov     (0x34, sp), d1
    sub     d1, d0
    add     a1, d0
    mov     d0, (0x1C, sp)
    mov     (0x30, sp), d0
    cmp     0, d0
    bne     wd_smooth
    # ---- nearest: four pixels a turn, in pieces of WH_SEG ----
    mov     WB_TOPV, a0
wn_piece:
    mov     (0x40, sp), d2          # d2 = V 9.7 << 16 | U 9.7 (rounded), d3 = dUV
    add     256, d2
    lsr     9, d2
    asl     16, d2
    mov     (0x3C, sp), d0
    add     256, d0
    lsr     9, d0
    add     d0, d2
    mov     (0x5C, sp), d3
    mov     a1, d0                  # the piece's end
    add     WH_SEG, d0
    mov     (0x1C, sp), d1
    cmp     d1, d0
    bls     wn_end
    mov     d1, d0
wn_end:
    mov     d0, (0x68, sp)
    mov     (0x24, sp), d0          # U, V at the next piece: + WH_SEG x (2c, -2s)
    asl     8, d0
    mov     (0x3C, sp), d1
    add     d0, d1
    mov     d1, (0x3C, sp)
    mov     (0x28, sp), d0
    asl     8, d0
    mov     (0x40, sp), d1
    sub     d0, d1
    mov     d1, (0x40, sp)
wn_four:
    mov     d2, d0                  # pixel 0: V's integer part << 9 | U's
    lsr     23, d0
    asl     9, d0
    mov     d2, d1
    asl     16, d1
    lsr     23, d1
    or      d1, d0
    movbu   (d0, a0), d0
    cmp     16, d0
    bcc     wn_ok0                  # the upper disk: its entry
    asl     8, d0                   # a window: the lower disk under its shadow level
    movbu   (0, a1), d1
    or      d1, d0
    add     WB_SHADE_OFF, d0
    movbu   (d0, a0), d0
wn_ok0:
    mov     d0, a3
    add     d3, d2
    mov     d2, d0                  # pixel 1: V's integer part << 9 | U's
    lsr     23, d0
    asl     9, d0
    mov     d2, d1
    asl     16, d1
    lsr     23, d1
    or      d1, d0
    movbu   (d0, a0), d0
    cmp     16, d0
    bcc     wn_ok1
    asl     8, d0
    movbu   (1, a1), d1
    or      d1, d0
    add     WB_SHADE_OFF, d0
    movbu   (d0, a0), d0
wn_ok1:
    asl     8, d0
    add     d0, a3
    add     d3, d2
    mov     d2, d0                  # pixel 2: V's integer part << 9 | U's
    lsr     23, d0
    asl     9, d0
    mov     d2, d1
    asl     16, d1
    lsr     23, d1
    or      d1, d0
    movbu   (d0, a0), d0
    cmp     16, d0
    bcc     wn_ok2
    asl     8, d0
    movbu   (2, a1), d1
    or      d1, d0
    add     WB_SHADE_OFF, d0
    movbu   (d0, a0), d0
wn_ok2:
    asl     16, d0
    add     d0, a3
    add     d3, d2
    mov     d2, d0                  # pixel 3: V's integer part << 9 | U's
    lsr     23, d0
    asl     9, d0
    mov     d2, d1
    asl     16, d1
    lsr     23, d1
    or      d1, d0
    movbu   (d0, a0), d0
    cmp     16, d0
    bcc     wn_ok3
    asl     8, d0
    movbu   (3, a1), d1
    or      d1, d0
    add     WB_SHADE_OFF, d0
    movbu   (d0, a0), d0
wn_ok3:
    asl     24, d0
    add     d0, a3
    add     d3, d2
    mov     a3, d0                  # the word: into the LCD when it differs from the copy (or the copy is unknown)
    mov     (a2), d1
    cmp     d1, d0
    bne     wn_st
    mov     (0x60, sp), d1
    cmp     0, d1
    beq     wn_same
wn_st:
    mov     d0, (a2)
    mov     (0x64, sp), d1
    mov     d0, (d1, a2)
    mov     (WH_NSTORE), d1
    inc     d1
    mov     d1, (WH_NSTORE)
wn_same:
    add     4, a1
    add     4, a2
    mov     (0x68, sp), d0
    cmp     d0, a1
    bcs     wn_four
    mov     (0x1C, sp), d0
    cmp     d0, a1
    bcs     wn_piece
    bra     wd_done
    # ---- bilinear: a pixel a turn into WT_LINE, then the row's words ----
wd_smooth:
    mov     a2, (0x54, sp)          # (the copy's row, for the store below)
    mov     WT_LINE, a0
    mov     a0, (0x58, sp)
wb_px:
    mov     (0x3C, sp), d0          # U' = U - 0x8000: i, fx
    add     -0x8000, d0
    mov     d0, d1
    lsr     13, d1
    and     7, d1
    mov     d1, (0x48, sp)
    mov     8, d2
    sub     d1, d2
    mov     d2, (0x44, sp)
    lsr     16, d0
    and     0x1FF, d0
    mov     d0, d3                  # (i)
    mov     (0x40, sp), d0          # V' = V - 0x8000: j, fy
    add     -0x8000, d0
    mov     d0, d1
    lsr     13, d1
    and     7, d1
    mov     d1, (0x50, sp)
    mov     8, d2
    sub     d1, d2
    mov     d2, (0x4C, sp)
    lsr     7, d0
    and     0x3FE00, d0
    or      d3, d0
    mov     WB_TOPV, a0
    add     d0, a0                  # a0 = TOP[j][i]
    movbu   (a1), d3                # d3 = the lower disk here
    mov     WB_SHADE, a2
    mov     WB_LANES, a3
    movbu   (a0), d0                # texel (i, j)
    call    wb_lane, 0, 0
    mov     (0x44, sp), d1
    mul     d1, d0
    mov     d0, d2
    movbu   (1, a0), d0             # (i + 1, j)
    call    wb_lane, 0, 0
    mov     (0x48, sp), d1
    mul     d1, d0
    add     d0, d2
    mov     (0x4C, sp), d1
    mul     d1, d2
    mov     d2, (0x74, sp)
    movbu   (512, a0), d0           # (i, j + 1)
    call    wb_lane, 0, 0
    mov     (0x44, sp), d1
    mul     d1, d0
    mov     d0, d2
    movbu   (513, a0), d0           # (i + 1, j + 1)
    call    wb_lane, 0, 0
    mov     (0x48, sp), d1
    mul     d1, d0
    add     d0, d2
    mov     (0x50, sp), d1
    mul     d1, d2
    mov     (0x74, sp), d0
    add     d0, d2
    add     0x02008020, d2          # (32 in each lane: rounded)
    mov     d2, d0                  # R << 8 | G << 4 | B
    lsr     18, d0
    and     0xF00, d0
    mov     d2, d1
    lsr     12, d1
    and     0xF0, d1
    or      d1, d0
    mov     d2, d1
    lsr     6, d1
    and     0xF, d1
    or      d1, d0
    mov     WB_INV, a0
    movbu   (d0, a0), d0
    mov     (0x58, sp), a0
    movbu   d0, (a0)
    inc     a0
    mov     a0, (0x58, sp)
    inc     a1
    mov     (0x3C, sp), d0
    mov     (0x14, sp), d1
    add     d1, d0
    mov     d0, (0x3C, sp)
    mov     (0x40, sp), d0
    mov     (0x18, sp), d1
    add     d1, d0
    mov     d0, (0x40, sp)
    mov     (0x1C, sp), d1
    cmp     d1, a1
    bcs     wb_px
    mov     WT_LINE, a0             # the row's words: a0 the line, a2 the copy, a1 its end
    mov     (0x54, sp), a2
    mov     (0x58, sp), a1
wb_st:
    mov     (a0), d0
    mov     (a2), d1
    cmp     d1, d0
    bne     wb_store
    mov     (0x60, sp), d1
    cmp     0, d1
    beq     wb_same
wb_store:
    mov     d0, (a2)
    mov     (0x64, sp), d1
    mov     d0, (d1, a2)
    mov     (WH_NSTORE), d1
    inc     d1
    mov     d1, (WH_NSTORE)
wb_same:
    add     4, a0
    add     4, a2
    cmp     a1, a0
    bcs     wb_st
wd_done:
    mov     (0x20, sp), d0          # the row's state
    asl     2, d0
    mov     WT_ROWST, a0
    add     d0, a0
    mov     (0x70, sp), d0
    mov     d0, (a0)
wd_next:
    mov     (0x20, sp), d0
    inc     d0
    mov     d0, (0x20, sp)
    bra     wd_row
wd_ret:
    ret     [d2,d3,a2,a3], 0x90

# wb_lane(d0 = a texel, d3 = the lower disk's entry here; a2 = WB_SHADE, a3 = WB_LANES) -> d0 = the colour's lanes:
# the upper disk's entry (16-255), or the lower one under the texel's shadow level (0-15). Leaf; uses d0, d1.
wb_lane:
    cmp     16, d0
    bcc     wbl_e
    asl     8, d0
    or      d3, d0
    movbu   (d0, a2), d0
wbl_e:
    asl     2, d0
    mov     (d0, a3), d0
    rets

# ---- the page's text: x, y (in the region), entry (1 white, 2 cyan, 3 yellow), 1 + region for a region's label (in
# yellow when shown), then the text (help.s's item format). The left margin: how to use the page; the right: the
# regions beside soft buttons 1, 3 and 5, the arrow's number, the drawing times. 10 characters at most a line. ----
    .align  4
wh_items:
    .word   0, 8, 2, 0
    .long   wh_t_title
    .word   0, 28, 3, 0
    .long   wh_t_tempo
    .word   0, 38, 3, 0
    .long   wh_t_tempo2
    .word   0, 48, 1, 0
    .long   wh_t_turn1
    .word   0, 58, 1, 0
    .long   wh_t_turn2
    .word   0, 68, 1, 0
    .long   wh_t_turn3
    .word   0, 88, 3, 0
    .long   wh_t_side
    .word   0, 98, 1, 0
    .long   wh_t_side2
    .word   0, 108, 1, 0
    .long   wh_t_side3
    .word   0, 118, 1, 0
    .long   wh_t_side4
    .word   0, 138, 3, 0
    .long   wh_t_pages
    .word   0, 148, 1, 0
    .long   wh_t_pages2
    .word   0, 168, 3, 0
    .long   wh_t_back
    .word   0, 178, 1, 0
    .long   wh_t_back2
    .word   0, 188, 1, 0
    .long   wh_t_back3
    .word   0, 228, 1, 0
    .long   wh_t_page
    .word   600, 31, 1, 1
    .long   wh_t_top
    .word   576, 120, 1, 2
    .long   wh_t_middle
    .word   576, 209, 1, 3
    .long   wh_t_bottom
    .word   560, 58, 3, 0
    .long   wh_t_arrow
    .word   560, 150, 1, 0
    .long   wh_t_draw
    .word   0xFFFF, 0
wh_name:        .asciz  "AWWH0.AW"
wh_t_title:     .asciz  "CODE WHEEL"
wh_t_tempo:     .asciz  "TEMPO/"
wh_t_tempo2:    .asciz  "PROGRAM"
wh_t_turn1:     .asciz  "turns the"
wh_t_turn2:     .asciz  "disk, a"
wh_t_turn3:     .asciz  "number a"
wh_t_side:      .asciz  "SIDE KEYS"
wh_t_side2:     .asciz  "1, 3, 5:"
wh_t_side3:     .asciz  "the part"
wh_t_side4:     .asciz  "shown"
wh_t_pages:     .asciz  "PAGE UP/DN"
wh_t_pages2:    .asciz  "the others"
wh_t_back:      .asciz  "EXIT, HELP"
wh_t_back2:     .asciz  "or a key:"
wh_t_back3:     .asciz  "the game"
wh_t_page:      .asciz  "Page 5/5  "
wh_t_top:       .asciz  "TOP >"
wh_t_middle:    .asciz  "MIDDLE >"
wh_t_bottom:    .asciz  "BOTTOM >"
wh_t_arrow:     .asciz  "ARROW AT"
wh_t_draw:      .asciz  "drawn, ms"
wh_t_turn:      .asciz  "turn"
wh_t_rest:      .asciz  "rest"
wh_t_loading:   .asciz  "Loading the wheel"
wh_t_missing:   .asciz  "WHEEL FILES MISSING"
wh_t_code:      .asciz  "OR BAD, CODE "
wh_t_nowheel:   .asciz  "NO WHEEL"
wh_t_crumb:     .asciz  "AWWHLOG steps, last ms: "
wh_t_crumbname: .asciz  "AWWHLOG.TXT"
    .align  4
