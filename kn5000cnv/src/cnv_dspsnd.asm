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
