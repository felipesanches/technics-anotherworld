# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# fwdraw.s -- the firmware's screen kept from drawing while the game task runs (README-CNV.md, "The firmware's
# screen"), as Pinball Fantasies does it (Pinball kn7000/src/app/fwdraw.c, where the firmware's side is traced).
# Answered request 5 on every converter call, program 893 changes to its text title again each time, and each change
# repaints STYLE CONVERT: ScreenProc (0x484177CE), the base of the screen's views, answers the paint event 0x600B2
# with DrawWall (the 150 KB wallpaper, RAM to RAM, and the whole screen marked for the LCD), and the title bar and the
# text box are drawn and copied to the LCD a dot at a time. While the game draws every frame that does not show; while
# a part loads the game task only waits, and the firmware's screen showed (Felipe on the instrument, 2026-11-02; in
# MAME, two whole repaints at the intro's hand-over to the lake: probes/cnv/README.md, "Speed").
#
# FwdrawHook (the main task, once the game task is started) finds the view procedures through the class table in RAM:
# group 4's entry (0x5011FAC8: id, group procedure, count 0x6B, records) points at its records in flash (0x48724914,
# 0x18 bytes each, the procedure first); record 0x41 is ScreenProc's. It copies the records to FD_COPY, puts
# FwScreenHook in record 0x41 and points the entry at the copy with one store. Anything else found there (another
# program) is left alone, and nothing below does anything. FwdrawQuiet (the game task, at every yield) then turns
# the drawing off: every record queued for the firmware's draw task checks DrawEnable (0x5002A018) and draws nothing
# while it is 0, and the draw task sets DrawEnable from 0x5002A01C whenever its queue runs empty, so that is 0 too.
# Only DrawWall writes 0x5002A01C: 0 as it begins, 1 as it ends; one under way must be let finish (Pinball found the
# main task waiting in it for good when both were set 0 meanwhile), so the drawing goes off only at a yield that
# finds 0x5002A01C at 1. FwdrawUnhook puts both back to 1 and the entry back on the flash records: at the quit,
# before the firmware's "Continue Next?", and from FwdrawQuiet when the firmware has not called the converter for
# WATCH_MS (it left STYLE CONVERT some other way: DISPLAY HOLD).

.equ FD_GROUP4,       0x5011FAC8    # group 4's entry in the class table: +8 the count, +0xC the records
.equ FD_RECORDS,      0x48724914    # program 893's view records, in flash
.equ FD_NRECORDS,     0x6B
.equ FD_REC_LEN,      0x18
.equ FD_SCREEN_REC,   0x41          # ScreenProc's record
.equ FD_SCREEN_PROC,  0x484177CE
.equ FD_PAINT,        0x600B2       # the paint event ScreenProc answers with DrawWall
.equ FD_DRAW_ENABLE,  0x5002A018    # nonzero: drawing allowed
.equ FD_DRAW_KEEP,    0x5002A01C    # what the draw task sets DrawEnable to when its queue is empty

# FwdrawHook: the view records copied, ScreenProc's replaced by FwScreenHook, the class table pointed at the copy;
# only when the firmware is program 893's layout. Main task. Leaf.
FwdrawHook:
    mov     (FD_HOOKED), d0
    cmp     0, d0
    bne     fh_ret
    mov     FD_GROUP4, a0
    mov     (12, a0), d0
    cmp     FD_RECORDS, d0
    bne     fh_ret
    mov     (8, a0), d0
    cmp     FD_NRECORDS, d0
    bne     fh_ret
    mov     FD_RECORDS + FD_SCREEN_REC * FD_REC_LEN, a1
    mov     (a1), d0
    cmp     FD_SCREEN_PROC, d0
    bne     fh_ret
    mov     FD_RECORDS, a0
    mov     FD_COPY, a1
    mov     FD_NRECORDS * FD_REC_LEN / 4, d1
fh_copy:
    mov     (a0), d0
    mov     d0, (a1)
    add     4, a0
    add     4, a1
    add     -1, d1
    bne     fh_copy
    mov     FwScreenHook, d0
    mov     d0, (FD_COPY + FD_SCREEN_REC * FD_REC_LEN)
    mov     (CV_CALLS), d0          # the watch starts now
    mov     d0, (FD_LASTCALLS)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (FD_LASTMS)
    mov     1, d0
    mov     d0, (FD_HOOKED)
    mov     FD_COPY, d0             # one store: the firmware sees the old records or the new
    mov     d0, (FD_GROUP4 + 0xC)
fh_ret:
    rets

# FwScreenHook: in ScreenProc's record while the game runs, called as view procedures are (`calls (a1)`, d0 the
# view, d1 the event): the paint event is answered 0 without DrawWall (and counted); every other goes on to
# ScreenProc with the registers and the stack as they came (a1, which held this address, is no argument).
FwScreenHook:
    cmp     FD_PAINT, d1
    beq     fsh_paint
    mov     FD_SCREEN_PROC, a1
    jmp     (a1)
fsh_paint:
    mov     (FD_SKIPPED), d0
    inc     d0
    mov     d0, (FD_SKIPPED)
    clr     d0
    rets

# FwdrawQuiet: on the game task, before every yield (DLY_TSK): the drawing off when no DrawWall is under way, or
# everything back when the firmware has stopped calling the converter. Leaf.
FwdrawQuiet:
    mov     (FD_HOOKED), d0
    cmp     0, d0
    beq     fq_ret
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d1                # d1 = now
    mov     (CV_CALLS), d0
    mov     (FD_LASTCALLS), a1
    cmp     a1, d0
    beq     fq_same
    mov     d0, (FD_LASTCALLS)
    mov     d1, (FD_LASTMS)
    bra     fq_draw
fq_same:
    mov     (FD_LASTMS), d0
    sub     d0, d1
    cmp     WATCH_MS, d1
    bcs     fq_draw
    mov     1, d0
    mov     d0, (FD_WATCHED)
    bra     FwdrawGone              # (its ret returns from here)
fq_draw:
    mov     (FD_DRAW_KEEP), d0
    cmp     0, d0
    beq     fq_ret                  # off already, or a DrawWall under way: the next yield
    clr     d0
    mov     d0, (FD_DRAW_KEEP)
    mov     d0, (FD_DRAW_ENABLE)
    mov     (FD_QUIET), d0
    cmp     0, d0
    beq     fq_first
    mov     (FD_REASSERTS), d0      # it was off before: something turned it on again
    inc     d0
    mov     d0, (FD_REASSERTS)
fq_first:
    mov     1, d0
    mov     d0, (FD_QUIET)
fq_ret:
    rets

# FwdrawGone: the firmware has stopped calling the converter (FwdrawQuiet's watch): its own frame on the LCD again
# (lcd8.s LcdRelease) and its drawing on.
FwdrawGone:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    LcdRelease, 0, 0
    call    FwdrawUnhook, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# FwdrawUnhook: the drawing on again and the class table back on the flash records. Either task. Leaf.
FwdrawUnhook:
    mov     (FD_HOOKED), d0
    cmp     0, d0
    beq     fu_ret
    mov     (FD_QUIET), d0
    cmp     0, d0
    beq     fu_table
    mov     1, d0
    mov     d0, (FD_DRAW_KEEP)
    mov     d0, (FD_DRAW_ENABLE)
    clr     d0
    mov     d0, (FD_QUIET)
fu_table:
    mov     FD_RECORDS, d0
    mov     d0, (FD_GROUP4 + 0xC)
    clr     d0
    mov     d0, (FD_HOOKED)
fu_ret:
    rets
