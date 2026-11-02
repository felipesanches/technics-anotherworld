# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# audio_stub.s -- the SP7001 build's (MAME only) stand-ins for audio.s, the KN7APP.BIN build's sound
# effects and music through the firmware's MIDI receive path: this build stays silent.

AudioInit:
AudioPoll:
AudioSound:
AudioMusic:
AudioStopAll:
AudioPause:
AudioResume:
    rets

# The help screen's first page's sound status (help.s): no sound, nothing to show.
HelpSoundState:
    clr     d0
    rets
DspModeText:
    rets
DV_MODETXT:                         # the page's sound, keybed-sound and sample-bank lines: empty
DV_KEYSTXT:
DV_BANKTXT:
    .byte   0
    .align  4
