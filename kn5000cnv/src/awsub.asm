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
; SUB_INIT loads the mixer into IC311 (I-RAM from 0, src/dspmix.inc) and starts timer 4. SUB_TICK steps the four
; channels over 8-bit samples in sub DRAM and writes their current samples into the DSP's data cells 0x05,
; 0x07, 0x08 and 0x09 (with the output level, 0x7FFFFF, into 0x06 between the first two), and a changed volume
; into C-RAM 0..3; the DSP program multiplies and sums them every frame (tools/dspmix.py has the layout).
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

DSP_CELL_SAMPLE	EQU 05h		; the first data cell the mixer reads (D-RAM; tools/dspmix.py SAMPLE_CELLS)
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
SUB_STATE:	DB 0		; 0 not set up, 1 running, 3 stopping, 2 stopped
SUB_REQ:	DB 0		; AW.CNV writes 1 to stop: SUB_HOOK passes it to SUB_TICK, which ends it
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
	LDB (SUB_STATE), 3	; SUB_TICK stops between two of its own DSP writes, never in one
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
	; C-RAM 4, the coefficient under the cursor at the presentation word, to 1.0 (tools/dspmix.py)
	CALL DSP_POKE_OPEN
	LD XIX, PKT_CPTR4
	CALL DSP_PACKET
	LD XIX, PKT_ONE
	CALL DSP_PACKET
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

; ---- SUB_STOP (from SUB_TICK): timer 4 stopped, the samples to 0, the sub program's own effects back ----
; First the words the mixer overwrote that the sub program uploads only at boot: the kernel (I-RAM 0..59) and
; the epilogue (60..82), from the sub program's own copies, verbatim at the same addresses in v1.40, v1.41 and
; v1.42 (SUB_KERNEL, SUB_EPILOGUE; found by matching the boot's uploads in MAME's IC311 capture against the three
; sub program images). Then everything else, as the sub program would rewrite it after a change of algorithm
; (technics-roms-disasm v142/subcpu, DSP_State_ApplyAll): its configuration's header word 6 is made to differ
; from its shadow (0x45D0), so DSP_AlgoChange_CheckAndFlag asks for a full rewrite of all five effect slots;
; and the rewrite is set off through the sub program's own DSP command ring, with the 0x2D message the main CPU
; sends for an effect slot (technics-docs audio-subsystem.md, "Command 0x2D"): 2D, 00, 0B (slot 1, whose path
; only hands the configuration to the apply task), 00, 00, 00, 38h (56 bytes follow), 00, then the slot's own 56
; bytes (0x44CE). Audio_Process_DSP, in the sub program's main loop, compares them with the slot's buffer and
; applies only a change, so once queued the buffer's first two bytes (the algorithm) are inverted, and the
; message puts them back. The ring (0x3B60: write index, read index, count, 2 KB of data) and these buffers are at
; the same addresses in v1.40, v1.41 and v1.42. Skipped while a stream from the main CPU is half in (0x448C, the
; consumer's gate) or the ring has no room. Measured with probes/dspram.lua (kn5000cnv/README.md).
SUB_STOP:
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	RES 0, (T16RUN)
	LD A, (INTET45)
	AND A, 0Fh
	LD (INTET45), A
	CALL DSP_SEND_SAMPLES_ZERO
	LD XIX, SUB_KERNEL
	LD DE, 0
	LD BC, 60 * 5
	CALL DSP_UPLOAD
	LD XIX, SUB_EPILOGUE
	LD DE, 60
	LD BC, 23 * 5
	CALL DSP_UPLOAD
	LD XIX, SUB_ZERO	; I-RAM 83 and C-RAM 0..4, which only the mixer wrote: 0, as at power-on (the
	LD DE, 83		; rewrite below sets those cells an effect uses)
	LD BC, 5
	CALL DSP_UPLOAD
	CALL DSP_POKE_OPEN
	LD XIX, PKT_CPTR0
	CALL DSP_PACKET
	LD B, 5
_sp_cram:
	LD XIX, PKT_ZERO
	CALL DSP_PACKET
	DJNZ B, _sp_cram
	CPW (448Ch), 0
	JR NZ, _sp_done
	LD WA, (3B64h)
	CP WA, 800h - 64
	JR UGT, _sp_done
	LD WA, (45D0h)
	CPL WA
	LD (45D0h), WA		; the header's shadow differs: a full rewrite
	LD XIX, SUB_MSG2D
	LD B, 8
_sp_hdr:
	LD A, (XIX)
	INC 1, XIX
	CALL _sp_put
	DJNZ B, _sp_hdr
	LD XHL, 44CEh		; slot 1's 56 bytes
	LD B, 38h
_sp_data:
	LD A, (XHL)
	INC 1, XHL
	CALL _sp_put
	DJNZ B, _sp_data
	LD WA, (44CEh)
	CPL WA
	LD (44CEh), WA		; its algorithm, inverted: the message is a change
_sp_done:
	LDB (SUB_STATE), 2
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	RET

; _sp_put: A into the DSP command ring, as DSP_RingBuf_Enqueue does
_sp_put:
	PUSH XWA
	PUSH XBC
	LD BC, (3B60h)
	INCW 1, (3B60h)
	AND BC, 7FFh
	EXTZ XBC
	ADD XBC, 3B66h
	LD (XBC), A
	INCW 1, (3B64h)
	POP XBC
	POP XWA
	RET

SUB_MSG2D:	DB 2Dh, 00h, 0Bh, 00h, 00h, 00h, 38h, 00h

SUB_ZERO:	DB 0, 0, 0, 0, 0
PKT_CPTR0:	DB 08h, 01h, 00h, 08h, 21h	; ldptr #$00: 801.0.00.821
PKT_ZERO:	DB 0Ah, 00h, 00h, 00h, 26h	; 0 into C-RAM

SUB_KERNEL	EQU 01E49Bh	; the 60 words of I-RAM 0..59, as the sub program sends them
SUB_EPILOGUE	EQU 01E641h	; the 23 words of I-RAM 60..82

; DSP_UPLOAD: DE = an I-RAM address, XIX = words, BC = their bytes: command 0x01, the address, the words
DSP_UPLOAD:
	PUSH XWA
	PUSH XBC
	PUSH XIX
	LD A, 01h
	CALL DSP_CMD
	LD A, D
	CALL DSP_DATA
	LD A, E
	CALL DSP_DATA
_du_byte:
	LD A, (XIX)
	INC 1, XIX
	CALL DSP_DATA
	DEC 1, BC
	CP BC, 0
	JR NZ, _du_byte
	POP XIX
	POP XBC
	POP XWA
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
	LD A, (SUB_STATE)
	CP A, 3
	JR NZ, _st_run
	CALL SUB_STOP
	JP _st_out
_st_run:
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
_st_out:
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
; DSP_SEND_SAMPLES: the D-RAM pointer to 0x05, then the first sample, the level (0x06), the other three
; (samples << 16, sign kept; the pointer steps by one a value). Every tick, so through DSP_FAST: at 4000 ticks
; a second the per-byte DSP_DATA took 61 % of the sub CPU (probes/dsnd.lua DS_PROF, kn5000cnv/README.md).
DSP_SEND_SAMPLES:
	SET 0, (PH)		; (READY's latch, as DSP_DATA sets it)
	SET 4, (P7)		; read strobe off
	RES 6, (P7)		; command
	RES 5, (P7)		; the chip selected for the whole burst (DSP_FAST)
	LD A, 01h
	CALL DSP_FAST
	SET 6, (P7)		; data from here on
	LD A, 01h		; I-RAM 0x0160, the poke port
	CALL DSP_FAST
	LD A, 60h
	CALL DSP_FAST
	LD XIX, PKT_DPTR
	CALL _dss_packet
	LD XIY, SUB_SAMPLES
	LD B, 4
_dss:
	CP B, 3
	JR NZ, _dss_sample
	LD XIX, PKT_LEVEL
	CALL _dss_packet
_dss_sample:
	LD A, 0Ah
	CALL DSP_FAST
	LD A, (XIY)		; v23..16: the sample
	CALL DSP_FAST
	LD A, 0
	CALL DSP_FAST
	CALL DSP_FAST
	LD A, 15h		; tag: D-RAM
	CALL DSP_FAST
	INC 1, XIY
	DJNZ B, _dss
	SET 5, (P7)		; deselected
	RET
_dss_packet:
	LD C, 5
_dsp_p:
	LD A, (XIX)
	INC 1, XIX
	CALL DSP_FAST
	DJNZ C, _dsp_p
	RET

; DSP_FAST: A = one byte to IC311, inside a burst (DSP_BURST_ON: the read strobe off, the chip selected): the
; write strobe low, READY waited for at most 255 polls (DSP_DATA: 8000, then it writes anyway), the byte, the
; write strobe high. DSP_DATA instead selects and deselects the chip around every byte; holding the select
; through a burst and latching each byte on the write strobe's rising edge is the usual timing of such a host
; port, but on the uPD6383 it is not checked: if the instrument shows otherwise, select per byte here.
; Keeps every register but W.
DSP_FAST:
	RES 3, (P7)
	LD W, 0
_df_wait:
	BIT 0, (PH)
	JR NZ, _df_ready
	DJNZ W, _df_wait
_df_ready:
	LD (PZ), A
	SET 3, (P7)
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

; DSP_SEND_VOLUMES: each channel whose volume changed: C-RAM[c] <- vol x 2^14 (0x400000 is 1.0, so 63 -> 0.246;
; four at full volume sum to just under 1.0)
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
	; value: vol << 14 = bytes (vol >> 2), (vol & 3) << 6, 0
	PUSH WA
	LD A, 0Ah
	CALL DSP_DATA
	POP WA
	PUSH WA
	SRL 2, A
	CALL DSP_DATA
	POP WA
	AND A, 3
	SLA 6, A
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

PKT_CPTR4:	DB 08h, 01h, 00h, 48h, 21h	; ldptr #$04: 801.0.04.821
PKT_ONE:	DB 0Ah, 40h, 00h, 00h, 26h	; 0x400000 (1.0) into C-RAM
PKT_LEVEL:	DB 0Ah, 7Fh, 0FFh, 0FFh, 15h	; 0x7FFFFF into D-RAM: the presentation's level
PKT_DPTR:	DB 00h, 00h, 10h | (DSP_CELL_SAMPLE >> 4), (DSP_CELL_SAMPLE & 0Fh) << 4, 00h	; 000.1.05.000

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
