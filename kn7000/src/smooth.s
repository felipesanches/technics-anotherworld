# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# smooth.s -- the bitmaps' bilinear enlargement (README-CNV.md, "Settings"; Felipe 2026-11-03): with BITMAP FILTER
# set to BILINEAR, a 320x200 bitmap shown at 384x240 is enlarged by bilinear interpolation instead of by repeating
# pixels. The game's pages hold 16 palette indices and the LCD's other 240 look-up table entries are the ambilight's,
# so each blended colour becomes the nearest of the game's 16 colours (Felipe's choice), in the palette it is shown
# with.
#
# That palette is often set after the bitmap is loaded (part 0x3E83 loads bitmap 0x49, then sets palette 0x19), so
# LoadBitmap still enlarges by repeating pixels (display.s PageUp), notes which indices the picture uses (SM_USED)
# and marks page 0 pending (SM_PEND, a bit a page); a plain copy of a pending page makes its destination pending too
# (the same pixels). The pending pages are smoothed in place, in the palette set then, at the first of: a palette set
# (OpSetPalette), a frame shown (UpdateDisplay), drawing on the page (a polygon or a string: SmDraw), or a scrolled
# copy from it; but only in a palette that tells apart every index the picture uses (SmReady): a fade's darker steps
# merge colours (the splash fades in from palette 0, all black, through 0x1A, 0x19 ...), and a mix's nearest colour
# taken in one of them would stay wrong once the fade is over. So the first two wait for a later palette, the last
# two leave that page as it is. A fill or another copy over a pending page, a part's start and a change of the
# resolution forget it.
#
# SmSmooth: output pixel (x, y) samples source ((10x - 1) / 12, (10y - 1) / 12) (pixel centres: (x + 1/2) x 5/6 -
# 1/2; at least 0), its four neighbours weighted in twelfths; when the four are the same index, that index, else
# their red, green and blue (4 bits each, as the palette's) mixed, rounded to 4 bits, and the nearest of the 16
# colours (squared distance, the lowest index on a tie; SM_LUT keeps each mix's answer). The source is read back
# from the page itself (source pixel s is at page pixel ceil(6s/5), PageUp's inverse), each source row into a ring of
# four (SM_RING) before the output overwrites its page row. probes/smoothcheck.py is the same in Python.

.equ SM_RW,           324            # a ring row: 320 pixels, a copy of the last (x1 of x0 = 319), padding

# SmLoaded: LoadBitmap has drawn a bitmap into page 0: pending, with the indices it uses, when the filter is on and
# the pages are 384x240.
SmLoaded:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (SM_PEND), d0
    and     0xE, d0
    mov     d0, (SM_PEND)
    clr     d0
    call    SmForget, 0, 0          # page 0 holds a new picture: no copy is the same as it
    movbu   (PR_SMOOTH), d1
    cmp     0, d1
    beq     sml_ret
    mov     (PG_W), d1
    cmp     BIG_W, d1
    bne     sml_ret
    mov     PAGE_BITMAP_0, a0
    call    SmScan, 0, 0
    mov     d0, (SM_USED)
    mov     (SM_PEND), d0
    or      1, d0
    mov     d0, (SM_PEND)
sml_ret:
    ret     [d2,d3,a2,a3], 0x20

# SmScan(a0 = a page) -> d0 = the indices it uses, a bit each (four pixels a word).
SmScan:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     sp, a1
    add     8, a1                   # a1 = 16 flags
    clr     d0
    mov     d0, (a1)
    mov     d0, (4, a1)
    mov     d0, (8, a1)
    mov     d0, (12, a1)
    mov     a0, a2
    mov     (PG_SIZE), d2
    lsr     2, d2
    mov     1, d1
ssc_word:
    mov     (a2), d3
    mov     d3, d0
    and     15, d0
    movbu   d1, (d0, a1)
    lsr     8, d3
    mov     d3, d0
    and     15, d0
    movbu   d1, (d0, a1)
    lsr     8, d3
    mov     d3, d0
    and     15, d0
    movbu   d1, (d0, a1)
    lsr     8, d3
    and     15, d3
    movbu   d1, (d3, a1)
    add     4, a2
    add     -1, d2
    bne     ssc_word
    clr     d0                      # the flags to bits
    mov     15, d2
ssc_bit:
    asl     1, d0
    movbu   (d2, a1), d1
    or      d1, d0
    add     -1, d2
    bge     ssc_bit
    ret     [d2,d3,a2,a3], 0x30

# SmIdx(a0 = a page) -> d0 = its number, 0-3, or 4: not one of the four pages. Leaf; uses d0, d1.
SmIdx:
    mov     a0, d0
    mov     PAGE_BITMAP_0, d1
    sub     d1, d0
    bcs     sid_no
    clr     d1
    mov     d1, mdr
    mov     PAGE_STRIDE, d1
    divu    d1, d0
    cmp     4, d0
    bcs     sid_ret
sid_no:
    mov     4, d0
sid_ret:
    rets

# SmBit(a0 = a page) -> d0 = its bit in SM_PEND (0: not one of the four pages). Uses d0, d1.
SmBit:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    SmIdx, 0, 0
    mov     d0, d1
    mov     1, d0
    asl     d1, d0
    and     15, d0
    ret     [d2,d3,a2,a3], 0x20

# SmClear(a0 = a page): not pending (a fill wrote it).
SmClear:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2
    call    SmIdx, 0, 0
    call    SmForget, 0, 0
    mov     a2, a0
    call    SmBit, 0, 0
    not     d0
    mov     (SM_PEND), d1
    and     d0, d1
    mov     d1, (SM_PEND)
    ret     [d2,d3,a2,a3], 0x20

# SmCopy(a0 = the source page, a1 = the destination, d0 = 1 a plain copy, 0 a scrolled one): before CopyPage copies.
# A plain copy carries the source's mark and its indices; a scrolled one smooths a pending source first and leaves
# the destination unmarked.
SmCopy:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2
    mov     a1, a3
    mov     d0, d2
    mov     a3, a0                  # the destination is overwritten: no page is the same as it
    call    SmIdx, 0, 0
    call    SmForget, 0, 0
    mov     a2, a0
    call    SmBit, 0, 0
    mov     d0, d3                  # d3 = the source's bit
    mov     a3, a0
    call    SmBit, 0, 0
    not     d0
    mov     (SM_PEND), d1
    and     d0, d1                  # the destination's bit cleared
    mov     d1, (SM_PEND)
    mov     d3, d0
    and     d1, d0
    beq     scp_ret                 # (the source not pending)
    cmp     0, d2
    beq     scp_scroll
    mov     a2, a0                  # plain: the destination pending too, with the source's indices
    call    SmIdx, 0, 0
    asl     2, d0
    mov     SM_USED, a0
    add     d0, a0
    mov     (a0), d2
    mov     a3, a0
    call    SmIdx, 0, 0
    asl     2, d0
    mov     SM_USED, a0
    add     d0, a0
    mov     d2, (a0)
    mov     a2, a0                  # and the same picture as the source's (or as what the source is a copy of)
    call    SmIdx, 0, 0
    mov     SM_SAME, a0
    movbu   (d0, a0), d1
    cmp     0xFF, d1
    beq     scp_root
    mov     d1, d0
scp_root:
    mov     d0, d2
    mov     a3, a0
    call    SmIdx, 0, 0
    mov     SM_SAME, a0
    movbu   d2, (d0, a0)
    mov     a3, a0
    call    SmBit, 0, 0
    mov     (SM_PEND), d1
    or      d0, d1
    mov     d1, (SM_PEND)
    bra     scp_ret
scp_scroll:
    not     d3
    mov     (SM_PEND), d1
    and     d3, d1
    mov     d1, (SM_PEND)
    mov     a2, a0
    call    SmIdx, 0, 0
    call    SmForget, 0, 0
    mov     a2, a0
    call    SmPage, 0, 0
scp_ret:
    ret     [d2,d3,a2,a3], 0x20

# SmDraw: before a polygon or a string is drawn on the work page (CUR_PAGE_1): smooth it first when pending. Keeps d0
# and d1 (the opcode, the string's id).
SmDraw:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, (0x04, sp)
    mov     d1, (0x08, sp)
    mov     (SM_PEND), d0
    cmp     0, d0
    beq     sdr_ret
    mov     (CUR_PAGE_1), a0
    call    SmBit, 0, 0
    mov     (SM_PEND), d1
    mov     d0, d2
    and     d1, d2
    beq     sdr_ret
    not     d0
    and     d0, d1
    mov     d1, (SM_PEND)
    mov     (CUR_PAGE_1), a0
    call    SmIdx, 0, 0
    call    SmForget, 0, 0
    mov     (CUR_PAGE_1), a0
    call    SmPage, 0, 0
sdr_ret:
    mov     (0x04, sp), d0
    mov     (0x08, sp), d1
    ret     [d2,d3,a2,a3], 0x20

# SmReady(a0 = a page) -> d0 = 1 when the palette tells apart every index its picture uses (SM_USED), else 0.
SmReady:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    SmIdx, 0, 0
    asl     2, d0
    mov     SM_USED, a0
    add     d0, a0
    mov     (a0), d0
    mov     d0, (0x04, sp)          # the indices used
    mov     palette, a2
    clr     d2                      # d2 = i
srd_i:
    mov     (0x04, sp), d0
    lsr     d2, d0
    btst    1, d0
    beq     srd_inext
    mov     d2, d0
    asl     1, d0
    movhu   (d0, a2), d1            # d1 = colour i
    mov     d2, d3                  # d3 = j, from i + 1
srd_j:
    inc     d3
    cmp     16, d3
    beq     srd_inext
    mov     (0x04, sp), d0
    lsr     d3, d0
    btst    1, d0
    beq     srd_j
    mov     d3, d0
    asl     1, d0
    movhu   (d0, a2), d0
    cmp     d1, d0
    bne     srd_j
    clr     d0                      # two used indices, one colour
    bra     srd_ret
srd_inext:
    inc     d2
    cmp     16, d2
    bne     srd_i
    mov     1, d0
srd_ret:
    ret     [d2,d3,a2,a3], 0x20

# SmAll: every pending page smoothed (a palette set, a frame shown), each once the palette tells its colours apart
# (SmReady); until then it waits. A page that is a plain copy of another (SM_SAME) still holding the same picture
# gets that one's smoothed pixels, copied, instead of being smoothed again.
SmAll:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (SM_PEND), d0
    cmp     0, d0
    beq     sma_ret
    clr     d3                      # d3 = the pages smoothed now, a bit each
    clr     d2                      # first the pages that are no copy, then the copies
sma_page:
    mov     d2, d0
    and     3, d0
    mov     (SM_PEND), d1
    lsr     d0, d1
    btst    1, d1
    beq     sma_next
    mov     SM_SAME, a0
    movbu   (d0, a0), d1            # d1 = the page it is a copy of (0xFF: none)
    cmp     4, d2
    bcc     sma_copy
    cmp     0xFF, d1                # first round: no copy
    bne     sma_next
    bra     sma_do
sma_copy:
    cmp     0xFF, d1                # second round: copies; of a page smoothed now: its pixels
    beq     sma_next
    mov     d3, d0
    lsr     d1, d0
    btst    1, d0
    beq     sma_do
    mov     d1, d0
    mov     PAGE_STRIDE, d1
    mulu    d1, d0
    mov     PAGE_BITMAP_0, a0
    add     d0, a0                  # a0 = from
    mov     d2, d0
    and     3, d0
    mov     PAGE_STRIDE, d1
    mulu    d1, d0
    mov     PAGE_BITMAP_0, a1
    add     d0, a1                  # a1 = to
    mov     a1, a2
    mov     (PG_SIZE), d1
    lsr     2, d1
sma_cw:
    mov     (a0), d0
    mov     d0, (a1)
    add     4, a0
    add     4, a1
    add     -1, d1
    bne     sma_cw
    bra     sma_done
sma_do:
    mov     d2, d0
    and     3, d0
    mov     PAGE_STRIDE, d1
    mulu    d1, d0
    mov     PAGE_BITMAP_0, a2
    add     d0, a2
    mov     a2, a0
    call    SmReady, 0, 0
    cmp     0, d0
    beq     sma_next
    mov     a2, a0
    call    SmSmooth, 0, 0
    mov     d2, d0
    and     3, d0
    mov     1, d1
    asl     d0, d1
    or      d1, d3
sma_done:
    mov     d2, d0                  # no longer pending, nor a copy of anything
    and     3, d0
    mov     SM_SAME, a0
    mov     0xFF, d1
    movbu   d1, (d0, a0)
    mov     1, d1
    asl     d0, d1
    not     d1
    mov     (SM_PEND), d0
    and     d1, d0
    mov     d0, (SM_PEND)
    mov     a2, a0
    call    PerfMarkDirty, 0, 0
sma_next:
    inc     d2
    cmp     8, d2
    bne     sma_page
sma_ret:
    ret     [d2,d3,a2,a3], 0x20

# SmForget(d0 = a page's number, 0-3; 4: none): it is a copy of nothing, and no page is a copy of it.
SmForget:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    cmp     4, d0
    bcc     sfg_ret
    mov     SM_SAME, a0
    mov     0xFF, d3
    movbu   d3, (d0, a0)
    clr     d2                      # d2 = another page
sfg_loop:
    movbu   (d2, a0), d1
    cmp     d0, d1
    bne     sfg_next
    movbu   d3, (d2, a0)
sfg_next:
    inc     d2
    cmp     4, d2
    bne     sfg_loop
sfg_ret:
    ret     [d2,d3,a2,a3], 0x20

# SmPage(a0 = a page): smoothed now (drawing on it, or a scrolled copy of it, cannot wait), unless the palette does
# not tell its colours apart (SmReady): then left as it is, enlarged by repeating pixels.
SmPage:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2
    call    SmReady, 0, 0
    cmp     0, d0
    beq     smg_ret
    mov     a2, a0
    call    SmSmooth, 0, 0
smg_ret:
    ret     [d2,d3,a2,a3], 0x20

# SmRow(d0 = source row s, a0 = the page): its 320 pixels, from page row ceil(6s/5) (in each six page pixels the
# source's five are at 0, 2, 3, 4, 5), into ring row s mod 4, the last one twice.
SmRow:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    and     3, d2
    mov     SM_RW, d1
    mulu    d1, d2
    mov     SM_RING, a1
    add     d2, a1                  # a1 = the ring row
    mov     6, d1
    mulu    d1, d0
    add     4, d0
    clr     d1
    mov     d1, mdr
    mov     5, d1
    divu    d1, d0
    mov     BIG_W, d1
    mulu    d1, d0
    add     d0, a0                  # a0 = the page row
    mov     AW_W / 5, d2
srw_grp:
    movbu   (a0), d0
    movbu   d0, (a1)
    movbu   (2, a0), d0
    movbu   d0, (1, a1)
    movbu   (3, a0), d0
    movbu   d0, (2, a1)
    movbu   (4, a0), d0
    movbu   d0, (3, a1)
    movbu   (5, a0), d0
    movbu   d0, (4, a1)
    add     6, a0
    add     5, a1
    add     -1, d2
    bne     srw_grp
    movbu   d0, (a1)                # x 320: x 319 again
    ret     [d2,d3,a2,a3], 0x20

# SmSmooth(a0 = a page): smoothed in place (above), in the palette now. Phase PAGE.
# Locals: 0x04 the page, 0x08 y, 0x0C the next source row to read, 0x10 12 - fy, 0x14 fy, 0x18 the output row,
# 0x1C-0x28 a0, a1, a2, d3 kept over a mix, 0x2C fx, 0x30-0x3C the four neighbours, 0x40 the mix's key, 0x44 its LUT
# entry, 0x48 the phase to go back to.
SmSmooth:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x50, sp
    mov     a0, (0x04, sp)
    mov     PH_PAGE, d0
    call    PerfPhase, 0, 0
    mov     d0, (0x48, sp)
    mov     (0x04, sp), a0
    call    PerfMarkDirty, 0, 0
    mov     (PF_DAMAGE), d0         # SHADOW is used here: the blit rebuilds it
    or      PFD_SHADOW, d0
    mov     d0, (PF_DAMAGE)
    mov     palette, a2             # the 16 colours: red << 16 | blue, then green (4 bits each)
    mov     SM_PAL, a3
    mov     16, d2
smo_pal:
    movhu   (a2), d0                # RGB565, each channel the palette's 4 bits shifted up
    mov     d0, d1
    lsr     12, d1
    asl     16, d1
    mov     d0, d3
    lsr     1, d3
    and     15, d3
    or      d3, d1
    mov     d1, (a3)
    lsr     7, d0
    and     15, d0
    mov     d0, (4, a3)
    add     2, a2
    add     8, a3
    add     -1, d2
    bne     smo_pal
    mov     SM_LUT, a2              # no mix's nearest colour known yet
    mov     -1, d0
    mov     4096 / 4, d2
smo_lut:
    mov     d0, (a2)
    add     4, a2
    add     -1, d2
    bne     smo_lut
    clr     d0
    mov     d0, (0x08, sp)          # y
    mov     d0, (0x0C, sp)          # the next source row to read
    mov     (0x04, sp), a0
    mov     a0, (0x18, sp)
smo_row:
    mov     (0x08, sp), d2          # read every source row whose page row is y + 1 or less (at most 239): the
    inc     d2                      # rows this output row and the next need, before they are overwritten
    cmp     BIG_H - 1, d2
    bls     smo_rlim
    mov     BIG_H - 1, d2
smo_rlim:
    mov     (0x0C, sp), d0
    cmp     AW_H, d0
    bcc     smo_rdone
    mov     6, d1                   # its page row: ceil(6s / 5)
    mulu    d1, d0
    add     4, d0
    clr     d1
    mov     d1, mdr
    mov     5, d1
    divu    d1, d0
    cmp     d2, d0
    bhi     smo_rdone
    mov     (0x0C, sp), d0
    mov     (0x04, sp), a0
    call    SmRow, 0, 0
    mov     (0x0C, sp), d0
    inc     d0
    mov     d0, (0x0C, sp)
    bra     smo_rlim
smo_rdone:
    mov     (0x08, sp), d0          # Y = 10 y - 1 (at least 0), in twelfths of a source row
    mov     10, d1
    mulu    d1, d0
    add     -1, d0
    cmp     0, d0
    bge     smo_y
    clr     d0
smo_y:
    clr     d1
    mov     d1, mdr
    mov     12, d1
    divu    d1, d0                  # y0
    mov     mdr, d1
    mov     d1, (0x14, sp)          # fy
    mov     12, d2
    sub     d1, d2
    mov     d2, (0x10, sp)          # 12 - fy
    mov     d0, d2                  # y1 = y0 + 1, at most 199
    inc     d2
    cmp     AW_H - 1, d2
    bls     smo_y1
    mov     AW_H - 1, d2
smo_y1:
    and     3, d0
    mov     SM_RW, d1
    mulu    d1, d0
    mov     SM_RING, a0
    add     d0, a0                  # a0 = row y0 at x0
    and     3, d2
    mov     SM_RW, d1
    mulu    d1, d2
    mov     SM_RING, a1
    add     d2, a1                  # a1 = row y1 at x0
    mov     (0x18, sp), a2          # a2 = the output pixel
    clr     d2                      # d2 = fx: x 0 at X 0; then X = 10 x - 1, fx -1 + 10 = 9 at x 1
    mov     BIG_W, d3               # d3 = pixels left
smo_px:
    movbu   (a0), d0                # the four the same: that index
    movbu   (1, a0), d1
    cmp     d0, d1
    bne     smo_mix
    movbu   (a1), d1
    cmp     d0, d1
    bne     smo_mix
    movbu   (1, a1), d1
    cmp     d0, d1
    bne     smo_mix
smo_put:
    movbu   d0, (a2)
    inc     a2
    cmp     BIG_W, d3
    bne     smo_fx
    mov     -1, d2                  # (after x 0)
smo_fx:
    add     10, d2
    cmp     12, d2
    blt     smo_xn
    add     -12, d2
    inc     a0
    inc     a1
smo_xn:
    add     -1, d3
    bne     smo_px
    mov     a2, (0x18, sp)
    mov     (0x08, sp), d0
    inc     d0
    mov     d0, (0x08, sp)
    cmp     BIG_H, d0
    bne     smo_row
    mov     (0x48, sp), d0
    call    PerfPhase, 0, 0
    ret     [d2,d3,a2,a3], 0x60
smo_mix:
    mov     a0, (0x1C, sp)
    mov     a1, (0x20, sp)
    mov     a2, (0x24, sp)
    mov     d3, (0x28, sp)
    mov     d2, (0x2C, sp)
    movbu   (a0), d0
    mov     d0, (0x30, sp)
    movbu   (1, a0), d0
    mov     d0, (0x34, sp)
    movbu   (a1), d0
    mov     d0, (0x38, sp)
    movbu   (1, a1), d0
    mov     d0, (0x3C, sp)
    clr     d2                      # d2 = red << 16 | blue, d3 = green, summed
    clr     d3
    mov     12, d1                  # x0 y0: (12 - fx)(12 - fy)
    mov     (0x2C, sp), d0
    sub     d0, d1
    mov     (0x10, sp), d0
    mul     d0, d1
    mov     (0x30, sp), d0
    call    SmAdd, 0, 0
    mov     (0x2C, sp), d1          # x1 y0: fx (12 - fy)
    mov     (0x10, sp), d0
    mul     d0, d1
    mov     (0x34, sp), d0
    call    SmAdd, 0, 0
    mov     12, d1                  # x0 y1: (12 - fx) fy
    mov     (0x2C, sp), d0
    sub     d0, d1
    mov     (0x14, sp), d0
    mul     d0, d1
    mov     (0x38, sp), d0
    call    SmAdd, 0, 0
    mov     (0x2C, sp), d1          # x1 y1: fx fy
    mov     (0x14, sp), d0
    mul     d0, d1
    mov     (0x3C, sp), d0
    call    SmAdd, 0, 0
    mov     d2, d0                  # each channel / 144, rounded: (s + 72) x 3641 >> 19
    lsr     16, d0
    add     72, d0
    mov     3641, d1
    mulu    d1, d0
    lsr     19, d0
    asl     8, d0
    mov     d0, (0x40, sp)
    mov     d3, d0
    add     72, d0
    mov     3641, d1
    mulu    d1, d0
    lsr     19, d0
    asl     4, d0
    mov     (0x40, sp), d1
    or      d1, d0
    mov     d0, (0x40, sp)
    mov     d2, d0
    and     0xFFFF, d0
    add     72, d0
    mov     3641, d1
    mulu    d1, d0
    lsr     19, d0
    mov     (0x40, sp), d1
    or      d1, d0                  # d0 = the mix, 0x0RGB
    mov     SM_LUT, a0
    add     d0, a0
    movbu   (a0), d1
    cmp     0xFF, d1
    bne     smo_known
    mov     a0, (0x44, sp)
    call    SmNearest, 0, 0
    mov     (0x44, sp), a0
    movbu   d0, (a0)
    bra     smo_back
smo_known:
    mov     d1, d0
smo_back:
    mov     (0x1C, sp), a0
    mov     (0x20, sp), a1
    mov     (0x24, sp), a2
    mov     (0x28, sp), d3
    mov     (0x2C, sp), d2
    bra     smo_put

# SmAdd(d0 = an index, d1 = its weight): its colour, weighted, added to SmSmooth's sums (d2: red << 16 | blue, d3:
# green). Leaf; uses d0, a0.
SmAdd:
    asl     3, d0
    mov     SM_PAL, a0
    add     d0, a0
    mov     (a0), d0
    mul     d1, d0
    add     d0, d2
    mov     (4, a0), d0
    mul     d1, d0
    add     d0, d3
    rets

# SmNearest(d0 = a colour 0x0RGB) -> d0 = the nearest of the 16 (SM_PAL; squared distance, the lowest index on a tie).
SmNearest:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x18, sp
    mov     d0, d1
    lsr     8, d1
    mov     d1, (0x04, sp)          # red
    mov     d0, d1
    lsr     4, d1
    and     15, d1
    mov     d1, (0x08, sp)          # green
    and     15, d0
    mov     d0, (0x0C, sp)          # blue
    clr     d2                      # d2 = the index
    mov     -1, d3                  # d3 = the best distance
    clr     d0
    mov     d0, (0x14, sp)          # the best index
    mov     SM_PAL, a2
smn_loop:
    mov     (a2), d0
    lsr     16, d0
    mov     (0x04, sp), d1
    sub     d1, d0
    mov     d0, d1
    mul     d1, d0
    mov     d0, (0x10, sp)
    mov     (a2), d0
    and     0xFFFF, d0
    mov     (0x0C, sp), d1
    sub     d1, d0
    mov     d0, d1
    mul     d1, d0
    mov     (0x10, sp), d1
    add     d1, d0
    mov     d0, (0x10, sp)
    mov     (4, a2), d0
    mov     (0x08, sp), d1
    sub     d1, d0
    mov     d0, d1
    mul     d1, d0
    mov     (0x10, sp), d1
    add     d1, d0                  # d0 = the distance
    cmp     d3, d0
    bcc     smn_next
    mov     d0, d3
    mov     d2, (0x14, sp)
smn_next:
    add     8, a2
    inc     d2
    cmp     16, d2
    bne     smn_loop
    mov     (0x14, sp), d0
    ret     [d2,d3,a2,a3], 0x28
