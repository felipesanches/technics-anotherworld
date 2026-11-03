# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# leds.s -- the control panel's LEDs follow the game (README-CNV.md, "The panel's LEDs"; Felipe, 2026-11-02): from the
# end of the firmware search to the quit every LED is off but those the game's effects light: the red LEDs at a laser
# shot (a guard's: all of them; Lester's: those of the half of the instrument he shoots towards), the eight PANEL
# MEMORY LEDs pulsing while his gun builds a charge (and, once it is the big blob, the green ones blinking with them),
# a flash of about 30% of the red LEDs (each with that chance, drawn anew each time) when a small charge is let go as
# a shield, every LED while the
# mega-blast shows, the green ones while the gun recharges at a station, every LED at the intro's lightning and thunder (blinking at the strike), and LEDs lit at
# random by the waterfall, more of them the louder it is (led_water), and the battle tank's panel mirrored (its LEDs,
# button blocks and lamps; its blinking white button on the four AUTO PLAY CHORD / SOUND ARRANGER LEDs), the green
# LEDs flashing when a skeleton explodes, the lift's bouncing light chased round the PANEL MEMORY ring (2-1-8-7-6-5-4-3
# left to right, the other way back, the lead full on and two behind it at half and a quarter), and a blinking light
# by a guard (part 0x3E83) on the leftmost red LED, SPLIT POINT G2. Shared by both builds; the LED effects setting
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
#   a skeleton explodes PLAY_SOUND 0x5A at the dying character's pc: guards 3E83 0x1044, 3E84 0x4D16, 3E86 0x417A;
#                      Lester 0x0FD6, 0x4CA4, 0x4101 (0x5A is also the mega-blast's impact: hence the pc)
#   the lift's light   part 0x3E84, the drawing thread's pc: room (var 0x67) 79, thread 5, pc 0x081F + 5k, k 0-12
#                      (0-6 left to right, 6-12 back); room 109, thread 1, 0x0864-0x087D left to right, 0x0882-0x0896
#                      back, 0x089A at rest on the left
#   a guard's light    part 0x3E83, thread 2 at pc 0x0C22-0x0C27 (lit; 0x0C19-0x0C1A dark): room 68's blinking
#                      polygon above its guard, 8 ticks each (a candidate: the scene is not confirmed)
#   the tank's panel   part 0x3E85 while thread 59 runs (it shows the panel); a press: var 0xFA != 0 on the cell var
#                      0x5F names; cell 0x0B lights about 30 of the panel's LEDs until the panel goes (no var: latched
#                      here); var 0x67 >= 2 and >= 3 its two button blocks; vars 0x72, 0x71 its red lamps, 0x74, 0x75
#                      its green ones; var 0x67 set to 6 at frame t6: the white button blinks, lit while
#                      (frame - t6 - 1) mod 4 < 2 (fingerprints tanksig.py, "Fourth pass")

.equ LED_REGS,        20
.equ LED_LASER_MS,    150
.equ LED_FLASH_MS,    150
.equ LED_THUNDER_MS,  100
.equ LED_BLINK_MS,    100            # a blink's on or off (the firmware sends every 24 ms)
.equ LED_PULSE_MS,    200            # the charge's pulse: a half period; 100 once the big blob forms
.equ LED_GREEN_MS,    1440           # the recharge: 18 ticks of 80 ms
.equ LED_RND_MS,      50             # the random LEDs drawn again this often
.equ LED_SHIELD_MS,   150            # the shield's flash
.equ LED_SHIELD_P,    77             # each red LED's chance in it, of 256 (30%), drawn anew each time
.equ LED_SKEL_MS,     200            # the skeleton's green flash
.equ LED_PWM_MS,      24             # the chase's trail: on or off for a whole flush of the firmware's
.equ LED_TRAIL_MS,    200            # ... and out this long after the lead last moved (the light at rest)
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
.equ W_SHIELD,        0x100          # those of LED_SHMASK
.equ W_TMANY,         0x200          # the tank: its "lot of LEDs" (led_tank)
.equ W_TB1,           0x400          # its first button block (register 13's eight red LEDs)
.equ W_TB2,           0x800          # its second (register 12's)
.equ W_TR1,           0x1000         # its red lamps: INTRO & ENDING 1
.equ W_TR2,           0x2000         # ... INTRO & ENDING 2
.equ W_TG1,           0x4000         # its green lamps: BEAT 2
.equ W_TG2,           0x8000         # ... BEAT 3
.equ W_APC,           0x10000        # its white button: the four AUTO PLAY CHORD / SOUND ARRANGER LEDs
.equ W_LIFT,          0x20000        # the lift's chase (LED_LIFTMASK)
.equ W_GLIGHT,        0x40000        # the guard's light: SPLIT POINT G2

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
    mov     d0, (LED_SKEL_T)
    mov     0x2545F491, d0
    mov     d0, (LED_SEED)
    mov     -1, d0
    mov     d0, (LED_LIFT)          # (its three bytes, and the pad after them)
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
    cmp     LEV_SKEL, d0
    bne     lev_green2
    add     LED_SKEL_MS, d1
    mov     d1, (LED_SKEL_T)
    rets
lev_green2:
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
    cmp     LEV_SHIELD, d0
    bne     lev_nocharge
    mov     (LED_CHARGE), d0        # a shield: the charge let go at its first stage
    cmp     1, d0
    bne     lev_nocharge
    add     LED_SHIELD_MS, d1
    mov     d1, (LED_SHIELD_T)
    mov     1, d0
    mov     d0, (LED_SHIELD_NEW)
lev_nocharge:
    clr     d0                      # LEV_STOP, LEV_SHIELD: no charge
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
    cmp     0x5A, d2                # a skeleton exploding: 0x5A at the dying character's pc (led_skel)
    bne     ls_noskel
    mov     a0, d0
    mov     (CUR_BYTECODE), d1
    sub     d1, d0
    add     -1, d0
    call    led_skel, 0, 0
    cmp     0, d0
    beq     ls_noskel
    mov     LEV_SKEL, d0
    call    LedEvent, 0, 0
    bra     ls_ret
ls_noskel:
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
    mov     LEV_SHIELD, d0
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
    cmp     0x67, d0                # the tank's white button: var 0x67 = 6 in part 0x3E85
    bne     lvr_blast2
    cmp     6, d1
    bne     lvr_ret
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E85, d0
    bne     lvr_ret
    mov     (FRAME_NO), d0
    inc     d0
    mov     d0, (LED_T6)
    bra     lvr_ret
lvr_blast2:
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

# led_water: LED_WATER from the loudest channel the waterfall plays on (LED_WCH): its volume squared / 32 of 256, so
# half the LEDs by the waterfall (64), one in 32 beside it (16: Felipe 2026-11-03, fainter); LedService draws them
# again every LED_RND_MS. Leaf; uses d0, d1, a1.
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
    mov     d0, d1
    mulu    d1, d0
    lsr     5, d0
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
    ble     lsv_skel
    or      W_GREEN, d2
lsv_skel:
    mov     (LED_SKEL_T), d0
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
    beq     lsv_shield
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
    bne     lsv_shield              # (the odd halves: off)
    or      W_PM, d2
    mov     (LED_CHARGE), d0        # the big blob: the green LEDs blink with the ring
    cmp     2, d0
    bne     lsv_shield
    or      W_GREEN, d2
lsv_shield:
    mov     (LED_SHIELD_NEW), d0    # a new shield: a new sample of 30% of the red LEDs
    cmp     0, d0
    beq     lsv_sh_t
    clr     d0
    mov     d0, (LED_SHIELD_NEW)
    mov     LED_SHIELD_P, d0
    mov     led_red, a0
    mov     LED_SHMASK, a1
    call    led_draw, 0, 0
lsv_sh_t:
    mov     (LED_SHIELD_T), d0
    sub     d3, d0
    ble     lsv_water
    or      W_SHIELD, d2
lsv_water:
    mov     (LED_WATER), d0
    cmp     0, d0
    beq     lsv_tank
    or      W_RAND, d2
    mov     (LED_RND_T), d0
    sub     d3, d0
    bgt     lsv_tank
    mov     d3, d0
    add     LED_RND_MS, d0
    mov     d0, (LED_RND_T)
    mov     (LED_WATER), d0
    mov     led_all, a0
    mov     LED_RNDMASK, a1
    call    led_draw, 0, 0
lsv_tank:
    movhu   (CURRENT_PART_ID), d0   # the tank's panel, while thread 59 shows it
    cmp     0x3E85, d0
    bne     lsv_tank_off
    movhu   (THREADS_DATA + 59 * 4 + PC_OFFSET), d0
    cmp     INACTIVE_THREAD, d0
    beq     lsv_tank_off
    movhu   (VM_VARIABLES + 2 * 0xFA), d0   # a press of cell 0x0B: its LEDs from now on
    cmp     0, d0
    beq     lt_latch
    movhu   (VM_VARIABLES + 2 * 0x5F), d0
    cmp     0x0B, d0
    bne     lt_latch
    mov     1, d0
    mov     d0, (LED_TANK)
lt_latch:
    mov     (LED_TANK), d0
    cmp     0, d0
    beq     lt_blocks
    or      W_TMANY, d2
lt_blocks:
    movhu   (VM_VARIABLES + 2 * 0x67), d0
    cmp     2, d0
    blt     lt_lamps
    or      W_TB1, d2
    cmp     3, d0
    blt     lt_lamps
    or      W_TB2, d2
lt_lamps:
    movhu   (VM_VARIABLES + 2 * 0x72), d0
    cmp     0, d0
    beq     lt_l2
    or      W_TR1, d2
lt_l2:
    movhu   (VM_VARIABLES + 2 * 0x71), d0
    cmp     0, d0
    beq     lt_l3
    or      W_TR2, d2
lt_l3:
    movhu   (VM_VARIABLES + 2 * 0x74), d0
    cmp     0, d0
    beq     lt_l4
    or      W_TG1, d2
lt_l4:
    movhu   (VM_VARIABLES + 2 * 0x75), d0
    cmp     0, d0
    beq     lt_white
    or      W_TG2, d2
lt_white:
    movhu   (VM_VARIABLES + 2 * 0x67), d0   # the white button: lit while (frame - t6 - 1) mod 4 < 2
    cmp     6, d0
    bne     lsv_lift
    mov     (LED_T6), d1
    cmp     0, d1
    beq     lsv_lift
    mov     (FRAME_NO), d0
    sub     d1, d0
    and     3, d0
    cmp     2, d0
    bcc     lsv_lift
    or      W_APC, d2
    bra     lsv_lift
lsv_tank_off:
    clr     d0
    mov     d0, (LED_TANK)
    mov     d0, (LED_T6)
lsv_lift:
    call    led_lift, 0, 0          # the lift's chase, the guard's light: d0 = their W_ bits
    or      d0, d2
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

# led_skel(d0 = a PLAY_SOUND 0x5A's pc) -> d0 = 1 when it is a dying character's (led_skel_pcs, for the part now).
# Leaf; uses d0, d1, a1.
led_skel:
    mov     d0, mdr                 # (the pc)
    mov     led_skel_pcs, a1
lsk_next:
    movhu   (a1), d0                # the part (0: the end)
    cmp     0, d0
    beq     lsk_ret
    movhu   (CURRENT_PART_ID), d1
    cmp     d1, d0
    bne     lsk_skip
    movhu   (2, a1), d0
    mov     mdr, d1
    cmp     d1, d0
    bne     lsk_skip
    mov     1, d0
    rets
lsk_skip:
    add     4, a1
    bra     lsk_next
lsk_ret:
    rets

# led_lift -> d0 = W_LIFT while the lift's light bounces (LED_LIFTMASK built: the lead and, by the firmware's flushes,
# the trail: the one behind it every other flush, the next one every fourth), | W_GLIGHT while the guard's light is
# lit; 0 else.
led_lift:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d3                      # d3 = the W_ bits
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E83, d0
    bne     ll_lift
    movhu   (THREADS_DATA + 2 * 4 + PC_OFFSET), d0   # the guard's light: thread 2 at 0x0C22-0x0C27
    cmp     0x0C22, d0
    bcs     ll_off
    cmp     0x0C27, d0
    bhi     ll_off
    or      W_GLIGHT, d3
    bra     ll_off
ll_lift:
    cmp     0x3E84, d0
    bne     ll_off
    movhu   (VM_VARIABLES + 2 * 0x67), d0
    cmp     79, d0
    bne     ll_109
    movhu   (THREADS_DATA + 5 * 4 + PC_OFFSET), d0   # room 79: thread 5, 0x081F + 5k
    mov     0x081F, d1
    mov     lift79, a0
    mov     13, d2
    bra     ll_frame
ll_109:
    cmp     109, d0
    bne     ll_off
    movhu   (THREADS_DATA + 1 * 4 + PC_OFFSET), d0   # room 109: thread 1
    cmp     0x089A, d0
    bne     ll_109lr
    clr     d2                      # at rest on the left
    bra     ll_pos
ll_109lr:
    mov     0x0864, d1
    mov     lift109, a0
    mov     11, d2                  # 0x0864-0x087D (k 0-5), then 0x0882-0x0896 back (k 6-10: 0x0882 = 0x0864 + 5 x 6)
ll_frame:
    sub     d1, d0                  # d0 = pc - base
    bcs     ll_keep
    clr     d1
    mov     d1, mdr
    mov     5, d1
    divu    d1, d0
    mov     mdr, d1
    cmp     0, d1
    bne     ll_keep                 # (not a frame's pc)
    cmp     d2, d0
    bcc     ll_keep
    movbu   (d0, a0), d2            # d2 = the ring position
ll_pos:
    movbu   (LED_LIFT), d0
    cmp     d2, d0
    beq     ll_mask
    movbu   (LED_LIFT + 1), d1      # moved: the trail moves up
    movbu   d1, (LED_LIFT + 2)
    movbu   d0, (LED_LIFT + 1)
    movbu   d2, (LED_LIFT)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (LED_LIFT_T)
ll_mask:
    mov     LED_LIFTMASK, a1
    clr     d0
    mov     LED_REGS, d1
ll_clr:
    movbu   d0, (a1)
    inc     a1
    add     -1, d1
    bne     ll_clr
    movbu   (LED_LIFT), d0          # the lead: always
    call    lift_set, 0, 0
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     (LED_LIFT_T), d1        # the light at rest a while: the trail out
    mov     d0, d2
    sub     d1, d2
    cmp     LED_TRAIL_MS, d2
    bcc     ll_on
    clr     d1
    mov     d1, mdr
    mov     LED_PWM_MS, d1
    divu    d1, d0
    mov     d0, d2                  # d2 = flushes so far
    btst    1, d2
    bne     ll_t2
    movbu   (LED_LIFT + 1), d0      # the one behind: every other flush
    call    lift_set, 0, 0
ll_t2:
    btst    3, d2
    bne     ll_on
    movbu   (LED_LIFT + 2), d0      # the next: every fourth
    call    lift_set, 0, 0
ll_on:
    or      W_LIFT, d3
    bra     ll_ret
ll_keep:
    movbu   (LED_LIFT), d0          # between frames (or a pc of another of its stretches): as last shown
    cmp     0xFF, d0
    bne     ll_mask
    bra     ll_ret
ll_off:
    mov     -1, d0                  # no lift: the chase starts afresh next time
    movbu   d0, (LED_LIFT)
    movbu   d0, (LED_LIFT + 1)
    movbu   d0, (LED_LIFT + 2)
ll_ret:
    mov     d3, d0
    ret     [d2,d3,a2,a3], 0x20

# lift_set(d0 = a ring position 0-7, or 0xFF: none): its PANEL MEMORY LED into LED_LIFTMASK. Leaf; uses d0, d1, a0, a1.
lift_set:
    cmp     8, d0
    bcc     lse_ret
    asl     1, d0
    mov     led_pm_seq, a0
    add     d0, a0
    movbu   (a0), d0                # the register
    movbu   (1, a0), d1             # the bit
    mov     LED_LIFTMASK, a1
    add     d0, a1
    movbu   (a1), d0
    or      d1, d0
    movbu   d0, (a1)
lse_ret:
    rets

# led_draw(d0 = chance of 256, a0 = the LED bits to draw from, 20 bytes; a1 = out, 20 bytes): each of those bits set
# with that chance (a linear congruential generator, LED_SEED, its bits 16-23): the waterfall's random LEDs, the
# shield's 30% of the red ones.
led_draw:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, (0x04, sp)          # the chance
    mov     a1, a2
    mov     a0, a3
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
    mov     (0x04, sp), d1
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
led_tank:                           # the tank's "lot of LEDs": 30 drawn once (probes/ledmasks.py)
    .byte   0x28, 0x2A, 0x1C, 0x09, 0x08, 0x00, 0x07, 0x0A, 0xE5, 0x80, 0x04, 0x52, 0x00, 0x00, 0x02, 0x00, 0x01, 0x00, 0x01, 0x01
led_r13:                            # register 13: STRINGS & VOCAL ... ACCORDION REGISTER (8 red)
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_r12:                            # register 12: SOLO ... TRANSPOSE / OCTAVE (8 red)
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_ie1:                            # INTRO & ENDING 1 (red)
    .byte   0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_ie2:                            # INTRO & ENDING 2 (red)
    .byte   0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_beat2:                          # BEAT 2 (green)
    .byte   0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_beat3:                          # BEAT 3 (green)
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_apc:                            # AUTO PLAY CHORD MODE, SOUND ARRANGER SET, AUTO PLAY CHORD OFF/ON, SOUND ARRANGER OFF/ON
    .byte   0x00, 0x00, 0x00, 0x00, 0x10, 0x10, 0x10, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_g2:                             # SPLIT POINT G2: the leftmost red LED (x 202 of the layout)
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_pm_seq:                         # the PANEL MEMORY ring left to right: 2, 1, 8, 7, 6, 5, 4, 3 (register, bit)
    .byte   8, 0x40, 15, 0x01, 9, 0x80, 9, 0x40, 9, 0x20, 8, 0x08, 8, 0x10, 8, 0x20
lift79:                             # room 79's frames k = 0-12 -> ring positions (min(k, 12 - k) of 6, at 7/6)
    .byte   0, 1, 2, 4, 5, 6, 7, 6, 5, 4, 2, 1, 0
lift109:                            # room 109's: 6 left to right (of 5, at 7/5), then 5 back (of 4, at 7/4)
    .byte   0, 1, 3, 4, 6, 7, 7, 5, 3, 2, 0
    .align  2
led_skel_pcs:                       # the part, the PLAY_SOUND 0x5A's pc of a dying character (guards', then Lester's)
    .word   0x3E83, 0x1044, 0x3E84, 0x4D16, 0x3E86, 0x417A
    .word   0x3E83, 0x0FD6, 0x3E84, 0x4CA4, 0x3E86, 0x4101
    .word   0
    .align  4
    .align  4
led_groups:                         # LedWrite: each wanted bit and the LEDs it lights
    .long   W_RED, led_red
    .long   W_REDL, led_redl
    .long   W_REDR, led_redr
    .long   W_PM, led_pm
    .long   W_GREEN, led_green
    .long   W_RAND, LED_RNDMASK
    .long   W_SHIELD, LED_SHMASK
    .long   W_TMANY, led_tank
    .long   W_TB1, led_r13
    .long   W_TB2, led_r12
    .long   W_TR1, led_ie1
    .long   W_TR2, led_ie2
    .long   W_TG1, led_beat2
    .long   W_TG2, led_beat3
    .long   W_APC, led_apc
    .long   W_LIFT, LED_LIFTMASK
    .long   W_GLIGHT, led_g2
    .long   W_ALL, led_all
    .long   0
