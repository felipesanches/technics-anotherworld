; =============================================================================
; cnv_sound.asm - Another World's sound effects and music on the KN5000's own voices
; =============================================================================
; The KN7000 port's tone-generator mode (../kn7000/src/audio.s, "THE TONE GENERATOR MODE"), on the
; KN5000. No sample is output: every PLAY_SOUND and every row of the music module becomes a note of
; one of the instrument's voices (CNV_SND, tools/aw_sound_map5.py), played by the sub CPU.
;
; HOW: the main CPU tells the sub CPU what to play with 4- and 5-byte records over the inter-CPU
; latch (technics-docs inter-cpu-protocol.md): 90 part note velocity (note on; velocity 0 = off),
; B0 part control value, C0 part program selector 0 (program change). The firmware's main loop,
; which turns MIDI and the keybed into those records, does not run while the game does, so the game
; sends them itself: CNV_SUB_SEND is the firmware's InterCPU_Send_Data_Block (v10 0xEF3345) and its
; byte loop, the same handshake on port Z (bit 3 the sub CPU's ready line, bit 0 our strobe), so it
; needs no address of the firmware's. Seen in MAME on the main screen: C3 pressed on the keybed sends
; 03 | 90 00 3C 64; BRASS sends 04 | C0 00 38 00 00 (kn5000cnv/README.md, "Sound").
;
; WHERE: the sub CPU's parts 0x03-0x0E are the MIDI receive parts of channels 4-15 (piano at power-on;
; 0x00-0x02 are RIGHT 1, RIGHT 2 and LEFT, 0x0F the MIDI drum kit, 0x10-0x16 the accompaniment). The
; game uses
;   parts 0x03-0x06  PLAY_SOUND's channels 0-3 (a program per sound)
;   parts 0x07-0x0A  the music's channels 0-3 (a program per instrument)
; drums included: they are voices at a fixed note (no drum kit plays in MAME), and puts back on leaving
; what the firmware gave those parts at power-on: piano, volume 100, expression 127, pan centre (the
; game refuses to start while a song is in memory, the only other user of those parts).
;
; WHEN: CNV_SND_POLL plays the module rows that are due and ends the notes whose time is up; the VM
; calls it at the end of every frame and all through its frame pause (PAUSE). Time is the firmware's
; 488 Hz counter (SYSTEM_TICKS, 2.048 ms a tick), its low 16 bits.
; =============================================================================

SND_PART_SFX	EQU 03h		; PLAY_SOUND channel c plays on part 3 + c
SND_PART_MUS	EQU 07h		; music channel c on part 7 + c
SND_DRUM_TICKS	EQU 73		; a drum note's length (150 ms)
SND_MIN_TICKS	EQU 15		; the shortest note (30 ms)
SND_MAX_ROWS	EQU 4		; module rows played at most per poll (then the player resyncs)
SND_MARK_VAR	EQU 0F4h	; the music's sync mark (rawgl VAR_MUSIC_SYNC)
SND_SLOT_SFX	EQU 4		; slots 0-3: the music's channels, 4-7: PLAY_SOUND's
LATCH		EQU 140000h	; the inter-CPU latch (main CPU writes reach the sub CPU)
LATCH_STATE	EQU 05E0h	; the firmware's transfer state word (0 idle, 1 sending)

; -----------------------------------------------------------------------------
; CNV_SUB_SEND - XDE = record bytes, C = their count (1..32): one packet to the sub CPU's
; MIDI-record ring (handler 0). Gives up after the firmware's timeouts if the sub CPU never answers.
; -----------------------------------------------------------------------------
CNV_SUB_SEND:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	LD HL, 0
_ss_ready:
	BIT 3, (PZ)		; SSTAT1: the sub CPU is ready
	JR NZ, _ss_go
	INC 1, HL
	CP HL, 0EA60h
	JR ULE, _ss_ready
	JR _ss_out
_ss_go:
	RES 0, (PZ)		; MSTAT0
	LDW (LATCH_STATE), 1
	LD A, C
	DEC 1, A		; handler 0 in bits 7-5, length - 1
	LD (LATCH), A
	LD HL, 0
_ss_ack:
	BIT 3, (PZ)		; the sub CPU took the header
	JR Z, _ss_data
	INC 1, HL
	CP HL, 0EA60h
	JR ULE, _ss_ack
	SET 0, (PZ)
	JR _ss_done
_ss_data:
	SET 0, (PZ)
	LD B, C
_ss_byte:
	LD A, (XDE)
	INC 1, XDE
	LD (LATCH), A
	LD L, 0
_ss_delay:
	INC 1, L		; the firmware's three-step pause between bytes
	CP L, 3
	JR C, _ss_delay
	DJNZ B, _ss_byte
_ss_done:
	LDW (LATCH_STATE), 0
_ss_out:
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

; _snd_send: C = the length of the record in SND_REC
_snd_send:
	PUSH XDE
	LD XDE, SND_REC
	CALL CNV_SUB_SEND
	POP XDE
	RET

; _snd_note: B = part, C = note, A = velocity (0 = off)
_snd_note:
	PUSH BC
	LDB (SND_REC), 90h
	JR _snd_3

; _snd_cc: B = part, C = controller, A = value
_snd_cc:
	PUSH BC
	LDB (SND_REC), 0B0h
_snd_3:
	LD (SND_REC + 1), B
	LD (SND_REC + 2), C
	LD (SND_REC + 3), A
	LD C, 4
	CALL _snd_send
	POP BC
	RET

; _snd_prog: B = part (0..15), C = program, A = bank selector; sent only when the part does not have it
_snd_prog:
	PUSH XHL
	PUSH BC
	LD L, B
	LD H, 0
	SLA 1, HL
	EXTZ XHL
	ADD XHL, SND_PROG	; XHL = this part's (program, selector)
	CP C, (XHL)
	JR NZ, _sp_send
	CP A, (XHL + 1)
	JR Z, _sp_out
_sp_send:
	LD (XHL), C
	LD (XHL + 1), A
	LDB (SND_REC), 0C0h
	LD (SND_REC + 1), B
	LD (SND_REC + 2), C
	LD (SND_REC + 3), A
	LDB (SND_REC + 4), 0
	LD C, 5
	CALL _snd_send
_sp_out:
	POP BC
	POP XHL
	RET

; -----------------------------------------------------------------------------
; Slots: the notes sounding. Slot s: SND_SLOTS + 4s = part (0FFh: none), note, end tick (LE16,
; 0 = held until stopped).
; -----------------------------------------------------------------------------
; _slot_ptr: A = slot -> XHL = its record
_slot_ptr:
	PUSH WA
	AND A, 7
	EXTZ WA
	SLA 2, WA
	EXTZ XWA
	LD XHL, SND_SLOTS
	ADD XHL, XWA
	POP WA
	RET

; _slot_off: A = slot: its note ends
_slot_off:
	PUSH XHL
	PUSH BC
	PUSH WA
	CALL _slot_ptr
	LD B, (XHL)
	CP B, 0FFh
	JR Z, _so_out
	LD C, (XHL + 1)
	LDB (XHL), 0FFh
	LD A, 0
	CALL _snd_note
_so_out:
	POP WA
	POP BC
	POP XHL
	RET

; _slot_on: A = slot, B = part, C = note, D = velocity, HL = length in ticks (0 = held)
_slot_on:
	PUSH XWA
	PUSH XHL
	PUSH XIY
	CALL _slot_off
	LD W, A			; W = slot
	LD A, D
	CALL _snd_note
	LD A, W
	PUSH XHL
	CALL _slot_ptr
	LD XIY, XHL		; XIY = the slot's record
	POP XHL
	LD (XIY), B
	LD (XIY + 1), C
	LD WA, HL
	CP WA, 0
	JR Z, _son_store	; held
	ADD WA, (SYSTEM_TICKS)
	CP WA, 0
	JR NZ, _son_store
	INC 1, WA		; (0 means held)
_son_store:
	LD (XIY + 2), WA
	POP XIY
	POP XHL
	POP XWA
	RET

; -----------------------------------------------------------------------------
; CNV_SND_INIT - at the start: the parts' programs unknown, no note, no module; the drum part gets
; the GM-layout kit
; -----------------------------------------------------------------------------
CNV_SND_INIT:
	PUSH XWA
	PUSH XBC
	PUSH XHL
	LD XHL, SND_PROG
	LD B, 32
_si_prog:
	LDB (XHL), 0FFh
	INC 1, XHL
	DJNZ B, _si_prog
	LD XHL, SND_SLOTS
	LD B, 8
_si_slot:
	LDB (XHL), 0FFh
	LDW (XHL + 2), 0
	INC 4, XHL
	DJNZ B, _si_slot
	LDB (MUS_MOD), 0
	LDW (MUS_LOADED), 0
	LDB (SND_READY), 1
	ifdef SND_TEST
	CALL CNV_SND_TEST
	endif
	POP XHL
	POP XBC
	POP XWA
	RET

	ifdef SND_TEST
; CNV_SND_TEST (test builds, make SND_TEST=1): before the game, one note at a time, 0.5 s on and 0.25 s
; off: piano C3 on each part the game uses (3..10, then the drum part's key 38); then each voice of
; SND_TEST_VOICES on part 3. A recording (-wavwrite) shows which are heard (kn5000cnv/README.md).
CNV_SND_TEST:
	PUSH XIX
	LD XIX, SND_TEST_DRUMS	; the drum keys first, on the rhythm part (its kit unchanged)
_st_drum0:
	LD C, (XIX)
	CP C, 0
	JR Z, _st_parts
	LD B, 14h
	CALL _st_note
	INC 1, XIX
	JR _st_drum0
_st_parts:
	LD B, SND_PART_SFX
_st_part:
	LD C, 0
	LD A, 0
	CALL _snd_prog
	LD C, 60
	CALL _st_note
	INC 1, B
	CP B, SND_PART_MUS + 4
	JR NZ, _st_part
	LD B, SND_PART_DRUM
	LD C, 38
	CALL _st_note
	LD C, 0			; the drum part with the standard kit, selector 0x40
	LD A, 40h
	CALL _snd_prog
	LD C, 38
	CALL _st_note
	LD C, 0
	LD A, 41h
	CALL _snd_prog
	LD XIX, SND_TEST_VOICES
_st_voice:
	LD A, (XIX + 1)
	CP A, 0FFh
	JR Z, _st_drums
	LD B, SND_PART_SFX
	LD C, (XIX)
	CALL _snd_prog
	LD C, 60
	CALL _st_note
	INC 2, XIX
	JR _st_voice
_st_drums:
	LD XIX, SND_TEST_DRUMS
_st_drum:
	LD C, (XIX)
	CP C, 0
	JR Z, _st_out
	LD B, 14h
	CALL _st_note
	INC 1, XIX
	JR _st_drum
_st_out:
	POP XIX
	RET
; _st_note: B = part, C = note: on at velocity 100 for 244 ticks, then off for 122
_st_note:
	LD A, 100
	CALL _snd_note
	LD HL, 244
	CALL _st_wait
	LD A, 0
	CALL _snd_note
	LD HL, 122
; _st_wait: HL ticks
_st_wait:
	PUSH WA
	LD WA, (SYSTEM_TICKS)
	ADD HL, WA
_stw_loop:
	LD WA, (SYSTEM_TICKS)
	SUB WA, HL
	BIT 7, W
	JR NZ, _stw_loop
	POP WA
	RET
SND_TEST_VOICES:	; (program, selector): candidate voices
	db 56, 000h, 6, 000h, 5, 000h, 60, 000h, 63, 000h, 117, 000h, 118, 000h, 94, 000h
	db 108, 000h, 120, 000h, 104, 000h, 105, 000h, 106, 000h, 84, 000h, 85, 000h, 96, 000h
	db 97, 000h, 98, 000h, 99, 000h, 39, 000h, 32, 000h, 48, 000h, 122, 000h, 123, 000h
	db 1, 000h, 2, 000h, 3, 000h, 16, 000h
	db 0, 0FFh
SND_TEST_DRUMS:		; drum keys, played on the rhythm part 0x14 with whatever kit it has
	db 35, 36, 38, 40, 41, 42, 46, 47, 48, 49, 51, 37, 39, 44, 0
	endif

; CNV_SND_STOPALL - every note ends and the module stops (a part switch, LOAD 0, the help screen)
CNV_SND_STOPALL:
	PUSH WA
	LD A, (SND_READY)
	CP A, 0
	JR Z, _ssa_out
	LDB (MUS_MOD), 0
	LD A, 0
_ssa_slot:
	CALL _slot_off
	INC 1, A
	CP A, 8
	JR NZ, _ssa_slot
_ssa_out:
	POP WA
	RET

; CNV_SND_END - leaving: all notes off on the parts used, and their power-on settings back
CNV_SND_END:
	PUSH XWA
	PUSH XBC
	LD A, (SND_READY)
	CP A, 0
	JR Z, _se_out
	CALL CNV_SND_STOPALL
	LD B, SND_PART_SFX
_se_part:
	CALL _se_restore
	LD C, 0			; piano
	LD A, 0
	CALL _snd_prog
	INC 1, B
	CP B, SND_PART_MUS + 4
	JR NZ, _se_part
	LDB (SND_READY), 0
_se_out:
	POP XBC
	POP XWA
	RET
; _se_restore: B = part: all notes off, volume 100, expression 127, pan centre
_se_restore:
	LD C, 7Bh
	LD A, 0
	CALL _snd_cc
	LD C, 07h
	LD A, 64h
	CALL _snd_cc
	LD C, 0Bh
	LD A, 7Fh
	CALL _snd_cc
	LD C, 0Ah
	LD A, 40h
	JP _snd_cc

; -----------------------------------------------------------------------------
; CNV_SND_PLAY - PLAY_SOUND: XIX = its operands (resource u16 BE, frequency index, volume, channel)
; -----------------------------------------------------------------------------
CNV_SND_PLAY:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIY
	LD A, (SND_READY)
	CP A, 0
	JP Z, _sdp_out
	LD A, (XIX + 4)
	AND A, 3
	ADD A, SND_SLOT_SFX
	LD E, A			; E = slot
	LD A, (XIX + 3)		; volume 0..63
	CP A, 0
	JP Z, _sdp_stop
	CP A, 63
	JR ULE, _sdp_vol
	LD A, 63
_sdp_vol:
	SLA 1, A
	INC 1, A
	LD D, A			; D = velocity
	LD A, (XIX)
	CP A, 0
	JP NZ, _sdp_out		; resource > 0xFF
	LD A, (XIX + 1)
	CP A, 92h
	JP UGE, _sdp_out
	CALL _snd_entry		; XIY = its CNV_SND entry
	LD A, (XIY)
	CP A, 0
	JP Z, _sdp_stop		; silent
	LD H, A			; H = kind
	LD A, E
	SUB A, SND_SLOT_SFX - SND_PART_SFX
	LD B, A			; B = part
	LD C, (XIY + 1)
	LD A, (XIY + 2)
	CALL _snd_prog
	CP H, 2
	JR NZ, _sdp_melodic
	LD C, (XIY + 3)		; a drum: its fixed note
	LD HL, SND_DRUM_TICKS
	JR _sdp_play
_sdp_melodic:
	LD A, (XIX + 2)		; frequency index, 0..39
	CP A, 39
	JR ULE, _sdp_freq
	LD A, 39
_sdp_freq:
	LD L, A			; L = index
	LD A, (XIY + 3)		; note = the note at 8363 Hz + index - 16
	ADD A, L
	SUB A, 16
	CALL _snd_clamp
	LD C, A			; C = note
	LD WA, (XIY + 4)	; ms at 8363 Hz, 0xFFFF loops
	CP WA, 0FFFFh
	JR NZ, _sdp_len
	LD HL, 0
	JR _sdp_play
_sdp_len:
	; ticks = ms x 8363 / Hz / 2.048 = ms x 4083 / Hz
	PUSH BC
	PUSH DE
	LD DE, 4083
	MUL XWA, DE
	LD H, 0
	SLA 1, HL
	EXTZ XHL
	ADD XHL, SND_FREQ
	LD BC, (XHL)		; Hz
	DIV XWA, BC
	POP DE
	POP BC
	CP WA, SND_MIN_TICKS
	JR UGE, _sdp_min
	LD WA, SND_MIN_TICKS
_sdp_min:
	LD HL, WA
_sdp_play:
	LD A, E
	CALL _slot_on
	JR _sdp_out
_sdp_stop:
	LD A, E
	CALL _slot_off
_sdp_out:
	POP XIY
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

; _snd_entry: A = resource id -> XIY = its CNV_SND entry
_snd_entry:
	PUSH XWA
	EXTZ WA
	AND WA, 0FFh
	SLA 3, WA
	EXTZ XWA
	LD XIY, CNV_SND
	ADD XIY, XWA
	POP XWA
	RET

; _snd_clamp: A = a note, possibly below 0 -> 0..127
_snd_clamp:
	BIT 7, A
	RET Z
	LD A, 0
	RET

; -----------------------------------------------------------------------------
; CNV_SND_MUSIC - PLAY_MUSIC: XIX = its operands (resource u16 BE, delay u16 BE, order u8): a
; resource starts its module at that order (with the module's own delay when 0); resource 0 with a
; delay retimes the module playing; both 0 stop it (rawgl snd_playMusic)
; -----------------------------------------------------------------------------
CNV_SND_MUSIC:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	LD A, (SND_READY)
	CP A, 0
	JP Z, _sm_out
	LD B, (XIX)
	LD C, (XIX + 1)		; BC = resource
	LD D, (XIX + 2)
	LD E, (XIX + 3)		; DE = delay
	CP BC, 0
	JR NZ, _sm_start
	CP DE, 0
	JR Z, _sm_stop
	CALL _mus_period
	JP _sm_out
_sm_stop:
	CALL _mus_stop
	JP _sm_out
_sm_start:
	CALL _mus_stop
	CP BC, 92h
	JP UGE, _sm_out
	CP BC, (MUS_LOADED)
	JR Z, _sm_have
	LD WA, BC		; read the module from the floppy
	SLA 2, WA
	EXTZ XWA
	ADD XWA, CNV_SIZES
	LD XWA, (XWA)
	CP XWA, 0
	JP Z, _sm_out		; not on the disk
	CP XWA, CNV_MAX_MUSIC
	JP UGT, _sm_out
	PUSH XDE
	LD A, C
	LD XDE, MUSIC_BUF
	CALL CNV_READ_RES
	POP XDE
	LD (MUS_LOADED), BC
_sm_have:
	LD A, (XIX + 4)
	LD (MUS_ORDER), A
	LD A, (MUSIC_BUF + 3Fh)	; orders in the module (u16 BE; at most 0x80)
	LD (MUS_NORD), A
	LDW (MUS_POS), 0
	CP DE, 0
	JR NZ, _sm_delay
	LD D, (MUSIC_BUF)	; the module's own delay
	LD E, (MUSIC_BUF + 1)
_sm_delay:
	CALL _mus_period
	LD WA, (SYSTEM_TICKS)	; the first row now
	EXTZ XWA
	SLL 8, XWA
	LD (MUS_TIME), XWA
	LDB (MUS_MOD), 1
_sm_out:
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

; _mus_period: DE = delay: a row lasts delay x 60000 / 7159092 ms (the Paula clock, rawgl SfxPlayer)
; = delay x 1073 / 1024 ticks / 256; MUS_PER is in 1/256 ticks
_mus_period:
	PUSH XWA
	PUSH DE
	LD WA, DE
	LD DE, 1073
	MUL XWA, DE
	SRL 10, XWA
	LD (MUS_PER), XWA
	POP DE
	POP XWA
	RET

; _mus_stop: no module; the music's notes end
_mus_stop:
	PUSH WA
	LDB (MUS_MOD), 0
	LD A, 0
_mst_slot:
	CALL _slot_off
	INC 1, A
	CP A, SND_SLOT_SFX
	JR NZ, _mst_slot
	POP WA
	RET

; _mus_row: the four channels' events of the current row, then the next row (rawgl handleEvents)
_mus_row:
	PUSH XWA
	PUSH XBC
	PUSH XIY
	LD A, (MUS_ORDER)
	CP A, 80h
	JR UGE, _mr_end
	EXTZ WA
	LD XIY, MUSIC_BUF + 40h
	ADD XIY, XWA		; (the order table at +0x40, one byte each)
	LD A, (XIY)		; the pattern
	EXTZ WA
	SLA 10, WA		; 1024 bytes each (64 rows of 16)
	ADD WA, (MUS_POS)
	EXTZ XWA
	LD XIY, MUSIC_BUF + 0C0h
	ADD XIY, XWA		; XIY = this row's four events
	LD C, 0
_mr_ch:
	CALL _mus_event		; C = channel, XIY = its event
	LD A, (MUS_MOD)
	CP A, 0
	JR Z, _mr_out
	INC 4, XIY
	INC 1, C
	CP C, 4
	JR NZ, _mr_ch
	LD WA, (MUS_POS)
	ADD WA, 16
	CP WA, 1024
	JR ULT, _mr_pos
	LD A, (MUS_ORDER)
	INC 1, A
	LD (MUS_ORDER), A
	CP A, (MUS_NORD)
	JR UGE, _mr_end		; past the last order: the module ends
	LD WA, 0
_mr_pos:
	LD (MUS_POS), WA
	JR _mr_out
_mr_end:
	CALL _mus_stop
_mr_out:
	POP XIY
	POP XBC
	POP XWA
	RET

; _mus_event: C = channel 0..3 (= its slot), XIY = its event: u16 BE note (an Amiga period, 0xFFFD the
; sync mark, 0xFFFE stop), u16 BE instrument << 12 | effect << 8 | value (rawgl SfxPlayer::handlePattern)
_mus_event:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	LD H, (XIY)
	LD L, (XIY + 1)		; HL = note
	LD D, (XIY + 2)
	LD E, (XIY + 3)		; DE = instrument / effect / value
	CP HL, 0FFFDh
	JR NZ, _me_notmark
	LD A, SND_MARK_VAR	; var 0xF4 = the value
	CALL _write_vm_var
	JP _me_out
_me_notmark:
	CP HL, 0FFFEh
	JR NZ, _me_notstop
	LD A, C
	CALL _slot_off
	JP _me_out
_me_notstop:
	LD A, D
	SRL 4, A		; instrument 1..15 (0: none)
	CP A, 0
	JP Z, _me_out
	DEC 1, A
	EXTZ WA
	SLA 2, WA
	EXTZ XWA
	LD XIX, MUSIC_BUF + 2
	ADD XIX, XWA		; XIX = the instrument: u16 BE resource, u16 BE volume
	LD A, (XIX)
	CP A, 0
	JP NZ, _me_out		; resource > 0xFF
	LD A, (XIX + 1)
	CP A, 0
	JP Z, _me_out
	CP A, 92h
	JP UGE, _me_out
	PUSH XIY
	CALL _snd_entry
	LD XIX, XIY		; (keep the entry in XIX: XIY is the row's event)
	POP XIY
	PUSH XIX
	LD XIX, MUSIC_BUF + 2	; the volume again
	LD A, D
	SRL 4, A
	DEC 1, A
	EXTZ WA
	SLA 2, WA
	EXTZ XWA
	ADD XIX, XWA
	LD A, (XIX + 3)		; volume (the low byte of the u16 BE)
	POP XIX
	LD B, D
	AND B, 0Fh		; effect: 5 volume up, 6 volume down
	CP B, 5
	JR NZ, _me_not5
	ADD A, E
	CP A, 63
	JR ULE, _me_vol
	LD A, 63
	JR _me_vol
_me_not5:
	CP B, 6
	JR NZ, _me_vol
	SUB A, E
	JR NC, _me_vol
	LD A, 0
_me_vol:
	CP HL, 0
	JP Z, _me_out		; no note: a volume change, nothing to send
	CP A, 0
	JR NZ, _me_audible
	LD A, C			; volume 0: silent
	CALL _slot_off
	JP _me_out
_me_audible:
	SLA 1, A
	INC 1, A
	LD D, A			; D = velocity
	LD A, (XIX)		; kind
	CP A, 0
	JP Z, _me_out
	LD A, C
	ADD A, SND_PART_MUS
	LD B, A			; B = part
	PUSH BC
	LD C, (XIX + 1)
	LD A, (XIX + 2)
	CALL _snd_prog
	POP BC
	LD A, (XIX)
	CP A, 2
	JR NZ, _me_melodic
	LD E, (XIX + 3)		; a drum: its fixed note
	LD HL, SND_DRUM_TICKS
	JR _me_play
_me_melodic:
	PUSH HL
	CALL _mus_semis		; HL = period -> A = semitones above period 428, signed
	ADD A, (XIX + 3)
	CALL _snd_clamp
	LD E, A			; E = note
	POP HL
	LD WA, (XIX + 4)	; ms at period 428, 0xFFFF loops
	CP WA, 0FFFFh
	JR NZ, _me_len
	LD HL, 0
	JR _me_play
_me_len:
	; ticks = ms x period / 428 / 2.048 = ms x period / 877
	PUSH BC
	PUSH DE
	LD DE, HL
	MUL XWA, DE
	LD BC, 877
	DIV XWA, BC
	POP DE
	POP BC
	CP WA, SND_MIN_TICKS
	JR UGE, _me_min
	LD WA, SND_MIN_TICKS
_me_min:
	LD HL, WA
_me_play:
	LD A, C			; slot = channel
	LD C, E
	CALL _slot_on
_me_out:
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

; _mus_semis: HL = an Amiga period -> A = the nearest ProTracker note, in semitones above period 428
; (856 -> -12 .. 113 -> +23)
_mus_semis:
	PUSH XHL
	PUSH XIY
	LD XIY, SND_PERIOD_MID
	LD A, -12
_ms_loop:
	CPW (XIY), 0
	JR Z, _ms_done
	CP HL, (XIY)
	JR UGE, _ms_out		; at or above the midpoint below this note: found
	INC 2, XIY
	INC 1, A
	JR _ms_loop
_ms_done:
	LD A, 23
_ms_out:
	POP XIY
	POP XHL
	RET

; -----------------------------------------------------------------------------
; CNV_SND_POLL - the module rows that are due, the notes whose time is up
; -----------------------------------------------------------------------------
CNV_SND_POLL:
	PUSH XWA
	PUSH XBC
	PUSH XHL
	LD A, (SND_READY)
	CP A, 0
	JR Z, _sp2_out
	LD B, SND_MAX_ROWS
_sp2_row:
	LD A, (MUS_MOD)
	CP A, 0
	JR Z, _sp2_slots
	LD WA, (SYSTEM_TICKS)
	SUB WA, (MUS_TIME + 1)	; the row's tick: MUS_TIME's bits 23-8
	BIT 7, W
	JR NZ, _sp2_slots	; not due yet
	CALL _mus_row
	LD XWA, (MUS_TIME)	; the next row
	ADD XWA, (MUS_PER)
	LD (MUS_TIME), XWA
	DJNZ B, _sp2_row
	LD WA, (SYSTEM_TICKS)	; too far behind: from now on
	EXTZ XWA
	SLL 8, XWA
	LD (MUS_TIME), XWA
_sp2_slots:
	LD A, 0
_sp2_slot:
	CALL _slot_ptr
	LD C, (XHL)
	CP C, 0FFh
	JR Z, _sp2_next		; no note
	PUSH WA
	LD WA, (XHL + 2)
	CP WA, 0
	JR Z, _sp2_keep		; held
	LD WA, (SYSTEM_TICKS)
	SUB WA, (XHL + 2)
	BIT 7, W
	JR NZ, _sp2_keep	; not yet
	POP WA
	CALL _slot_off
	JR _sp2_next
_sp2_keep:
	POP WA
_sp2_next:
	INC 1, A
	CP A, 8
	JR NZ, _sp2_slot
_sp2_out:
	POP XHL
	POP XBC
	POP XWA
	RET

; ---- tables ------------------------------------------------------------------
SND_FREQ:	; PLAY_SOUND's 40 frequencies, Hz (rawgl freqTable): a semitone apart
	dw 0CFFh, 0DC3h, 0E91h, 0F6Fh, 1056h, 114Eh, 1259h, 136Ch
	dw 149Fh, 15D9h, 1726h, 1888h, 19FDh, 1B86h, 1D21h, 1EDEh
	dw 20ABh, 229Ch, 24B3h, 26D7h, 293Fh, 2BB2h, 2E4Ch, 3110h
	dw 33FBh, 370Dh, 3A43h, 3DDFh, 4157h, 4538h, 4998h, 4DE5h
	dw 5240h, 5764h, 5C9Ah, 61C8h, 6793h, 6E19h, 7485h, 7BBDh
SND_PERIOD_MID:	; the midpoints between the ProTracker periods 856, 808 .. 120, 113: a period at
		; or above entry k is note k (k - 12 semitones from 428); 0 ends the table
	dw 832, 785, 741, 699, 659, 622, 587, 554, 523, 494, 467, 441
	dw 416, 393, 371, 350, 330, 311, 294, 277, 262, 247, 233, 220
	dw 208, 196, 185, 175, 165, 156, 147, 139, 131, 124, 117, 0
