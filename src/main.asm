; =============================================================================
; main.asm - Another World VM for KN5000
; =============================================================================
; Unified platform wrapper for dual-target build:
;   - TARGET_MAINCPU: Standalone main CPU ROM (0xE00000, for MAME testing)
;   - TARGET_EXTENSION: HDAE5000 extension board ROM (0x280000)
;
; Build: make maincpu  OR  make extension
;
; Target: TMP94C241F (TLCS-900/H2) @ 16 MHz
; =============================================================================

	cpu 96c141		; TLCS-900/H target
	page 0
	maxmode on

; =============================================================================
; Include shared definitions from kn5000-roms-disasm
; =============================================================================
	include "sfr_tmp94c241.asm"
	include "vga_constants.asm"
	include "tmp94c241.inc"

; Local macros not in the disasm repo
	include "local_macros.inc"

; The VM drives the control panel itself (SC1) in the standalone build only.
	ifdef TARGET_MAINCPU
HAS_CPANEL	EQU 1
	endif

; =============================================================================
; RAM Section (target-specific base address)
; =============================================================================
; MAINCPU:   Uses 1MB DRAM at 0x000000-0x0FFFFF (stack in 0x000-0xFFF)
; EXTENSION: Uses 512KB extension board SRAM at 0x200000-0x27FFFF
	ifdef TARGET_MAINCPU
	ORG 010000h
	endif
	ifdef TARGET_EXTENSION
	ORG 0200000h
	endif

	include "vm_ram.inc"

; =============================================================================
; Main CPU ROM Layout
; =============================================================================
	ifdef TARGET_MAINCPU

STACK_TOP		EQU 001000h	; Stack in internal RAM
OFFSCREEN_BUFFER_1	EQU 060000h	; Offscreen buffer (required by vga_init, in DRAM)

	ORG 0E00000h

; Fill with 0xFF until code section
	rept 0F0000h		; ~960KB of padding
	db 0FFh
	endm

	ORG 0EF0000h

; Jump to Reset_Handler (VGA code is included first for macro definitions)
	jp Reset_Handler

; Include shared VGA I/O and initialization routines
	include "vga_io.asm"
	include "vga_init.asm"
	ret			; VGA_Setup has no ret (designed for inline use)

; Entry Point - Called after hardware reset
Reset_Handler:
	include "boot_hw_init.asm"

	; Set up stack pointer (after hardware init)
	LDA_XWA_IMM24 STACK_TOP
	ld XSP, XWA

	; Initialize VGA display using shared code
	CALR VGA_Setup

	; Turn screen on (sequencer clocking mode)
	VGA_SEQUENCER 01h, 001h

	jp ENTRY

	endif ; TARGET_MAINCPU

; =============================================================================
; Extension Board ROM Layout
; =============================================================================
	ifdef TARGET_EXTENSION

STACK_TOP		EQU 0200000h + 0400h	; Stack in extension SRAM (after VM vars)
OFFSCREEN_BUFFER_1	EQU 0210000h		; Offscreen buffer in extension SRAM

	ORG 0280000h

EXTENSION_HEADER:
	db 'XAPR'
	dd POINTERS
	JP ENTRY_EXT
POINTERS:
	db 0Eh, 00h, 00h, 00h; EMPTY_ROUTINE
	db 0Eh, 00h, 00h, 00h; EMPTY_ROUTINE
	db 0Eh, 00h, 00h, 00h; EMPTY_ROUTINE
	db 0Eh, 00h, 00h, 00h; EMPTY_ROUTINE
	db 0Eh, 00h, 00h, 00h; EMPTY_ROUTINE

; Include shared VGA I/O routines (needed by VM for palette writes)
	include "vga_io.asm"

ENTRY_EXT:
	; Extension entry: firmware already initialized hardware
	; Set up our own stack in extension SRAM
	LDA_XWA_IMM24 STACK_TOP
	ld XSP, XWA
	jp ENTRY

	endif ; TARGET_EXTENSION

; =============================================================================
; VM Code (shared between both targets)
; =============================================================================
	include "another_world_vm.asm"

; =============================================================================
; ROM End (target-specific)
; =============================================================================
	ifdef TARGET_MAINCPU

INTT1_Handler:
	PUSH XWA
	LD XWA, (SYSTEM_TICKS)
	INC 1, XWA
	LD (SYSTEM_TICKS), XWA
	POP XWA
	RETI

Default_Handler:
	halt
	jr Default_Handler

; Reset Handler Location
	ORG 0FFFEE0h
Reset_Entry:
	jp Reset_Handler

; Fill gap between reset entry and vector table
	ORG 0FFFEE4h
	rept 01Ch
	db 0FFh
	endm

; Interrupt Vector Table
	ORG 0FFFF00h
VECTOR_TABLE:
	dd 00FFFEE0h		; Vector 0: Reset
	dd Default_Handler	; Vector 1
	dd Default_Handler	; Vector 2
	dd Default_Handler	; Vector 3
	dd Default_Handler	; Vector 4
	dd Default_Handler	; Vector 5
	dd Default_Handler	; Vector 6
	dd Default_Handler	; Vector 7

	rept 13				; Entries 8-20 (offsets 0x20-0x50)
	dd Default_Handler
	endm
	dd INTT1_Handler		; Entry 21 (offset 0x54): INTT1
	rept 42				; Entries 22-63 (offsets 0x58-0xFC)
	dd Default_Handler
	endm

	endif ; TARGET_MAINCPU

	ifdef TARGET_EXTENSION

	ORG 02FFFFFh
	db 0FFh

	endif ; TARGET_EXTENSION

; =============================================================================
; End of ROM
; =============================================================================
	end
