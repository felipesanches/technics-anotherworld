; =============================================================================
; awsub.asm - the sub CPU half of Another World's sound on the KN5000: a four-channel sample streamer
; feeding a four-channel MIXER PROGRAM of ours in the effects DSP (IC311, uPD6383GF)
; =============================================================================
; AW.CNV (the main CPU) puts this block into the sub CPU's DRAM with E1 transfers, then points two of the sub
; program's RAM interrupt trampolines at it (technics-roms-disasm v142/subcpu/subcpu_vectors.s: 0x400 + 5 x slot,
; `jp target` + `ret`):
;   slot 20, INTT1 (the audio tick, 0x464)  -> SUB_HOOK: once, SUB_INIT; on request, SUB_STOP; then on to the
;                                              sub program's own handler (SUB_ORIG_TICK, filled in by AW.CNV)
;   slot 24, INTT5 (timer 4, unused by the sub program, 0x478) -> SUB_TICK, SUB_RATE times a second
; SUB_INIT loads the mixer into IC311 (I-RAM 0..82, src/dspmix.inc) and starts timer 4. SUB_TICK steps the four
; channels over 8-bit samples in sub DRAM and writes their current samples into the DSP's data cells
; 0x40..0x43, and a changed volume into C-RAM 0..3; the DSP program multiplies and sums them every frame.
; The DSP is written as the sub program writes it (DSP_Send_Data, v1.42 0x0367EE): P7.6 data/command, P7.3
; write strobe, P7.5 chip select, PH.0 ready, PZ the byte; commands 0x01 with an I-RAM address, 0x0160 being
; the poke port of pointer and value packets (kn7000_mame src/devices/cpu/upd6383/upd6383.cpp host_w).
;
; Channel records (CH_*), written by AW.CNV over E1, 32 bytes each:
;   +0 seq   AW.CNV writes the whole record, then a new seq: SUB_TICK takes the record when seq changes
;   +1 vol   0..63
;   +4 start, +8 end (exclusive), +12 loop length in bytes (0: no loop): sub DRAM addresses
;   +16 step, 16.16 bytes per tick
; and SUB_TICK's own state: +20 pos (16.16: +20 fraction word, +22.. the address, 24 bits used), +28 lastseq,
; +29 active, +30 the volume last sent to the DSP (0FFh: none yet)
; =============================================================================

	cpu 96c141
	page 0
	maxmode on

	include "sfr_tmp94c241.asm"

	ifndef SUB_BASE
SUB_BASE	EQU 0F0000h
	endif
	ifndef SUB_TREG5
SUB_TREG5	EQU 625		; timer 4's period in its clock (set by the build: SUB_RATE)
	endif

DSP_CELL_SAMPLE	EQU 40h		; data cells the mixer reads (D-RAM, mode-2 pointer)
CH_SEQ		EQU 0
CH_VOL		EQU 1
CH_START	EQU 4
CH_END		EQU 8
CH_LOOP		EQU 12
CH_STEP		EQU 16
CH_POSF		EQU 20
CH_POS		EQU 22		; (a long at +22: the address, low 24 bits)
CH_LASTSEQ	EQU 28
CH_ACTIVE	EQU 29
CH_SENTVOL	EQU 30
CH_SIZE		EQU 32

	ORG SUB_BASE

; ---- the header AW.CNV reads and fills ----------------------------------------
SUB_MAGIC:	DB "AWS1"
SUB_ORIG_JP:	DB 1Bh, 0, 0, 0	; `jp` to the sub program's INTT1 handler: AW.CNV writes the address from the
				; sub program's own trampoline (its image in main memory, 0x800064)
SUB_STATE:	DB 0		; 0 not set up, 1 running, 2 stopped
SUB_REQ:	DB 0		; AW.CNV writes 1 to stop: SUB_HOOK stops the timer and silences the DSP
SUB_TICKS:	DD 0		; ticks run (for probes)
		ALIGN 4
CH0:		DB CH_SIZE DUP (0)
CH1:		DB CH_SIZE DUP (0)
CH2:		DB CH_SIZE DUP (0)
CH3:		DB CH_SIZE DUP (0)

; ---- SUB_HOOK: the INTT1 trampoline lands here --------------------------------
SUB_HOOK:
	PUSH XWA
	LD A, (SUB_REQ)
	CP A, 1
	JR NZ, _sh_notstop
	LD A, (SUB_STATE)
	CP A, 1
	JR NZ, _sh_out
	CALL SUB_STOP
	JR _sh_out
_sh_notstop:
	LD A, (SUB_STATE)
	CP A, 0
	JR NZ, _sh_out
	CALL SUB_INIT
_sh_out:
	POP XWA
	JP SUB_ORIG_JP		; on to the sub program's handler, which ends with its own RETI

; ---- SUB_INIT: the mixer into the DSP, the channels silent, timer 4 started ----
SUB_INIT:
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	; the program: command 0x01, I-RAM address 0, the 83 words
	LD A, 01h
	CALL DSP_CMD
	LD A, 0
	CALL DSP_DATA
	LD A, 0
	CALL DSP_DATA
	LD XIX, DSP_PROGRAM
	LD BC, DSP_PROGRAM_LEN
_si_word:
	LD A, (XIX)
	CALL DSP_DATA
	INC 1, XIX
	DJNZ BC, _si_word
	; the four channels: inactive, nothing sent; the volumes and samples to 0
	LD XIX, CH0
	LD B, 4
_si_ch:
	LDB (XIX + CH_ACTIVE), 0
	LDB (XIX + CH_SENTVOL), 0FFh
	LD A, (XIX + CH_SEQ)
	LD (XIX + CH_LASTSEQ), A
	LD XWA, CH_SIZE
	ADD XIX, XWA
	DJNZ B, _si_ch
	CALL DSP_SEND_SAMPLES_ZERO
	; timer 4: T4MOD = 05h (as the sub program sets it), TREG5 = the period, its upper interrupt at level 2
	RES 0, (T16RUN)
	LD A, 05h
	LD (T4MOD), A
	LD WA, SUB_TREG5
	LD (TREG5L), WA
	LD A, (INTET45)
	AND A, 0Fh
	OR A, 20h		; INTT5 (the upper nibble) at level 2
	LD (INTET45), A
	SET 0, (T16RUN)
	SET 7, (T16RUN)
	LDB (SUB_STATE), 1
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	RET

; ---- SUB_STOP: timer 4 stopped, the samples to 0 -------------------------------
SUB_STOP:
	RES 0, (T16RUN)
	LD A, (INTET45)
	AND A, 0Fh
	LD (INTET45), A
	CALL DSP_SEND_SAMPLES_ZERO
	LDB (SUB_STATE), 2
	RET

; ---- SUB_TICK: the INTT5 trampoline lands here --------------------------------
SUB_TICK:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	PUSH XIY
	EI 3			; the inter-CPU link and the sub program's own work stay above us
	LD XWA, (SUB_TICKS)
	INC 1, XWA
	LD (SUB_TICKS), XWA
	LD XIX, CH0
	LD XIY, SUB_SAMPLES
	LD B, 4
_st_ch:
	; a new record?
	LD A, (XIX + CH_SEQ)
	CP A, (XIX + CH_LASTSEQ)
	JR Z, _st_same
	LD (XIX + CH_LASTSEQ), A
	LD XWA, (XIX + CH_START)
	LD (XIX + CH_POS), XWA
	LDW (XIX + CH_POSF), 0
	LD XDE, (XIX + CH_END)
	CP XWA, XDE
	LD A, 0
	JR UGE, _st_act
	LD A, 1
_st_act:
	LD (XIX + CH_ACTIVE), A
_st_same:
	LD A, (XIX + CH_ACTIVE)
	CP A, 0
	JR Z, _st_silent
	LD XHL, (XIX + CH_POS)
	AND XHL, 0FFFFFFh
	LD A, (XHL)		; the sample, signed 8 bits
	LD (XIY), A
	; pos += step (16.16): the whole part first (SRL sets the carry), then the fraction's carry into it
	LD XDE, (XIX + CH_STEP)
	SRL 16, XDE		; the step's whole part
	LD WA, (XIX + CH_POSF)
	ADD WA, (XIX + CH_STEP)	; the fractions (the step's low word); the carry out goes into ADC
	LD (XIX + CH_POSF), WA
	ADC XHL, XDE
	LD XDE, (XIX + CH_END)
	CP XHL, XDE
	JR ULT, _st_store
	LD XDE, (XIX + CH_LOOP)
	CP XDE, 0
	JR Z, _st_end
	SUB XHL, XDE		; back by the loop's length
	JR _st_store
_st_end:
	LDB (XIX + CH_ACTIVE), 0
_st_store:
	LD (XIX + CH_POS), XHL
	JR _st_next
_st_silent:
	LDB (XIY), 0
_st_next:
	INC 1, XIY
	LD XWA, CH_SIZE
	ADD XIX, XWA
	DJNZ B, _st_ch
	; the volumes that changed, then the four samples
	CALL DSP_SEND_VOLUMES
	CALL DSP_SEND_SAMPLES
	DI
	POP XIY
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RETI

SUB_SAMPLES:	DB 4 DUP (0)

; ---- the DSP: packets ---------------------------------------------------------
; DSP_SEND_SAMPLES: the D-RAM pointer to 0x40, then the four samples (<< 16, sign kept)
DSP_SEND_SAMPLES:
	CALL DSP_POKE_OPEN
	LD XIX, PKT_DPTR
	CALL DSP_PACKET
	LD XIY, SUB_SAMPLES
	LD B, 4
_dss:
	LD A, 0Ah
	CALL DSP_DATA
	LD A, (XIY)		; v23..16: the sample
	CALL DSP_DATA
	LD A, 0
	CALL DSP_DATA
	LD A, 0
	CALL DSP_DATA
	LD A, 15h		; tag: D-RAM
	CALL DSP_DATA
	INC 1, XIY
	DJNZ B, _dss
	RET

DSP_SEND_SAMPLES_ZERO:
	PUSH XIY
	LD XIY, SUB_SAMPLES
	LDB (XIY), 0
	LDB (XIY + 1), 0
	LDB (XIY + 2), 0
	LDB (XIY + 3), 0
	CALL DSP_SEND_SAMPLES
	POP XIY
	RET

; DSP_SEND_VOLUMES: each channel whose volume changed: C-RAM[c] <- vol x 2^15 (63 -> 0.246; four at full
; volume sum to just under 1.0)
DSP_SEND_VOLUMES:
	LD XIX, CH0
	LD C, 0
_dsv:
	LD A, (XIX + CH_VOL)
	AND A, 3Fh
	CP A, (XIX + CH_SENTVOL)
	JR Z, _dsv_next
	LD (XIX + CH_SENTVOL), A
	PUSH WA
	CALL DSP_POKE_OPEN
	LD A, 08h		; ldptr #$0c: 801.0.0c.821 -> 08 01 0c' 8 21 (addr8 c at bits 19:12)
	CALL DSP_DATA
	LD A, 01h
	CALL DSP_DATA
	LD A, C			; addr8 high nibble in byte 2's low nibble (c < 16)
	SRL 4, A
	CALL DSP_DATA
	LD A, C
	SLA 4, A
	OR A, 08h
	CALL DSP_DATA
	LD A, 21h
	CALL DSP_DATA
	POP WA
	; value: vol << 15 = bytes (vol >> 1), (vol & 1) << 7, 0
	PUSH WA
	LD A, 0Ah
	CALL DSP_DATA
	POP WA
	PUSH WA
	SRL 1, A
	CALL DSP_DATA
	POP WA
	AND A, 1
	SLA 7, A
	CALL DSP_DATA
	LD A, 0
	CALL DSP_DATA
	LD A, 26h		; tag: C-RAM
	CALL DSP_DATA
_dsv_next:
	LD XWA, CH_SIZE
	ADD XIX, XWA
	INC 1, C
	CP C, 4
	JR NZ, _dsv
	RET

; DSP_POKE_OPEN: command 0x01 at I-RAM address 0x0160, the poke port
DSP_POKE_OPEN:
	LD A, 01h
	CALL DSP_CMD
	LD A, 01h
	CALL DSP_DATA
	LD A, 60h
	JP DSP_DATA

; DSP_PACKET: XIX = five bytes
DSP_PACKET:
	PUSH BC
	LD B, 5
_dp:
	LD A, (XIX)
	CALL DSP_DATA
	INC 1, XIX
	DJNZ B, _dp
	POP BC
	RET

PKT_DPTR:	DB 00h, 00h, 10h | (DSP_CELL_SAMPLE >> 4), (DSP_CELL_SAMPLE & 0Fh) << 4, 00h	; 000.1.40.000

; ---- the DSP: one byte, as DSP_Send_Data / DSP_Send_Command do it ---------------
; DSP_CMD / DSP_DATA: A = the byte. Waits for READY (PH.0) up to 8000 polls.
DSP_CMD:
	RES 6, (P7)		; command
	JR _dsp_byte
DSP_DATA:
	SET 6, (P7)		; data
_dsp_byte:
	PUSH BC
	SET 4, (P7)		; read strobe off
	RES 3, (P7)		; write strobe on
	RES 5, (P7)		; chip select (DSP1)
	LD BC, 8000
_db_wait:
	SET 0, (PH)
	BIT 0, (PH)
	JR NZ, _db_ready
	DJNZ BC, _db_wait
_db_ready:
	LD (PZ), A
	SET 5, (P7)		; deselect
	SET 3, (P7)		; write strobe off
	POP BC
	RET

; ---- the mixer program (I-RAM 0..82), built by tools/dspmix.py -----------------
DSP_PROGRAM:
	include "dspmix.inc"
DSP_PROGRAM_END:
DSP_PROGRAM_LEN	EQU DSP_PROGRAM_END - DSP_PROGRAM

SUB_END:
	end
