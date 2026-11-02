# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# leds.s -- the control panel's LEDs follow the game (README-CNV.md, "The panel's LEDs"; Felipe, 2026-11-02): from the
# end of the firmware search to the quit every LED is off but those the game's effects light: the red LEDs at a laser
# shot (a guard's: all of them; Lester's: those of the half of the instrument he shoots towards), the eight PANEL
# MEMORY LEDs pulsing while his gun builds a charge, every LED while the mega-blast shows, the green ones while the gun
# recharges at a station, every LED at the intro's lightning and thunder (blinking at the strike), and LEDs lit at
# random by the waterfall, more of them the louder it is (led_water). Shared by both builds; the LED effects setting
# (prefs.s PR_LEDS) off leaves the LEDs to the firmware.
#
# The panel's LEDs (research-scratch kn7000-leds, MAME-checked on 893 and 941): the firmware keeps them in a shadow
# of 20 one-byte registers in work RAM, and a task of its own sends every register that differs from its mirror
# (0x20 further) to the panel every 24 ms; its LED routines only set or clear bits in the shadow, when its state
# changes. So the game writes its pattern into the shadow at every yield (LedService), over whatever the firmware
# set meanwhile, which it folds into the copy it saved first (the bits that changed since its last write). At the
# quit, or when the setting is turned off (LedEnd), the saved bits go back, and the four refresh requests are raised
# so that the firmware puts the LEDs of its own state back: every bit but the fourth mask's 0x10, the freeze/unfreeze
# routine (893 func_484B086A, 935 0x484B0A35, 941 0x484B0A77, 942 0x484B0A66), which zeroes the mirror and, run
# before the flush has sent the restore, left the registers set back to 0 showing the effect (MAME,
# probes/cnv/awcnv_inplog.lua AW_TXTRACE, 2026-11-02). The groups (led_* below): colour by the service manual's parts
# list, left or right half by the MAME layout (probes/ledmasks.py). Effects only on a known build (the loader's
# FWV_BUILD: led_builds), on the KN7000's own panel (bank flag 0) and with the firmware's LED output not frozen.
#
# What sets them off (research-scratch kn7000-aw-reference/fingerprints, found and checked in rustyworld):
#   a laser shot       PLAY_SOUND 0x52 at a volume above 0, any thread; Lester's is thread 20's, and var 0x04 then
#                      says where he faces: 0x20 left, 0x30 right (bit 0x10)
#   a charge           PLAY_SOUND 0x5B at frequency 20 by thread 23 (Lester's gun): the charge ball; 0x59 by thread
#                      23: the big blob; it ends at 0x58 by thread 23 (released early: a shield), at the blast, or a
#                      part switch
#   the mega-blast     var 0x88 set to 100 by thread 23; it shows while var 0x88 is 100 or 0x8000 | 100..137 (the
#                      beam, then its impact: thread 47 stores it every tick), about 0.9 s
#   the recharge       var 0x06 set to 1000 (part 0x3E84, thread 54, pc 0x34A0: the only such instruction); the
#                      station's sparkles and Lester's pose last 18 ticks, 1.44 s
#   lightning          SET_PALETTE 0x02 in the intro (part 0x3E81): the screen white for three frames
#   thunder            PLAY_SOUND 0x0A at a volume of 50 or more in the intro
#   the strike         SET_PALETTE 0x17 at pc 0x065A in the intro: the bolt hits the tower

.equ LED_REGS,        20
.equ LED_LASER_MS,    150
.equ LED_FLASH_MS,    150
.equ LED_THUNDER_MS,  100
.equ LED_BLINK_MS,    100            # a blink's on or off (the firmware sends every 24 ms)
.equ LED_PULSE_MS,    200            # the charge's pulse: a half period; 100 once the big blob forms
.equ LED_GREEN_MS,    1440           # the recharge: 18 ticks of 80 ms
.equ LED_RND_MS,      50             # the random LEDs drawn again this often
.equ LED_MAGIC_V,     0x4C454453     # LedInit has run
# what LedService wants written (LedWrite's d0)
.equ W_RED,           0x01           # every red LED
.equ W_ALL,           0x02           # every LED
.equ W_PM,            0x04           # the PANEL MEMORY ring
.equ W_DARK,          0x08           # the rest off (always, while the effects are on)
.equ W_REDL,          0x10           # the red LEDs of the left half
.equ W_REDR,          0x20           # ... of the right half
.equ W_GREEN,         0x40           # the green LEDs
.equ W_RAND,          0x80           # those of LED_RNDMASK

# LedInit: the LEDs' addresses for this program build, or effects off (LED_SH 0). After the firmware search (the
# converter's main task, cnv_main.s) and at the game task's start (display.s); only the first call does anything.
# Leaf.
LedInit:
    mov     (LED_MAGIC), d0
    mov     LED_MAGIC_V, d1
    cmp     d1, d0
    beq     lin_ret
    mov     d1, (LED_MAGIC)
    clr     d0
    mov     d0, (LED_SH)
    mov     d0, (LED_ACTIVE)
    mov     d0, (LED_CHARGE)
    mov     d0, (LED_RED_T)
    mov     d0, (LED_REDL_T)
    mov     d0, (LED_REDR_T)
    mov     d0, (LED_ALL_T)
    mov     d0, (LED_GREEN_T)
    mov     d0, (LED_BLINKS)
    mov     d0, (LED_BLAST)
    mov     d0, (LED_WATER)
    mov     d0, (LED_RND_T)
    mov     0x2545F491, d0
    mov     d0, (LED_SEED)
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
    bne     lev_laser_l
    add     LED_LASER_MS, d1
    mov     d1, (LED_RED_T)
    rets
lev_laser_l:
    cmp     LEV_LASER_L, d0
    bne     lev_laser_r
    add     LED_LASER_MS, d1
    mov     d1, (LED_REDL_T)
    rets
lev_laser_r:
    cmp     LEV_LASER_R, d0
    bne     lev_flash
    add     LED_LASER_MS, d1
    mov     d1, (LED_REDR_T)
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
    bne     lev_blast
    mov     d1, (LED_BLINK_T)       # three blinks: 6 halves from now
    mov     6, d0
    mov     d0, (LED_BLINKS)
    rets
lev_blast:
    cmp     LEV_BLAST, d0
    bne     lev_green
    mov     1, d0                   # LedService follows var 0x88 from here
    mov     d0, (LED_BLAST)
    clr     d0
    mov     d0, (LED_CHARGE)
    rets
lev_green:
    cmp     LEV_GREEN, d0
    bne     lev_charge
    add     LED_GREEN_MS, d1
    mov     d1, (LED_GREEN_T)
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
    movbu   (4, a0), d0             # the waterfall: sound 0x6A loops on its channel until another sound takes it
    and     3, d0                   # (volume 64 by it, 16 on the screens beside it)
    mov     LED_WCH, a1
    add     d0, a1
    clr     d0
    cmp     0x6A, d2
    bne     ls_wch
    movbu   (3, a0), d0
ls_wch:
    movbu   d0, (a1)
    call    led_water, 0, 0
    movbu   (2, a0), d3             # d3 = frequency
    movbu   (3, a0), d0
    mov     d0, (0x0C, sp)          # (the volume)
    movbu   (CURRENT_THREAD), d1
    cmp     0x52, d2                # a laser shot
    bne     ls_charge
    mov     (0x0C, sp), d0
    cmp     0, d0
    beq     ls_ret
    mov     LEV_LASER, d0           # a guard's: every red LED
    cmp     20, d1
    bne     ls_event
    movhu   (VM_VARIABLES + 2 * 0x04), d1   # Lester's: var 0x04 bit 0x10 set when he faces right
    mov     LEV_LASER_L, d0
    btst    0x10, d1
    beq     ls_event
    mov     LEV_LASER_R, d0
    bra     ls_event
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

# LedVar(d0 = var, d1 = value) (interp.s OpMovConst): the mega-blast (var 0x88 = 100 by thread 23) and the recharge
# (var 0x06 = 1000).
LedVar:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    cmp     0x06, d0
    bne     lvr_blast
    cmp     1000, d1
    bne     lvr_ret
    mov     LEV_GREEN, d0
    bra     lvr_event
lvr_blast:
    cmp     0x88, d0
    bne     lvr_ret
    cmp     100, d1
    bne     lvr_ret
    movbu   (CURRENT_THREAD), d0
    cmp     23, d0
    bne     lvr_ret
    mov     LEV_BLAST, d0
lvr_event:
    call    LedEvent, 0, 0
lvr_ret:
    ret     [d2,d3,a2,a3], 0x20

# led_water: LED_WATER from the loudest channel the waterfall plays on (LED_WCH): twice its volume of 256, so half
# the LEDs by the waterfall (64) and an eighth beside it (16); LedService draws them again every LED_RND_MS. Leaf;
# uses d0, d1, a1.
led_water:
    clr     d0
    mov     LED_WCH, a1
    mov     4, d1
lwa_ch:
    mov     d1, mdr
    movbu   (a1), d1
    cmp     d1, d0
    bcc     lwa_next
    mov     d1, d0
lwa_next:
    mov     mdr, d1
    inc     a1
    add     -1, d1
    bne     lwa_ch
    asl     1, d0
    cmp     256, d0
    bcs     lwa_set
    mov     255, d0
lwa_set:
    mov     d0, (LED_WATER)
    rets

# LedPart: a part switch (interp.s InitForPart): no charge, blast or waterfall goes on across it (the part's load
# stops every sound). Leaf.
LedPart:
    clr     d0
    mov     d0, (LED_CHARGE)
    mov     d0, (LED_BLAST)
    mov     d0, (LED_WATER)
    mov     d0, (LED_WCH)
    rets

# LedService: at every yield of the game task (cnv_main.s DLY_TSK), and on the converter's calls before the game task
# runs: the pattern the effects running want, written into the shadow; with the setting off, the LEDs as they were
# (LedEnd).
LedService:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (LED_SH), d0
    cmp     0, d0
    beq     lsv_ret
    clr     d2                      # d2 = what is wanted (W_*)
    movbu   (PR_LEDS), d0           # turned off in the settings: end what runs, the firmware's LEDs back
    cmp     0, d0
    bne     lsv_on
    mov     d0, (LED_CHARGE)
    mov     d0, (LED_BLINKS)
    mov     d0, (LED_BLAST)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (LED_RED_T)
    mov     d0, (LED_REDL_T)
    mov     d0, (LED_REDR_T)
    mov     d0, (LED_ALL_T)
    mov     d0, (LED_GREEN_T)
    bra     lsv_apply
lsv_on:
    mov     W_DARK, d2
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d3                # d3 = now
    mov     (LED_RED_T), d0
    sub     d3, d0
    ble     lsv_redl
    or      W_RED, d2
lsv_redl:
    mov     (LED_REDL_T), d0
    sub     d3, d0
    ble     lsv_redr
    or      W_REDL, d2
lsv_redr:
    mov     (LED_REDR_T), d0
    sub     d3, d0
    ble     lsv_all
    or      W_REDR, d2
lsv_all:
    mov     (LED_ALL_T), d0
    sub     d3, d0
    ble     lsv_green
    or      W_ALL, d2
lsv_green:
    mov     (LED_GREEN_T), d0
    sub     d3, d0
    ble     lsv_blast
    or      W_GREEN, d2
lsv_blast:
    mov     (LED_BLAST), d0         # the mega-blast: every LED while var 0x88 says it shows
    cmp     0, d0
    beq     lsv_charge
    movhu   (VM_VARIABLES + 2 * 0x88), d0
    cmp     100, d0
    beq     lsv_blast_on
    btst    0x8000, d0
    beq     lsv_blast_off
    and     0x7FFF, d0
    cmp     100, d0
    bcs     lsv_blast_off
    cmp     137, d0
    bhi     lsv_blast_off
lsv_blast_on:
    or      W_ALL, d2
    bra     lsv_charge
lsv_blast_off:
    clr     d0
    mov     d0, (LED_BLAST)
lsv_charge:
    mov     (LED_CHARGE), d0
    cmp     0, d0
    beq     lsv_water
    mov     d3, d1
    mov     (LED_PULSE_T), d0
    sub     d0, d1                  # d1 = ms since the pulse began
    mov     d1, d0
    clr     d1                      # (MDR: the dividend's high word)
    mov     d1, mdr
    mov     (LED_CHARGE), d1        # the pulse's half period: 200 ms, 100 with the big blob
    cmp     2, d1
    beq     lsv_fast
    mov     LED_PULSE_MS, d1
    bra     lsv_div
lsv_fast:
    mov     LED_PULSE_MS / 2, d1
lsv_div:
    divu    d1, d0                  # halves so far
    btst    1, d0
    bne     lsv_water               # (the odd halves: off)
    or      W_PM, d2
lsv_water:
    mov     (LED_WATER), d0
    cmp     0, d0
    beq     lsv_blink
    or      W_RAND, d2
    mov     (LED_RND_T), d0
    sub     d3, d0
    bgt     lsv_blink
    mov     d3, d0
    add     LED_RND_MS, d0
    mov     d0, (LED_RND_T)
    call    led_random, 0, 0
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
    or      W_ALL, d2               # the even halves: all on
    bra     lsv_apply
lsv_bl_off:
    mov     W_DARK, d2              # the odd ones: all off
lsv_apply:
    mov     d2, d0
    call    LedWrite, 0, 0
lsv_ret:
    ret     [d2,d3,a2,a3], 0x20

# led_random: LED_RNDMASK drawn again: each LED bit set with the chance LED_WATER of 256 (a linear congruential
# generator, LED_SEED, its bits 16-23).
led_random:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     LED_RNDMASK, a2
    mov     led_all, a3
    clr     d3                      # d3 = the register
lr_reg:
    movbu   (d3, a3), d2            # d2 = its LED bits
    clr     d0
    mov     d0, (0x0C, sp)          # what is lit
    mov     1, d0
    mov     d0, (0x08, sp)          # the bit being drawn
lr_bit:
    mov     (0x08, sp), d0
    and     d2, d0
    beq     lr_next
    mov     (LED_SEED), d0
    mov     1103515245, d1
    mulu    d1, d0
    add     12345, d0
    mov     d0, (LED_SEED)
    lsr     16, d0
    and     0xFF, d0
    mov     (LED_WATER), d1
    cmp     d1, d0
    bcc     lr_next                 # not below the chance: off
    mov     (0x0C, sp), d0
    mov     (0x08, sp), d1
    or      d1, d0
    mov     d0, (0x0C, sp)
lr_next:
    mov     (0x08, sp), d0
    asl     1, d0
    mov     d0, (0x08, sp)
    cmp     0x100, d0
    bne     lr_bit
    mov     (0x0C, sp), d0
    movbu   d0, (d3, a2)
    inc     d3
    cmp     LED_REGS, d3
    bne     lr_reg
    ret     [d2,d3,a2,a3], 0x20

# LedWrite(d0 = what is wanted, W_*; 0: nothing): the shadow's LED bits, register by register: on the first call
# after none (or after LedEnd), the LEDs saved; then the bits the firmware changed since the last write folded into
# the saved copy, and the LED bits written: the saved ones (none with W_DARK), with the effects' groups lit over them
# (the register's other bits as the firmware has them). 0: LedEnd.
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
    mov     (0x18, sp), d1
    btst    W_DARK, d1
    beq     lw_groups
    clr     d0
lw_groups:
    mov     led_groups, a3          # each W_ bit and its table: lit over what is there
lw_group:
    mov     (a3), d1                # the bit (0: the end)
    cmp     0, d1
    beq     lw_store
    mov     d0, (0x14, sp)
    mov     (0x18, sp), d0
    and     d1, d0
    beq     lw_gskip
    mov     (4, a3), a0             # its table
    movbu   (d2, a0), d1
    mov     (0x14, sp), d0
    or      d1, d0
    bra     lw_gnext
lw_gskip:
    mov     (0x14, sp), d0
lw_gnext:
    add     8, a3
    bra     lw_group
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

# LedEnd: the quit (cnv_main.s, fwdraw.s) or the setting turned off: the saved LED bits back into the shadow, with the firmware's own
# changes since our last write, and its refresh requests raised but the freeze routine's (interrupts off: it updates
# them too) so that it puts back the LEDs of its state.
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
    movhu   (12, a1), d1            # the fourth: all but bit 0x10 (kept as the firmware has it), whose routine
    or      0xFFEF, d1              # re-applies the freeze state and zeroes the mirror: run before the flush has
    movhu   d1, (12, a1)            # sent this restore, it would leave the registers set back to 0 unsent
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
led_all:                            # the bits of each register that are LEDs (101)
    .byte   0x3F, 0x3F, 0x3F, 0x3F, 0x1F, 0x1F, 0x1F, 0x1F, 0xFF, 0xFA, 0xFF, 0xFF, 0xFF, 0xFF, 0x03, 0x01, 0x03, 0x03, 0x03, 0x03
led_red:                            # ... red (71)
    .byte   0x3F, 0x2F, 0x2F, 0x2F, 0x0E, 0x0C, 0x1E, 0x0D, 0x80, 0x08, 0xFC, 0x7C, 0xFF, 0xFF, 0x03, 0x00, 0x03, 0x03, 0x01, 0x03
led_redl:                           # ... red, on the left half of the instrument (32)
    .byte   0x1F, 0x2F, 0x2F, 0x2F, 0x0E, 0x0C, 0x1E, 0x0D, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_redr:                           # ... red, on the right half (39)
    .byte   0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x08, 0xFC, 0x7C, 0xFF, 0xFF, 0x03, 0x00, 0x03, 0x03, 0x01, 0x03
led_green:                          # ... green (22)
    .byte   0x00, 0x10, 0x10, 0x10, 0x11, 0x13, 0x01, 0x12, 0x07, 0x12, 0x03, 0x83, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00
led_pm:                             # ... the PANEL MEMORY ring, amber (8)
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00
    .align  4
led_groups:                         # LedWrite: each wanted bit and the LEDs it lights
    .long   W_RED, led_red
    .long   W_REDL, led_redl
    .long   W_REDR, led_redr
    .long   W_PM, led_pm
    .long   W_GREEN, led_green
    .long   W_RAND, LED_RNDMASK
    .long   W_ALL, led_all
    .long   0
