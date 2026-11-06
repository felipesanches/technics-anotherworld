# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# wheel.s -- the code wheel help page (README-CNV.md, "The code wheel page"): the original game's code wheel, from the
# owner's drawing of it (tools/codewheel_render.py), its upper disk turned by the TEMPO/PROGRAM wheel, a number a
# detent. The KN7APP.BIN build's (the SP7001 build has wheel_stub.s).
#
#   * The pictures and tables (the blob: codewheel_render.py's W_* layout, WB_* here) come from the SD card, AWWH0.AW ..
#     AWWH4.AW, ByteKiller-packed pieces of 32 KB, the first time the page is shown in a game: the main task reads a
#     piece a converter call (WheelService) into the scratch after the blob, the game task unpacks it in place
#     (cnv_main.s BkUnpack) and checks the whole (magic, version, size, words summing to 0). The blob then stays in the
#     LCD's display memory (WD_CACHE: nothing shows it), and later pages copy it from there.
#   * The RAM it is used in is the VM's pages 2 and 3 (WRAM, 184,320 bytes): while the help screen is up the VM does not
#     run, so they are copied to display memory (WD_SAVE) when the page is first shown and copied back when the help
#     screen closes (WheelRestore).
#   * The page takes the whole LCD (FB8, 640 x 240): the wheel's 256 x 240 at x 192 (the pin in the LCD's middle), the
#     text left and right of it; look-up table entries 16-255 hold the wheel's 240 colours while it shows (the
#     ambilight's otherwise: WheelHide writes them back from AMB_LUT and FB8 back from display memory, WD_FB8, and the
#     window is drawn again at the next page or blit).
#   * The upper disk is drawn at any angle from its one picture, row by row over the spans it can reach (WheelDraw):
#     nearest texel while it turns, bilinear (in RGB, back to an entry through INV) when it comes to rest. The angle of
#     each number (ANGLES) and the arithmetic are codewheel_render.py's; its render() is this, pixel for pixel.
#   * The TEMPO/PROGRAM wheel: each detent comes from the panel as a frame [0x17, step] into the firmware's panel
#     receive ring, which the firmware decodes on its main task and adds to the tempo. While the page shows, the
#     converter calls (the main task too: WheelService) look at the ring first: a wheel frame's step is counted
#     (WH_STEPS) and set to 0 in the ring while the firmware has not decoded it yet; one it decoded first (the tempo
#     moved) gets a frame of the opposite step put into the ring after it, so the tempo goes back. As the PDF viewer and
#     Pinball Fantasies do it (kn5000_homebrew demos/kn7000_pdf src/app/entry.c wheel_scan). Every firmware task and
#     ours run at the same priority without time slices, so nothing decodes the ring while WheelService runs.
#   * Each detent moves the target a number (accumulating while the disk is still turning) and starts a turn from
#     where the disk is to the target's angle, easing out (1 - (1 - t)^3) over 180 ms + 100 ms a number, at most 800
#     ms; frames are drawn as fast as they come (the help loop sleeps 2 ms between them).
# Convention as the rest of the port: d0, d1, a0, a1 scratch; d2, d3, a2, a3 kept; a routine that calls makes a frame
# first; locals from (0x14, sp) (the firmware's routines use the caller's sp + 4 .. + 0x10).

# ---- the blob in RAM (codewheel_render.py W_*: the same offsets) ----
.equ WRAM,          PAGE_BITMAP_2   # the VM's pages 2 and 3, borrowed while the help screen is up
.equ WRAM_LEN,      2 * PAGE_STRIDE # 0x2D000
.equ WB_TOP,        WRAM + 0x00000  # 256 x 256: the upper disk (16-255 its colours; 0-15 its shadow over the lower)
.equ WB_BOT,        WRAM + 0x10000  # 256 x 240: the lower disk
.equ WB_SIN,        WRAM + 0x1F000  # 4096 x s16: sin x 32767
.equ WB_SHADE,      WRAM + 0x21000  # 16 x 256: an entry under each shadow level
.equ WB_LUT,        WRAM + 0x22000  # 256 x u16: 0x0RGB of entries 16-255
.equ WB_SPANS,      WRAM + 0x22200  # 240 x (u16 x0, u16 x1): what the upper disk can reach, each row
.equ WB_ANGLES,     WRAM + 0x22600  # 20 x u16: the upper disk's angle for each number, 1/65536 of a turn
.equ WB_LANES,      WRAM + 0x22700  # 256 x u32: R << 20 | G << 10 | B, for the blend
.equ WB_INV,        WRAM + 0x22B00  # 4096: the entry nearest each 4-bit colour
.equ WB_HDR,        WRAM + 0x23B00  # "AWWH", version, size; the blob's last word makes all the words sum to 0
.equ WB_SIZE,       0x23C00
.equ WB_LINE,       WRAM + 0x24000  # a row being drawn (and, while loading, a packed piece: 0x9000 bytes)
.equ WB_SCRATCH,    WB_LINE
.equ WB_SCRATCH_MAX, 0x9000
.equ WB_PIECE,      0x8000
.equ WB_PIECES,     5
.equ WB_MAGIC,      0x48575741      # "AWWH"
.equ WB_VERSION,    1
# ---- display memory (nothing shows it: FB8 is 0x50000-0x757FF; Pinball Fantasies keeps its table up to 0x11A800) ----
.equ WD_SAVE,       FB + 0x90000    # pages 2 and 3 while borrowed, to FB + 0xBD000
.equ WD_CACHE,      FB + 0xC0000    # the blob, once loaded, to FB + 0xE3C00
.equ WD_FB8,        FB + 0xE4000    # FB8 as it was before the page (the ambilight's border), to FB + 0x109800
# ---- RAM free while the page shows ----
.equ WSHADOW,       SHADOW          # 256 x 240: the wheel's area as the LCD holds it (SHADOW and REPORT_BUF's room, to
                                    #   0x502D7000, below AW_FONT; HelpDrawPage and the exit's blit rebuild SHADOW)
.equ WH_SROWS,      24              # rows of the picture at rest a poll
# ---- the page ----
.equ WHEEL_X0,      192             # the wheel's 256 columns in FB8
.equ WHEEL_NUMS,    20
.equ WHEEL_ROWS,    240
.equ WH_REST_MS,    50              # a converter call looks at the panel's ring this long while the page shows
.equ WH_FRAME_WAIT, 6               # and waits this long for a frame's second byte
.equ PRING_LEN,     0x5C            # the panel's receive ring: 92 bytes, read index, write index before it
.equ WH_TURN_MS,    180             # a turn: 180 ms + 100 ms a number, at most WH_TURN_MAX
.equ WH_TURN_MAX,   800
.equ WH_LOAD_MS,    15000           # a piece the main task has not read after this: the load fails
# ---- variables (WHEEL_VARS, 0x200 bytes; zeroed by the loader with the application area) ----
# WH_RXRD, WHEEL_VARS + 0x00: the panel ring's read index (platformcnv.inc; fwfind.s step 8; 0: not found), write
# index +2, ring +4
.equ WH_ON,         WHEEL_VARS + 0x04   # 1 while the page shows: the converter calls take the wheel's frames
.equ WH_SCAN,       WHEEL_VARS + 0x08   # main task: 1 once WH_AT follows the ring
.equ WH_AT,         WHEEL_VARS + 0x0C   # main task: the next frame to look at
.equ WH_STEPS,      WHEEL_VARS + 0x10   # main task: the detents so far, signed
.equ WH_TAKEN,      WHEEL_VARS + 0x14   # game task: the detents it has acted on
.equ WH_FRAMES,     WHEEL_VARS + 0x18   # wheel frames seen
.equ WH_LATE,       WHEEL_VARS + 0x1C   # of them, those the firmware had decoded first
.equ WH_UNDONE,     WHEEL_VARS + 0x20   # frames put into the ring to take a late one's step back
.equ WH_UNDO_N,     WHEEL_VARS + 0x24   # the ring positions of those not met yet: up to 8
.equ WH_UNDO_AT,    WHEEL_VARS + 0x28   #   (8 x u32, to +0x48)
.equ WH_BORROW,     WHEEL_VARS + 0x48   # 1 while pages 2 and 3 are in WD_SAVE
.equ WH_INRAM,      WHEEL_VARS + 0x4C   # 1 while WRAM holds the checked blob
.equ WH_CACHED,     WHEEL_VARS + 0x50   # 1 once WD_CACHE holds it
.equ WH_LOADREQ,    WHEEL_VARS + 0x54   # game task: piece n + 1 to read; the main task sets 0 when done
.equ WH_LOADRES,    WHEEL_VARS + 0x58   # main task: its bytes (-1: no file)
.equ WH_FAIL,       WHEEL_VARS + 0x5C   # why the blob could not be had: 0x10 + piece (read), 0x20 + piece (unpack), 0x30 (check)
.equ WH_POS,        WHEEL_VARS + 0x60   # the number the arrow rests at, or turns to (0-19: 1-20)
.equ WH_ANG,        WHEEL_VARS + 0x64   # the angle drawn last (1/65536 turn)
.equ WH_FROM,       WHEEL_VARS + 0x68   # a turn: from this angle
.equ WH_DELTA,      WHEEL_VARS + 0x6C   #   by this much (signed)
.equ WH_T0,         WHEEL_VARS + 0x70   #   started at this ms
.equ WH_DUR,        WHEEL_VARS + 0x74   #   lasting this many ms
.equ WH_MOVING,     WHEEL_VARS + 0x78   # 1 while turning
.equ WH_SHOWN,      WHEEL_VARS + 0x7C   # 1 while the LCD holds the page (WheelHide puts the rest back)
.equ WH_SEQ,        WHEEL_VARS + 0x80   # + 2 at each picture finished (the probes' taps)
.equ WH_SMOOTH,     WHEEL_VARS + 0x84   # the last picture: 1 bilinear (at rest), 0 nearest (turning)
.equ WH_NFRAMES,    WHEEL_VARS + 0x88   # pictures drawn turning, so far
.equ WH_NREST,      WHEEL_VARS + 0x8C   # pictures drawn at rest
.equ WH_TURNF,      WHEEL_VARS + 0x90   # pictures drawn in the last turn
.equ WH_TLAST,      WHEEL_VARS + 0x94   # the last turning picture's time, in 1/2001 ms (perf.s Stamp)
.equ WH_TMAX,       WHEEL_VARS + 0x98   # the longest turning picture's
.equ WH_TREST,      WHEEL_VARS + 0x9C   # the last picture at rest's
.equ WH_POLLS,      WHEEL_VARS + 0xA0   # help polls on the page (LcdCheck every 16)
.equ WH_LOADMS,     WHEEL_VARS + 0xA4   # the last load from the card, ms
.equ WH_LOADS,      WHEEL_VARS + 0xA8   # loads from the card so far
.equ WH_SAVES,      WHEEL_VARS + 0xAC   # pages 2 and 3 borrowed so far
.equ WH_BUSY,       WHEEL_VARS + 0xB0   # 1 while a picture is being made (the probes read the LCD when 0)
.equ WH_SROW,       WHEEL_VARS + 0xB4   # the next row of the picture at rest (made 24 rows a poll); 240: none to make
.equ WH_R0,         WHEEL_VARS + 0xB8   # WheelDraw's rows: from
.equ WH_R1,         WHEEL_VARS + 0xBC   #   to
.equ WH_STORES,     WHEEL_VARS + 0xC0   # stores into the LCD in the last turning picture (the words that changed)
.equ WH_SSTORES,    WHEEL_VARS + 0xC4   # in the last picture at rest
.equ WH_NSTORE,     WHEEL_VARS + 0xC8   # (WheelDraw's count)
.equ WH_TACC,       WHEEL_VARS + 0xCC   # the picture at rest's time so far
.equ WH_NAME,       WHEEL_VARS + 0x100  # 16 bytes: "AWWHn.AW"
.equ WH_TEXT,       WHEEL_VARS + 0x110  # 64 bytes: a line being made

# =================================================================================
# The main task (cnv_main.s CnvEntry, every converter call while the game runs).
# WheelService: a piece the game task asked for, read from the card; while the page shows, the wheel's frames taken
# from the panel's ring: at once, then for up to WH_REST_MS (sleeping a ms at a time, so the game task draws meanwhile)
# until bytes come that the firmware must decode (a button: they are looked at first), then the second byte of a
# frame whose first has come (WH_FRAME_WAIT ms at most).
WheelService:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (WH_LOADREQ), d0
    cmp     0, d0
    beq     wsv_ring
    call    WheelReadPiece, 0, 0
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
# in after the panel's (WheelUndo). A frame WheelUndo put in is passed over. Frames are 2 bytes; a first byte whose
# second has not come waits for the next look.
WheelScanRing:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
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
    add     d0, a0
    movbu   (a0), d0                # the frame's first byte
    cmp     0x17, d0
    bne     wsr_step
    mov     (WH_AT), d0             # one WheelUndo wrote?
    call    WheelUndone, 0, 0
    cmp     0, d0
    bne     wsr_step
    mov     a2, a0                  # the step
    add     4, a0
    mov     (0x18, sp), d0
    add     d0, a0
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
    mov     (WH_AT), d0             # ahead = (at - rd) mod len, filled = (wr - rd) mod len
    sub     d2, d0
    bge     wsr_a
    add     PRING_LEN, d0
wsr_a:
    mov     d3, d1
    sub     d2, d1
    bge     wsr_f
    add     PRING_LEN, d1
wsr_f:
    cmp     d1, d0
    bcc     wsr_late
    clr     d1                      # still to be decoded: the firmware sees no step
    movbu   d1, (a0)
    bra     wsr_step
wsr_late:
    mov     (WH_LATE), d1
    inc     d1
    mov     d1, (WH_LATE)
    mov     (0x1C, sp), d0
    call    WheelUndo, 0, 0
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
    ret     [d2,d3,a2,a3], 0x30

# WheelUndone(d0 = a ring position) -> d0 = 1 when WheelUndo wrote the frame there (and it is forgotten), else 0. Leaf.
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

# WheelUndo(d0 = step): a frame [0x17, -step] into the ring at its write index, as the panel's receive interrupt puts
# one (interrupts off meanwhile), when it fits; remembered so that WheelScanRing passes over it.
WheelUndo:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    cmp     0, d2
    beq     wun_ret
    mov     (WH_UNDO_N), d0
    cmp     8, d0
    bcc     wun_ret
    mov     (WH_RXRD), a2
    mov     psw, d3                 # interrupts off
    and     0xF7FF, psw
    nop
    nop
    movhu   (2, a2), d0             # wr
    movhu   (a2), d1                # rd
    cmp     PRING_LEN, d0
    bcc     wun_on
    btst    1, d0
    bne     wun_on
    mov     d0, a1                  # filled = (wr - rd) mod len: room for 2 more, and one free byte
    sub     d1, d0
    bge     wun_f
    add     PRING_LEN, d0
wun_f:
    add     2, d0
    cmp     PRING_LEN, d0
    bcc     wun_on
    mov     a1, d0                  # ring[wr] = 0x17, ring[wr + 1] = -step, wr += 2
    mov     a2, a0
    add     4, a0
    add     d0, a0
    mov     0x17, d1
    movbu   d1, (a0)
    clr     d1
    sub     d2, d1
    movbu   d1, (1, a0)             # (wr is even and len is even: wr + 1 needs no wrap)
    add     2, d0
    cmp     PRING_LEN, d0
    bcs     wun_w
    clr     d0
wun_w:
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
wun_on:
    mov     d3, psw
    nop
wun_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelReadPiece: piece WH_LOADREQ - 1 (AWWHn.AW, in the game's folder) into WB_SCRATCH, as LoadStep reads a file:
# the drive switch, open, FILE_PIECE at a time until a short read, close, the switch back. WH_LOADRES = its bytes
# (-1: it could not be opened; a file of WB_SCRATCH_MAX bytes or more is not one of ours: -1). Then WH_LOADREQ = 0.
WheelReadPiece:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     WH_NAME, a0             # "AWWHn.AW"
    mov     wh_name, a1
    call    StrPut, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     (WH_LOADREQ), d0
    add     0x30 - 1, d0
    movbu   d0, (WH_NAME + 4)
    mov     WB_SCRATCH, a0          # (the guard's view: inside the game's RAM)
    mov     WB_SCRATCH_MAX, d0
    call    GuardRange, 0, 0
    cmp     0, d0
    bne     wrp_none
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
    mov     4, d0                   # (the probes' taps: an SD read into the borrowed pages)
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
    mov     (FW_CLOSE), a3
    calls   (a3)
    mov     (FW_RESETEXT), a3
    calls   (a3)
    mov     d3, (WH_LOADRES)
    bra     wrp_done
wrp_back:
    mov     (FW_RESETEXT), a3
    calls   (a3)
wrp_none:
    mov     -1, d0
    mov     d0, (WH_LOADRES)
wrp_done:
    clr     d0
    mov     d0, (WH_LOADREQ)
    ret     [d2,d3,a2,a3], 0x30

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

# WheelShow: the page (help.s HelpDrawPage): the whole LCD black, the text, the blob (WheelEnsure), the wheel's colours
# into entries 16-255, the lower disk, the upper one at the number it was left at. The converter calls take the wheel's
# frames from then on (WH_ON).
WheelShow:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d0
    mov     d0, (WH_ON)
    call    PalCheck, 0, 0          # entries 0-15: the help screen's colours (the text)
    mov     (WH_SHOWN), d0          # FB8 kept as it is (the border's dither pattern: WheelHide puts it back)
    cmp     0, d0
    bne     wsh_clear
    mov     FB8, a0
    mov     WD_FB8, a1
    mov     FB8_STRIDE * FB_H / 4, d0
    call    WheelCopy, 0, 0
wsh_clear:
    call    WheelClear, 0, 0
    mov     1, d0
    mov     d0, (WH_SHOWN)
    mov     1, d0
    mov     d0, (PF_DAMAGE)         # (the window in full at the next page or blit; WheelHide makes sure)
    call    WheelTexts, 0, 0
    call    WheelEnsure, 0, 0
    cmp     0, d0
    beq     wsh_have
    mov     wh_t_missing, a0        # no wheel: say why
    mov     WHEEL_X0 + 24, d0
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
    mov     WHEEL_X0 + 24, d0
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
    call    WheelBottom, 0, 0
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
    clr     d0
    mov     d0, (WH_SROW)
    call    WheelArrowText, 0, 0
    mov     (WH_STEPS), d0          # detents from before the page: not for it
    mov     d0, (WH_TAKEN)
    mov     1, d0
    mov     d0, (WH_ON)
wsh_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelHide: another page, or the help screen closing: the converter calls leave the ring alone, a turn is finished
# (the arrow on its number), entries 16-255 hold the ambilight's colours again (AMB_LUT: what lcd8.s last wrote there,
# black where it is unknown), FB8 is as it was before the page (WD_FB8: the border's dither pattern exactly as drawn),
# and the window is drawn again by the next ShadowOut or blit (PF_DAMAGE).
WheelHide:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d0
    mov     d0, (WH_ON)
    mov     d0, (WH_MOVING)
    mov     d0, (WH_BUSY)
    mov     WHEEL_ROWS, d1
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
    mov     WD_FB8, a0
    mov     FB8, a1
    mov     FB8_STRIDE * FB_H / 4, d0
    call    WheelCopy, 0, 0
    mov     1, d0
    mov     d0, (PF_DAMAGE)
whd_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelRestore: the help screen closes (help.s): the page hidden, and pages 2 and 3 back from display memory when
# they were borrowed.
WheelRestore:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    WheelHide, 0, 0
    mov     (WH_BORROW), d0
    cmp     0, d0
    beq     wrs_ret
    mov     WD_SAVE, a0
    mov     WRAM, a1
    mov     WRAM_LEN / 4, d0
    call    WheelCopy, 0, 0
    clr     d0
    mov     d0, (WH_BORROW)
    mov     d0, (WH_INRAM)
wrs_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelCopy(a0 = from, a1 = to, d0 = words) -> d0 = the words' sum. Leaf.
WheelCopy:
    movm    [d2], (sp)
    mov     d0, d2
    clr     d1
wcp_loop:
    mov     (a0), d0
    mov     d0, (a1)
    add     d0, d1
    add     4, a0
    add     4, a1
    add     -1, d2
    bne     wcp_loop
    mov     d1, d0
    ret     [d2], 4

# WheelEnsure -> d0 = 0 when WRAM holds the checked blob, else 1 (WH_FAIL says why). Pages 2 and 3 are saved first.
WheelEnsure:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (WH_INRAM), d0
    cmp     0, d0
    bne     wen_ok
    mov     (WH_BORROW), d0
    cmp     0, d0
    bne     wen_have
    mov     WRAM, a0                # pages 2 and 3 into display memory
    mov     WD_SAVE, a1
    mov     WRAM_LEN / 4, d0
    call    WheelCopy, 0, 0
    mov     1, d0
    mov     d0, (WH_BORROW)
    mov     (WH_SAVES), d0
    inc     d0
    mov     d0, (WH_SAVES)
wen_have:
    mov     (WH_CACHED), d0
    cmp     0, d0
    beq     wen_load
    mov     WD_CACHE, a0            # loaded before: from display memory
    mov     WRAM, a1
    mov     WB_SIZE / 4, d0
    call    WheelCopy, 0, 0
    call    WheelValid, 0, 0
    cmp     0, d0
    beq     wen_inram
    clr     d0                      # (not as it was left: from the card again)
    mov     d0, (WH_CACHED)
wen_load:
    mov     wh_t_loading, a0
    mov     WHEEL_X0 + 32, d0
    mov     116, d1
    mov     1, d2
    call    WText, 0, 0
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (0x14, sp)          # the load's start
    clr     d2                      # d2 = piece
wen_piece:
    mov     d2, d0
    inc     d0
    mov     d0, (WH_LOADREQ)        # the main task reads it (WheelService)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d3
wen_wait:
    call    HelpSleep, 0, 0
    mov     (WH_LOADREQ), d0
    cmp     0, d0
    beq     wen_read
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    sub     d3, d0
    cmp     WH_LOAD_MS, d0
    bcs     wen_wait
    clr     d0
    mov     d0, (WH_LOADREQ)
    bra     wen_rfail
wen_read:
    mov     (WH_LOADRES), d0
    cmp     8, d0
    bgt     wen_unpack
wen_rfail:
    mov     0x10, d0
    bra     wen_fail
wen_unpack:
    mov     d2, d1                  # BkUnpack(a0 = packed, d0 = its size, a1 = its place, d1 = the piece's size)
    asl     15, d1
    mov     WRAM, a1
    add     d1, a1
    mov     WB_SIZE, d3
    sub     d1, d3
    mov     WB_PIECE, d1
    cmp     d1, d3
    bcc     wen_size
    mov     d3, d1
wen_size:
    mov     WB_SCRATCH, a0
    call    BkUnpack, 0, 0
    cmp     0, d0
    beq     wen_next
    mov     0x20, d0
    bra     wen_fail
wen_next:
    inc     d2
    cmp     WB_PIECES, d2
    bne     wen_piece
    call    WheelValid, 0, 0
    cmp     0, d0
    beq     wen_good
    mov     0x30, d0
    clr     d2
    bra     wen_fail
wen_good:
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     (0x14, sp), d1
    sub     d1, d0
    mov     d0, (WH_LOADMS)
    mov     (WH_LOADS), d0
    inc     d0
    mov     d0, (WH_LOADS)
    mov     WRAM, a0                # kept in display memory for the next time
    mov     WD_CACHE, a1
    mov     WB_SIZE / 4, d0
    call    WheelCopy, 0, 0
    mov     1, d0
    mov     d0, (WH_CACHED)
    mov     wh_t_blank, a0          # (the loading line off)
    mov     WHEEL_X0 + 32, d0
    mov     116, d1
    mov     1, d2
    call    WText, 0, 0
wen_inram:
    mov     1, d0
    mov     d0, (WH_INRAM)
wen_ok:
    clr     d0
    bra     wen_ret
wen_fail:
    add     d2, d0
    mov     d0, (WH_FAIL)
    mov     1, d0
wen_ret:
    ret     [d2,d3,a2,a3], 0x30

# WheelValid -> d0 = 0 when WRAM holds a blob of this build's kind: "AWWH", version, size, its words summing to 0.
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
    cmp     WB_SIZE, d0
    bne     wvl_ret
    mov     WRAM, a0
    mov     WB_SIZE / 4, d1
    clr     d0
wvl_sum:
    mov     (a0), a1
    add     a1, d0
    add     4, a0
    add     -1, d1
    bne     wvl_sum
    cmp     0, d0
    bne     wvl_ret
    clr     d2
wvl_ret:
    mov     d2, d0
    ret     [d2,d3,a2,a3], 0x20

# WheelClear: all of FB8 entry 0 (black). Leaf.
WheelClear:
    mov     FB8, a0
    mov     FB8_STRIDE * FB_H / 4, d1
    clr     d0
wcl_loop:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     wcl_loop
    rets

# WheelBottom: the lower disk, all of it (WB_BOT, 256 x 240), into FB8 at WHEEL_X0 and into WSHADOW. Leaf.
WheelBottom:
    movm    [d2,a2], (sp)
    mov     WB_BOT, a0
    mov     WSHADOW, a2
    mov     FB8 + WHEEL_X0, a1
    mov     FB_H, d1
wbt_row:
    mov     64, d2
wbt_w:
    mov     (a0), d0
    mov     d0, (a1)
    mov     d0, (a2)
    add     4, a0
    add     4, a1
    add     4, a2
    add     -1, d2
    bne     wbt_w
    add     FB8_STRIDE - 256, a1
    add     -1, d1
    bne     wbt_row
    ret     [d2,a2], 8

# WheelTexts: the page's fixed text, left and right of the wheel.
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
    mov     (8, a2), a0
    call    WText, 0, 0
    add     12, a2
    bra     wtx_item
wtx_more:
    mov     (WH_RXRD), d0           # no wheel found in this firmware: say so
    cmp     0, d0
    bne     wtx_ret
    mov     wh_t_nowheel, a0
    mov     8, d0
    mov     160, d1
    mov     3, d2
    call    WText, 0, 0
wtx_ret:
    ret     [d2,d3,a2,a3], 0x20

# WheelArrowText: "ARROW AT n" (the number turned to) and the drawing times, right of the wheel.
WheelArrowText:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     WH_TEXT, a0
    mov     (WH_POS), d0
    inc     d0
    mov     2, d1
    call    FmtNum, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     WH_TEXT, a0
    mov     560, d0
    mov     36, d1
    mov     1, d2
    call    WText, 0, 0
    call    WheelTimeText, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# WheelTimeText: how long the last picture took, turning and at rest, in ms (for the owner's unit: README-CNV.md).
WheelTimeText:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     WH_TEXT, a0
    mov     (WH_TLAST), d0
    call    wh_ms, 0, 0
    mov     wh_t_ms, a1
    call    StrPut, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     WH_TEXT, a0
    mov     456 + 9 * 8, d0
    mov     188, d1
    mov     2, d2
    call    WText, 0, 0
    mov     WH_TEXT, a0
    mov     (WH_TREST), d0
    call    wh_ms, 0, 0
    mov     wh_t_ms, a1
    call    StrPut, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     WH_TEXT, a0
    mov     456 + 9 * 8, d0
    mov     200, d1
    mov     2, d2
    call    WText, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# wh_ms(d0 = 1/2001 ms counts, a0 = where) -> a0 past "nnn.n": tenths of a ms, 5 characters.
wh_ms:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2
    mov     10, d1
    mul     d1, d0
    mov     2001, d1
    call    Div, 0, 0
    mov     a2, a0
    mov     0x105, d1               # width 5, one decimal
    call    FmtNum, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# WText(a0 = NUL-terminated text, d0 = x (a multiple of 4), d1 = y, d2 = entry): into FB8, 8x8 glyphs from AW_FONT, each
# cell written whole (its background entry 0), four pixels a store. Keeps d2.
WText:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, a2                  # a2 = text
    mov     FB8_STRIDE, d3
    mulu    d1, d3
    add     d0, d3
    mov     FB8, a3
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
    add     FB8_STRIDE - 8, a1
    mov     (0x18, sp), d0
    add     -1, d0
    mov     d0, (0x18, sp)
    bne     wtt_row
    add     8, a3
    bra     wtt_char
wtt_ret:
    ret     [d2,d3,a2,a3], 0x30

# WheelSleepMs -> d0 = how long the help loop sleeps (help.s HelpSleep): 2 ms while the disk turns or its picture at rest
# is being made, else 30. Leaf.
WheelSleepMs:
    mov     2, d0
    mov     (WH_MOVING), d1
    cmp     0, d1
    bne     wsm_ret
    mov     (WH_SROW), d1
    cmp     WHEEL_ROWS, d1
    bcs     wsm_ret
    mov     30, d0
wsm_ret:
    rets

# WheelPoll: the help loop on the page (help.s): the detents counted since the last look start a turn (WheelStep); a
# turn under way gets its next picture; every 16 looks the LCD's controller is checked (lcd8.s LcdCheck). -> d0 = 1
# while turning (help.s HelpSleep then sleeps 2 ms, not 30).
WheelPoll:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (WH_ON), d0
    cmp     0, d0
    beq     wpl_ret
    mov     (WH_STEPS), d0
    mov     (WH_TAKEN), d1
    cmp     d1, d0
    beq     wpl_turn
    mov     d0, (WH_TAKEN)
    sub     d1, d0
    call    WheelStep, 0, 0
wpl_turn:
    mov     (WH_MOVING), d0
    cmp     0, d0
    beq     wpl_rest
    call    WheelTurn, 0, 0
    bra     wpl_check
wpl_rest:
    mov     (WH_SROW), d0           # the picture at rest, WH_SROWS rows a poll (a detent meanwhile stops it)
    cmp     WHEEL_ROWS, d0
    bcc     wpl_check
    call    WheelSmoothStep, 0, 0
wpl_check:
    mov     (WH_POLLS), d0
    inc     d0
    mov     d0, (WH_POLLS)
    and     15, d0
    bne     wpl_ret
    call    LcdCheck, 0, 0
wpl_ret:
    mov     (WH_MOVING), d0
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
    mov     WHEEL_ROWS, d1          # (the picture at rest, if one was being made: not now)
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

# WheelPicture(d0 = angle): the whole wheel at that angle, nearest (a turning picture): WH_ANG, WH_SMOOTH 0, WH_SEQ + 2,
# its time (WH_TLAST, WH_TMAX) and its stores into the LCD (WH_STORES).
WheelPicture:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, d2
    mov     1, d0
    mov     d0, (WH_BUSY)
    call    Stamp, 0, 0
    mov     d0, d3
    clr     d0
    mov     d0, (WH_R0)
    mov     WHEEL_ROWS, d0
    mov     d0, (WH_R1)
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

# WheelSmoothStep: WH_SROWS more rows of the picture at rest (bilinear) at WH_ANG, from WH_SROW; the last ones finish it:
# WH_SMOOTH 1, WH_SEQ + 2, its time (WH_TREST: the rows' times added up) and stores (WH_SSTORES); the drawing times shown.
WheelSmoothStep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     1, d0
    mov     d0, (WH_BUSY)
    call    Stamp, 0, 0
    mov     d0, d3
    mov     (WH_SROW), d0
    mov     d0, (WH_R0)
    add     WH_SROWS, d0
    cmp     WHEEL_ROWS, d0
    bls     wss_r1
    mov     WHEEL_ROWS, d0
wss_r1:
    mov     d0, (WH_R1)
    mov     d0, (WH_SROW)
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
    cmp     WHEEL_ROWS, d0
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
# WheelDraw(d0 = angle, 1/65536 turn; d1 = 1 bilinear (at rest), 0 nearest (turning)): rows WH_R0 .. WH_R1 - 1 of the
# wheel, the upper disk at that angle over the lower one (codewheel_render.py render()), each row's span made in WB_LINE
# and then stored into FB8, four pixels a store, only the words that differ from WSHADOW (WH_NSTORE counts them).
#   c = SIN[(angle >> 4) + 1024], s = SIN[angle >> 4];  dx2 = 2x + 1 - 256, dy2 = 2y + 1 - 240
#   U = (128 << 16) + c dx2 + s dy2;  V = (128 << 16) - s dx2 + c dy2   (16.16, at the span's first pixel)
#   nearest: U and V to 8.8, rounded, in one word, V << 16 | U, and so the step along the row, (dV << 16) + dU with
#     dU = (2c + 128) >> 8, dV = (-2s + 128) >> 8: one add a pixel; the texel row is bits 24-31, its column bits 8-15
#   bilinear: 16.16, U and V each a stack variable, a pixel a turn
# Locals: 0x14 dU (16.16), 0x18 dV, 0x1C the row's end in WB_LINE, 0x20 y, 0x24 c, 0x28 s, 0x30 smooth, 0x34 x0, 0x38 x1;
# the bilinear's 0x3C U, 0x40 V, 0x44 8 - fx, 0x48 fx, 0x4C 8 - fy, 0x50 fy, 0x54 the first row's sum, 0x58 where the
# pixel goes; 0x5C dUV (nearest).
WheelDraw:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x60, sp
    mov     d1, (0x30, sp)
    clr     d1
    mov     d1, (WH_NSTORE)
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
    mov     (0x14, sp), d0          # dUV = (((dV + 128) >> 8) << 16) + ((dU + 128) >> 8)
    add     128, d0
    asr     8, d0
    mov     (0x18, sp), d1
    add     128, d1
    asr     8, d1
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
    asl     2, d0
    mov     WB_SPANS, a0
    add     d0, a0
    movhu   (a0), d0
    mov     d0, (0x34, sp)          # x0
    movhu   (2, a0), d1
    mov     d1, (0x38, sp)          # x1
    cmp     d1, d0
    bcc     wd_next                 # (no span)
    # U, V at x0
    mov     (0x34, sp), d2          # dx2 = 2 x0 + 1 - 256
    asl     1, d2
    add     1 - 256, d2
    mov     (0x20, sp), d3          # dy2 = 2 y + 1 - 240
    asl     1, d3
    add     1 - 240, d3
    mov     (0x24, sp), d0          # U = (128 << 16) + c dx2 + s dy2
    mul     d2, d0
    mov     (0x28, sp), d1
    mul     d3, d1
    add     d1, d0
    add     128 << 16, d0
    mov     d0, (0x3C, sp)
    mov     (0x28, sp), d0          # V = (128 << 16) - s dx2 + c dy2
    mul     d2, d0
    mov     (0x24, sp), d1
    mul     d3, d1
    sub     d0, d1
    add     128 << 16, d1
    mov     d1, (0x40, sp)
    mov     (0x20, sp), d0          # a1 = BOT[y][x0], a3 = WB_LINE + x0, the end WB_LINE + x1
    asl     8, d0
    mov     (0x34, sp), d1
    add     d1, d0
    mov     WB_BOT, a1
    add     d0, a1
    mov     WB_LINE, a3
    add     d1, a3
    mov     WB_LINE, a0
    mov     (0x38, sp), d0
    add     d0, a0
    mov     a0, (0x1C, sp)
    mov     (0x30, sp), d0
    cmp     0, d0
    bne     wd_smooth
    # ---- nearest: four pixels a turn ----
    mov     (0x40, sp), d2          # d2 = V 8.8 << 16 | U 8.8 (rounded), d3 = dUV, a0 = TOP, a2 = SHADE
    add     128, d2
    lsr     8, d2
    asl     16, d2
    mov     (0x3C, sp), d0
    add     128, d0
    lsr     8, d0
    add     d0, d2
    mov     (0x5C, sp), d3
    mov     WB_TOP, a0
    mov     WB_SHADE, a2
wn_four:
    mov     d2, d0                  # pixel 0: the texel at (U >> 8 & 0xFF, U lane; V lane's >> 24)
    lsr     16, d0
    and     0xFF00, d0
    mov     d2, d1
    lsr     8, d1
    and     0xFF, d1
    or      d1, d0
    movbu   (d0, a0), d0
    cmp     16, d0
    bcc     wn_ok0                  # the upper disk: its entry
    asl     8, d0                   # a window: the lower disk under its shadow level
    movbu   (0, a1), d1
    or      d1, d0
    movbu   (d0, a2), d0
wn_ok0:
    movbu   d0, (0, a3)
    add     d3, d2
    mov     d2, d0                  # pixel 1: the texel at (U >> 8 & 0xFF, U lane; V lane's >> 24)
    lsr     16, d0
    and     0xFF00, d0
    mov     d2, d1
    lsr     8, d1
    and     0xFF, d1
    or      d1, d0
    movbu   (d0, a0), d0
    cmp     16, d0
    bcc     wn_ok1                  # the upper disk: its entry
    asl     8, d0                   # a window: the lower disk under its shadow level
    movbu   (1, a1), d1
    or      d1, d0
    movbu   (d0, a2), d0
wn_ok1:
    movbu   d0, (1, a3)
    add     d3, d2
    mov     d2, d0                  # pixel 2: the texel at (U >> 8 & 0xFF, U lane; V lane's >> 24)
    lsr     16, d0
    and     0xFF00, d0
    mov     d2, d1
    lsr     8, d1
    and     0xFF, d1
    or      d1, d0
    movbu   (d0, a0), d0
    cmp     16, d0
    bcc     wn_ok2                  # the upper disk: its entry
    asl     8, d0                   # a window: the lower disk under its shadow level
    movbu   (2, a1), d1
    or      d1, d0
    movbu   (d0, a2), d0
wn_ok2:
    movbu   d0, (2, a3)
    add     d3, d2
    mov     d2, d0                  # pixel 3: the texel at (U >> 8 & 0xFF, U lane; V lane's >> 24)
    lsr     16, d0
    and     0xFF00, d0
    mov     d2, d1
    lsr     8, d1
    and     0xFF, d1
    or      d1, d0
    movbu   (d0, a0), d0
    cmp     16, d0
    bcc     wn_ok3                  # the upper disk: its entry
    asl     8, d0                   # a window: the lower disk under its shadow level
    movbu   (3, a1), d1
    or      d1, d0
    movbu   (d0, a2), d0
wn_ok3:
    movbu   d0, (3, a3)
    add     d3, d2
    add     4, a1
    add     4, a3
    mov     (0x1C, sp), d0
    cmp     d0, a3
    bcs     wn_four
    bra     wd_store
    # ---- bilinear: a pixel a turn ----
wd_smooth:
    mov     a3, (0x58, sp)
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
    and     0xFF, d0
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
    lsr     8, d0
    and     0xFF00, d0
    or      d3, d0
    mov     WB_TOP, a0
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
    mov     d2, (0x54, sp)
    movbu   (256, a0), d0           # (i, j + 1)
    call    wb_lane, 0, 0
    mov     (0x44, sp), d1
    mul     d1, d0
    mov     d0, d2
    movbu   (257, a0), d0           # (i + 1, j + 1)
    call    wb_lane, 0, 0
    mov     (0x48, sp), d1
    mul     d1, d0
    add     d0, d2
    mov     (0x50, sp), d1
    mul     d1, d2
    mov     (0x54, sp), d0
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
    cmp     d1, a0
    bcs     wb_px
    # ---- the row into FB8: the words WSHADOW does not hold ----
wd_store:
    mov     (0x34, sp), d0
    mov     WB_LINE, a0
    add     d0, a0                  # a0 = the row's words
    mov     (0x20, sp), d1
    asl     8, d1
    add     d0, d1
    mov     WSHADOW, a2
    add     d1, a2                  # a2 = what the LCD holds there
    mov     (0x20, sp), d1
    mov     FB8_STRIDE, d2
    mulu    d2, d1
    add     d1, d0
    mov     FB8 + WHEEL_X0, a1
    add     d0, a1                  # a1 = the LCD
    mov     (0x1C, sp), d3
    mov     (WH_NSTORE), d2
wd_st:
    mov     (a0), d0
    mov     (a2), d1
    cmp     d1, d0
    beq     wd_same
    mov     d0, (a1)
    mov     d0, (a2)
    inc     d2
wd_same:
    add     4, a0
    add     4, a1
    add     4, a2
    cmp     d3, a0
    bcs     wd_st
    mov     d2, (WH_NSTORE)
wd_next:
    mov     (0x20, sp), d0
    inc     d0
    mov     d0, (0x20, sp)
    bra     wd_row
wd_ret:
    ret     [d2,d3,a2,a3], 0x70

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

# ---- the page's text: x, y, entry (1 white, 2 cyan, 3 yellow), 0, then the text (help.s's item format) ----
    .align  4
wh_items:
    .word   8, 8, 2, 0
    .long   hs_title1
    .word   8, 20, 2, 0
    .long   wh_t_title
    .word   8, 48, 3, 0
    .long   wh_t_tempo
    .word   8, 58, 1, 0
    .long   wh_t_turn1
    .word   8, 68, 1, 0
    .long   wh_t_turn2
    .word   8, 92, 3, 0
    .long   wh_t_pages
    .word   8, 102, 1, 0
    .long   wh_t_pages2
    .word   8, 126, 3, 0
    .long   wh_t_back
    .word   8, 136, 1, 0
    .long   wh_t_back2
    .word   456, 36, 3, 0
    .long   wh_t_arrow
    .word   456, 176, 1, 0
    .long   wh_t_draw
    .word   456, 188, 1, 0
    .long   wh_t_turning
    .word   456, 200, 1, 0
    .long   wh_t_still
    .word   456, 224, 1, 0
    .long   wh_t_page
    .word   0xFFFF, 0
wh_name:        .asciz  "AWWH0.AW"
wh_t_title:     .asciz  "CODE WHEEL"
wh_t_tempo:     .asciz  "TEMPO/PROGRAM"
wh_t_turn1:     .asciz  "turns the disk"
wh_t_turn2:     .asciz  "one number a click"
wh_t_pages:     .asciz  "PAGE UP / DOWN"
wh_t_pages2:    .asciz  "the other pages"
wh_t_back:      .asciz  "EXIT, HELP or a key"
wh_t_back2:     .asciz  "back to the game"
wh_t_arrow:     .asciz  "ARROW AT"
wh_t_draw:      .asciz  "drawn in:"
wh_t_turning:   .asciz  "turning"
wh_t_still:     .asciz  "at rest"
wh_t_page:      .asciz  "Page 5/5"
wh_t_ms:        .asciz  " ms"
wh_t_loading:   .asciz  "Loading the wheel"
wh_t_blank:     .asciz  "                 "
wh_t_missing:   .asciz  "CODE WHEEL FILES MISSING"
wh_t_code:      .asciz  "OR BAD, CODE "
wh_t_nowheel:   .asciz  "(no TEMPO wheel found)"
    .align  4
