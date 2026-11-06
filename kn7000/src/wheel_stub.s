# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# wheel_stub.s -- the SP7001 build has no code wheel page (wheel.s is KN7APP.BIN's: its files come from the SD card
# through the loader, and its RAM is the converter's): the fifth help page is blank there, and HELP opens page 1.
WheelAtQuestion:
    clr     d0
    rets
WheelSleepMs:
    mov     30, d0
    rets
WheelPoll:
    clr     d0
WheelHide:
WheelRestore:
    rets
WheelShow:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    ShadowClear, 0, 0
    call    ShadowOut, 0, 0
    ret     [d2,d3,a2,a3], 0x20
