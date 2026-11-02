# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Shared by both KN7000 builds (main.s: SP7001 plug-in; cnv_main.s: KN7APP.BIN for KN7LOAD.CNV):
# the game task, the page blit (only what changed) and the border fill, and their data.

.equ SG_REASONS,      5             # StopGame's reasons (sg_why), GUARD_PAGE .. GUARD_FILE

# =================================================================================
# The game task: let the firmware settle, reset the VM, then run it until the run-time guard
# refuses a write (vm.inc GUARD_*), which stops the game.
GameTask:
    add     -0x10, sp
    mov     2500, d0                # let the firmware reach its static screen first
    mov     DLY_TSK, a1
    calls   (a1)
    call    PerfInit, 0, 0          # the speed measurement (perf.s): from here on
    call    DisplayInit, 0, 0       # the pages' resolution (after PerfInit, which clears PF_MODE)
    call    PerfRegs, 0, 0
    call    PerfBench, 0, 0
    call    PerfRestart, 0, 0
    call    GameReset, 0, 0
gt_loop:
    call    ExecuteInstruction, 0, 0
    mov     (GUARD_WHAT), d0
    cmp     0, d0
    beq     gt_loop
    call    StopGame, 0, 0          # does not return

# StopGame: the game cannot go on (vm.inc GUARD_WHAT says why). Show it on the LCD, with the
# address involved, and keep yielding: the platform ends the task from DLY_TSK when the player
# quits (cnv_main.s). The text uses the help screens' font, palette and HelpText (help.s).
StopGame:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    AudioStopAll, 0, 0      # no note left sounding (audio.s)
    call    ShadowClear, 0, 0       # drawn in SHADOW, as the help screens (the VM is not running)
    mov     help_palette, a0
    mov     palette, a1
    call    hs_copy_pal, 0, 0
    mov     sg_title, a3
    mov     76, d0
    mov     64, d1
    mov     2, d2
    call    HelpText, 0, 0
    mov     (GUARD_WHAT), d0        # the reason: sg_why[GUARD_WHAT - 1]
    add     -1, d0
    cmp     SG_REASONS, d0
    bcs     sg_known
    mov     SG_REASONS - 1, d0      # out of range: the last, generic one
sg_known:
    asl     2, d0
    mov     sg_why, a0
    add     d0, a0
    mov     (a0), a3
    mov     16, d0
    mov     88, d1
    mov     1, d2
    call    HelpText, 0, 0
    mov     (GUARD_ADDR), d0        # "AT 0x12345678"
    mov     GUARD_TEXT, a0
    call    HexText, 0, 0
    mov     GUARD_TEXT, a3
    mov     16, d0
    mov     102, d1
    mov     1, d2
    call    HelpText, 0, 0
    mov     sg_quit, a3
    mov     16, d0
    mov     130, d1
    mov     3, d2
    call    HelpText, 0, 0
    mov     PH_PAUSE, d0
    call    PerfPhase, 0, 0
sg_loop:
    call    ShadowOut, 0, 0         # show it, all of it, again every second: the firmware may repaint
    mov     1000, d0
    mov     DLY_TSK, a1
    calls   (a1)
    bra     sg_loop

# HexText(d0 = value, a0 = 16-byte buffer): "AT 0x" and eight upper-case hex digits, NUL-ended.
# Leaf; uses d0, d1, a0, a1.
HexText:
    mov     d0, a1                  # the value, shifted left a nibble per digit
    mov     0x30205441, d0          # "AT 0"
    mov     d0, (a0)
    mov     0x78, d0                # "x"
    movbu   d0, (4, a0)
    add     5, a0
    mov     8, d1
ht_digit:
    mov     a1, d0
    lsr     28, d0                  # the top nibble
    cmp     10, d0
    bcs     ht_dec
    add     7, d0
ht_dec:
    add     0x30, d0
    movbu   d0, (a0)
    inc     a0
    mov     a1, d0
    asl     4, d0
    mov     d0, a1
    add     -1, d1
    bne     ht_digit
    clr     d0
    movbu   d0, (a0)
    rets

# =================================================================================
# BlitPage(a0 = a page): show it in the LCD's window through the 16-entry palette: 384x240 at (BIG_X0, 0) in
# the high-resolution mode, 320x200 at (AW_X0, AW_Y0) at the original resolution (PG_W, PG_H: the pages are of
# that size; DisplayInit, DisplayConvert). The LCD is slow to write (README-CNV.md, "Speed"), so only what it
# does not show already is written: SHADOW holds the colour indices the window shows, 4 bits a pixel, PF_PAL the
# palette it was drawn with, and pixels whose indices differ are written two to a 32-bit store (PF_PAIR: the
# RGB565 of both pixels of a packed byte). The window is written whole when the palette has changed, and border
# and window both when the LCD may not hold what was drawn (PF_DAMAGE: nothing shown yet, a sentinel pixel that
# changed under us, the periodic repaint, a switch of the mode, a part's load, SHADOW used for something else).
# The page shown last, when nothing has drawn on it since (PF_DIRTY), is not even compared. Phase BLIT (BORD for
# the border).
BlitPage:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, a2                  # the page
    mov     PH_BLIT, d0
    call    PerfPhase, 0, 0
    mov     d0, (0x10, sp)          # the phase to go back to
    call    PalCheck, 0, 0          # d0 = 1: a new palette, the pair table rebuilt
    mov     d0, d3                  # d3 = 1: write the whole window
    mov     (PF_DAMAGE), d0
    cmp     0, d0
    beq     bp_shown
    call    FillBorder, 0, 0        # repaint everything
    clr     d0
    mov     d0, (PF_DAMAGE)
    mov     d0, (PF_SINCE_REP)
    mov     (PF_REPAINTS), d0
    inc     d0
    mov     d0, (PF_REPAINTS)
    mov     1, d3
    bra     bp_write
bp_shown:
    cmp     0, d3
    bne     bp_write
    mov     (PF_LAST_SRC), a0       # the page on the LCD, not drawn on since: nothing to do
    cmp     a2, a0
    bne     bp_write
    call    PageDirty, 0, 0
    cmp     0, d0
    bne     bp_write
    mov     (PF_SKIPS), d0
    inc     d0
    mov     d0, (PF_SKIPS)
    bra     bp_done
bp_write:
    mov     a2, a0
    mov     d3, d0
    call    BlitPacked, 0, 0
    mov     a2, (PF_LAST_SRC)
    mov     a2, a0
    call    PageClean, 0, 0
    mov     (PF_BLITS), d0
    inc     d0
    mov     d0, (PF_BLITS)
bp_done:
    mov     (0x10, sp), d0
    call    PerfPhase, 0, 0
    ret     [d2,d3,a2,a3], 0x30

# WinBase -> a1 = the window's first LCD pixel for the pages' size now. Leaf; uses d0.
WinBase:
    mov     (PG_W), d0
    cmp     BIG_W, d0
    bne     wb_orig
    mov     FB + BIG_X0*2, a1
    rets
wb_orig:
    mov     FB + AW_Y0*FB_STRIDE + AW_X0*2, a1
    rets

# BlitPacked(a0 = page, d0 = 1 to write every pixel, 0 only those SHADOW does not hold): the page into the
# window, through PF_PAIR, and into SHADOW. Eight pixels a turn: the page's two words packed to 4 bits a pixel
# (pixel 0 in the lowest nibble: each byte is a PF_PAIR index), compared with SHADOW's word; each half that
# differs is two 32-bit stores. Counts the pixels written (PF_FRAME_PX).
BlitPacked:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, a2                  # a2 = the page
    mov     d0, (0x10, sp)          # write all
    call    WinBase, 0, 0
    mov     a1, (0x14, sp)          # a1 = this row's first LCD pixel
    mov     SHADOW, a3              # a3 = what the window shows
    mov     PF_PAIR, a0
    mov     (PG_H), d0
    mov     d0, (0x18, sp)          # rows left
    clr     d0
    mov     d0, (0x1C, sp)          # halves of four pixels written
bk_row:
    mov     (PG_W), d2
    lsr     3, d2                   # d2 = groups of eight left in the row
bk_grp:
    mov     (4, a2), d0             # pixels 4..7 -> bits 16..31
    and     0x0F0F0F0F, d0
    mov     d0, d1
    lsr     4, d1
    or      d1, d0
    and     0x00FF00FF, d0
    mov     d0, d1
    lsr     8, d1
    or      d1, d0
    asl     16, d0
    mov     d0, d3
    mov     (a2), d0                # pixels 0..3 -> bits 0..15
    and     0x0F0F0F0F, d0
    mov     d0, d1
    lsr     4, d1
    or      d1, d0
    and     0x00FF00FF, d0
    mov     d0, d1
    lsr     8, d1
    or      d1, d0
    and     0xFFFF, d0
    or      d3, d0                  # d0 = the eight pixels
    mov     (a3), d1
    mov     (0x10, sp), d3
    cmp     0, d3
    bne     bk_all
    xor     d0, d1                  # d1 = what differs
    beq     bk_next
    mov     d0, (a3)
    mov     d1, d3
    and     0xFFFF, d3
    beq     bk_hi
    mov     d0, d3                  # pixels 0, 1
    and     0xFF, d3
    asl     2, d3
    mov     (d3, a0), d3
    mov     d3, (a1)
    mov     d0, d3                  # pixels 2, 3
    lsr     6, d3
    and     0x3FC, d3
    mov     (d3, a0), d3
    mov     d3, (4, a1)
    mov     (0x1C, sp), d3
    inc     d3
    mov     d3, (0x1C, sp)
bk_hi:
    lsr     16, d1
    beq     bk_next
    mov     d0, d3                  # pixels 4, 5
    lsr     14, d3
    and     0x3FC, d3
    mov     (d3, a0), d3
    mov     d3, (8, a1)
    mov     d0, d3                  # pixels 6, 7
    lsr     22, d3
    and     0x3FC, d3
    mov     (d3, a0), d3
    mov     d3, (12, a1)
    mov     (0x1C, sp), d3
    inc     d3
    mov     d3, (0x1C, sp)
    bra     bk_next
bk_all:
    mov     d0, (a3)
    call    bk_put8, 0, 0
    mov     (0x1C, sp), d3
    add     2, d3
    mov     d3, (0x1C, sp)
bk_next:
    add     8, a2
    add     4, a3
    add     16, a1
    add     -1, d2
    bne     bk_grp
    mov     (0x14, sp), a1          # the next row
    add     FB_STRIDE, a1
    mov     a1, (0x14, sp)
    mov     (0x18, sp), d0
    add     -1, d0
    mov     d0, (0x18, sp)
    bne     bk_row
    mov     (0x1C, sp), d0          # pixels written
    asl     2, d0
    mov     (PF_FRAME_PX), d1
    add     d0, d1
    mov     d1, (PF_FRAME_PX)
    ret     [d2,d3,a2,a3], 0x30

# bk_put8(d0 = eight pixels, 4 bits each; a0 = PF_PAIR, a1 = their LCD pixels): four 32-bit stores. Leaf;
# uses d1.
bk_put8:
    mov     d0, d1
    and     0xFF, d1
    asl     2, d1
    mov     (d1, a0), d1
    mov     d1, (a1)
    mov     d0, d1
    lsr     6, d1
    and     0x3FC, d1
    mov     (d1, a0), d1
    mov     d1, (4, a1)
    mov     d0, d1
    lsr     14, d1
    and     0x3FC, d1
    mov     (d1, a0), d1
    mov     d1, (8, a1)
    mov     d0, d1
    lsr     22, d1
    and     0x3FC, d1
    mov     (d1, a0), d1
    mov     d1, (12, a1)
    rets

# ShadowOut: SHADOW to the whole window, and the border black, through the palette now (the help and stop
# screens, drawn in SHADOW: help.s HelpText). The next blit of a page compares it with what this showed.
ShadowOut:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    call    PalCheck, 0, 0
    call    FillBorder, 0, 0
    call    WinBase, 0, 0
    mov     a1, (0x14, sp)
    mov     SHADOW, a3
    mov     PF_PAIR, a0
    mov     (PG_H), d3              # rows
so_row:
    mov     (PG_W), d2
    lsr     3, d2
so_grp:
    mov     (a3), d0
    call    bk_put8, 0, 0
    add     4, a3
    add     16, a1
    add     -1, d2
    bne     so_grp
    mov     (0x14, sp), a1
    add     FB_STRIDE, a1
    mov     a1, (0x14, sp)
    add     -1, d3
    bne     so_row
    clr     d0
    mov     d0, (PF_DAMAGE)
    mov     SHADOW, d0              # no page is on the LCD (the next page's blit compares), and the
    mov     d0, (PF_LAST_SRC)       #   sentinels check what this showed
    ret     [d2,d3,a2,a3], 0x30

# ShadowClear: SHADOW black, for the help or stop screen at the pages' size now. Leaf.
ShadowClear:
    mov     SHADOW, a0
    mov     (PG_SIZE), d1
    lsr     3, d1                   # words: 8 pixels each
    clr     d0
sc_loop:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     sc_loop
    rets

# ShadowPlot(d0 = x, d1 = y, d2 = colour): one pixel of SHADOW, in the pages' coordinates now. Leaf; uses d0,
# d1, a0, a1; keeps d2.
ShadowPlot:
    mov     d0, a1                  # x
    mov     (PG_W), d0
    mulu    d1, d0
    add     a1, d0                  # d0 = y * PG_W + x
    mov     d0, d1
    lsr     1, d1
    mov     SHADOW, a0
    add     d1, a0
    movbu   (a0), d1
    btst    1, d0
    bne     spl_hi
    and     0xF0, d1                # even pixel: the low nibble
    mov     d2, d0
    and     15, d0
    or      d0, d1
    movbu   d1, (a0)
    rets
spl_hi:
    and     0x0F, d1                # odd pixel: the high nibble
    mov     d2, d0
    and     15, d0
    asl     4, d0
    or      d0, d1
    movbu   d1, (a0)
    rets

# ToPg(d0 = a coordinate of the 320x200 game, 0 or more) -> d0 = that place on the pages now: d0 * 6 / 5 in the
# high-resolution mode, d0 at the original resolution. Leaf; uses d1.
ToPg:
    mov     (PG_W), d1
    cmp     BIG_W, d1
    bne     tpg_ret
    mov     6, d1
    mulu    d1, d0
    clr     d1
    mov     d1, mdr
    mov     5, d1
    divu    d1, d0
tpg_ret:
    rets

# ToPgSigned(d0 = a signed 16-bit coordinate of the 320x200 game) -> d0 = floor(d0 * 6 / 5) in the high-resolution
# mode, d0 (sign-extended) at the original resolution. Leaf; uses d1.
ToPgSigned:
    exth    d0
    mov     (PG_W), d1
    cmp     BIG_W, d1
    bne     tps_ret
    mov     6, d1
    mul     d1, d0                  # -196,608 .. 196,602
    add     200000, d0              # a multiple of 5 that makes it positive: floor() as an unsigned divide
    clr     d1
    mov     d1, mdr
    mov     5, d1
    divu    d1, d0
    add     -40000, d0
tps_ret:
    rets

# =================================================================================
# The display mode's pages. DisplayInit (the game task's start, after PerfInit): high resolution (PF_MODE 0),
# unless the build has no room for it (HIRES_OK 0) or a probe asked for the original resolution (DISP_ORIG).
DisplayInit:
    mov     HIRES_OK, d1
    cmp     0, d1
    beq     di_orig
    mov     (DISP_ORIG), d1
    mov     DISP_ORIG_MAGIC, d0
    cmp     d0, d1
    beq     di_orig
    clr     d0
    bra     di_set
di_orig:
    mov     1, d0
di_set:
    mov     d0, (PF_MODE)
# DisplayGeom: PG_W, PG_H, PG_SIZE for PF_MODE. Leaf.
DisplayGeom:
    mov     (PF_MODE), d0
    cmp     0, d0
    bne     dg_orig
    mov     BIG_W, d0
    mov     d0, (PG_W)
    mov     BIG_H, d0
    mov     d0, (PG_H)
    mov     BIG_W * BIG_H, d0
    mov     d0, (PG_SIZE)
    rets
dg_orig:
    mov     AW_W, d0
    mov     d0, (PG_W)
    mov     AW_H, d0
    mov     d0, (PG_H)
    mov     AW_W * AW_H, d0
    mov     d0, (PG_SIZE)
    rets

# DisplayConvert: PF_MODE has changed (perf.s PerfInput): the four pages to its size, in place (PageUp, PageDown:
# what they hold carries on, scaled, until the game draws it again), then the next blit repaints everything.
DisplayConvert:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (PF_MODE), d0
    cmp     0, d0
    bne     dc_down
    mov     (PG_W), d0
    cmp     BIG_W, d0
    beq     dc_ret                  # (already)
    mov     PAGE_BITMAP_0, a0
    call    PageUp, 0, 0
    mov     PAGE_BITMAP_1, a0
    call    PageUp, 0, 0
    mov     PAGE_BITMAP_2, a0
    call    PageUp, 0, 0
    mov     PAGE_BITMAP_3, a0
    call    PageUp, 0, 0
    bra     dc_geom
dc_down:
    mov     (PG_W), d0
    cmp     AW_W, d0
    beq     dc_ret
    mov     PAGE_BITMAP_0, a0
    call    PageDown, 0, 0
    mov     PAGE_BITMAP_1, a0
    call    PageDown, 0, 0
    mov     PAGE_BITMAP_2, a0
    call    PageDown, 0, 0
    mov     PAGE_BITMAP_3, a0
    call    PageDown, 0, 0
dc_geom:
    call    DisplayGeom, 0, 0
    mov     (PF_DAMAGE), d0
    or      PFD_MODE, d0
    mov     d0, (PF_DAMAGE)
    clr     d0
    mov     d0, (PF_LAST_SRC)
dc_ret:
    ret     [d2,d3,a2,a3], 0x20

# PageUp(a0 = page): its 320x200 picture (stride 320, at its start) scaled to 384x240 in place, nearest pixel:
# row r of 240 from row floor(5r/6), pixel x of 384 from floor(5x/6) (each 5 become 6: p0 p0 p1 p2 p3 p4).
# Bottom row first, each row from its end, so that nothing is overwritten before it is read. LoadBitmap's
# bitmaps (320x200 is all there is of them) and DisplayConvert. Leaf (saves d2, d3, a2, a3).
PageUp:
    movm    [d2,d3,a2,a3], (sp)
    mov     a0, a1                  # a1 = the page
    mov     BIG_H - 1, d3           # d3 = r
pu_row:
    mov     d3, d0                  # s = floor(5r / 6)
    mov     5, d1
    mulu    d1, d0
    clr     d1
    mov     d1, mdr
    mov     6, d1
    divu    d1, d0
    mov     AW_W, d1
    mulu    d1, d0
    mov     a1, a2
    add     d0, a2
    add     AW_W, a2                # a2 = the end of source row s
    mov     d3, d0
    mov     BIG_W, d1
    mulu    d1, d0
    mov     a1, a3
    add     d0, a3
    add     BIG_W, a3               # a3 = the end of row r
    mov     AW_W / 5, d2
pu_grp:
    add     -5, a2
    add     -6, a3
    movbu   (4, a2), d0
    movbu   d0, (5, a3)
    movbu   (3, a2), d0
    movbu   d0, (4, a3)
    movbu   (2, a2), d0
    movbu   d0, (3, a3)
    movbu   (1, a2), d0
    movbu   d0, (2, a3)
    movbu   (a2), d0
    movbu   d0, (1, a3)
    movbu   d0, (a3)
    add     -1, d2
    bne     pu_grp
    add     -1, d3
    bge     pu_row
    ret     [d2,d3,a2,a3], 0x10

# PageDown(a0 = page): its 384x240 picture to 320x200 in place (stride 320, at its start): row t from row
# t + ceil(t/5), pixel 5g+k from 6g + (0, 2, 3, 4, 5)[k] (the pixels PageUp would have doubled are dropped). Top row
# first, each row from its start. Leaf (saves d2, d3, a2, a3).
PageDown:
    movm    [d2,d3,a2,a3], (sp)
    mov     a0, a1
    clr     d3                      # d3 = t
pd_row:
    mov     d3, d0                  # s = t + (t + 4) / 5
    add     4, d0
    clr     d1
    mov     d1, mdr
    mov     5, d1
    divu    d1, d0
    add     d3, d0
    mov     BIG_W, d1
    mulu    d1, d0
    mov     a1, a2
    add     d0, a2                  # a2 = source row s
    mov     d3, d0
    mov     AW_W, d1
    mulu    d1, d0
    mov     a1, a3
    add     d0, a3                  # a3 = row t
    mov     AW_W / 5, d2
pd_grp:
    movbu   (a2), d0
    movbu   d0, (a3)
    movbu   (2, a2), d0
    movbu   d0, (1, a3)
    movbu   (3, a2), d0
    movbu   d0, (2, a3)
    movbu   (4, a2), d0
    movbu   d0, (3, a3)
    movbu   (5, a2), d0
    movbu   d0, (4, a3)
    add     6, a2
    add     5, a3
    add     -1, d2
    bne     pd_grp
    inc     d3
    cmp     AW_H, d3
    bne     pd_row
    ret     [d2,d3,a2,a3], 0x10

# PalCheck -> d0 = 1 when palette is not the one the LCD was drawn with (PF_PAL): PF_PAL becomes it and
# the pair table PF_PAIR is rebuilt (entry i0 | i1 << 4 = palette[i0] | palette[i1] << 16, pixel 0 in the
# low half, at the lower address); else 0. Leaf (saves d2, d3, a2).
PalCheck:
    movm    [d2,d3,a2], (sp)
    mov     palette, a0
    mov     PF_PAL, a1
    mov     8, d1
pk_cmp:
    mov     (a0), d0
    mov     (a1), d2
    cmp     d2, d0
    bne     pk_new
    add     4, a0
    add     4, a1
    add     -1, d1
    bne     pk_cmp
    clr     d0
    ret     [d2,d3,a2], 0xC
pk_new:
    mov     palette, a0
    mov     PF_PAL, a1
    mov     8, d1
pk_copy:
    mov     (a0), d0
    mov     d0, (a1)
    add     4, a0
    add     4, a1
    add     -1, d1
    bne     pk_copy
    mov     PF_PAL, a1
    mov     PF_PAIR, a2
    clr     d2
pk_pair:
    mov     d2, d0
    and     15, d0
    asl     1, d0
    movhu   (d0, a1), d3            # pixel 0's colour
    mov     d2, d0
    lsr     4, d0
    asl     1, d0
    movhu   (d0, a1), d0            # pixel 1's
    asl     16, d0
    or      d3, d0
    mov     d0, (a2)
    add     4, a2
    inc     d2
    cmp     256, d2
    bne     pk_pair
    mov     (PF_PAIR_N), d0
    inc     d0
    mov     d0, (PF_PAIR_N)
    mov     1, d0
    ret     [d2,d3,a2], 0xC

# PageIdx(a0) -> d0 = 0..3 when a0 is one of the four pages, else -1. Leaf; uses d0, d1; keeps a0.
PageIdx:
    mov     a0, d1
    mov     PAGE_BITMAP_0, d0
    cmp     d0, d1
    beq     pix_0
    mov     PAGE_BITMAP_1, d0
    cmp     d0, d1
    beq     pix_1
    mov     PAGE_BITMAP_2, d0
    cmp     d0, d1
    beq     pix_2
    mov     PAGE_BITMAP_3, d0
    cmp     d0, d1
    beq     pix_3
    mov     -1, d0
    rets
pix_0:
    clr     d0
    rets
pix_1:
    mov     1, d0
    rets
pix_2:
    mov     2, d0
    rets
pix_3:
    mov     3, d0
    rets

# PerfMarkDirty(a0 = a page about to be drawn on): note it, so that the blit does not skip it. Anything
# that is not one of the four pages is ignored. Uses d0, d1, a1; keeps a0.
PerfMarkDirty:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    PageIdx, 0, 0
    cmp     0, d0
    blt     pmd_ret
    mov     PF_DIRTY, a1
    mov     1, d1
    movbu   d1, (d0, a1)
pmd_ret:
    ret     [d2,d3,a2,a3], 0x20

# PageDirty(a0 = page) -> d0 = 0 when a0 is one of the four pages and nothing has drawn on it since it
# was shown, else 1. Uses d0, d1, a1; keeps a0.
PageDirty:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    PageIdx, 0, 0
    cmp     0, d0
    blt     pdy_yes
    mov     PF_DIRTY, a1
    movbu   (d0, a1), d0
    ret     [d2,d3,a2,a3], 0x20
pdy_yes:
    mov     1, d0
    ret     [d2,d3,a2,a3], 0x20

# PageClean(a0 = page): the LCD shows it as it is now. Uses d0, d1, a1; keeps a0.
PageClean:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    PageIdx, 0, 0
    cmp     0, d0
    blt     pcl_ret
    mov     PF_DIRTY, a1
    clr     d1
    movbu   d1, (d0, a1)
pcl_ret:
    ret     [d2,d3,a2,a3], 0x20

# FillBorder: paint everything around the game's window black, so that the firmware's screen behind the
# game never shows: in the high-resolution mode, the 128-pixel strips beside the 384x240 window; at the original
# resolution, the 20-row bands above and below the 320x200 window and the 160-pixel strips beside it. Done
# when BlitPage repaints everything (PF_DAMAGE). 32-bit stores, 8 per loop. Phase BORD.
FillBorder:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     PH_BORD, d0
    call    PerfPhase, 0, 0
    mov     d0, (0x10, sp)
    mov     (PG_W), d1
    clr     d0
    cmp     BIG_W, d1
    bne     fb_orig
    mov     FB, a1                  # enlarged: the side strips, every row
    mov     FB_H, d2
fb_big_row:
    mov     a1, a0                  # left strip: x 0..BIG_X0-1
    mov     BIG_X0 * 2 / 32, d1
    call    fb_run, 0, 0
    mov     a1, a0                  # right strip: x BIG_X0+BIG_W..FB_W-1
    add     (BIG_X0 + BIG_W) * 2, a0
    mov     (FB_W - BIG_X0 - BIG_W) * 2 / 32, d1
    call    fb_run, 0, 0
    add     FB_STRIDE, a1
    add     -1, d2
    bne     fb_big_row
    bra     fb_done
fb_orig:
    mov     FB, a0                  # top band: rows 0..AW_Y0-1, full width
    mov     AW_Y0 * FB_STRIDE / 32, d1
    call    fb_run, 0, 0
    mov     FB + (AW_Y0 + AW_H) * FB_STRIDE, a0   # bottom band
    mov     (FB_H - AW_Y0 - AW_H) * FB_STRIDE / 32, d1
    call    fb_run, 0, 0
    mov     FB + AW_Y0 * FB_STRIDE, a1            # side strips, one row at a time
    mov     AW_H, d2
fb_row:
    mov     a1, a0                  # left strip: x 0..AW_X0-1
    mov     AW_X0 * 2 / 32, d1
    call    fb_run, 0, 0
    mov     a1, a0                  # right strip: x AW_X0+AW_W..FB_W-1
    add     (AW_X0 + AW_W) * 2, a0
    mov     (FB_W - AW_X0 - AW_W) * 2 / 32, d1
    call    fb_run, 0, 0
    add     FB_STRIDE, a1
    add     -1, d2
    bne     fb_row
fb_done:
    mov     (0x10, sp), d0
    call    PerfPhase, 0, 0
    ret     [d2,d3,a2,a3], 0x30

# LcdBlack: the whole LCD frame black, border and window (a part's load: EnsurePart); the next blit repaints
# everything (PF_DAMAGE).
LcdBlack:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d0
    mov     FB, a0
    mov     FB_H * FB_STRIDE / 32, d1
    call    fb_run, 0, 0
    mov     (PF_DAMAGE), d0
    or      PFD_BLACK, d0
    mov     d0, (PF_DAMAGE)
    ret     [d2,d3,a2,a3], 0x20

# fb_run(a0 = start, d1 = 32-byte blocks, d0 = 0): store d1 * 8 zero words from a0. Leaf.
fb_run:
    mov     d0, (a0)
    mov     d0, (4, a0)
    mov     d0, (8, a0)
    mov     d0, (12, a0)
    mov     d0, (16, a0)
    mov     d0, (20, a0)
    mov     d0, (24, a0)
    mov     d0, (28, a0)
    add     32, a0
    add     -1, d1
    bne     fb_run
    rets

# =================================================================================
    .align  4
game_ctsk:
    .long   0
    .long   1
    .long   GameTask
    .word   TASK_PRI
    .word   0
    .long   TASK_STACK
    .align  4
palette:
    .space  16*2, 0
    .align  4
sg_why:                             # GUARD_WHAT 1.. (vm.inc)
    .long   sg_page, sg_stack, sg_load, sg_bitmap, sg_file     # SG_REASONS of them
sg_title:   .asciz  "ANOTHER WORLD STOPPED"
sg_page:    .asciz  "a page pointer was not a page"
sg_stack:   .asciz  "the VM stack ran over"
sg_load:    .asciz  "a load outside the game's RAM"
sg_bitmap:  .asciz  "a bitmap that was not loaded"
sg_file:    .asciz  "a game file was missing or bad"
sg_quit:    .asciz  "Hold EXIT to quit."
    .align  4
