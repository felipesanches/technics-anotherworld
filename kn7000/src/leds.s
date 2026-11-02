# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# leds.s -- the control panel's LEDs follow the game (README-CNV.md, "LED effects"; Felipe, 2026-11-02): every red
# LED on while a laser shot shows, the other LEDs pulsing while Lester's gun builds a charge, every LED blinking at the
# mega-blast and at the intro's thunder and lightning. Shared by both builds; the LED effects setting (prefs.s
# PR_LEDS) turns them off.
#
# The panel's LEDs (research-scratch kn7000-leds, MAME-checked on 893 and 941): the firmware keeps them in a shadow
# of 20 one-byte registers in work RAM, and a task of its own sends every register that differs from its mirror
# (0x20 further) to the panel every 24 ms; its LED routines only set or clear bits in the shadow, when its state
# changes. So, while an effect runs, the game writes its pattern into the shadow at every yield (LedService), over
# whatever the firmware set meanwhile, which it folds into the copy it saved first (the bits that changed since its
# last write). When the effect ends (and at the quit: LedEnd) the saved bits go back, and the four refresh requests
# are raised so that the firmware puts the LEDs of its own state back. 71 of the 101 LEDs are red (by part number:
# the service manual's parts list): LED_RED; LED_ALL are the bits that are LEDs. Effects only on a known build (the
# loader's FWV_BUILD: led_builds), on the KN7000's own panel (bank flag 0) and with the firmware's LED output not
# frozen.
#
# What sets them off (research-scratch kn7000-aw-reference/fingerprints, found and checked in rustyworld):
#   a laser shot       PLAY_SOUND 0x52 at a volume above 0, any thread (Lester's, the guards', the beams)
#   a charge           PLAY_SOUND 0x5B at frequency 20 by thread 23 (Lester's gun): the charge ball; 0x59 by thread
#                      23: the big blob; it ends at 0x58 by thread 23 (released early: a shield), at the blast, or a
#                      part switch
#   the mega-blast     var 0x88 set to 100 by thread 23
#   lightning          SET_PALETTE 0x02 in the intro (part 0x3E81): the screen white for three frames
#   thunder            PLAY_SOUND 0x0A at a volume of 50 or more in the intro
#   the strike         SET_PALETTE 0x17 at pc 0x065A in the intro: the bolt hits the tower

.equ LED_REGS,        20
.equ LED_LASER_MS,    150
.equ LED_FLASH_MS,    150
.equ LED_THUNDER_MS,  100
.equ LED_BLINK_MS,    100            # a blink's on or off (the firmware sends every 24 ms)
.equ LED_PULSE_MS,    200            # the charge's pulse: a half period; 100 once the big blob forms

# LedInit: the LEDs' addresses for this program build, or effects off (LED_SH 0). The game task's start. Leaf.
LedInit:
    clr     d0
    mov     d0, (LED_SH)
    mov     d0, (LED_ACTIVE)
    mov     d0, (LED_CHARGE)
    mov     d0, (LED_RED_T)
    mov     d0, (LED_ALL_T)
    mov     d0, (LED_BLINKS)
    mov     (FWV_BUILD), d1
    mov     led_builds, a0
lin_next:
    mov     (a0), d0
    cmp     0, d0
    beq     lin_ret
    cmp     d1, d0
    beq     lin_found
    add     16, a0
    bra     lin_next
lin_found:
    mov     (8, a0), a1             # the bank flag: 0, the KN7000's own panel
    movbu   (a1), d0
    cmp     0, d0
    bne     lin_ret
    mov     (12, a0), a1            # the refresh masks; the freeze flag is at +0x13
    movbu   (0x13, a1), d0
    btst    1, d0
    bne     lin_ret
    mov     a1, (LED_MASKS)
    mov     (4, a0), d0
    mov     d0, (LED_SH)
lin_ret:
    rets

# LedEvent(d0 = LEV_*): an effect starts (the interpreter's hooks below). Leaf; uses d0, d1, a0.
LedEvent:
    mov     (LED_SH), d1
    cmp     0, d1
    beq     lev_ret
    movbu   (PR_LEDS), d1
    cmp     0, d1
    beq     lev_ret
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d1                # d1 = now
    cmp     LEV_LASER, d0
    bne     lev_flash
    add     LED_LASER_MS, d1
    mov     d1, (LED_RED_T)
    rets
lev_flash:
    cmp     LEV_FLASH, d0
    bne     lev_thunder
    add     LED_FLASH_MS, d1
    mov     d1, (LED_ALL_T)
    rets
lev_thunder:
    cmp     LEV_THUNDER, d0
    bne     lev_blink
    add     LED_THUNDER_MS, d1
    mov     d1, (LED_ALL_T)
    rets
lev_blink:
    cmp     LEV_BLINK, d0
    bne     lev_charge
    mov     d1, (LED_BLINK_T)       # three blinks: 6 halves from now
    mov     6, d0
    mov     d0, (LED_BLINKS)
    clr     d0
    mov     d0, (LED_CHARGE)
    rets
lev_charge:
    cmp     LEV_CHARGE, d0
    bne     lev_mega
    mov     (LED_CHARGE), d0
    cmp     0, d0
    bne     lev_ret
    mov     1, d0
    mov     d0, (LED_CHARGE)
    mov     d1, (LED_PULSE_T)
    rets
lev_mega:
    cmp     LEV_MEGA, d0
    bne     lev_stop
    mov     2, d0
    mov     d0, (LED_CHARGE)
    rets
lev_stop:
    clr     d0                      # LEV_STOP: no charge
    mov     d0, (LED_CHARGE)
lev_ret:
    rets

# LedSound(a0 = PLAY_SOUND's operands: resource u16 big-endian, frequency, volume, channel) (interp.s OpPlaySound)
LedSound:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    movbu   (a0), d2
    asl     8, d2
    movbu   (1, a0), d0
    or      d0, d2                  # d2 = the sound
    movbu   (2, a0), d3             # d3 = frequency
    movbu   (3, a0), d0
    mov     d0, (0x0C, sp)          # (the volume)
    movbu   (CURRENT_THREAD), d1
    cmp     0x52, d2                # a laser shot
    bne     ls_charge
    mov     (0x0C, sp), d0
    cmp     0, d0
    beq     ls_ret
    mov     LEV_LASER, d0
    call    LedEvent, 0, 0
    bra     ls_ret
ls_charge:
    cmp     23, d1                  # Lester's gun: thread 23
    bne     ls_intro
    mov     LEV_CHARGE, d0
    cmp     0x5B, d2
    bne     ls_mega
    cmp     20, d3
    beq     ls_event
    bra     ls_ret
ls_mega:
    mov     LEV_MEGA, d0
    cmp     0x59, d2
    beq     ls_event
    mov     LEV_STOP, d0
    cmp     0x58, d2
    beq     ls_event
    bra     ls_ret
ls_intro:
    cmp     0x0A, d2                # thunder, in the intro
    bne     ls_ret
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E81, d0
    bne     ls_ret
    mov     (0x0C, sp), d0
    cmp     50, d0
    bcs     ls_ret
    mov     LEV_THUNDER, d0
ls_event:
    call    LedEvent, 0, 0
ls_ret:
    ret     [d2,d3,a2,a3], 0x20

# LedPalette(d0 = palette index, d1 = the SET_PALETTE's pc) (interp.s OpSetPalette): the intro's lightning and strike.
LedPalette:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E81, d0
    bne     lp_ret
    mov     LEV_FLASH, d0
    cmp     0x02, d2
    beq     lp_event
    cmp     0x17, d2
    bne     lp_ret
    cmp     0x065A, d1
    bne     lp_ret
    mov     LEV_BLINK, d0
lp_event:
    call    LedEvent, 0, 0
lp_ret:
    ret     [d2,d3,a2,a3], 0x20

# LedVar(d0 = var, d1 = value) (interp.s OpMovConst): the mega-blast: var 0x88 = 100 by thread 23.
LedVar:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    cmp     0x88, d0
    bne     lvr_ret
    cmp     100, d1
    bne     lvr_ret
    movbu   (CURRENT_THREAD), d0
    cmp     23, d0
    bne     lvr_ret
    mov     LEV_BLINK, d0
    call    LedEvent, 0, 0
lvr_ret:
    ret     [d2,d3,a2,a3], 0x20

# LedService: at every yield of the game task (cnv_main.s DLY_TSK): the pattern the effects running want, written into
# the shadow; when none runs any more, the LEDs as they were (LedEnd).
LedService:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (LED_SH), d0
    cmp     0, d0
    beq     lsv_ret
    movbu   (PR_LEDS), d0           # turned off in the settings: end what runs
    cmp     0, d0
    bne     lsv_on
    clr     d0
    mov     d0, (LED_CHARGE)
    mov     d0, (LED_BLINKS)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (LED_RED_T)
    mov     d0, (LED_ALL_T)
lsv_on:
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d3                # d3 = now
    clr     d2                      # d2 = what is wanted: bit 0 red, 1 all, 2 the non-red, 3 all off
    mov     (LED_RED_T), d0
    sub     d3, d0
    ble     lsv_all
    or      1, d2
lsv_all:
    mov     (LED_ALL_T), d0
    sub     d3, d0
    ble     lsv_charge
    or      2, d2
lsv_charge:
    mov     (LED_CHARGE), d0
    cmp     0, d0
    beq     lsv_blink
    mov     d3, d1
    mov     (LED_PULSE_T), d0
    sub     d0, d1                  # d1 = ms since the pulse began
    mov     d1, d0
    mov     (LED_CHARGE), d1        # the pulse's half period: 200 ms, 100 with the big blob
    cmp     2, d1
    beq     lsv_fast
    mov     LED_PULSE_MS, d1
    bra     lsv_div
lsv_fast:
    mov     LED_PULSE_MS / 2, d1
lsv_div:
    mov     0, a1
    mov     a1, mdr
    divu    d1, d0                  # halves so far
    btst    1, d0
    bne     lsv_blink               # (the odd halves: the non-red as they are)
    or      4, d2
lsv_blink:
    mov     (LED_BLINKS), d0
    cmp     0, d0
    beq     lsv_apply
    mov     d3, d0
    mov     (LED_BLINK_T), d1
    sub     d1, d0                  # ms since the blinks began
    clr     d1
    mov     d1, mdr
    mov     LED_BLINK_MS, d1
    divu    d1, d0                  # halves so far
    mov     (LED_BLINKS), d1
    cmp     d1, d0
    bcs     lsv_bl_on
    clr     d0                      # done
    mov     d0, (LED_BLINKS)
    bra     lsv_apply
lsv_bl_on:
    btst    1, d0
    bne     lsv_bl_off
    or      2, d2                   # the even halves: all on
    bra     lsv_apply
lsv_bl_off:
    or      8, d2                   # the odd ones: all off
lsv_apply:
    mov     d2, d0
    call    LedWrite, 0, 0
lsv_ret:
    ret     [d2,d3,a2,a3], 0x20

# LedWrite(d0 = what is wanted, LedService's bits; 0: nothing): the shadow's LED bits, register by register: on the
# first, the LEDs saved; then the bits the firmware changed since the last write folded into the saved copy, and the
# saved bits with the effects' over them written (the register's other bits as the firmware has them). 0 after
# something: LedEnd.
LedWrite:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, (0x18, sp)          # what is wanted
    cmp     0, d0
    bne     lw_go
    call    LedEnd, 0, 0
    bra     lw_ret
lw_go:
    mov     (LED_SH), a2
    mov     (LED_ACTIVE), d0
    cmp     0, d0
    bne     lw_regs
    mov     1, d0                   # the effects begin: what the LEDs show now, saved
    mov     d0, (LED_ACTIVE)
    clr     d2
lw_save:
    movbu   (d2, a2), d0
    mov     LED_SAVED, a0
    movbu   d0, (d2, a0)
    mov     LED_LAST, a0
    movbu   d0, (d2, a0)
    inc     d2
    cmp     LED_REGS, d2
    bne     lw_save
lw_regs:
    clr     d2                      # d2 = the register
lw_reg:
    mov     led_all, a0
    movbu   (d2, a0), d3            # d3 = its LED bits
    call    led_fold, 0, 0          # d0 = the LEDs as they would be without us (saved, with the firmware's changes)
    mov     (0x18, sp), d1          # the effects over them
    btst    8, d1                   # all off
    beq     lw_n1
    clr     d0
lw_n1:
    btst    1, d1                   # red on
    beq     lw_n2
    mov     led_red, a0
    movbu   (d2, a0), d1
    or      d1, d0
    mov     (0x18, sp), d1
lw_n2:
    btst    4, d1                   # the non-red on
    beq     lw_n3
    mov     led_red, a0
    movbu   (d2, a0), d1
    not     d1
    and     d3, d1
    or      d1, d0
    mov     (0x18, sp), d1
lw_n3:
    btst    2, d1                   # all on
    beq     lw_store
    mov     d3, d0
lw_store:
    and     d3, d0                  # the LED bits ours, the others the firmware's
    movbu   (d2, a2), d1
    not     d3
    and     d3, d1
    or      d1, d0
    movbu   d0, (d2, a2)
    mov     LED_LAST, a0
    movbu   d0, (d2, a0)
    inc     d2
    cmp     LED_REGS, d2
    bne     lw_reg
lw_ret:
    ret     [d2,d3,a2,a3], 0x30

# led_fold(d2 = register, d3 = its LED bits, a2 = the shadow) -> d0 = the saved LED bits with those the firmware changed
# since our last write (shadow ^ LED_LAST) taken from it; LED_SAVED updated. Leaf; uses d0, d1, a0, a1.
led_fold:
    movbu   (d2, a2), d0
    mov     LED_LAST, a0
    movbu   (d2, a0), d1
    xor     d0, d1
    and     d3, d1                  # d1 = changed
    and     d1, d0                  # d0 = the firmware's value of them
    mov     d0, a1
    not     d1
    mov     LED_SAVED, a0
    movbu   (d2, a0), d0
    and     d1, d0
    and     d3, d0
    mov     a1, d1
    or      d1, d0
    movbu   d0, (d2, a0)
    rets

# LedEnd: the effects over (or the quit, cnv_main.s): the saved LED bits back into the shadow, with the firmware's own
# changes since our last write, and its four refresh requests raised (interrupts off: it updates them too) so that it
# puts back the LEDs of its state.
LedEnd:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (LED_ACTIVE), d0
    cmp     0, d0
    beq     len_ret
    clr     d0
    mov     d0, (LED_ACTIVE)
    mov     (LED_SH), a2
    clr     d2
len_reg:
    mov     led_all, a0
    movbu   (d2, a0), d3
    call    led_fold, 0, 0
    movbu   (d2, a2), d1            # the register's other bits as the firmware has them
    not     d3
    and     d3, d1
    or      d1, d0
    movbu   d0, (d2, a2)
    inc     d2
    cmp     LED_REGS, d2
    bne     len_reg
    mov     psw, d0
    mov     d0, a0
    and     0xF7FF, psw
    nop
    nop
    mov     (LED_MASKS), a1
    mov     0xFFFF, d1
    movhu   d1, (a1)
    movhu   d1, (4, a1)
    movhu   d1, (8, a1)
    movhu   d1, (12, a1)
    mov     a0, d0
    mov     d0, psw
    nop
len_ret:
    ret     [d2,d3,a2,a3], 0x20

    .align  4
# the builds the LEDs are known on: the build, the shadow, the bank flag, the refresh masks (the freeze flag: +0x13)
led_builds:
    .long   893, 0x50150A18, 0x5006BE90, 0x5006BFB8
    .long   941, 0x50150A3C, 0x5006BE94, 0x5006BFBC
    .long   935, 0x50150A3C, 0x5006BE94, 0x5006BFBC
    .long   942, 0x50150A4C, 0x5006BEA4, 0x5006BFCC
    .long   0
led_all:                            # the bits of each register that are LEDs
    .byte   0x3F, 0x3F, 0x3F, 0x3F, 0x1F, 0x1F, 0x1F, 0x1F, 0xFF, 0xFA, 0xFF, 0xFF, 0xFF, 0xFF, 0x03, 0x01, 0x03, 0x03, 0x03, 0x03
led_red:                            # ... that are red LEDs
    .byte   0x3F, 0x2F, 0x2F, 0x2F, 0x0E, 0x0C, 0x1E, 0x0D, 0x80, 0x08, 0xFC, 0x7C, 0xFF, 0xFF, 0x03, 0x00, 0x03, 0x03, 0x01, 0x03
    .align  4
