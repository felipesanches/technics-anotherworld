# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# leds.s -- the control panel's LEDs follow the game (README-CNV.md, "The panel's LEDs"; Felipe, 2026-11-02): from the
# end of the firmware search to the quit every LED is off but those the game's effects light: the red LEDs at a laser
# shot (a guard's: all of them; Lester's: those of the half of the instrument he shoots towards), the eight PANEL
# MEMORY LEDs pulsing while his gun builds a charge (and, once it is the big ball, the green ones blinking with them),
# a flash of about 30% of the red LEDs (each with that chance, drawn anew each time) when a small charge is let go as
# a shield, every LED while the
# mega-blast shows, the green ones (the PANEL MEMORY ring's too) blinking fast at random while the gun recharges at a station, every LED at the intro's lightning and thunder (blinking at the strike), and LEDs lit at
# random by the waterfall, more of them the louder it is (led_water), and the battle tank's panel mirrored (its LEDs,
# button blocks and lamps; its blinking white button on the four AUTO PLAY CHORD / SOUND ARRANGER LEDs), the green
# LEDs (the PANEL MEMORY ring's too) flashing when a skeleton explodes, when the lamps of a lamp holder shot down
# burst and at the explosion in the lake Lester lands in, the lift's bouncing light chased along the PANEL MEMORY ring (2-1-8-7-6-5-4-3 left to right in eight even steps
# over the light's sweep, 3 back to 2 on its way back: the lead and the one behind it, two at most; none once the light
# is gone), and a blinking light
# above the stranded guard (part 0x3E86, room 170) on the red LATIN & WORLD LED, the guard under the glass
# globe in the dome (part 0x3E84, room 80) on PANEL MEMORY 1-4, and the globe's crash: the ring pulsing and fireworks
# on the LEDs around it, the nearer the more (led_glass), and the green LEDs flashing at each door panel a mega-blast
# beam bursts (the HBHK corridor's doors, part 0x3E84; over the blast's own all-LED flash). Shared by both builds; the LED effects setting
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
#   the lake           SET_PALETTE 0x02 at pc 0x3BCD in part 0x3E82, thread 3, at its tick 25 (with sounds 0x3E and
#                      0x31): the explosion in the lake Lester lands in, the screen white for two ticks
#   a skeleton explodes PLAY_SOUND 0x5A at the dying character's pc: guards 3E83 0x1044, 3E84 0x4D16, 3E86 0x417A;
#                      Lester 0x0FD6, 0x4CA4, 0x4101 (0x5A is also the mega-blast's impact: hence the pc)
#   the lamps' burst   PLAY_SOUND 0x5B at pc 0xD050 and 0xD057 of part 0x3E84 (room 107, thread 53): the lamp holder
#                      Lester shot down bursting, its two lamps a tick apart (fingerprints "Sixth pass (b)")
#   the lift's light   part 0x3E84, the drawing thread's pc: room (var 0x67) 79, thread 5, pc 0x081F + 5k, k 0-12
#                      (0-6 left to right, 7-12 back, then a tick with none drawn: 7 ticks each way); room 109,
#                      thread 1, 0x0864-0x087D left to right (6 ticks), 0x0882-0x0896 back (5), waiting at 0x089A on
#                      the left, nothing drawn. (The pcs of the draws; a thread's pc between ticks is the one after
#                      its yield, 4 on: 0x0824 + 5k, 0x081F for the empty tick; 0x0869 + 5k, 0x089B waiting.) The chase: the lead at 8 x (ms into the sweep) / (the sweep's ms), a
#                      tick being var 0xFF x 20 ms
#   a guard's lamp     part 0x3E86, room (var 0x67) 170 (code TXHF, then left): thread 4's pc 0x0FAF-0x0FB9 lit,
#                      0x0FBA-0x0FBB dark (3 ticks on, 2 off), polygon 0xF54C, red dots above the stranded guard
#                      (fingerprints "Sixth pass (a)", guardlamp.py)
#   the dome's guard   part 0x3E84, room (var 0x67) 80, the screen right of room 79's recharge station: thread 5's pc
#                      0xCD93-0xCE86 while he patrols, var 0xE6 his place (-7 far left .. 0 under the big glass globe
#                      .. 7 far right; only his reflection in the globes is drawn), var 0xB2 bit 1 once he is killed
#   the globe's crash  PLAY_SOUND 0x6B at pc 0xCC17 of part 0x3E84 (thread 4, 11 ticks after the shot hits; also
#                      0xCC1D the same tick and 0xCC4B two later; 0x6B in other parts too) (fingerprints "Seventh pass")
#   a door bursting    PLAY_SOUND 0x56 at pc 0x6B85 (the beam going right) or 0x6CE6 (left) of part 0x3E84, thread 47:
#                      a mega-blast beam knocking a panel out of a door (rooms 145-148 from code HBHK; 69, 78, 79), the
#                      burst 9 ticks; also the guards' blast through room 145's left wall (fingerprints "Eighth pass")
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
.equ LED_LAKE_MS,     300            # the lake's
.equ LED_TRAIL_MS,    200            # the chase's trail: out this long after the lead last moved (the light at rest)
.equ LED_GRN_MS,      60             # the recharge's green LEDs drawn again this often ...
.equ LED_GRN_P,       128            # ... each lit with this chance, of 256
.equ LED_GLASS_MS,    1800           # the glass globe's crash: its fireworks last this long
.equ LED_GLPULSE_MS,  120            # ... the PANEL MEMORY ring's pulse: a half period
.equ LED_FW_MS,       50             # ... the sparks drawn again this often
.equ LED_FW_STEP,     90             # ... each ring of distance starting this much after the one inside it
.equ LED_DOOR_MS,     600            # a door panel's burst: the green LEDs flash this long (the burst shows 9 ticks)
.equ LED_DOOR_HALF,   100            # ... on, off, on, ...: each half this long
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
.equ W_GLIGHT,        0x40000        # the guard's light: LATIN & WORLD
.equ W_GRNRND,        0x80000        # the recharge's random green LEDs (LED_GRNMASK)
.equ W_GRNALL,        0x100000       # every green LED, the PANEL MEMORY ring's too (a skeleton, the lake)
.equ W_FW,            0x200000       # the glass crash's sparks (LED_FWMASK)
.equ W_GUARD,         0x400000       # the guard under the globe (LED_GDMASK)

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
    mov     d0, (LED_GLASS_S)
    mov     d0, (LED_DOOR_S)
    mov     LED_GDMASK, a0          # the guard's mask: only registers 8 and 15 are ever written
    mov     LED_REGS / 4, d1
lin_gd:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     lin_gd
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
    bne     lev_lake
    add     LED_SKEL_MS, d1
    mov     d1, (LED_SKEL_T)
    rets
lev_lake:
    cmp     LEV_LAKE, d0
    bne     lev_glass
    add     LED_LAKE_MS, d1
    mov     d1, (LED_SKEL_T)
    rets
lev_glass:
    cmp     LEV_GLASS, d0
    bne     lev_door
    mov     d1, (LED_FW_RT)         # the sparks drawn at once
    or      1, d1                   # (never 0: none)
    mov     d1, (LED_GLASS_S)
    rets
lev_door:
    cmp     LEV_DOOR, d0
    bne     lev_green2
    or      1, d1                   # each burst starts the flashes again
    mov     d1, (LED_DOOR_S)
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
    cmp     0x5B, d2                # the fallen lamp holder's lamps bursting (part 0x3E84, room 107): 0x5B at pc 0xD050,
    bne     ls_nolamp               # then 0xD057 (0x5B is also the gun's charge: hence the pc)
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E84, d0
    bne     ls_nolamp
    mov     a0, d0
    mov     (CUR_BYTECODE), d1
    sub     d1, d0
    add     -1, d0
    cmp     0xD050, d0
    beq     ls_lamp
    cmp     0xD057, d0
    bne     ls_nolamp
ls_lamp:
    mov     LEV_SKEL, d0            # every green LED, as at a skeleton's explosion
    call    LedEvent, 0, 0
    bra     ls_ret
ls_nolamp:
    cmp     0x6B, d2                # the glass globe crashing down in the dome (part 0x3E84, room 80): 0x6B at pc
    bne     ls_noglass              # 0xCC17, thread 4 (0x6B also at 0xCC1D, 0xCC4B after it, and in other parts)
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E84, d0
    bne     ls_noglass
    mov     a0, d0
    mov     (CUR_BYTECODE), d1
    sub     d1, d0
    add     -1, d0
    cmp     0xCC17, d0
    bne     ls_noglass
    mov     LEV_GLASS, d0
    call    LedEvent, 0, 0
    bra     ls_ret
ls_noglass:
    cmp     0x56, d2                # a mega-blast beam bursting a door panel (part 0x3E84: the doors of rooms 145-148,
    bne     ls_nodoor               # 69, 78, 79): 0x56 at pc 0x6B85 (the beam going right) or 0x6CE6 (left), thread 47
    movhu   (CURRENT_PART_ID), d0   # (3E83 and 3E86 play 0x56 at other pcs: hence the part and the pc)
    cmp     0x3E84, d0
    bne     ls_nodoor
    mov     a0, d0
    mov     (CUR_BYTECODE), d1
    sub     d1, d0
    add     -1, d0
    cmp     0x6B85, d0
    beq     ls_door
    cmp     0x6CE6, d0
    bne     ls_nodoor
ls_door:
    mov     LEV_DOOR, d0
    call    LedEvent, 0, 0
    bra     ls_ret
ls_nodoor:
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
    cmp     0x3E82, d0              # the lake's explosion: SET_PALETTE 0x02 at pc 0x3BCD
    bne     lp_intro
    cmp     0x02, d2
    bne     lp_ret
    cmp     0x3BCD, d1
    bne     lp_ret
    mov     LEV_LAKE, d0
    bra     lp_event
lp_intro:
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
    mov     d0, (LED_GLASS_S)
    mov     d0, (LED_DOOR_S)
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
    mov     (LED_GREEN_T), d0       # the recharge: the green LEDs at random, drawn again every LED_GRN_MS
    sub     d3, d0
    ble     lsv_skel
    or      W_GRNRND, d2
    mov     (LED_GRN_RT), d0
    sub     d3, d0
    bgt     lsv_skel
    mov     d3, d0
    add     LED_GRN_MS, d0
    mov     d0, (LED_GRN_RT)
    mov     LED_GRN_P, d0
    mov     led_grnall, a0
    mov     LED_GRNMASK, a1
    call    led_draw, 0, 0
lsv_skel:
    mov     (LED_SKEL_T), d0
    sub     d3, d0
    ble     lsv_blast
    or      W_GRNALL, d2
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
    mov     d3, d0
    call    led_glass, 0, 0         # the glass globe's crash: its fireworks
    or      d0, d2
    call    led_guard, 0, 0         # the guard walking under it
    or      d0, d2
    mov     (LED_DOOR_S), d1        # a door panel bursting: the green LEDs flash, on first; over every other effect's
    cmp     0, d1                   # greens, and the mega-blast's all LEDs dropped meanwhile (Lester's own blast
    beq     lsv_blink               # bursts a door in the same tick: the flashes show through it)
    mov     d3, d0
    sub     d1, d0                  # ms since the burst
    cmp     LED_DOOR_MS, d0
    bcs     lsv_door
    clr     d0
    mov     d0, (LED_DOOR_S)
    bra     lsv_blink
lsv_door:
    clr     d1
    mov     d1, mdr
    mov     LED_DOOR_HALF, d1
    divu    d1, d0                  # halves so far
    and     ~(W_ALL | W_GRNALL | W_GREEN | W_GRNRND), d2
    btst    1, d0
    bne     lsv_blink
    or      W_GRNALL, d2
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

# led_lift -> d0 = W_LIFT while the lift's light bounces (LED_LIFTMASK built: the lead and the one behind it, the
# latter until the light has rested LED_TRAIL_MS), | W_GLIGHT while the guard's light is lit; 0 else.
led_lift:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d3                      # d3 = the W_ bits
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E86, d0
    bne     ll_lift
    movhu   (THREADS_DATA + 4 * 4 + PC_OFFSET), d0   # the guard's lamp: thread 4 at 0x0FAF-0x0FB9 (room 170)
    cmp     0x0FAF, d0
    bcs     ll_off
    cmp     0x0FB9, d0
    bhi     ll_off
    or      W_GLIGHT, d3
    bra     ll_off
ll_lift:
    cmp     0x3E84, d0
    bne     ll_off
    movhu   (VM_VARIABLES + 2 * 0x67), d0
    cmp     79, d0
    bne     ll_109
    movhu   (THREADS_DATA + 5 * 4 + PC_OFFSET), d0   # room 79: thread 5; its pc after the yield that follows a
    cmp     0x081F, d0              # frame's draw: 0x0824 + 5k drew frame k (0-6 left to right, 7-12 back), then
    bne     ll_79                   # 0x081F: a tick with none drawn (k 13)
    mov     0x0824 + 5 * 13, d0
ll_79:
    mov     0x0824, d1
    mov     14, d2
    mov     14, a2                  # a2: the light's period in ticks
    mov     1, a3                   # a3: the phase of frame 0 (step 0 at the left end: the empty tick, between two
    bra     ll_frame                # draws of the leftmost frame; step 7 at k 6, the rightmost)
ll_109:
    cmp     109, d0
    bne     ll_off
    movhu   (THREADS_DATA + 1 * 4 + PC_OFFSET), d0   # room 109: thread 1, 0x0869 + 5k drew frame k: 0-5 left to
    mov     0x0869, d1              # right, 6-10 back; it waits at 0x089B (k 10, drawn once) while Lester is left of
    mov     11, d2                  # the lift, drawing nothing
    mov     11, a2                  # (step 0 at the left end: between k 10 and k 0, both the leftmost frame; step 7
    mov     0, a3                   # in the middle of k 5, the rightmost)
ll_frame:
    sub     d1, d0                  # d0 = pc - base
    bcs     ll_last
    clr     d1
    mov     d1, mdr
    mov     5, d1
    divu    d1, d0
    mov     mdr, d1
    cmp     0, d1
    bne     ll_last                 # (not a frame's pc)
    cmp     d2, d0
    bcc     ll_last
    movbu   (LED_LIFT + 2), d1
    cmp     d1, d0
    beq     ll_where
    movbu   d0, (LED_LIFT + 2)      # a new frame: when it came
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d1
    mov     d1, (LED_LIFT_KT)
    bra     ll_where
ll_last:
    movbu   (LED_LIFT + 2), d0      # between frames (the empty tick, or another of its pcs): the last frame's sweep
    cmp     0xFF, d0                # goes on
    beq     ll_off
ll_where:                           # d0 = k: the period's tick p = (k + a3) mod a2
    mov     a3, d1
    add     d1, d0
    mov     a2, d1
    cmp     d1, d0
    bcs     ll_p
    sub     d1, d0
ll_p:
    mov     d0, (0x04, sp)          # p
    movhu   (VM_VARIABLES + 2 * VAR_PAUSE_SLICES), d0
    mov     SLICE_MS, d1
    mul     d1, d0                  # d0 = a tick's ms (the frame's pause)
    cmp     0, d0
    bne     ll_tick
    mov     80, d0
ll_tick:
    mov     d0, d2                  # d2 = the tick
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     (LED_LIFT_KT), d1
    sub     d1, d0                  # d0 = ms into this frame, short of a tick (a late frame: held)
    cmp     d2, d0
    bcs     ll_into
    mov     d2, d1                  # the same frame two ticks on: the light waits, not drawn (room 109): the chase out
    asl     1, d1
    cmp     d1, d0
    bcc     ll_gone
    mov     d2, d0
    add     -1, d0
ll_into:
    mov     (0x04, sp), d1
    mul     d2, d1
    add     d1, d0                  # ms into the period
    mov     14, d1
    mul     d1, d0
    mov     a2, d1
    mul     d2, d1                  # the period's ms
    clr     d2
    mov     d2, mdr
    divu    d1, d0                  # d0 = the step, 0-13, evenly over the period: 0-7 left to right, 8-13 back
    cmp     7, d0                   # (to 6 ... 1)
    bls     ll_lead
    mov     14, d1
    sub     d0, d1
    mov     d1, d0
ll_lead:
    mov     d0, d2                  # d2 = the lead's ring position
    movbu   (LED_LIFT), d0
    cmp     d2, d0
    beq     ll_mask
    movbu   d0, (LED_LIFT + 1)      # moved: the old lead behind it
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
    mov     (LED_LIFT_T), d1        # the light at rest a while: the one behind it out
    sub     d1, d0
    cmp     LED_TRAIL_MS, d0
    bcc     ll_on
    movbu   (LED_LIFT + 1), d0      # the one behind it
    call    lift_set, 0, 0
ll_on:
    or      W_LIFT, d3
    bra     ll_ret
ll_off:
    mov     -1, d0                  # no lift: the chase starts afresh next time
    movbu   d0, (LED_LIFT + 2)
ll_gone:
    mov     -1, d0                  # (the light waiting: its frame kept, to tell when it moves again)
    movbu   d0, (LED_LIFT)
    movbu   d0, (LED_LIFT + 1)
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

# led_guard -> d0 = W_GUARD while the guard under the glass globe patrols (part 0x3E84, room (var 0x67) 80, thread
# 5's pc 0xCD93-0xCE86, var 0xB2 bit 1 clear: alive), LED_GDMASK then his place on PANEL MEMORY 1-4: var 0xE6, -7 at
# the far left to +7 at the far right, 0 right under the globe, in seven half steps: 1, 1+2, 2, 2+3 (under the globe),
# 3, 3+4, 4 (led_gd_r8, led_gd_r15); else 0. Leaf.
led_guard:
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E84, d0
    bne     lgd_none
    movhu   (VM_VARIABLES + 2 * 0x67), d0
    cmp     80, d0
    bne     lgd_none
    movhu   (VM_VARIABLES + 2 * 0xB2), d0
    btst    0x02, d0
    bne     lgd_none
    movhu   (THREADS_DATA + 5 * 4 + PC_OFFSET), d0
    cmp     0xCD93, d0
    bcs     lgd_none
    cmp     0xCE86, d0
    bhi     lgd_none
    movhu   (VM_VARIABLES + 2 * 0xE6), d0
    exth    d0
    cmp     -7, d0                  # (alerted, he walks on to 14: the far right)
    bge     lgd_lo
    mov     -7, d0
lgd_lo:
    cmp     7, d0
    ble     lgd_hi
    mov     7, d0
lgd_hi:
    add     7, d0
    mov     led_gd_r8, a0
    add     d0, a0
    movbu   (a0), d1
    mov     LED_GDMASK, a0
    movbu   d1, (8, a0)
    mov     led_gd_r15, a0
    add     d0, a0
    movbu   (a0), d1
    mov     LED_GDMASK, a0
    movbu   d1, (15, a0)
    mov     W_GUARD, d0
    rets
lgd_none:
    clr     d0
    rets

# led_glass(d0 = now) -> d0 = the W_* bits of the glass globe's crash (LEV_GLASS), 0 when none: for LED_GLASS_MS the
# PANEL MEMORY ring pulsing, on and off every LED_GLPULSE_MS, and the other LEDs sparking around it, drawn anew every
# LED_FW_MS: each LED of ring k of distance from the ring (led_fw0-3, probes/ledrings.py) lit with chance
# led_fw_p[k] x (what is left of the effect), from k x LED_FW_STEP on: the near ones first and most, the far ones
# later and sparser, all fading out.
led_glass:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d3                  # d3 = now
    mov     (LED_GLASS_S), d0
    cmp     0, d0
    beq     lgl_none
    mov     d3, d2
    sub     d0, d2                  # d2 = ms into it
    cmp     LED_GLASS_MS, d2
    bcs     lgl_on
    clr     d0
    mov     d0, (LED_GLASS_S)
lgl_none:
    clr     d0
    bra     lgl_ret
lgl_on:
    mov     (LED_FW_RT), d0
    sub     d3, d0
    bgt     lgl_pulse
    mov     d3, d0
    add     LED_FW_MS, d0
    mov     d0, (LED_FW_RT)
    clr     d0
    mov     d0, (LED_FWMASK)        # no sparks yet: LED_FWMASK's 20 bytes cleared
    mov     d0, (LED_FWMASK + 4)
    mov     d0, (LED_FWMASK + 8)
    mov     d0, (LED_FWMASK + 12)
    mov     d0, (LED_FWMASK + 16)
    clr     d0
    mov     d0, (0x04, sp)          # (0x04, sp) = the ring k
lgl_ring:
    mov     (0x04, sp), d0
    mov     LED_FW_STEP, d1
    mulu    d1, d0                  # its start
    cmp     d0, d2
    bcs     lgl_pulse               # not yet (nor the rings outside it)
    mov     LED_GLASS_MS, d0        # the chance: led_fw_p[k] x (LED_GLASS_MS - ms) / LED_GLASS_MS
    sub     d2, d0
    mov     led_fw_p, a0
    mov     (0x04, sp), d1
    add     d1, a0
    movbu   (a0), d1
    mulu    d1, d0
    clr     d1
    mov     d1, mdr
    mov     LED_GLASS_MS, d1
    divu    d1, d0
    mov     d0, (0x08, sp)          # (0x08, sp) = the chance
    mov     (0x04, sp), d1          # a0 = led_fw0 + 20 k
    mov     LED_REGS, d0
    mulu    d0, d1
    mov     led_fw0, a0
    add     d1, a0
    mov     (0x08, sp), d0
    mov     LED_FWTMP, a1
    call    led_draw, 0, 0
    mov     LED_FWTMP, a0           # joined to LED_FWMASK
    mov     LED_FWMASK, a1
    mov     LED_REGS / 4, d1
lgl_or:
    mov     (a0), d0
    mov     (a1), d3
    or      d3, d0
    mov     d0, (a1)
    add     4, a0
    add     4, a1
    add     -1, d1
    bne     lgl_or
    mov     (0x04, sp), d0
    inc     d0
    mov     d0, (0x04, sp)
    cmp     4, d0
    bne     lgl_ring
lgl_pulse:
    mov     W_FW, d3                # the sparks; the ring's pulse: on in the even halves
    mov     d2, d0
    clr     d1
    mov     d1, mdr
    mov     LED_GLPULSE_MS, d1
    divu    d1, d0
    btst    1, d0
    bne     lgl_d3
    or      W_PM, d3
lgl_d3:
    mov     d3, d0
lgl_ret:
    ret     [d2,d3,a2,a3], 0x20

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
led_pm:                             # ... the PANEL MEMORY ring (8): green on the instrument (Felipe 2026-11-03), amber in
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00
led_grnall:                         # the parts list; with led_green: every green LED (30)
    .byte   0x00, 0x10, 0x10, 0x10, 0x11, 0x13, 0x01, 0x12, 0x7F, 0xF2, 0x03, 0x83, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x02, 0x00
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
led_latin:                          # LATIN & WORLD (red; Felipe 2026-11-03, in place of SPLIT POINT G2)
    .byte   0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_fw0:                            # the LEDs by their distance from the PANEL MEMORY ring's centre (probes/ledrings.py,
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x86, 0x1A, 0x00, 0x3C, 0x0F, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00
led_fw1:                            # MAME layout units): below 250 (15 LEDs), 250-500 (26), 500-900 (8), the left
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xC3, 0xF0, 0x61, 0x02, 0x00, 0x03, 0x03, 0x01, 0x00
led_fw2:                            # half of the instrument (44)
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9E, 0x00, 0x00, 0x00, 0x00, 0x02, 0x03
led_fw3:
    .byte   0x3F, 0x3F, 0x3F, 0x3F, 0x1F, 0x1F, 0x1F, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_fw_p:                           # each ring's chance at the crash, of 256 (then fading with the effect)
    .byte   220, 140, 80, 30
led_gd_r8:                          # the guard's var 0xE6 + 7 (0-14): his PANEL MEMORY 2, 3, 4 (register 8: 0x40 0x20 0x10)
    .byte   0x00, 0x00, 0x40, 0x40, 0x40, 0x40, 0x60, 0x60, 0x60, 0x20, 0x20, 0x30, 0x30, 0x10, 0x10
led_gd_r15:                         # ... and PANEL MEMORY 1 (register 15: 0x01)
    .byte   0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
led_pm_seq:                         # the PANEL MEMORY ring left to right: 2, 1, 8, 7, 6, 5, 4, 3 (register, bit)
    .byte   8, 0x40, 15, 0x01, 9, 0x80, 9, 0x40, 9, 0x20, 8, 0x08, 8, 0x10, 8, 0x20
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
    .long   W_GLIGHT, led_latin
    .long   W_GRNRND, LED_GRNMASK
    .long   W_GRNALL, led_grnall
    .long   W_FW, LED_FWMASK
    .long   W_GUARD, LED_GDMASK
    .long   W_ALL, led_all
    .long   0
