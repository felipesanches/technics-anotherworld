# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# chain.s -- back to the program menu at the quit (README-CNV.md, "Quitting"; Felipe 2026-11-02: no firmware message,
# no "Continue Next?", the menu at once). When the program menu started the game (its launch block named a folder:
# cnv_main.s LaunchFolder, AW_PREFIX not empty), the quit reads the menu, C:\KN7APP.BIN, into STAGE, checks it as the
# loader checks an application (the header's magic, loader ABI, size, link address and entry, and the CRC-32 from
# AH_NAME to the end), and starts it the way the menu starts a program: through the menu's own trampoline (technics-
# roms-disasm kn7000/tools/kn7menu/tramp.s, assembled for T_CODE; its image tramp_bin.inc and its addresses
# tramp_syms.inc), which copies STAGE to APP_BASE, zeroes the rest of the application area, writes the launch block
# (here all zero: the menu runs from the root), syncs the caches and returns to the loader with request 1, from the
# stack pointer the loader called the game with (CV_ENTRY_SP). From the next converter call the loader calls the menu,
# as if it had loaded it itself; the menu's first call draws its screen. The LCD goes back to the firmware's frame
# (LcdRelease) only once the menu is read and checked, and that frame is made black first (FwFrameBlack), so nothing
# else shows in between.
# STAGE, T_CODE, T_DATA and the TD_* offsets are the menu's (kn7menu/menu.inc); tools/chain_check.py checks that they
# still are, at every build.

.include "tramp_syms.inc"          # T_LAUNCH, TRAMP_LEN (kn7menu/build, from tramp.s's map)
.equ CH_STAGE,      0x502E8000      # menu.inc STAGE
.equ CH_STAGE_MAX,  LB_ADDR - APP_BASE
.equ CH_T_CODE,     0x50368000      # menu.inc T_CODE (tramp_syms.inc T_LAUNCH)
.equ CH_T_DATA,     0x50369800      # menu.inc T_DATA
.equ CH_TD_RETSP,   0x00            # menu.inc TD_*
.equ CH_TD_SIZE,    0x04
.equ CH_TD_MS,      0x08
.equ CH_TD_FG,      0x14
.equ CH_TD_BG,      0x18
.equ CH_TD_MSG,     0x120
.equ CH_TD_LEN,     0x180
.equ CH_APP_MAGIC,  0x41374E4B      # "KN7A"
# CV_CHAIN: what ChainMenu found (the probes read it): 0 not tried, else why the menu was not started
.equ CHR_OPEN,      2               # C:\KN7APP.BIN not there
.equ CHR_SIZE,      3               # empty, too short for a header, or larger than STAGE_MAX
.equ CHR_HEADER,    4               # not an application of this loader
.equ CHR_CRC,       5               # damaged

# ChainMenu: start the menu (returns only when it cannot: CV_CHAIN says why; the quit then goes on as before).
ChainMenu:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     1, d0                   # the file layer to the SD card
    mov     (FW_SETEXT), a3
    calls   (a3)
    mov     chain_name, a0
    mov     mode_rb, a1
    mov     (FW_OPEN), a3
    calls   (a3)
    exth    d0
    cmp     0, d0
    blt     cm_noopen
    clr     d3                      # d3: bytes read
    mov     CH_STAGE, a0
    mov     a0, (0x18, sp)
cm_piece:
    mov     CH_STAGE_MAX + 1, d0    # one byte more than may come: a longer file fails
    sub     d3, d0
    cmp     0, d0
    beq     cm_close
    mov     FILE_PIECE, d1
    cmp     d1, d0
    bls     cm_ask
    mov     d1, d0
cm_ask:
    mov     d0, (0x14, sp)
    mov     (0x18, sp), a0
    mov     (FW_READ), a3
    calls   (a3)                    # d0 = bytes read
    cmp     0, d0
    blt     cm_close
    add     d0, d3
    mov     (0x18, sp), d1
    add     d0, d1
    mov     d1, (0x18, sp)
    mov     (0x14, sp), d1
    cmp     d1, d0
    beq     cm_piece
cm_close:
    mov     (FW_CLOSE), a3
    calls   (a3)
    mov     (FW_RESETEXT), a3
    calls   (a3)
    mov     CHR_SIZE, d2            # the checks, as the loader's
    cmp     0x40, d3
    bcs     cm_fail
    mov     CH_STAGE_MAX, d0
    cmp     d0, d3
    bhi     cm_fail
    mov     CHR_HEADER, d2
    mov     (CH_STAGE + AH_MAGIC), d0
    mov     CH_APP_MAGIC, d1
    cmp     d1, d0
    bne     cm_fail
    mov     (CH_STAGE + AH_ABI), d0
    cmp     LOADER_ABI, d0
    bne     cm_fail
    mov     (CH_STAGE + AH_SIZE), d0
    cmp     d3, d0
    bne     cm_fail
    mov     (CH_STAGE + AH_BASE), d0
    mov     APP_BASE, d1
    cmp     d1, d0
    bne     cm_fail
    mov     (CH_STAGE + AH_ENTRY), d0
    cmp     d1, d0                  # APP_BASE + 0x40 <= entry < APP_BASE + size
    bcs     cm_fail
    sub     d1, d0
    cmp     0x40, d0
    bcs     cm_fail
    cmp     d3, d0
    bcc     cm_fail
    mov     CHR_CRC, d2
    mov     CH_STAGE + AH_NAME, a0
    mov     d3, d0
    mov     AH_NAME, d1
    sub     d1, d0
    call    ChainCrc, 0, 0
    mov     (CH_STAGE + AH_CRC), d1
    cmp     d1, d0
    bne     cm_fail
    mov     CH_STAGE, a0            # zeros after the file, to a word boundary (the trampoline copies words)
    add     d3, a0
    clr     d0
    movbu   d0, (a0)
    movbu   d0, (1, a0)
    movbu   d0, (2, a0)
    mov     chain_tramp, a0         # the trampoline
    mov     CH_T_CODE, a1
    mov     TRAMP_LEN, d1
cm_code:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d1
    bne     cm_code
    mov     CH_T_DATA, a2           # its data: all zero (the launch block too: the root), then ...
    mov     a2, a0
    mov     CH_TD_LEN / 4, d1
    clr     d0
cm_clr:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     cm_clr
    mov     (CV_ENTRY_SP), d0
    mov     d0, (CH_TD_RETSP, a2)
    mov     d3, (CH_TD_SIZE, a2)
    mov     (SVC + SV_MSCOUNT), d0
    mov     d0, (CH_TD_MS, a2)
    mov     0xFFFF, d0              # its failure screen's colours and text (it cannot fail: a RAM copy)
    mov     d0, (CH_TD_FG, a2)
    mov     0x0010, d0
    mov     d0, (CH_TD_BG, a2)
    mov     CH_T_DATA + CH_TD_MSG, a0
    mov     chain_failed, a1
cm_msg:
    movbu   (a1), d0
    movbu   d0, (a0)
    inc     a0
    inc     a1
    cmp     0, d0
    bne     cm_msg
    mov     1, d0
    mov     d0, (CV_CHAIN)
    call    FwFrameBlack, 0, 0      # the firmware's frame black (it still holds STYLE CONVERT's screen), then
    call    LcdRelease, 0, 0        # on the LCD: the menu draws its screen into it
    call    CacheSync, 0, 0         # the trampoline to RAM, no old line of its region in the I-cache
    mov     T_LAUNCH, a0
    calls   (a0)                    # returns to the loader, not here
cm_hang:
    bra     cm_hang
cm_noopen:
    mov     (FW_RESETEXT), a3
    calls   (a3)
    mov     CHR_OPEN, d2
cm_fail:
    mov     d2, (CV_CHAIN)
    ret     [d2,d3,a2,a3], 0x30

# FwFrameBlack: the firmware's 16-bit frame (the one LcdRelease shows again: its start address LCD_SAVE+1..3, the
# bottom-right pixel's word under the 180-degree SwivelView, and 240 lines of LCD_SAVE+4..5 words before it) all
# zeros, black: while the menu draws its first screen, nothing of the firmware's shows. Display memory only; the
# firmware draws its screens again whenever it opens one.
FwFrameBlack:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    movbu   (LCD_SAVE + 3), d0      # the start, in words
    asl     16, d0
    movbu   (LCD_SAVE + 2), d1
    asl     8, d1
    or      d1, d0
    movbu   (LCD_SAVE + 1), d1
    or      d1, d0
    inc     d0
    asl     1, d0                   # the byte after the frame's last pixel
    movbu   (LCD_SAVE + 5), d1      # words a line
    asl     8, d1
    movbu   (LCD_SAVE + 4), d2
    or      d2, d1
    mov     240 * 2, d2
    mulu    d2, d1                  # bytes in the frame
    cmp     d1, d0
    bcs     ffb_ret                 # (not a frame this can be)
    mov     0x50000, d2             # FB8 lies past it (vm.inc FB8_OFS): never more than that
    cmp     d2, d1
    bhi     ffb_ret
    sub     d1, d0
    mov     FB, a0
    add     d0, a0                  # its first byte
    lsr     2, d1                   # words of 32 bits
    clr     d0
ffb_loop:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     ffb_loop
ffb_ret:
    ret     [d2,d3,a2,a3], 0x20

# ChainCrc(a0 = bytes, d0 = how many) -> d0 = their CRC-32 (the loader's: reflected, 0xEDB88320, from ~0, inverted),
# a bit at a time.
ChainCrc:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d3
    mov     -1, d0
    cmp     0, d3
    beq     cc_end
cc_byte:
    movbu   (a0), d1
    xor     d1, d0
    mov     8, d2
cc_bit:
    btst    1, d0
    beq     cc_zero
    lsr     1, d0
    mov     0xEDB88320, d1
    xor     d1, d0
    bra     cc_next
cc_zero:
    lsr     1, d0
cc_next:
    add     -1, d2
    bne     cc_bit
    inc     a0
    add     -1, d3
    bne     cc_byte
cc_end:
    not     d0
    ret     [d2,d3,a2,a3], 0x20

.include "cachesync.inc"            # CacheSync (technics-roms-disasm kn7000/tools/kn7menu)

chain_name:
    .asciz  "KN7APP.BIN"
chain_failed:
    .asciz  "THE MENU COULD NOT START"
    .align  4
chain_tramp:
.include "tramp_bin.inc"            # tramp.s, assembled for T_CODE (kn7menu/build)
    .align  4
