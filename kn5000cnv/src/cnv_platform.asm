; =============================================================================
; cnv_platform.asm - what the VM needs to run as a KN5000 style converter
; =============================================================================
; The firmware's side (v7 disassembly, sequencer/accompaniment_engine.s): it
; calls 0x80000 with a return address on the stack and serves the request the
; converter leaves in the mailbox at 0xFFC00 when it returns. Request 5 shows
; the text at 0xFFC01; request 0xFE ends the run ("Continue Next?").
;
; First call:
;   1. find the firmware's file routines (CNV_FIND_FIRMWARE): their addresses
;      differ between v5..v10, so each candidate is checked by its code bytes;
;   2. check that the sequencer's song memory holds no song (CNV_SONG_CHECK),
;      since the game's pages live there;
;   3. take the control-panel serial port and the 16 game colours over
;      (CNV_HW_TAKE) and run the VM, which never returns;
; until EXIT is held (CNV_CHECK_EXIT) or a file cannot be read: then put the
; hardware, the colours and the song memory back as they were and end the run.
; =============================================================================

CNV_MAILBOX	EQU 0FFC00h	; request byte; text from +1
CNV_REQ_TEXT	EQU 5		; show the text at CNV_MAILBOX+1 (the firmware calls again at once)
CNV_TEXT_TICKS	EQU 1953	; a message stays up 4 s (488 Hz counter)
CNV_REQ_END	EQU 0FEh	; stop calling; "Continue Next?"

; The sequencer's song memory: 1240 blocks of 256 bytes, chained at every power-on
; (v5..v10: the routine around 0xF41BFC in v10). Its state after boot, with no song:
;   block n (1..1240) at 0xB0000 + (n-1)*256: byte 0 = 0x80 for n <= 2, else 0;
;   bytes 1-2 = previous block (0 for n <= 3, else n-1); bytes 3-4 = next block
;   (0xFFFF for n <= 2 and for the last, else n+1); byte 5 = 0x82; the rest 0;
;   and 0xFD800-0xFDFFF all 0. (Measured: kn5000cnv/README.md.) v5 builds the chain later, not at
;   boot: there the empty state is all 0. Both count as empty; the one found is put back.
CNV_SONG_BASE	EQU 0B0000h
CNV_SONG_BLOCKS	EQU 04D8h
CNV_SONG_END	EQU 0FE000h

CNV_INTA_VECTOR	EQU 0FFFF48h	; interrupt vector 18, INTA (the panels' data line, PE.5)
CNV_DISPATCH2	EQU 0E0001Ah	; SeqRingBuf_WriteDispatch_Table entry 2 (SeqDMA_WriteMidi_NoteOn)

; The keybed's controls, as on the KN7000 port (technics-anotherworld kn7000/README-CNV.md), as MIDI
; notes; the names are the KN5000's own (its SPLIT POINT screen: middle C, MIDI 60, is C3)
CNV_NOTE_LEFT	EQU 77		; F4
CNV_NOTE_UP1	EQU 80		; Ab4
CNV_NOTE_DOWN	EQU 81		; A4
CNV_NOTE_UP2	EQU 82		; Bb4
CNV_NOTE_RIGHT	EQU 84		; C5
CNV_NOTE_ACTION	EQU 60		; C3 and every key below it: action
CNV_EXIT_HOLD	EQU 732		; ticks of the 488 Hz counter EXIT is held before the game ends (1.5 s)

; -----------------------------------------------------------------------------
; CNV_CALL - every call from the firmware lands here
; -----------------------------------------------------------------------------
CNV_CALL:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	PUSH XIY
	PUSH XIZ
	LD A, (CNV_STATE)
	CP A, 0
	JP EQ, CNV_FIRST
	CP A, 2
	JP EQ, CNV_TEXT_AGAIN
	JP CNV_END_RUN		; after the game, or YES on "Continue Next?": stop

CNV_FIRST:
	LDB (CNV_STATE), 1
	CALL CNV_FIND_FIRMWARE	; Z = found
	JP NZ, CNV_NO_FIRMWARE
	CALL CNV_SONG_CHECK	; Z = no song in memory
	JP NZ, CNV_SONG_IN_USE
	CALL CNV_FIND_NOTERING	; the keybed, if this firmware's note ring is found
	PUSH SR
	LD (CNV_SAVED_SP), XSP
	CALL CNV_HW_TAKE
	CALL CNV_SND_INIT	; the game's sound on the instrument's voices (cnv_sound.asm)
	ifdef DSND_TEST
	CALL CNV_DSND_INSTALL	; the DSP sound's streamer into the sub CPU (cnv_dspsnd.asm)
	CALL CNV_DSND_TEST
	endif
	JP ENTRY		; the VM; it leaves through CNV_EXIT

CNV_NO_FIRMWARE:
	LD XHL, CNV_TXT_FIRMWARE
	JP CNV_SHOW_TEXT
CNV_SONG_IN_USE:
	LD XHL, CNV_TXT_SONG
	JP CNV_SHOW_TEXT

; CNV_EXIT - leave the game: from CNV_CHECK_EXIT, or CNV_READ_RES on a failed read
; (CNV_EXIT_TEXT then points at the message to show)
CNV_EXIT:
	DI
	LD XSP, (CNV_SAVED_SP)
	CALL CNV_SND_END	; the parts the game used, as the firmware set them
	CALL CNV_DSND_REMOVE	; the sub CPU's trampolines as they were (cnv_dspsnd.asm)
	CALL CNV_HW_GIVE_BACK
	CALL CNV_SONG_RESTORE
	POP SR
	LD XHL, (CNV_EXIT_TEXT)
	CP XHL, 0
	JP NE, CNV_SHOW_TEXT
CNV_END_RUN:
	LDB (CNV_MAILBOX), CNV_REQ_END
CNV_RETURN:
	POP XIZ
	POP XIY
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

; CNV_SHOW_TEXT - XHL = text: ask the firmware to show it. The firmware's text screen calls the
; converter again as soon as it is up (StylCnvTxtTtlFunc), so the request is repeated for 4 s
; (CNV_TEXT_AGAIN); then the run ends.
CNV_SHOW_TEXT:
	LDB (CNV_STATE), 2
	LD (CNV_TEXT_PTR), XHL
	LD XWA, (SYSTEM_TICKS)
	LD (CNV_TEXT_SINCE), XWA
CNV_TEXT_POST:
	LD XHL, (CNV_TEXT_PTR)
	LD XDE, CNV_MAILBOX + 1
_cnv_text_loop:
	LD A, (XHL)
	LD (XDE), A
	INC 1, XHL
	INC 1, XDE
	CP A, 0
	JR NZ, _cnv_text_loop
	LDB (CNV_MAILBOX), CNV_REQ_TEXT
	JP CNV_RETURN

CNV_TEXT_AGAIN:
	LD XWA, (SYSTEM_TICKS)
	LD XBC, (CNV_TEXT_SINCE)
	SUB XWA, XBC
	CP XWA, CNV_TEXT_TICKS
	JP ULT, CNV_TEXT_POST
	LDB (CNV_STATE), 1
	JP CNV_END_RUN

CNV_TXT_FIRMWARE:	DB "AW: UNKNOWN FIRMWARE", 0
CNV_TXT_SONG:		DB "AW: SAVE SONGS, SWITCH OFF+ON", 0
CNV_TXT_READ:		DB "AW: DISK READ ERROR", 0

; -----------------------------------------------------------------------------
; CNV_FIND_FIRMWARE - pick this firmware's FileIO routines; Z = found
; -----------------------------------------------------------------------------
; open(XWA = name, XBC = mode) -> HL = 0 when open; read(XWA = dest, XBC = count)
; -> XHL = bytes read; seek(XWA = offset, BC = whence); close(). One file at a time.
; Found by kn5000cnv/tools/find_fileio.py; each line is checked by its opening bytes:
;   open  BF 80 37 3E   (lda xsp,xsp-0x80; push xiz)
;   read  BF EE 37 3E   (lda xsp,xsp-0x12; push xiz)
;   seek  E1 .. .. 22 EA E2   (ld xde,(handle); or xde,xde)
;   close E1 .. .. 20 E8 E0   (ld xwa,(handle); or xwa,xwa)
CNV_FW_TABLE:
	dd 0F88BC7h, 0F88D74h, 0F88EE0h, 0F88C48h	; v8, v9, v10
	dd 0F887BAh, 0F88967h, 0F88AD3h, 0F8883Bh	; v7
	dd 0F886C5h, 0F88872h, 0F889DEh, 0F88746h	; v6
	dd 0F883B8h, 0F88565h, 0F886D1h, 0F88439h	; v5
	dd 0

CNV_FIND_FIRMWARE:
	LD XIX, CNV_FW_TABLE
_cnv_fw_next:
	LD XWA, (XIX)
	CP XWA, 0
	JP EQ, _cnv_fw_none
	LD XBC, (XWA)
	CP XBC, 03E3780BFh
	JR NE, _cnv_fw_skip
	LD XWA, (XIX + 4)
	LD XBC, (XWA)
	CP XBC, 03E37EEBFh
	JR NE, _cnv_fw_skip
	LD XWA, (XIX + 8)
	LD B, (XWA + 3)
	CP B, 022h
	JR NE, _cnv_fw_skip
	LD BC, (XWA + 4)
	CP BC, 0E2EAh
	JR NE, _cnv_fw_skip
	LD XWA, (XIX + 12)
	LD B, (XWA + 3)
	CP B, 020h
	JR NE, _cnv_fw_skip
	LD BC, (XWA + 4)
	CP BC, 0E0E8h
	JR NE, _cnv_fw_skip
	; this line: keep it
	LD XWA, (XIX)
	LD (CNV_FW_OPEN), XWA
	LD XWA, (XIX + 4)
	LD (CNV_FW_READ), XWA
	LD XWA, (XIX + 8)
	LD (CNV_FW_SEEK), XWA
	LD XWA, (XIX + 12)
	LD (CNV_FW_CLOSE), XWA
	; The firmware keeps RAM copies of the write-only PFCR and PFFC (port F: SC1's pins), the
	; latter one byte after the former (v7 0x8CF2/3, v10 0x8D8E/F); its INTA handler reads
	; the PFCR copy at +0x12 (ld a,(addr): C1 lo hi 21), in every version.
	LD XWA, (CNV_INTA_VECTOR)
	LD B, (XWA + 12h)
	CP B, 0C1h
	JR NE, _cnv_fw_none
	LD B, (XWA + 15h)
	CP B, 021h
	JR NE, _cnv_fw_none
	LD BC, (XWA + 13h)
	EXTZ XBC
	LD (CNV_PFCR_COPY), XBC
	LD A, 0
	CP A, 0			; Z
	RET
_cnv_fw_skip:
	ADD XIX, 16
	JP _cnv_fw_next
_cnv_fw_none:
	LD A, 1
	CP A, 0			; NZ
	RET

; -----------------------------------------------------------------------------
; The song memory: check it holds no song; give it back as found
; -----------------------------------------------------------------------------
; _cnv_song_header: IX = block number n -> A = byte 0, DE = previous, BC = next
_cnv_song_header:
	LD A, 0
	CP IX, 2
	JR UGT, _cnv_sh_b0
	LD A, 080h
_cnv_sh_b0:
	LD DE, IX
	DEC 1, DE
	CP IX, 3
	JR UGT, _cnv_sh_prev
	LD DE, 0
_cnv_sh_prev:
	LD BC, IX
	INC 1, BC
	CP IX, 2
	JR UGT, _cnv_sh_n1
	LD BC, 0FFFFh
_cnv_sh_n1:
	CP IX, CNV_SONG_BLOCKS
	JR NE, _cnv_sh_n2
	LD BC, 0FFFFh
_cnv_sh_n2:
	RET

; CNV_SONG_CHECK - Z when 0xB0000-0xFDFFF holds no song: all 0 (CNV_SONG_KIND = 2) or exactly the
; chain the firmware builds (CNV_SONG_KIND = 1)
CNV_SONG_CHECK:
	LD XHL, CNV_SONG_BASE
_cnv_sc_allzero:
	LD XWA, (XHL)
	CP XWA, 0
	JR NE, _cnv_sc_chain
	ADD XHL, 4
	CP XHL, CNV_SONG_END
	JR NE, _cnv_sc_allzero
	LDB (CNV_SONG_KIND), 2
	LD A, 0
	CP A, 0			; Z
	RET
_cnv_sc_chain:
	LDB (CNV_SONG_KIND), 1
	LD XHL, CNV_SONG_BASE
	LD IX, 1
_cnv_sc_block:
	CALL _cnv_song_header
	CP A, (XHL)
	JP NE, _cnv_sc_bad
	LD WA, (XHL + 1)
	CP WA, DE
	JP NE, _cnv_sc_bad
	LD WA, (XHL + 3)
	CP WA, BC
	JP NE, _cnv_sc_bad
	LD A, (XHL + 5)
	CP A, 082h
	JP NE, _cnv_sc_bad
	LD WA, (XHL + 6)
	CP WA, 0
	JP NE, _cnv_sc_bad
	LD XDE, XHL
	ADD XDE, 8
	LD BC, 62		; bytes 8..255
_cnv_sc_zero:
	LD XWA, (XDE)
	CP XWA, 0
	JP NE, _cnv_sc_bad
	ADD XDE, 4
	DJNZ BC, _cnv_sc_zero
	ADD XHL, 256
	INC 1, IX
	CP IX, CNV_SONG_BLOCKS + 1
	JP NE, _cnv_sc_block
	; XHL = 0xFD800: the tail up to CNV_SONG_END is 0
_cnv_sc_tail:
	LD XWA, (XHL)
	CP XWA, 0
	JP NE, _cnv_sc_bad
	ADD XHL, 4
	CP XHL, CNV_SONG_END
	JR NE, _cnv_sc_tail
	LD A, 0
	CP A, 0			; Z
	RET
_cnv_sc_bad:
	LD A, 1
	CP A, 0			; NZ
	RET

; CNV_SONG_RESTORE - write the empty state CNV_SONG_CHECK found back over 0xB0000-0xFDFFF
CNV_SONG_RESTORE:
	LD XHL, CNV_SONG_BASE
	LD XWA, 0
_cnv_sr_zero:
	LD (XHL), XWA
	ADD XHL, 4
	CP XHL, CNV_SONG_END
	JR NE, _cnv_sr_zero
	LD A, (CNV_SONG_KIND)
	CP A, 2
	RET EQ			; all 0: done
	LD XHL, CNV_SONG_BASE
	LD IX, 1
_cnv_sr_block:
	CALL _cnv_song_header
	LD (XHL), A
	LD (XHL + 1), DE
	LD (XHL + 3), BC
	LDB (XHL + 5), 082h
	ADD XHL, 256
	INC 1, IX
	CP IX, CNV_SONG_BLOCKS + 1
	JR NE, _cnv_sr_block
	RET

; -----------------------------------------------------------------------------
; The panel serial port and the colours: take them over, give them back
; -----------------------------------------------------------------------------
; The firmware runs the panel link by interrupt: INTA (a panel has data) switches SC1 to
; receive, INTRX1/INTTX1 step its state machine. The VM polls SC1 itself, set up as the
; standalone build's boot does (boot_hw_init.asm), so those three are masked meanwhile.
CNV_HW_TAKE:
	LD A, (INTEAB)
	LD (CNV_SAVE_INTEAB), A
	LD A, (INTES1)
	LD (CNV_SAVE_INTES1), A
	LD A, (SC1MOD)
	LD (CNV_SAVE_SC1MOD), A
	LD A, (SC1CR)
	LD (CNV_SAVE_SC1CR), A
	LD A, (BR1CR)
	LD (CNV_SAVE_BR1CR), A
	LDB (INTEAB), 000h
	LDB (INTES1), 000h
	; SC1's TXD and SCLK pins on, as the firmware's own transmit path sets them (or 0x50)
	LD XHL, (CNV_PFCR_COPY)
	LD A, (XHL + 1)
	OR A, 050h
	LD (PFFC), A
	LD A, (XHL)
	OR A, 050h
	LD (PFCR), A
	LDB (SC1MOD), 001h
	LDB (BR1CR), 014h
	LDB (SC1CR), 001h
	LDB (INTCLR), 012h	; INTA
	LDB (INTCLR), 022h	; INTRX1
	LDB (INTCLR), 023h	; INTTX1
	; the 16 colours the game sets: DAC entries 0-15
	LD WA, 3C7h		; DAC read address
	LD C, 0
	CALR Write_VGA_Register
	LD XIY, CNV_SAVE_DAC
_cnv_take_dac:
	LD WA, VGA_DAC_DATA
	CALR Read_VGA_Register
	LD (XIY), L
	INC 1, XIY
	CP XIY, CNV_SAVE_DAC + 48
	JR NE, _cnv_take_dac
	; clear the whole LCD (the game draws lines 20-219 only)
	LD XHL, VIDEO_RAM_BASE
	LD XWA, 0
_cnv_take_cls:
	LD (XHL), XWA
	ADD XHL, 4
	CP XHL, VIDEO_RAM_BASE + 320*240
	JR NE, _cnv_take_cls
	RET

CNV_HW_GIVE_BACK:
	LD WA, VGA_DAC_ADDR_WRITE
	LD C, 0
	CALR Write_VGA_Register
	LD XIY, CNV_SAVE_DAC
_cnv_give_dac:
	LD C, (XIY)
	LD WA, VGA_DAC_DATA
	CALR Write_VGA_Register
	INC 1, XIY
	CP XIY, CNV_SAVE_DAC + 48
	JR NE, _cnv_give_dac
	LDB (INTEAB), 000h
	LDB (INTES1), 000h
	LD A, (CNV_SAVE_SC1MOD)
	LD (SC1MOD), A
	LD A, (CNV_SAVE_BR1CR)
	LD (BR1CR), A
	LD A, (CNV_SAVE_SC1CR)
	LD (SC1CR), A
	LD XHL, (CNV_PFCR_COPY)
	LD A, (XHL)
	LD (PFCR), A
	LD A, (XHL + 1)
	LD (PFFC), A
	LDB (INTCLR), 012h
	LDB (INTCLR), 022h
	LDB (INTCLR), 023h
	LD A, (CNV_SAVE_INTES1)
	AND A, 077h		; levels only, not the request flags
	LD (INTES1), A
	LD A, (CNV_SAVE_INTEAB)
	AND A, 077h
	LD (INTEAB), A
	RET

; CNV_CHECK_EXIT - from the VM's input routine, once per frame: EXIT (left panel segment 7,
; bit 3) held for 1.5 s ends the game
CNV_CHECK_EXIT:
	PUSH XWA
	PUSH XBC
	; left panel, segment 7 (the 4-byte exchange of _cpanel_query_segment, each reply kept)
	LD A, 020h
	CALL _cpanel_send_byte
	LD (CNV_DBG_REPLY), A
	LD A, 007h
	CALL _cpanel_send_byte
	LD (CNV_DBG_REPLY + 1), A
	LD A, 0FFh
	CALL _cpanel_send_byte
	LD (CNV_DBG_REPLY + 2), A
	LD A, 0FFh
	CALL _cpanel_send_byte
	LD (CNV_DBG_REPLY + 3), A
	AND A, 008h
	JR Z, _cnv_exit_released
	LD A, (CNV_EXIT_COUNT)
	CP A, 0
	JR NZ, _cnv_exit_held
	LDB (CNV_EXIT_COUNT), 1		; just pressed: note when
	LD XWA, (SYSTEM_TICKS)
	LD (CNV_EXIT_SINCE), XWA
	JR _cnv_exit_done
_cnv_exit_held:
	LD XWA, (SYSTEM_TICKS)
	LD XBC, (CNV_EXIT_SINCE)
	SUB XWA, XBC
	CP XWA, CNV_EXIT_HOLD
	JP UGE, CNV_EXIT
	JR _cnv_exit_done
_cnv_exit_released:
	LDB (CNV_EXIT_COUNT), 0
_cnv_exit_done:
	POP XBC
	POP XWA
	RET

; -----------------------------------------------------------------------------
; Reading the game's files (AWnn.BIN, one per resource, in the floppy's root)
; -----------------------------------------------------------------------------
; CNV_LOAD_PART - WA = part id (0x3E80..0x3E89): read its palette, bytecode and polygons
; (and the shared polygons, once) into the buffers PART_RESOURCE_TABLE names
CNV_LOAD_PART:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	PUSH XIY
	CP WA, (CNV_LOADED_PART)
	JP EQ, _cnv_lp_done
	LD (CNV_LOADED_PART), WA
	SUB WA, GAME_PART_FIRST
	SLA 2, WA
	EXTZ XWA
	ADD XWA, CNV_PARTS
	LD XIY, XWA
	LD A, (XIY + 3)
	CP A, 0
	JR Z, _cnv_lp_parts
	LD A, (CNV_VIDEO2_LOADED)
	CP A, 0
	JR NZ, _cnv_lp_parts
	LD A, (XIY + 3)
	LD XDE, VIDEO2_BUF
	CALL CNV_READ_RES
	LDB (CNV_VIDEO2_LOADED), 1
_cnv_lp_parts:
	LD A, (XIY)
	LD XDE, PALETTE_BUF
	CALL CNV_READ_RES
	LD A, (XIY + 1)
	LD XDE, BYTECODE_BUF
	CALL CNV_READ_RES
	LD A, (XIY + 2)
	LD XDE, VIDEO1_BUF
	CALL CNV_READ_RES
_cnv_lp_done:
	POP XIY
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET

; CNV_LOAD_SCREEN - WA = resource id -> XHL = SCREEN_BUF holding it, or 0 if it is no screen
CNV_LOAD_SCREEN:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	CP WA, 092h
	JR UGE, _cnv_ls_none
	LD B, A
	EXTZ XWA
	SLA 2, XWA
	ADD XWA, CNV_SIZES
	LD XWA, (XWA)
	CP XWA, 32000
	JR NE, _cnv_ls_none
	LD A, B
	LD XDE, SCREEN_BUF
	CALL CNV_READ_RES
	LD XHL, SCREEN_BUF
	JR _cnv_ls_done
_cnv_ls_none:
	LD XHL, 0
_cnv_ls_done:
	POP XDE
	POP XBC
	POP XWA
	RET

; CNV_READ_RES - A = resource id, XDE = destination: read AWnn.BIN whole, through the
; firmware's FileIO routines. A failed read ends the game with a message.
CNV_READ_RES:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XHL
	PUSH XIX
	PUSH XIY
	PUSH XIZ
	LD (CNV_CUR_ID), A
	LD (CNV_CUR_DEST), XDE
	LD XHL, CNV_NAME
	LDB (XHL), 'A'
	LDB (XHL + 1), 'W'
	LD B, A
	SRL 4, B
	CALL _cnv_hex_digit
	LD (XHL + 2), B
	LD B, A
	AND B, 0Fh
	CALL _cnv_hex_digit
	LD (XHL + 3), B
	LDB (XHL + 4), '.'
	LDB (XHL + 5), 'B'
	LDB (XHL + 6), 'I'
	LDB (XHL + 7), 'N'
	LDB (XHL + 8), 0
	LD XWA, CNV_NAME
	LD XBC, CNV_MODE_RB
	LD XIX, (CNV_FW_OPEN)
	CALL (XIX)
	CP HL, 0
	JP NE, _cnv_rr_failed
	LD A, (CNV_CUR_ID)
	EXTZ WA			; A -> WA (W = 0)
	AND WA, 0FFh
	EXTZ XWA
	SLA 2, XWA
	ADD XWA, CNV_SIZES
	LD XBC, (XWA)
	LD (CNV_CUR_SIZE), XBC
	LD XWA, (CNV_CUR_DEST)
	LD XIX, (CNV_FW_READ)
	CALL (XIX)
	LD (CNV_LAST_READ), XHL
	LD XIX, (CNV_FW_CLOSE)
	CALL (XIX)
	LD XHL, (CNV_LAST_READ)
	LD XBC, (CNV_CUR_SIZE)
	CP XHL, XBC
	JP NE, _cnv_rr_failed
	POP XIZ
	POP XIY
	POP XIX
	POP XHL
	POP XDE
	POP XBC
	POP XWA
	RET
_cnv_rr_failed:
	LD XHL, CNV_TXT_READ
	LD (CNV_EXIT_TEXT), XHL
	JP CNV_EXIT

; _cnv_hex_digit: B = 0..15 -> B = '0'..'9', 'A'..'F'
_cnv_hex_digit:
	CP B, 10
	JR ULT, _cnv_hex_num
	ADD B, 'A' - 10
	RET
_cnv_hex_num:
	ADD B, '0'
	RET

CNV_MODE_RB:	DB "rb", 0

; -----------------------------------------------------------------------------
; The keybed
; -----------------------------------------------------------------------------
; The sub CPU sends each keybed note as a packet with header 0x42 (slot 2, 3 bytes): 90 note velocity,
; velocity 0 for a release. The firmware's interrupt handlers put note and velocity into a 256-byte ring
; (SeqDMA_WriteMidi_NoteOn -> SeqBuf_NoteEvent_WriteByte -> Seq_RingBuf_WriteByte_Small), which its main
; loop empties -- and which, with the main loop stopped, would fill after 127 notes and then drop them.
; So AW.CNV reads it as the main loop does (Seq_RingBuf_ReadByte: X-8 read index, X-2 free count;
; X-4 is the writer's index). X is 0x202CB in v5..v10 (tools/find_noterng.py).

; CNV_FIND_NOTERING - CNV_NOTERING = X, found by the walk find_noterng.py describes, or 0 (no keybed);
; any notes already in the ring are dropped
CNV_FIND_NOTERING:
	LD XHL, (CNV_DISPATCH2)
	LD B, 040h
_cnv_fn_call:
	LD A, (XHL)
	CP A, 028h		; push wa
	JR NE, _cnv_fn_call_next
	LD A, (XHL + 1)
	CP A, 01Dh		; call abs24
	JR EQ, _cnv_fn_call_found
_cnv_fn_call_next:
	INC 1, XHL
	DJNZ B, _cnv_fn_call
	JR _cnv_fn_none
_cnv_fn_call_found:
	LD XWA, (XHL + 2)
	AND XWA, 0FFFFFFh
	LD XHL, XWA		; SeqBuf_NoteEvent_WriteByte
	LD B, 020h
_cnv_fn_lda:
	LD A, (XHL)
	CP A, 0F2h		; lda xde,abs24: F2 lo mid hi 32
	JR NE, _cnv_fn_lda_next
	LD A, (XHL + 4)
	CP A, 032h
	JR EQ, _cnv_fn_lda_found
_cnv_fn_lda_next:
	INC 1, XHL
	DJNZ B, _cnv_fn_lda
	JR _cnv_fn_none
_cnv_fn_lda_found:
	LD XWA, (XHL + 1)
	AND XWA, 0FFFFFFh
	LD (CNV_NOTERING), XWA
	LD XIX, XWA
	PUSH SR
	DI
	LD WA, (XIX - 4)
	LD (XIX - 8), WA	; read index = write index: nothing pending
	LDW (XIX - 2), 0FFh	; all 255 free, as Seq_RingBuf_Init_256 leaves it
	POP SR
	RET
_cnv_fn_none:
	LD XWA, 0
	LD (CNV_NOTERING), XWA
	RET

; CNV_KEYS_POLL - from the VM's input routine, once per frame: take the keybed's notes out of the ring,
; and OR its controls into H (right panel segment 4: 0x40 right, 0x10 left, 0x20 down, 0x02 up) and
; L (left panel segment 4: 0x08 action), the panel bits the VM reads. Of two opposing directions held
; at once, the one already in use stays until it is released.
CNV_KEYS_POLL:
	PUSH XWA
	PUSH XBC
	PUSH XDE
	PUSH XIX
	PUSH XIY
	LD XIX, (CNV_NOTERING)
	CP XIX, 0
	JP EQ, _cnv_kp_done
_cnv_kp_next:
	LD WA, (XIX - 4)
	SUB WA, (XIX - 8)
	AND WA, 0FFh
	CP WA, 2		; a note and its velocity
	JR ULT, _cnv_kp_apply
	LD BC, (XIX - 8)
	LD D, (XIX + BC)	; note
	INC 1, BC
	AND BC, 0FFh
	LD E, (XIX + BC)	; velocity (0 = released)
	INC 1, BC
	AND BC, 0FFh
	LD (XIX - 8), BC
	INCW 1, (XIX - 2)
	INCW 1, (XIX - 2)
	CALL _cnv_key_store
	JR _cnv_kp_next
_cnv_kp_apply:
	; left / right
	LD D, CNV_NOTE_LEFT
	CALL _cnv_key_held	; A = 1 if held
	LD B, A
	LD D, CNV_NOTE_RIGHT
	CALL _cnv_key_held
	LD C, A
	LD A, (CNV_LR)		; 0 none, 1 right, 2 left
	CALL _cnv_pick_dir
	LD (CNV_LR), A
	CP A, 1
	JR NE, _cnv_kp_notright
	OR H, 040h
_cnv_kp_notright:
	CP A, 2
	JR NE, _cnv_kp_notleft
	OR H, 010h
_cnv_kp_notleft:
	; up / down
	LD D, CNV_NOTE_UP1
	CALL _cnv_key_held
	LD B, A
	LD D, CNV_NOTE_UP2
	CALL _cnv_key_held
	OR B, A
	LD D, CNV_NOTE_DOWN
	CALL _cnv_key_held
	LD C, A
	LD A, (CNV_UD)		; 0 none, 1 down, 2 up
	CALL _cnv_pick_dir
	LD (CNV_UD), A
	CP A, 1
	JR NE, _cnv_kp_notdown
	OR H, 020h
_cnv_kp_notdown:
	CP A, 2
	JR NE, _cnv_kp_notup
	OR H, 002h
_cnv_kp_notup:
	; action: any key up to CNV_NOTE_ACTION (bytes 0-6 = notes 0-55, byte 7 bits 0-4 = notes 56-60)
	LD XIY, CNV_KEYS
	LD B, 7
	LD A, 0
_cnv_kp_bass:
	OR A, (XIY)
	INC 1, XIY
	DJNZ B, _cnv_kp_bass
	LD B, (XIY)
	AND B, 01Fh
	OR A, B
	JR Z, _cnv_kp_done
	OR L, 008h
_cnv_kp_done:
	POP XIY
	POP XIX
	POP XDE
	POP XBC
	POP XWA
	RET

; _cnv_pick_dir: A = the direction in use (0 none, 1 = C's key, 2 = B's key), B = 1 if the "2" key is
; held, C = 1 if the "1" key is held -> A = the direction now: both held keeps the one in use (or takes
; 1 if none was), one held takes it, none gives 0
_cnv_pick_dir:
	CP B, 0
	JR Z, _cnv_pd_no2
	CP C, 0
	JR Z, _cnv_pd_only2
	CP A, 0			; both held
	RET NZ
	LD A, 1
	RET
_cnv_pd_only2:
	LD A, 2
	RET
_cnv_pd_no2:
	LD A, 0
	CP C, 0
	RET Z
	LD A, 1
	RET

; _cnv_key_store: D = note, E = velocity -> CNV_KEYS bit for the note set (E != 0) or cleared
_cnv_key_store:
	CALL _cnv_key_addr	; XIY = the byte, B = the bit mask
	LD A, (XIY)
	CP E, 0
	JR Z, _cnv_ks_off
	OR A, B
	LD (XIY), A
	RET
_cnv_ks_off:
	CPL B
	AND A, B
	LD (XIY), A
	RET

; _cnv_key_held: D = note -> A = 1 if it is held, else 0 (B, C kept)
_cnv_key_held:
	PUSH XBC
	CALL _cnv_key_addr
	LD A, (XIY)
	AND A, B
	JR Z, _cnv_kh_out
	LD A, 1
_cnv_kh_out:
	POP XBC
	RET

; _cnv_key_addr: D = note -> XIY = its byte in CNV_KEYS, B = its bit
_cnv_key_addr:
	LD A, D
	AND A, 07Fh
	LD C, A
	SRL 3, A
	LD XIY, CNV_KEYS
	EXTZ WA
	AND WA, 0FFh
	EXTZ XWA
	ADD XIY, XWA
	LD A, C
	AND A, 07h
	LD B, 1
	JR Z, _cnv_ka_out	; `sll A,r' with A = 0 shifts by 16, not 0
	SLL A, B
_cnv_ka_out:
	RET

