# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# prefs.s -- the player's settings (README-CNV.md, "Settings"), shared by both builds: the help screen's fourth page
# shows and changes them (keybed: UP Ab5 or Bb5 and DOWN A5 choose a row, LEFT F5 and RIGHT C6 change it), they apply
# at once, and the KN7APP.BIN build keeps them on the SD card, AWPREFS.CFG in its root (cnv_main.s PrefsRead,
# PrefsSave). The block at PREFS_AT is also the file's 16 bytes:
#   +0 "AWP1"   +4 resolution (0 384x240, 1 320x200)   +5 ambilight (1 on)   +6 light scatter (0 short .. 3 very long)
#   +7 keybed sound (1 on)   +8 LED effects (1 on)   +9 bitmap filter (0 off, 1 bilinear: smooth.s)   +10..+15 zero
# then the page's state. Defaults: 384x240, ambilight on, scatter long, keybed sound on, LED effects on, bilinear.

# (The block's equates, PR_*: vm.inc.)

# PrefsInit: the defaults, unless the block holds settings already (read from the card, or set this run). Leaf.
PrefsInit:
    mov     (PREFS_AT), d0
    cmp     PR_MAGIC_V, d0
    beq     pin_ret
    mov     PR_MAGIC_V, d0
    mov     d0, (PREFS_AT)
    mov     0x00020100, d0          # resolution 0, ambilight 1, scatter 2 (long), keybed sound 0 (then set)
    mov     d0, (PREFS_AT + 4)
    mov     0x0101, d0
    mov     d0, (PREFS_AT + 8)      # LED effects 1, bilinear 1, +10..+11 zero
    mov     1, d0
    movbu   d0, (PR_KEYS)
    clr     d0
    mov     d0, (PREFS_AT + 12)
pin_ret:
    rets

# PrefsValid(a0 = 16 bytes) -> d0 = 1 when they are settings this build understands. Leaf.
PrefsValid:
    mov     (a0), d0
    cmp     PR_MAGIC_V, d0
    bne     pva_no
    movbu   (4, a0), d0
    cmp     1, d0
    bhi     pva_no
    movbu   (5, a0), d0
    cmp     1, d0
    bhi     pva_no
    movbu   (6, a0), d0
    cmp     3, d0
    bhi     pva_no
    movbu   (7, a0), d0
    cmp     1, d0
    bhi     pva_no
    movbu   (8, a0), d0
    cmp     1, d0
    bhi     pva_no
    movbu   (9, a0), d0
    cmp     1, d0
    bhi     pva_no
    mov     1, d0
    rets
pva_no:
    clr     d0
    rets

# PrefsInput: the settings page's keys (help.s, page 4): a key pressed (not held from before) moves the chosen row or
# changes its value; the page is drawn again when anything changed.
PrefsInput:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d2                      # d2 = the keys held now, or pressed since the last look (NOTES_HIT)
    mov     80, d0                  # UP: Ab5 or Bb5
    call    pr_key, 0, 0
    mov     d0, d3
    mov     82, d0
    call    pr_key, 0, 0
    or      d3, d0
    beq     pri_dn
    or      1, d2
pri_dn:
    mov     81, d0                  # DOWN: A5
    call    pr_key, 0, 0
    cmp     0, d0
    beq     pri_lf
    or      2, d2
pri_lf:
    mov     77, d0                  # LEFT: F5
    call    pr_key, 0, 0
    cmp     0, d0
    beq     pri_rt
    or      4, d2
pri_rt:
    mov     84, d0                  # RIGHT: C6
    call    pr_key, 0, 0
    cmp     0, d0
    beq     pri_arm
    or      8, d2
pri_arm:
    mov     (PR_ARMED), d0          # the page just shown: what is held (or was pressed before) changes nothing
    cmp     0, d0
    bne     pri_new
    mov     1, d0
    mov     d0, (PR_ARMED)
    mov     d2, (PR_KEYPREV)
    bra     pri_ret
pri_new:
    mov     (PR_KEYPREV), d0
    mov     d2, (PR_KEYPREV)
    not     d0
    and     d0, d2                  # d2 = the keys pressed since the last look
    beq     pri_ret
    mov     (PR_SEL), d3
    btst    1, d2
    beq     pri_nup
    add     PR_ROWS - 1, d3         # up, wrapping
pri_nup:
    btst    2, d2
    beq     pri_ndn
    inc     d3
pri_ndn:
    mov     d3, d0
    clr     d1
    mov     d1, mdr
    mov     PR_ROWS, d1
    divu    d1, d0
    mov     mdr, d3
    mov     d3, (PR_SEL)
    btst    4, d2
    beq     pri_nlf
    mov     d3, d0
    mov     -1, d1
    call    PrefsStep, 0, 0
pri_nlf:
    btst    8, d2
    beq     pri_draw
    mov     d3, d0
    mov     1, d1
    call    PrefsStep, 0, 0
pri_draw:
    call    HelpDrawPage, 0, 0
pri_ret:
    ret     [d2,d3,a2,a3], 0x20

# pr_key(d0 = note) -> d0 != 0 while it is held or once it was pressed since the last look (its NOTES_HIT latch,
# cleared here). Uses d0, d1, a0, a1.
pr_key:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    mov     d0, d1
    call    NotesAnyHeld, 0, 0
    mov     NOTES_HIT, a0
    add     d2, a0
    movbu   (a0), d1
    or      d1, d0
    clr     d1
    movbu   d1, (a0)
    ret     [d2,d3,a2,a3], 0x20

# PrefsStep(d0 = row, d1 = +1 or -1): that setting's next or previous value, wrapping, applied now and marked to be
# saved.
PrefsStep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    mov     pr_rows, a2             # the row's byte and its number of values
    mov     d2, d0
    asl     3, d0
    add     d0, a2
    mov     (a2), a3                # the setting's address
    mov     (4, a2), d3             # its values
    movbu   (a3), d0
    add     d1, d0
    add     d3, d0
    clr     d1
    mov     d1, mdr
    divu    d3, d0
    mov     mdr, d0
    movbu   d0, (a3)
    mov     1, d0
    mov     d0, (PR_DIRTY)
    mov     d2, d0
    call    PrefsApply, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# PrefsApply(d0 = row): make the setting so now. The resolution: the display mode (display.s ModeSwitch: the pages
# converted, the border drawn for the new window); the ambilight and its scatter: the border's entries again, from
# the game's picture and palette (lcd8.s AmbiUpdate); the keybed sound: audio.s KeysSync tells the instrument at its
# next poll; the LED effects: read where they are made; the bitmap filter: at the next bitmap (smooth.s).
PrefsApply:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    cmp     0, d0
    bne     pap_ambi
    movbu   (PR_RES), d0
    call    ModeSwitch, 0, 0
    bra     pap_ret
pap_ambi:
    cmp     3, d0
    beq     pap_keys
    bcc     pap_ret                 # (the LED effects)
    mov     (CUR_PAGE_2), a0        # rows 1, 2: the ambilight from the game's picture, in its own palette
    mov     HELP_PAL_SAVE, a1
    call    AmbiUpdate, 0, 0
    bra     pap_ret
pap_keys:
    call    PrefsKeys, 0, 0
pap_ret:
    ret     [d2,d3,a2,a3], 0x20

# PrefsPageBuild: the settings page's items (help.s format) into PF_ITEMS: the titles, each row's name and value (the
# chosen row yellow, with a marker), how to use it, the page's number.
PrefsPageBuild:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     PF_ITEMS, a2
    mov     pr_head, a0             # the fixed items
pb_head:
    movhu   (a0), d0
    cmp     0xFFFF, d0
    beq     pb_rows
    mov     (a0), d0
    mov     d0, (a2)
    mov     (4, a0), d0
    mov     d0, (4, a2)
    mov     (8, a0), d0
    mov     d0, (8, a2)
    add     12, a0
    add     12, a2
    bra     pb_head
pb_rows:
    clr     d2                      # d2 = row
pb_row:
    mov     d2, d0                  # y = PR_ROW_Y0 + row * PR_ROW_DY
    mov     PR_ROW_DY, d1
    mulu    d1, d0
    add     PR_ROW_Y0, d0
    mov     d0, d3                  # d3 = y
    mov     1, a1                   # colour: 1 white, 3 yellow when chosen
    mov     (PR_SEL), d0
    cmp     d0, d2
    bne     pb_col
    mov     3, a1
    mov     16, d0                  # the marker
    movhu   d0, (a2)
    movhu   d3, (2, a2)
    mov     a1, d0
    movhu   d0, (4, a2)
    clr     d0
    movhu   d0, (6, a2)
    mov     pr_mark, a0
    mov     a0, (8, a2)
    add     12, a2
pb_col:
    mov     32, d0                  # the row's name
    movhu   d0, (a2)
    movhu   d3, (2, a2)
    mov     a1, d0
    movhu   d0, (4, a2)
    clr     d0
    movhu   d0, (6, a2)
    mov     pr_names, a0
    mov     d2, d0
    asl     2, d0
    add     d0, a0
    mov     (a0), a0
    mov     a0, (8, a2)
    add     12, a2
    mov     184, d0                 # its value's text: pr_vals[row][value]
    movhu   d0, (a2)
    movhu   d3, (2, a2)
    mov     a1, d0
    cmp     1, d0
    bne     pb_vcol
    mov     2, d0                   # (cyan when not chosen)
pb_vcol:
    movhu   d0, (4, a2)
    clr     d0
    movhu   d0, (6, a2)
    mov     pr_rows, a0
    mov     d2, d0
    asl     3, d0
    add     d0, a0
    mov     (a0), a3                # the setting
    movbu   (a3), d0
    asl     2, d0
    mov     pr_vals, a0
    mov     d2, d1
    asl     4, d1
    add     d1, a0
    add     d0, a0
    mov     (a0), a0
    mov     a0, (8, a2)
    add     12, a2
    inc     d2
    cmp     PR_ROWS, d2
    bne     pb_row
    mov     0xFFFF, d0
    movhu   d0, (a2)
    clr     d0
    movhu   d0, (2, a2)
    ret     [d2,d3,a2,a3], 0x20

    .align  4
# each row: the setting's address, its number of values
pr_rows:
    .long   PR_RES, 2
    .long   PR_AMBI, 2
    .long   PR_REACH, 4
    .long   PR_KEYS, 2
    .long   PR_LEDS, 2
    .long   PR_SMOOTH, 2
pr_names:
    .long   prn_res, prn_ambi, prn_reach, prn_keys, prn_leds, prn_smooth
pr_vals:                            # 4 per row
    .long   prv_hi, prv_lo, prv_hi, prv_hi
    .long   prv_off, prv_on, prv_off, prv_off
    .long   prv_short, prv_med, prv_long, prv_vlong
    .long   prv_off, prv_on, prv_off, prv_off
    .long   prv_off, prv_on, prv_off, prv_off
    .long   prv_off, prv_bilin, prv_off, prv_off
pr_head:
    .word   108, 8, 2, 0
    .long   hs_title1
    .word   116, 20, 2, 0
    .long   hs_title2
    .word   8, 40, 1, 0
    .long   prn_title
    .word   8, 136, 1, 0
    .long   prn_hint1
    .word   8, 148, 1, 0
    .long   prn_hint2
    .word   8, 164, 1, 0
    .long   prn_hint3
    .word   256, 188, 1, 0
    .long   prn_page
    .word   0xFFFF, 0
prn_title:  .asciz  "SETTINGS"
prn_res:    .asciz  "RESOLUTION"
prn_ambi:   .asciz  "AMBILIGHT"
prn_reach:  .asciz  "LIGHT SCATTER"
prn_keys:   .asciz  "KEYBED SOUND"
prn_leds:   .asciz  "LED EFFECTS"
prn_smooth: .asciz  "BITMAP FILTER"
prv_hi:     .asciz  "384x240"
prv_lo:     .asciz  "320x200"
prv_on:     .asciz  "ON"
prv_off:    .asciz  "OFF"
prv_bilin:  .asciz  "BILINEAR"
prv_short:  .asciz  "SHORT"
prv_med:    .asciz  "MEDIUM"
prv_long:   .asciz  "LONG"
prv_vlong:  .asciz  "VERY LONG"
pr_mark:    .asciz  ">"
prn_hint1:  .asciz  "Ab5 or Bb5 / A5: choose a row"
prn_hint2:  .asciz  "F5 / C6: change it"
prn_hint3:  .asciz  "kept on the SD card"
prn_page:   .asciz  "Page 4/4"
    .align  4
