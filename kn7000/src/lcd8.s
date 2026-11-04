# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# lcd8.s -- the LCD at 8 bits a pixel through its look-up table, and the ambilight around the game's window
# (README-CNV.md, "The screen"). Shared by both builds.
#
# The LCD controller (an S1D13806: the S1D13506's registers, 1280 KB of display memory) shows 640 x 240 dots from its
# display memory at the start address REG[042h]-[044h] (16-bit words), lines of REG[046h]-[047h] words; REG[040h] bits
# 2-0 its bits a pixel, bit 4 the 180-degree SwivelView the KN7000's panel needs (the start address is then the
# bottom-right pixel's word and memory is fetched backwards). At 8 bits a pixel each byte is an entry of its look-up
# table (REG[1E2h] the entry, then three writes of REG[1E4h], red, green, blue in bits 7-4, which move to the next
# entry): 4 bits a channel, the original game's own colour depth. All of this is what Pinball Fantasies does on the
# owner's KN7000 (Pinball kn7000/src/game/screen.cpp; probes PFT14 and PFT15 on the unit) and what kn7000_mame models.
#
# The game's frame is FB8, past the firmware's 16-bit frame (FB, left alone): LcdOwn (the game task's start) saves
# the firmware's REG[040h], [042h]-[044h], [046h]-[047h], clears FB8, draws the ambilight's border pattern, loads the
# look-up table black and points the controller at FB8; LcdRelease puts the firmware's registers back (the quit, or
# the firmware no longer calling the converter: fwdraw.s), and its own picture shows again as it was. Entries 0-15
# are the game's palette (display.s PalCheck), so a palette change is 16 entries written, never a pixel; a part's
# load makes every entry black (LcdBlack). Nothing the firmware draws reaches FB8.
#
# The ambilight: the LCD around the window (the 128-pixel strips beside the 384x240 window, or the 160-pixel strips
# and the 20-row bands around the 320x200 one) holds entries 16-255, drawn once for each window size (AmbiFill) and
# never again: 2 sides x 8 bands of rows x 15 levels of brightness, the first level beside the window. A pixel's
# level follows its distance from the window, plus a random -1 to +2 levels, and its band its row, plus a random
# offset of up to a band either way; above and below the window a pixel takes the right side's colours with a
# chance that grows across the window's width: so neither the levels, nor the bands, nor the two sides show as
# edges, the dither mixing them along and across (AmbPixel). For every page shown, AmbiUpdate takes, for each side and band, the colours of the window's
# quarter on that side in those rows (every 4th pixel of every 2nd row), their average colour, half way from the one
# before (a little smoothing), and writes its 15 levels into the entries that changed: the brightest at 0.9 of it, the
# others falling off as the square of the distance, to black at the far edge.

# LcdOwn: the LCD for the game (DisplayInit). Once.
LcdOwn:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (LCD_OWNED), d0
    cmp     0, d0
    bne     lco_ret
    movbu   (LCDC + 0x40), d0       # the firmware's settings, for LcdRelease
    movbu   d0, (LCD_SAVE + 0)
    movbu   (LCDC + 0x42), d0
    movbu   d0, (LCD_SAVE + 1)
    movbu   (LCDC + 0x43), d0
    movbu   d0, (LCD_SAVE + 2)
    movbu   (LCDC + 0x44), d0
    movbu   d0, (LCD_SAVE + 3)
    movbu   (LCDC + 0x46), d0
    movbu   d0, (LCD_SAVE + 4)
    movbu   (LCDC + 0x47), d0
    movbu   d0, (LCD_SAVE + 5)
    call    LutBlack, 0, 0          # everything black until the game's palette and the ambilight are set
    mov     1, d0                   # but the loading screen's text (entry 1)
    mov     LOAD_TEXT_COL, d1
    call    LutSet, 0, 0
    mov     FB8, a0                 # the frame: entry 0 everywhere (the border's pattern: the first blit's)
    mov     FB8_STRIDE * FB_H / 32, d1
    clr     d0
    call    fb_run, 0, 0
    clr     d0
    mov     d0, (AMB_GEOM)
    call    LcdSet, 0, 0
    mov     1, d0
    mov     d0, (LCD_OWNED)
    mov     d0, (LOAD_ON)
    mov     -1, d0
    mov     d0, (LOAD_PCT)
lco_ret:
    ret     [d2,d3,a2,a3], 0x20

# LcdSet: the controller on FB8: lines of 320 words, 8 bits a pixel (the firmware's SwivelView kept), FB8's start.
# Leaf (LcdStart's).
LcdSet:
    mov     0x40, d0                # 320 words = 0x0140: FB8_STRIDE / 2
    movbu   d0, (LCDC + 0x46)
    mov     0x01, d0
    movbu   d0, (LCDC + 0x47)
    movbu   (LCD_SAVE + 0), d0
    and     0xF8, d0
    or      3, d0
    movbu   d0, (LCDC + 0x40)
    mov     FB8_START, d0
    bra     LcdStart

# LcdRelease: the firmware's settings back, and its picture with them (cnv_main.s at the quit; fwdraw.s when the
# firmware stops calling). Leaf (LcdStart's).
LcdRelease:
    mov     (LCD_OWNED), d0
    cmp     0, d0
    beq     lcr_ret
    clr     d0
    mov     d0, (LCD_OWNED)
    movbu   (LCD_SAVE + 4), d0
    movbu   d0, (LCDC + 0x46)
    movbu   (LCD_SAVE + 5), d0
    movbu   d0, (LCDC + 0x47)
    movbu   (LCD_SAVE + 0), d0
    movbu   d0, (LCDC + 0x40)
    movbu   (LCD_SAVE + 3), d0
    asl     16, d0
    movbu   (LCD_SAVE + 2), d1
    asl     8, d1
    or      d1, d0
    movbu   (LCD_SAVE + 1), d1
    or      d1, d0
    bra     LcdStart
lcr_ret:
    rets

# LcdStart(d0 = start address, words): REG[042h]-[044h], within one of the controller's frames: it latches the
# address as a frame begins, so the bytes go outside the vertical non-display period (REG[03Ah] bit 7, waited out for
# up to 2000 reads), with interrupts off, the low two as one 16-bit write (Pinball's writeStart, from what the unit
# showed). Leaf; uses d0, d1, a0, a1.
LcdStart:
    mov     d0, a1
    mov     2000, d1
lcs_spin:
    movbu   (LCDC + 0x3A), d0
    btst    0x80, d0
    beq     lcs_go
    add     -1, d1
    bne     lcs_spin
lcs_go:
    mov     psw, d0
    mov     d0, a0
    and     0xF7FF, psw
    nop
    nop
    mov     a1, d1
    movhu   d1, (LCDC + 0x42)
    lsr     16, d1
    movbu   d1, (LCDC + 0x44)
    mov     a0, d0
    mov     d0, psw
    nop
lcs_ret:
    rets

# LcdCheck: is the controller still on FB8 (8 bits a pixel, FB8's start)? If something else set it, set it back and
# repaint the window (perf.s PerfSentinels). Leaf (LcdSet's).
LcdCheck:
    mov     (LCD_OWNED), d0
    cmp     0, d0
    beq     lcs_ret
    movbu   (LCDC + 0x40), d0
    and     7, d0
    cmp     3, d0
    bne     lck_bad
    movhu   (LCDC + 0x42), d0
    cmp     0xABFF, d0              # FB8_START's low 16 bits (240639 = 0x3ABFF)
    bne     lck_bad
    rets
lck_bad:
    mov     (PF_DAMAGE), d0
    or      PFD_SENTINEL, d0
    mov     d0, (PF_DAMAGE)
    mov     (PF_SENT_BAD), d0
    inc     d0
    mov     d0, (PF_SENT_BAD)
    bra     LcdSet

# LutSet(d0 = entry, d1 = colour 0x0RGB, 4 bits each): one look-up table entry. Leaf; uses d0.
LutSet:
    movbu   d0, (LCDC + 0x1E2)
    mov     d1, d0
    lsr     4, d0
    and     0xF0, d0
    movbu   d0, (LCDC + 0x1E4)      # red
    mov     d1, d0
    and     0xF0, d0
    movbu   d0, (LCDC + 0x1E4)      # green
    mov     d1, d0
    asl     4, d0
    and     0xF0, d0
    movbu   d0, (LCDC + 0x1E4)      # blue
    rets

# LutBlack: all 256 entries black, and what was written to them forgotten (PF_PAL, AMB_LUT), so that the next blit's
# PalCheck and AmbiUpdate write them all again. Leaf.
LutBlack:
    clr     d0
    movbu   d0, (LCDC + 0x1E0)      # (the look-up table's mode: written as the LCD's; Pinball's)
    movbu   d0, (LCDC + 0x1E2)
    mov     768, d1
lbk_lut:
    movbu   d0, (LCDC + 0x1E4)
    add     -1, d1
    bne     lbk_lut
    mov     -1, d0
    mov     PF_PAL, a0
    mov     8, d1
lbk_pal:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     lbk_pal
    mov     AMB_LUT, a0
    mov     (2 * 240) / 4, d1
lbk_amb:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     lbk_amb
    rets

# LcdBlack: the whole LCD black while a part loads (cnv_main.s EnsurePart): every entry black, but the loading
# screen's text while it shows (the first part's load). The frame is not touched; the next blit puts the palette
# and the ambilight back.
LcdBlack:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    LutBlack, 0, 0
    mov     (LOAD_ON), d0
    cmp     0, d0
    beq     lbl_ret
    mov     1, d0
    mov     LOAD_TEXT_COL, d1
    call    LutSet, 0, 0
lbl_ret:
    ret     [d2,d3,a2,a3], 0x20

# LoadShow(d0 = 0..100): the loading screen's "Loading... NN%", when it shows and the number changed: 16x16 letters
# (the game's 8x8 font, each dot 2x2: the image's copy, LoadFont, there from the first call; until 2026-11-04 AW_FONT,
# which the global files fill only after the firmware search, so that the line showed only from 5 %) in entry 1, in the middle of the LCD, inside either window (the game's first
# blit writes over it). The firmware's own screen is not shown: the LCD is the game's from its first call
# (cnv_main.s), so nothing of the instrument's interface shows while the game loads.
LoadShow:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (LOAD_ON), d1
    cmp     0, d1
    beq     lsh_ret
    mov     (LCD_OWNED), d1
    cmp     0, d1
    beq     lsh_ret
    cmp     100, d0
    bls     lsh_pct
    mov     100, d0
lsh_pct:
    mov     (LOAD_PCT), d1
    cmp     d1, d0
    beq     lsh_ret
    mov     d0, (LOAD_PCT)
    mov     d0, d2
    mov     LOAD_LINE, a0           # "Loading... NN%" into the line buffer
    mov     load_text, a1
lsh_cpy:
    movbu   (a1), d0
    cmp     0, d0
    beq     lsh_num
    movbu   d0, (a0)
    inc     a0
    inc     a1
    bra     lsh_cpy
lsh_num:
    cmp     100, d2
    bcs     lsh_lt100
    mov     0x31, d0                # "100"
    movbu   d0, (a0)
    mov     0x30, d0
    movbu   d0, (1, a0)
    movbu   d0, (2, a0)
    add     3, a0
    bra     lsh_sign
lsh_lt100:
    mov     d2, d0
    clr     d1
    mov     d1, mdr
    mov     10, d1
    divu    d1, d0                  # d0 = tens, mdr = units
    add     0x30, d0
    cmp     0x30, d0
    bne     lsh_tens
    mov     0x20, d0                # one digit: a space before it
lsh_tens:
    movbu   d0, (a0)
    mov     mdr, d0
    add     0x30, d0
    movbu   d0, (1, a0)
    add     2, a0
lsh_sign:
    mov     0x25, d0                # "%"
    movbu   d0, (a0)
    inc     a0
    clr     d0
    movbu   d0, (a0)
    mov     FB8 + LOAD_Y * FB8_STRIDE + LOAD_X, a0   # the line's area black (entry 0)
    mov     16, d2
lsh_clr:
    mov     a0, a1
    mov     LOAD_CHARS * 16 / 4, d1
    clr     d0
lsh_clrw:
    mov     d0, (a1)
    add     4, a1
    add     -1, d1
    bne     lsh_clrw
    add     FB8_STRIDE, a0
    add     -1, d2
    bne     lsh_clr
    mov     LOAD_LINE, a2           # the letters
    mov     FB8 + LOAD_Y * FB8_STRIDE + LOAD_X, a3
lsh_char:
    movbu   (a2), d0
    cmp     0, d0
    beq     lsh_ret
    inc     a2
    add     -0x20, d0
    asl     3, d0
    mov     LoadFont, a0            # (the image's copy: AW_FONT is loaded only after the firmware search)
    add     d0, a0                  # the glyph's 8 rows
    mov     a3, a1
    mov     8, d3
lsh_row:
    movbu   (a0), d2
    inc     a0
    mov     8, d1
lsh_dot:
    btst    0x80, d2
    beq     lsh_nodot
    mov     0x0101, d0              # 2x2 of entry 1
    movhu   d0, (a1)
    movhu   d0, (FB8_STRIDE, a1)
lsh_nodot:
    asl     1, d2
    add     2, a1
    add     -1, d1
    bne     lsh_dot
    add     2 * FB8_STRIDE - 16, a1
    add     -1, d3
    bne     lsh_row
    add     16, a3
    bra     lsh_char
lsh_ret:
    ret     [d2,d3,a2,a3], 0x30

load_text:
    .asciz  "Loading... "
    .align  4

# AmbRand -> d0: the next of a xorshift32 sequence (the dither). Leaf; uses d1.
AmbRand:
    mov     (AMB_RNG), d0
    cmp     0, d0
    bne     arn_go
    mov     0x2545F491, d0
arn_go:
    mov     d0, d1
    asl     13, d1
    xor     d1, d0
    mov     d0, d1
    lsr     17, d1
    xor     d1, d0
    mov     d0, d1
    asl     5, d1
    xor     d1, d0
    mov     d0, (AMB_RNG)
    rets

.equ AMB_X0,          LCD8_VARS + 0x2A0   # the window: x X0 .. X1-1, y Y0 .. Y1-1 (AmbiFill's)
.equ AMB_X1,          LCD8_VARS + 0x2A4
.equ AMB_Y0,          LCD8_VARS + 0x2A8
.equ AMB_Y1,          LCD8_VARS + 0x2AC
.equ AMB_DMAX,        LCD8_VARS + 0x2B0   # the farthest distance from it
.equ AMB_H,           LCD8_VARS + 0x2B4   # its rows
.equ AMB_SECH,        LCD8_VARS + 0x2B8   # a band's rows
.equ AMB_WIDTH,       LCD8_VARS + 0x2BC   # the window's width

# AmbiFill: the border's pattern for the window size now (PG_W), every byte of FB8 outside the window (AmbPixel's).
# Four pixels a 32-bit store: the windows' edges are on multiples of 4.
AmbiFill:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (PG_W), d0
    cmp     BIG_W, d0
    bne     afl_orig
    mov     BIG_X0, d0
    mov     d0, (AMB_X0)
    mov     BIG_X0 + BIG_W, d0
    mov     d0, (AMB_X1)
    clr     d0
    mov     d0, (AMB_Y0)
    mov     BIG_H, d0
    mov     d0, (AMB_Y1)
    mov     d0, (AMB_H)
    mov     BIG_X0, d0              # the strips' width
    mov     d0, (AMB_DMAX)
    bra     afl_go
afl_orig:
    mov     AW_X0, d0
    mov     d0, (AMB_X0)
    mov     AW_X0 + AW_W, d0
    mov     d0, (AMB_X1)
    mov     AW_Y0, d0
    mov     d0, (AMB_Y0)
    mov     AW_Y0 + AW_H, d0
    mov     d0, (AMB_Y1)
    mov     AW_H, d0
    mov     d0, (AMB_H)
    mov     AW_X0 + AW_Y0 / 2, d0   # a corner's distance (max + min / 2)
    mov     d0, (AMB_DMAX)
afl_go:
    mov     (AMB_H), d0
    lsr     3, d0
    mov     d0, (AMB_SECH)
    mov     (AMB_X1), d0
    mov     (AMB_X0), d1
    sub     d1, d0
    mov     d0, (AMB_WIDTH)
    clr     d3                      # d3 = y
afl_row:
    mov     d3, d0
    mov     FB8_STRIDE, d1
    mulu    d1, d0
    mov     FB8, a3
    add     d0, a3                  # a3 = the row
    clr     d2                      # d2 = x, 4 at a time
afl_word:
    mov     (AMB_Y0), d0
    cmp     d0, d3
    blt     afl_out
    mov     (AMB_Y1), d0
    cmp     d0, d3
    bge     afl_out
    mov     (AMB_X0), d0
    cmp     d0, d2
    blt     afl_out
    mov     (AMB_X1), d0
    cmp     d0, d2
    blt     afl_next                # the window
afl_out:
    clr     d0
    mov     d0, (0x10, sp)          # the four pixels' entries
    mov     d0, (0x14, sp)          # k
afl_px:
    mov     (0x14, sp), d0
    add     d2, d0
    mov     d3, d1
    call    AmbPixel, 0, 0
    mov     (0x14, sp), d1
    asl     3, d1
    asl     d1, d0
    mov     (0x10, sp), d1
    or      d0, d1
    mov     d1, (0x10, sp)
    mov     (0x14, sp), d0
    inc     d0
    mov     d0, (0x14, sp)
    cmp     4, d0
    bne     afl_px
    mov     (0x10, sp), d0
    mov     d0, (d2, a3)
afl_next:
    add     4, d2
    cmp     FB8_STRIDE, d2
    bne     afl_word
    inc     d3
    cmp     FB_H, d3
    bne     afl_row
    mov     (PG_W), d0
    mov     d0, (AMB_GEOM)
    ret     [d2,d3,a2,a3], 0x30

# AmbPixel(d0 = x, d1 = y, outside the window) -> d0 = its entry: AMB_BASE + (side * 8 + band) * 15 + level. The
# distance d = the larger of its distances across and down from the window, plus half the smaller (1 beside it);
# level = (d - 1) * 15 / DMAX plus a random offset, the sum of three random fractions less 1 (-1 .. +2, most often
# near +0.5), rounded down, within 0..14; band = its row plus a random offset, the sum of two random fractions of a
# band less one band (-1 .. +1 band, most often near 0), within the window's rows, in eighths of them; side: left of
# the window the left, right of it the right, and above or below it the right with a chance that grows from 0 to 1
# across the window's width, so that the two sides' colours mix over the whole band with no seam (Felipe, 2026-11-02).
AmbPixel:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x18, sp
    mov     d0, d2                  # x
    mov     d1, d3                  # y
    clr     d0                      # across
    mov     (AMB_X0), d1
    cmp     d1, d2
    bge     apx_x1
    mov     d1, d0
    sub     d2, d0                  # X0 - x
    bra     apx_ax
apx_x1:
    mov     (AMB_X1), d1
    cmp     d1, d2
    blt     apx_ax
    mov     d2, d0
    sub     d1, d0
    inc     d0                      # x - X1 + 1
apx_ax:
    mov     d0, a2                  # a2 = across
    clr     d0                      # down
    mov     (AMB_Y0), d1
    cmp     d1, d3
    bge     apx_y1
    mov     d1, d0
    sub     d3, d0
    bra     apx_ad
apx_y1:
    mov     (AMB_Y1), d1
    cmp     d1, d3
    blt     apx_ad
    mov     d3, d0
    sub     d1, d0
    inc     d0
apx_ad:
    mov     a2, d1                  # d0 = down, d1 = across
    cmp     d1, d0
    bge     apx_big
    mov     d0, a2                  # (swap: d0 the larger)
    mov     d1, d0
    mov     a2, d1
apx_big:
    lsr     1, d1
    add     d1, d0                  # d
    mov     d0, a2                  # a2 = d
    call    AmbRand, 0, 0
    mov     d0, a3                  # a3 = random bits: bytes 0-2 the level's, byte 3 the side's
    mov     a2, d0                  # level, x 256 = (d - 1) * 15 * 256 / DMAX
    add     -1, d0
    mov     AMB_LVLS * 256, d1
    mulu    d1, d0
    clr     d1
    mov     d1, mdr
    mov     (AMB_DMAX), d1
    divu    d1, d0
    mov     a3, d1                  # + three random bytes - 255
    and     0xFF, d1
    add     d1, d0
    mov     a3, d1
    lsr     8, d1
    and     0xFF, d1
    add     d1, d0
    mov     a3, d1
    lsr     16, d1
    and     0xFF, d1
    add     d1, d0
    add     -255, d0
    cmp     0, d0
    bge     apx_lpos
    clr     d0
apx_lpos:
    lsr     8, d0
    cmp     AMB_LVLS - 1, d0
    bls     apx_lvl
    mov     AMB_LVLS - 1, d0
apx_lvl:
    mov     d0, (0x10, sp)          # level
    call    AmbRand, 0, 0           # the band's row: y + (r % SECH) + (r' % SECH) - SECH
    mov     d0, (0x14, sp)
    and     0xFFFF, d0
    clr     d1
    mov     d1, mdr
    mov     (AMB_SECH), d1
    divu    d1, d0
    mov     mdr, d0
    mov     d0, a2
    mov     (0x14, sp), d0
    lsr     16, d0
    clr     d1
    mov     d1, mdr
    mov     (AMB_SECH), d1
    divu    d1, d0
    mov     mdr, d0
    mov     a2, d1
    add     d1, d0
    mov     (AMB_SECH), d1
    sub     d1, d0
    add     d3, d0
    mov     (AMB_Y0), d1
    cmp     d1, d0
    bge     apx_ylo
    mov     d1, d0
apx_ylo:
    mov     (AMB_Y1), d1
    add     -1, d1
    cmp     d1, d0
    ble     apx_yhi
    mov     d1, d0
apx_yhi:
    mov     (AMB_Y0), d1
    sub     d1, d0
    asl     3, d0
    clr     d1
    mov     d1, mdr
    mov     (AMB_H), d1
    divu    d1, d0                  # band 0..7
    mov     d0, a2                  # a2 = band
    mov     (AMB_X0), d1            # the side
    cmp     d1, d2
    blt     apx_left
    mov     (AMB_X1), d0
    cmp     d0, d2
    bge     apx_right
    mov     d2, d0                  # above or below the window: right when a random byte < (x - X0) * 256 / width
    sub     d1, d0
    asl     8, d0
    clr     d1
    mov     d1, mdr
    mov     (AMB_WIDTH), d1
    divu    d1, d0                  # t, of 256
    mov     a3, d1
    lsr     24, d1
    cmp     d0, d1
    bcs     apx_right
apx_left:
    mov     a2, d0
    bra     apx_entry
apx_right:
    mov     a2, d0
    add     AMB_SECS, d0
apx_entry:
    mov     AMB_LVLS, d1
    mulu    d1, d0
    mov     (0x10, sp), d1
    add     d1, d0
    add     AMB_BASE, d0
    ret     [d2,d3,a2,a3], 0x28

# AmbiUpdate(a0 = the page just shown, a1 = the palette it is shown in): each side's and band's colour, and its 15
# entries where they changed; with the ambilight off (prefs.s PR_AMBI), black. The levels' brightness: the light
# scatter setting's table (PR_REACH).
AmbiUpdate:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x38, sp
    mov     a0, (0x10, sp)          # the page
    mov     a1, (0x34, sp)          # its palette
    clr     d0
    mov     d0, (0x14, sp)          # g = side * 8 + band
aup_region:
    mov     AMB_HIST, a0
    mov     16, d1
    clr     d0
aup_hclr:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     aup_hclr
    mov     (0x14, sp), d2
    and     7, d2                   # band
    mov     (PG_H), d0
    mulu    d2, d0
    lsr     3, d0
    mov     d0, (0x18, sp)          # first row
    mov     d2, d0
    inc     d0
    mov     (PG_H), d1
    mulu    d1, d0
    lsr     3, d0
    mov     d0, (0x1C, sp)          # past the last
    clr     d0                      # the window's quarter on this side: its first column
    mov     (0x14, sp), d1
    cmp     AMB_SECS, d1
    blt     aup_c0
    mov     (PG_W), d0
    mov     d0, d1
    lsr     2, d1
    sub     d1, d0
aup_c0:
    mov     d0, (0x20, sp)
    clr     d0
    mov     d0, (0x24, sp)          # samples
    mov     AMB_HIST, a3
aup_row:
    mov     (0x18, sp), d0
    mov     (PG_W), d1
    mulu    d1, d0
    mov     (0x10, sp), a2
    add     d0, a2
    mov     (0x20, sp), d0
    add     d0, a2                  # a2 = the row's first sample
    mov     (PG_W), d2
    lsr     4, d2                   # a quarter of the row, every 4th pixel
    mov     (0x24, sp), d3
    add     d2, d3
    mov     d3, (0x24, sp)
aup_px:
    movbu   (a2), d0
    and     15, d0
    asl     2, d0
    mov     (d0, a3), d1
    inc     d1
    mov     d1, (d0, a3)
    add     4, a2
    add     -1, d2
    bne     aup_px
    mov     (0x18, sp), d0
    add     2, d0
    mov     d0, (0x18, sp)
    mov     (0x1C, sp), d1
    cmp     d1, d0
    blt     aup_row
    clr     d0                      # the counts' colours, summed per channel (4 bits each)
    mov     d0, (0x28, sp)
    mov     d0, (0x2C, sp)
    mov     d0, (0x30, sp)
    mov     (0x34, sp), a2
    clr     d2
aup_sum:
    mov     d2, d0
    asl     2, d0
    mov     (d0, a3), d3            # this colour's count
    cmp     0, d3
    beq     aup_snext
    mov     d2, d0
    asl     1, d0
    movhu   (d0, a2), d1            # its RGB565
    mov     d1, d0
    lsr     12, d0
    and     15, d0
    mulu    d3, d0
    mov     d0, a0
    mov     (0x28, sp), d0
    add     a0, d0
    mov     d0, (0x28, sp)
    mov     d1, d0
    lsr     7, d0
    and     15, d0
    mulu    d3, d0
    mov     d0, a0
    mov     (0x2C, sp), d0
    add     a0, d0
    mov     d0, (0x2C, sp)
    mov     d1, d0
    lsr     1, d0
    and     15, d0
    mulu    d3, d0
    mov     d0, a0
    mov     (0x30, sp), d0
    add     a0, d0
    mov     d0, (0x30, sp)
aup_snext:
    inc     d2
    cmp     16, d2
    bne     aup_sum
    mov     (0x14, sp), d0          # a2 = this band's colour now
    mov     6, d1
    mulu    d1, d0
    mov     AMB_CUR, a2
    add     d0, a2
    mov     (0x28, sp), d0
    mov     (0x24, sp), d1
    mov     a2, a0
    call    AmbChan, 0, 0
    mov     (0x2C, sp), d0
    mov     (0x24, sp), d1
    mov     a2, a0
    add     2, a0
    call    AmbChan, 0, 0
    mov     (0x30, sp), d0
    mov     (0x24, sp), d1
    mov     a2, a0
    add     4, a0
    call    AmbChan, 0, 0
    clr     d2                      # the 15 levels
aup_lvl:
    movbu   (PR_REACH), d0          # this level's brightness, of 256, in the scatter setting's table
    asl     4, d0
    mov     amb_bright, a0
    add     d0, a0
    movbu   (d2, a0), d3
    movhu   (a2), d0
    mov     d3, d1
    call    AmbLevel, 0, 0
    asl     8, d0
    mov     d0, (0x28, sp)
    movhu   (2, a2), d0
    mov     d3, d1
    call    AmbLevel, 0, 0
    asl     4, d0
    mov     (0x28, sp), d1
    or      d1, d0
    mov     d0, (0x28, sp)
    movhu   (4, a2), d0
    mov     d3, d1
    call    AmbLevel, 0, 0
    mov     (0x28, sp), d1
    or      d0, d1                  # d1 = the entry's colour
    movbu   (PR_AMBI), d0           # (black with the ambilight off)
    cmp     0, d0
    bne     aup_on
    clr     d1
aup_on:
    mov     (0x14, sp), d0          # its index among the ambilight's: g * 15 + level
    mov     AMB_LVLS, d3
    mulu    d3, d0
    add     d2, d0
    mov     AMB_LUT, a1
    add     d0, a1
    add     d0, a1
    movhu   (a1), d3
    cmp     d1, d3
    beq     aup_lnext
    movhu   d1, (a1)
    add     AMB_BASE, d0
    call    LutSet, 0, 0
aup_lnext:
    inc     d2
    cmp     AMB_LVLS, d2
    bne     aup_lvl
    mov     (0x14, sp), d0
    inc     d0
    mov     d0, (0x14, sp)
    cmp     2 * AMB_SECS, d0
    bne     aup_region
    ret     [d2,d3,a2,a3], 0x48

# AmbChan(d0 = a channel's sum, d1 = samples, a0 = that channel's colour now, u16): the colour now goes half way to
# the samples' average (4 bits x 256). Leaf; uses a1.
AmbChan:
    asl     8, d0
    mov     d1, a1
    clr     d1
    mov     d1, mdr
    mov     a1, d1
    divu    d1, d0
    movhu   (a0), d1
    add     d1, d0
    lsr     1, d0
    movhu   d0, (a0)
    rets

# AmbLevel(d0 = a channel, 4 bits x 256; d1 = brightness, of 256) -> d0 = 0..15. Leaf.
AmbLevel:
    mulu    d1, d0
    lsr     8, d0
    add     128, d0
    lsr     8, d0
    cmp     15, d0
    bls     alv_ret
    mov     15, d0
alv_ret:
    rets

# the levels' brightness, of 256: 230 x ((15 - level) / 15)^p, a table of 16 bytes for each light scatter setting
# (prefs.s PR_REACH): p = 4 short, 2 medium, 1 long (the default), 0.5 very long
amb_bright:
    .byte   230, 175, 130, 94, 67, 45, 30, 19, 11, 6, 3, 1, 0, 0, 0, 0
    .byte   230, 200, 173, 147, 124, 102, 83, 65, 50, 37, 26, 16, 9, 4, 1, 0
    .byte   230, 215, 199, 184, 169, 153, 138, 123, 107, 92, 77, 61, 46, 31, 15, 0
    .byte   230, 222, 214, 206, 197, 188, 178, 168, 157, 145, 133, 119, 103, 84, 59, 0
    .align  4
