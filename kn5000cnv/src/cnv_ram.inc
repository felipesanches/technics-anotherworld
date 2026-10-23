; =============================================================================
; cnv_ram.inc - cnv_platform.asm's variables (no initial data: the firmware zeroes
; the 192 KB at 0x80000 before it loads the converter)
; =============================================================================

CNV_STATE:		DB ?		; 0 before the first call, 1 after it, 2 while a message is up
CNV_EXIT_COUNT:		DB ?		; 1 while EXIT is held
CNV_VIDEO2_LOADED:	DB ?		; the shared polygons are in VIDEO2_BUF
CNV_CUR_ID:		DB ?		; resource being read
CNV_SONG_KIND:		DB ?		; the empty song memory found: 1 = the firmware's chain, 2 = all 0
CNV_Q_HEADER:		DB ?		; the panel query's reply header and bitmap (another_world_vm.asm)
CNV_Q_BITS:		DB ?
CNV_SAVE_INTEAB:	DB ?
CNV_SAVE_INTES1:	DB ?
CNV_SAVE_SC1MOD:	DB ?
CNV_SAVE_SC1CR:		DB ?
CNV_SAVE_BR1CR:		DB ?
CNV_LOADED_PART:	DW ?		; part whose resources are in the buffers (0 = none)
CNV_SAVED_SP:		DD ?		; the firmware's stack, as the first call found it
CNV_FW_OPEN:		DD ?		; this firmware's FileIO routines (CNV_FW_TABLE)
CNV_FW_READ:		DD ?
CNV_FW_SEEK:		DD ?
CNV_FW_CLOSE:		DD ?
CNV_PFCR_COPY:		DD ?		; address of the firmware's RAM copy of PFCR
CNV_CUR_DEST:		DD ?
CNV_CUR_SIZE:		DD ?
CNV_LAST_READ:		DD ?
CNV_EXIT_TEXT:		DD ?		; message to show on leaving (0 = none)
CNV_EXIT_SINCE:		DD ?		; SYSTEM_TICKS when EXIT went down
CNV_TEXT_PTR:		DD ?		; the message being shown
CNV_TEXT_SINCE:		DD ?		; SYSTEM_TICKS when it was first shown
CNV_SAVE_DAC:		DB 48 DUP (?)	; DAC entries 0-15 (R, G, B) as the firmware set them
CNV_NAME:		DB 16 DUP (?)	; "AWnn.BIN"
CNV_NOTERING:		DD ?		; the keybed note ring's buffer address (0 = no keybed)
CNV_KEYS:		DB 16 DUP (?)	; held keybed notes, one bit per MIDI note
CNV_LR:			DB ?		; direction in use: 0 none, 1 right, 2 left
CNV_UD:			DB ?		; 0 none, 1 down, 2 up
CNV_DBG_REPLY:		DB 4 DUP (?)	; the last EXIT query's four reply bytes (probes)
; cnv_sound.asm
SND_READY:		DB ?		; 1 once CNV_SND_INIT has run, until CNV_SND_END
SND_REC:		DB 5 DUP (?)	; the record being sent to the sub CPU
SND_PROG:		DB 32 DUP (?)	; per part 0..15: the (program, selector) last sent, 0FFh = unknown
SND_SLOTS:		DB 32 DUP (?)	; 8 notes sounding: part (0FFh none), note, end tick (0 = held)
MUS_MOD:		DB ?		; 1 while a module plays
MUS_ORDER:		DB ?		; its order index
MUS_NORD:		DB ?		; orders in it
			DB ?
MUS_LOADED:		DW ?		; the module in MUSIC_BUF (resource id, 0 = none)
MUS_POS:		DW ?		; the row's offset in its pattern, 0..1008 in 16s
MUS_TIME:		DD ?		; when the next row is due, in 1/256 ticks (bits 23-8: the tick)
MUS_PER:		DD ?		; a row's length, 1/256 ticks
; cnv_dspsnd.asm
DSND_ON:		DB ?		; 1 while the streamer is in the sub CPU
DSND_BYTE:		DB ?
DSND_TRAMP:		DB 5 DUP (?)	; a trampoline being sent: jp target, ret
			ALIGN 2
DSND_ORIG1:		DD ?		; the sub program's INTT1 and INTT5 handlers (CNV_DSND_INSTALL)
DSND_ORIG5:		DD ?
DSND_HDR:		DB 6 DUP (?)	; an E1 header: destination, count
DSND_SEQ:		DB 4 DUP (?)	; each channel's last sequence byte
DSND_REC:		DB 20 DUP (?)	; a channel record being sent (+1 vol, +4 start, +8 end, +12 loop, +16 step)
