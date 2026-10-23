; =============================================================================
; cnv_dspsnd.asm - the main CPU half of the DSP sound: putting src/awsub.asm into the sub CPU, and driving
; its four channels
; =============================================================================
; The sub CPU's DRAM is written with E1 transfers (CNV_E1_SEND, the firmware's InterCPU_E1_Bulk_Transfer,
; v10 0xEF3457: the port Z handshake, the byte E1 on the latch, a six-byte header -- destination and count --
; then the bytes), which the running sub program takes by micro-DMA (v1.42 MICRODMA_CH0_HANDLER, state 2).
; Its RAM interrupt trampolines (0x400 + 5 x slot: `jp target`, `ret`) are rewritten the same way:
;   slot 24 (0x478), INTT5  -> SUB_TICK   (timer 4; the sub program leaves it unused)
;   slot 20 (0x464), INTT1  -> SUB_HOOK   (the audio tick: sets the streamer up, then the original handler)
; and put back when the game ends. The trampolines' original targets differ between the sub programs, and the
; main CPU cannot read the sub CPU's memory, so they come from a table (DSND_SUBVERS), picked by the start of the
; sub program as the boot sent it: IC19 flash holds it SLIDE4K-compressed at 0x3E0000 (technics-roms-disasm v7
; SubCPU_Send_Payload; kn7000_mame kn5000.cpp), and its first literals, from offset 0x0C, are sub 0x400..0x407:
; the payload entry and slot 1's trampoline, whose target is the sub program's EMPTY_HANDLER. Another sub
; program is left alone: no streamer, no DSP sound.
; =============================================================================

SUB_TRAMP_INTT1	EQU 0464h
SUB_TRAMP_INTT5	EQU 0478h
SUB_FLASH_LIT	EQU 3E000Ch		; the compressed sub program's first literals in IC19 flash: sub 0x400..0x407
SUB_BANK	EQU 0A0000h		; the samples, in the sub CPU's DRAM (kn5000cnv/README.md, "DSP sound")
DSND_RATE	EQU 2500000 / SUB_TREG5	; the streamer's ticks a second (timer 4 at 2.5 MHz; 4000 measured at 625)

; -----------------------------------------------------------------------------
; CNV_E1_SEND - XWA = source (main), XDE = destination (sub), BC = count (1..65535); all registers kept
; -----------------------------------------------------------------------------
CNV_E1_SEND:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	LD XIX, XWA		; XIX = source
	LD HL, 0
_e1_idle:
	LD WA, (LATCH_STATE)	; (the firmware's own transfers must be over)
	CP WA, 0
	JR Z, _e1_ready0
	INC 1, HL
	CP HL, 0EA60h
	JR ULE, _e1_idle
	JP _e1_out
_e1_ready0:
	LD HL, 0
_e1_ready:
	BIT 3, (PZ)
	JR NZ, _e1_go
	INC 1, HL
	CP HL, 0EA60h
	JR ULE, _e1_ready
	JP _e1_out
_e1_go:
	RES 0, (PZ)
	LDW (LATCH_STATE), 2
	LDB (LATCH), 0E1h
	LD HL, 0
_e1_ack:
	BIT 3, (PZ)
	JR Z, _e1_hdr
	INC 1, HL
	CP HL, 0EA60h
	JR ULE, _e1_ack
	SET 0, (PZ)
	JP _e1_done
_e1_hdr:
	SET 0, (PZ)
	; the header: destination (4 bytes, LE), count (2 bytes, LE)
	LD (DSND_HDR), XDE
	LD (DSND_HDR + 4), BC
	LD XWA, DSND_HDR
	LD HL, 6
	CALL _e1_bytes
	LDW (LATCH_STATE), 1
	LD WA, 0
_e1_pause:
	INC 1, WA		; the firmware's pause between the two phases
	CP WA, 0C8h
	JR C, _e1_pause
	LD XWA, XIX
	LD HL, BC
	CALL _e1_bytes
	LD WA, 0
_e1_after:
	INC 1, WA
	CP WA, 0C8h
	JR C, _e1_after
_e1_done:
	LDW (LATCH_STATE), 0
_e1_out:
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

; _e1_bytes: XWA = bytes, HL = count: each to the latch, with the firmware's three-step pause
_e1_bytes:
	PUSH XDE
	LD XDE, XWA
_eb_loop:
	LD A, (XDE)
	INC 1, XDE
	LD (LATCH), A
	LD W, 0
_eb_delay:
	INC 1, W
	CP W, 3
	JR C, _eb_delay
	DEC 1, HL
	CP HL, 0
	JR NZ, _eb_loop
	POP XDE
	RET

; -----------------------------------------------------------------------------
; CNV_DSND_INSTALL - the streamer into the sub CPU, and the two trampolines; Z set when done, NZ when the sub
; program is not one DSND_SUBVERS knows
; -----------------------------------------------------------------------------
CNV_DSND_INSTALL:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	; which sub program: its first eight bytes against each row of DSND_SUBVERS
	LD XIX, DSND_SUBVERS
_di_row:
	LD A, (XIX)
	CP A, 0
	JP Z, _di_fail		; none: leave the sub CPU alone
	LD XDE, SUB_FLASH_LIT
	LD XHL, XIX
	LD B, 8
_di_cmp:
	LD A, (XDE)
	CP A, (XHL)
	JR NZ, _di_next
	INC 1, XDE
	INC 1, XHL
	DJNZ B, _di_cmp
	; a match: the row's two targets
	LD XWA, (XIX + 8)
	LD (DSND_ORIG1), XWA
	LD (AWSUB_IMAGE + (SUB_ORIG_JP - SUB_BASE) + 1), WA	; the streamer's own `jp` to the INTT1 handler
	SRL 16, XWA
	LD (AWSUB_IMAGE + (SUB_ORIG_JP - SUB_BASE) + 3), A
	LD XWA, (XIX + 12)
	LD (DSND_ORIG5), XWA
	JR _di_found
_di_next:
	LD XWA, 16
	ADD XIX, XWA
	JR _di_row
_di_found:
	; the streamer
	LD XWA, AWSUB_IMAGE
	LD XDE, SUB_BASE
	LD BC, AWSUB_IMAGE_LEN
	CALL CNV_E1_SEND
	; INTT5 -> SUB_TICK, then INTT1 -> SUB_HOOK
	LD XWA, SUB_TICK
	CALL _dsnd_tramp
	LD XDE, SUB_TRAMP_INTT5
	LD XWA, DSND_TRAMP
	LD BC, 5
	CALL CNV_E1_SEND
	LD XWA, SUB_HOOK
	CALL _dsnd_tramp
	LD XDE, SUB_TRAMP_INTT1
	LD XWA, DSND_TRAMP
	LD BC, 5
	CALL CNV_E1_SEND
	LDB (DSND_ON), 1
	LD A, 0
	CP A, 0			; Z
	JR _di_out
_di_fail:
	LDB (DSND_ON), 0
	LD A, 1
	CP A, 0			; NZ
_di_out:
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

; DSND_SUBVERS: per sub program, 16 bytes: its first eight (sub 0x400..0x407: `jp RESET`, `ret`, and slot 1's
; `jp EMPTY_HANDLER` as far as its middle byte), the INTT1 handler, the INTT5 handler (EMPTY_HANDLER); then 0.
; From kn7000-emulator roms/kn5000 kn5000_subprogram_v14x.rom (file offset = sub address - 0x400): the
; trampolines at 0x464 and 0x478
DSND_SUBVERS:
	DB 1Bh, 24h, 0F9h, 01h, 0Eh, 1Bh, 0BCh, 0FBh	; v1.42 (firmware v9, v10)
	DD 01FB41h, 01FBBCh
	DB 1Bh, 24h, 0F9h, 01h, 0Eh, 1Bh, 0A5h, 0FBh	; v1.40, v1.41 (firmware v5 - v8)
	DD 01FB2Ah, 01FBA5h
	DB 0

; _dsnd_tramp: XWA = target -> DSND_TRAMP = jp target, ret
_dsnd_tramp:
	LDB (DSND_TRAMP), 1Bh
	LD (DSND_TRAMP + 1), WA
	SRL 16, XWA
	LD (DSND_TRAMP + 3), A
	LDB (DSND_TRAMP + 4), 0Eh
	RET

; -----------------------------------------------------------------------------
; CNV_DSND_REMOVE - stop the streamer, then the sub program's own trampolines back
; -----------------------------------------------------------------------------
CNV_DSND_REMOVE:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	LD A, (DSND_ON)
	CP A, 0
	JR Z, _dr_out
	LDB (DSND_BYTE), 1	; SUB_REQ <- 1: the next audio tick stops timer 4
	LD XWA, DSND_BYTE
	LD XDE, SUB_REQ
	LD BC, 1
	CALL CNV_E1_SEND
	LD WA, (SYSTEM_TICKS)	; ten of our ticks (20 ms): several of the sub CPU's
	ADD WA, 10
	LD DE, WA
_dr_wait:
	LD WA, (SYSTEM_TICKS)
	SUB WA, DE
	BIT 7, W
	JR NZ, _dr_wait
	LD XWA, (DSND_ORIG1)
	CALL _dsnd_tramp
	LD XDE, SUB_TRAMP_INTT1
	LD XWA, DSND_TRAMP
	LD BC, 5
	CALL CNV_E1_SEND
	LD XWA, (DSND_ORIG5)
	CALL _dsnd_tramp
	LD XDE, SUB_TRAMP_INTT5
	LD XWA, DSND_TRAMP
	LD BC, 5
	CALL CNV_E1_SEND
	LDB (DSND_ON), 0
_dr_out:
	POP XDE
	POP XBC
	POP XWA
	RET

; -----------------------------------------------------------------------------
; CNV_DSND_CHANNEL - A = channel 0..3; DSND_REC (+1 vol, +4 start, +8 end, +12 loop, +16 step) is sent as the
; channel's record, then a new sequence byte
; -----------------------------------------------------------------------------
CNV_DSND_CHANNEL:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	AND A, 3
	EXTZ WA
	EXTZ XWA
	LD XHL, XWA		; XHL = channel
	SLA 5, XWA		; x 32
	ADD XWA, CH0
	LD XDE, XWA		; XDE = the record in the sub CPU
	PUSH XDE
	INC 1, XDE		; +1..+19
	LD XWA, DSND_REC + 1
	LD BC, 19
	CALL CNV_E1_SEND
	POP XDE
	ADD XHL, DSND_SEQ	; XHL = this channel's seq, main side
	INCB 1, (XHL)
	LD XWA, XHL
	LD BC, 1
	CALL CNV_E1_SEND	; +0: the new seq
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

; -----------------------------------------------------------------------------
; CNV_SBANK_LOAD - WA = part id (0x3E80..0x3E89): its sounds (CNV_SPARTS) into the sub CPU's DRAM at
; SUB_BANK + their offsets, as 8-bit samples. AWSND.BIN is opened once; each sound's ADPCM is sought (CNV_SOFF)
; and read whole into the screen buffer (free while a part loads: the part's setup points the VM back at its
; own polygons), then decoded (CNV_ADPCM) and sent (CNV_E1_SEND) SB_CHUNK samples at a time. One file because
; opening one costs the firmware about 1.5 s (kn5000cnv/README.md). Without AWSND.BIN the part has no sounds;
; the game goes on.
; -----------------------------------------------------------------------------
CNV_SBANK_LOAD:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	PUSH XIY
	PUSH XIZ
	LD B, (DSND_ON)
	CP B, 0
	JP Z, _sl_out
	CP WA, (DSND_BANK_PART)
	JP EQ, _sl_out
	LD (DSND_BANK_PART), WA
	SUB WA, GAME_PART_FIRST
	SLA 2, WA
	EXTZ XWA
	ADD XWA, CNV_SPARTS
	LD XIZ, (XWA)		; the part's list
	LD (DSND_LIST), XIZ
	LD (DSND_CUR), XIZ
	LD XWA, DSND_FILE
	LD XBC, CNV_MODE_RB
	LD XIX, (CNV_FW_OPEN)
	CALL (XIX)
	CP HL, 0
	JP NE, _sl_none
_sl_sound:
	LD XIZ, (DSND_CUR)	; (the firmware's file routines need not keep XIZ)
	LD A, (XIZ)
	CP A, 0FFh
	JP Z, _sl_close
	EXTZ WA
	EXTZ XWA
	LD XHL, XWA		; XHL = the sound's id
	LD XWA, (XIZ + 1)
	ADD XWA, SUB_BANK
	LD (DSND_DEST), XWA
	LD XWA, XHL
	SLA 3, XWA
	ADD XWA, CNV_SLEN
	LD XDE, (XWA)
	ADD XDE, (XWA + 4)	; length + loop length
	LD (DSND_LEFT), XDE
	LD XWA, XHL
	SLA 2, XWA
	ADD XWA, CNV_SOFF
	LD XWA, (XWA)		; its place in AWSND.BIN
	LD BC, 0		; from the start
	LD XIX, (CNV_FW_SEEK)
	CALL (XIX)
	CP HL, 0
	JP NE, _sl_close	; (the rest would be wrong too)
	LD XBC, (DSND_LEFT)
	INC 1, XBC
	SRL 1, XBC		; its ADPCM bytes
	LD XWA, SCREEN_BUF
	LD XIX, (CNV_FW_READ)
	CALL (XIX)
	LD XWA, 0
	LD (DSND_PRED), XWA
	LDB (DSND_IDX), 0
	LD XWA, SCREEN_BUF
	LD (DSND_SRC), XWA
_sl_chunk:
	LD XBC, (DSND_LEFT)
	CP XBC, 0
	JP EQ, _sl_next
	CP XBC, SB_CHUNK
	JR ULE, _sl_n
	LD XBC, SB_CHUNK
_sl_n:
	LD XIX, (DSND_SRC)
	LD XIY, SB_OUT
	LD WA, BC
	CALL CNV_ADPCM		; (SB_CHUNK is even: a chunk ends on a byte)
	LD XWA, XBC
	SRL 1, XWA
	ADD XIX, XWA
	LD (DSND_SRC), XIX
	LD XWA, SB_OUT
	LD XDE, (DSND_DEST)
	CALL CNV_E1_SEND
	ADD XDE, XBC
	LD (DSND_DEST), XDE
	LD XWA, (DSND_LEFT)
	SUB XWA, XBC
	LD (DSND_LEFT), XWA
	JP _sl_chunk
_sl_next:
	LD XIZ, (DSND_CUR)
	LD XWA, 5
	ADD XIZ, XWA
	LD (DSND_CUR), XIZ
	JP _sl_sound
_sl_close:
	LD XIX, (CNV_FW_CLOSE)
	CALL (XIX)
	JR _sl_out
_sl_none:
	LD XWA, 0
	LD (DSND_LIST), XWA	; no sounds
_sl_out:
	POP XIZ
	POP XIY
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

DSND_FILE:	DB "AWSND.BIN", 0

; -----------------------------------------------------------------------------
; CNV_ADPCM - XIX = IMA ADPCM bytes (low nibble first), XIY = where the samples go, WA = how many (1..65535):
; decode, carrying the predictor and step index in DSND_PRED / DSND_IDX from one call to the next. Each sample
; is the predictor's high byte, as tools/aw_sbank.py decode() makes it (the build checks it against encode()).
; -----------------------------------------------------------------------------
CNV_ADPCM:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	PUSH XIY
	LD BC, WA		; BC = samples left
	LD XHL, (DSND_PRED)
	LD D, (DSND_IDX)
_ad_byte:
	LD A, (XIX)
	INC 1, XIX
	LD E, A
	AND E, 0Fh
	CALL _ad_step
	DEC 1, BC		; (no flags from a word DEC)
	CP BC, 0
	JR Z, _ad_done
	LD E, A
	SRL 4, E
	CALL _ad_step
	DEC 1, BC
	CP BC, 0
	JR NZ, _ad_byte
_ad_done:
	LD (DSND_PRED), XHL
	LD (DSND_IDX), D
	POP XIY
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

; _ad_step: E = a 4-bit code, XHL = the predictor (-32768..32767), D = the step index: both updated, the
; predictor's high byte stored at (XIY+); XWA and XBC kept
_ad_step:
	PUSH XWA
	PUSH XBC
	LD A, D
	EXTZ WA
	SLA 1, WA
	EXTZ XWA
	ADD XWA, ADPCM_STEPS
	LD WA, (XWA)
	EXTZ XWA		; XWA = the step
	LD XBC, XWA
	SRL 3, XBC		; difference = step / 8
	BIT 2, E
	JR Z, _as_b1
	ADD XBC, XWA		; + step
_as_b1:
	SRL 1, XWA
	BIT 1, E
	JR Z, _as_b0
	ADD XBC, XWA		; + step / 2
_as_b0:
	SRL 1, XWA
	BIT 0, E
	JR Z, _as_sign
	ADD XBC, XWA		; + step / 4
_as_sign:
	BIT 3, E
	JR Z, _as_add
	SUB XHL, XBC
	CP XHL, -32768
	JR GE, _as_index
	LD XHL, -32768
	JR _as_index
_as_add:
	ADD XHL, XBC
	CP XHL, 32767
	JR LE, _as_index
	LD XHL, 32767
_as_index:
	LD A, E
	AND A, 7
	EXTZ WA
	EXTZ XWA
	ADD XWA, ADPCM_INDEX
	LD A, (XWA)
	ADD A, D		; -1 .. 96
	BIT 7, A
	JR Z, _as_pos
	LD A, 0
_as_pos:
	CP A, 88
	JR ULE, _as_idx
	LD A, 88
_as_idx:
	LD D, A
	LD (XIY), H		; the sample: bits 15..8 of the predictor
	INC 1, XIY
	POP XBC
	POP XWA
	RET

ADPCM_STEPS:	; IMA ADPCM's 89 steps (tools/aw_sbank.py STEPS)
	dw 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88
	dw 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658
	dw 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660
	dw 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818
	dw 18500, 20350, 22385, 24623, 27086, 29794, 32767
ADPCM_INDEX:	; the step index's move per code & 7
	db -1, -1, -1, -1, 2, 4, 6, 8

; -----------------------------------------------------------------------------
; CNV_DSND_PLAY - PLAY_SOUND on the DSP: XIX = its operands (resource u16 BE, frequency index, volume 0..63,
; channel): the sound on that channel from its start, at the frequency's rate, its loop repeating; volume 0
; stops the channel. A sound not in the loaded part's bank is not played.
; -----------------------------------------------------------------------------
CNV_DSND_PLAY:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIZ
	LD A, (XIX + 3)
	CP A, 63
	JR ULE, _dp_vol
	LD A, 63
_dp_vol:
	LD (DSND_REC + 1), A
	CP A, 0
	JP Z, _dp_stop
	LD A, (XIX)
	CP A, 0
	JP NZ, _dp_out
	LD B, (XIX + 1)		; B = the sound
	LD XIZ, (DSND_LIST)
	CP XIZ, 0
	JP EQ, _dp_out
_dp_find:
	LD A, (XIZ)
	CP A, 0FFh
	JP Z, _dp_out
	CP A, B
	JR Z, _dp_found
	LD XWA, 5
	ADD XIZ, XWA
	JR _dp_find
_dp_found:
	LD XHL, (XIZ + 1)
	ADD XHL, SUB_BANK
	LD (DSND_REC + 4), XHL	; start
	LD A, B
	EXTZ WA
	EXTZ XWA
	SLA 3, XWA
	ADD XWA, CNV_SLEN
	ADD XHL, (XWA)
	ADD XHL, (XWA + 4)
	LD (DSND_REC + 8), XHL	; end: length + loop length on
	LD XHL, (XWA + 4)
	LD (DSND_REC + 12), XHL	; loop length
	; step = Hz / DSND_RATE, 16.16: the whole part, then the fraction from the remainder
	LD A, (XIX + 2)
	CP A, 39
	JR ULE, _dp_freq
	LD A, 39
_dp_freq:
	EXTZ WA
	SLA 1, WA
	EXTZ XWA
	ADD XWA, SND_FREQ
	LD WA, (XWA)
	EXTZ XWA		; Hz
	LD BC, DSND_RATE
	DIV XWA, BC		; WA = whole, QWA = remainder
	LD XHL, XWA
	SRL 16, XHL		; the remainder
	SLA 16, XWA		; the whole part, << 16 (WA's upper half dropped)
	LD XDE, XWA
	SLA 14, XHL		; remainder x 16384
	LD BC, DSND_RATE / 4	; / (rate / 4): remainder x 65536 / rate
	DIV XHL, BC
	EXTZ XHL
	OR XDE, XHL
	LD (DSND_REC + 16), XDE
	JR _dp_send
_dp_stop:
	LD XWA, 0
	LD (DSND_REC + 4), XWA
	LD (DSND_REC + 8), XWA	; start = end: the channel stops
_dp_send:
	LD A, (XIX + 4)
	CALL CNV_DSND_CHANNEL
_dp_out:
	POP XIZ
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

	ifdef DSND_TEST
; CNV_DSND_TEST (test builds, make DSND_TEST=1): a 256-sample sine into SUB_BANK, looped on channel 0 at
; DSND_TEST_STEP (16.16 samples per streamer tick), volume 63
CNV_DSND_TEST:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	LD XWA, DSND_SINE
	LD XDE, SUB_BANK
	LD BC, 256
	CALL CNV_E1_SEND
	LDB (DSND_REC + 1), 63
	LD XWA, SUB_BANK
	LD (DSND_REC + 4), XWA
	ADD XWA, 256
	LD (DSND_REC + 8), XWA
	LD XWA, 256
	LD (DSND_REC + 12), XWA
	LD XWA, DSND_TEST_STEP
	LD (DSND_REC + 16), XWA
	LD A, 0
	CALL CNV_DSND_CHANNEL
	POP XDE
	POP XBC
	POP XWA
	RET
DSND_SINE:
	include "dsnd_sine.inc"
	endif

; the streamer's image (build/AWSUB.BIN, assembled from src/awsub.asm at SUB_BASE)
AWSUB_IMAGE:
	binclude "AWSUB.BIN"
AWSUB_IMAGE_END:
AWSUB_IMAGE_LEN	EQU AWSUB_IMAGE_END - AWSUB_IMAGE
