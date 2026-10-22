; =============================================================================
; aw_cnv.asm - Another World for the KN5000, as a style converter (AW.CNV)
; =============================================================================
; DISK MENU > STYLE CONVERT loads this file whole at 0x80000 and calls its first
; byte (kn5000cnv/README.md). The VM (../src/another_world_vm.asm, TARGET_CNV)
; runs inside that first call; the game's resources are read from the same
; floppy, part by part (cnv_platform.asm). Holding EXIT for 1.5 s ends the game
; and returns to the firmware.
;
; Memory (all work DRAM, 0x80000-0xFDFFF):
;   0x080000  this program, its tables, the VM's variables, then the palette,
;             bytecode and polygon buffers of the current part
;   0x0B0000  the four 320x200 pages, 64 KB apart (the sequencer's song memory,
;             used only when it holds no song, and given back as found)
;   0x0EFA00  the shared polygons (resource 0x11), then the screen buffer
; and VRAM 0x1B3000 for the help screen's draw buffer.
;
; Build: kn5000cnv/Makefile.
; =============================================================================

	cpu 96c141		; TLCS-900/H
	page 0
	maxmode on

	include "sfr_tmp94c241.asm"
	include "vga_constants.asm"
	include "tmp94c241.inc"
	include "local_macros.inc"

HAS_CPANEL	EQU 1		; the VM reads the panel itself while it runs (SC1)
OFFSCREEN_BUFFER_1	EQU 01B3000h	; the help screen's 320x200 draw buffer: VRAM past the visible
					; 320x240 (0x1A0000-0x1B2BFF), which the firmware does not draw while we run

	ORG 080000h

CNV_ENTRY:
	JP CNV_CALL		; the firmware calls the file's first byte

	include "vga_io.asm"
	include "another_world_vm.asm"
	include "cnv_platform.asm"
	include "awfiles.inc"

; The VM finds each part's resources here (initForPart); CNV_LOAD_PART fills the buffers.
PART_RESOURCE_TABLE:
	dd PALETTE_BUF, BYTECODE_BUF, VIDEO1_BUF, 0		; 0 protection
	dd PALETTE_BUF, BYTECODE_BUF, VIDEO1_BUF, 0		; 1 intro
	dd PALETTE_BUF, BYTECODE_BUF, VIDEO1_BUF, VIDEO2_BUF	; 2 water
	dd PALETTE_BUF, BYTECODE_BUF, VIDEO1_BUF, VIDEO2_BUF	; 3 jail
	dd PALETTE_BUF, BYTECODE_BUF, VIDEO1_BUF, VIDEO2_BUF	; 4 citadel
	dd PALETTE_BUF, BYTECODE_BUF, VIDEO1_BUF, 0		; 5 battlechar
	dd PALETTE_BUF, BYTECODE_BUF, VIDEO1_BUF, VIDEO2_BUF	; 6 arena
	dd PALETTE_BUF, BYTECODE_BUF, VIDEO1_BUF, VIDEO2_BUF	; 7 final
	dd PALETTE_BUF, BYTECODE_BUF, VIDEO1_BUF, 0		; 8 password
	dd PALETTE_BUF, BYTECODE_BUF, VIDEO1_BUF, 0		; 9 password (same)

CNV_IMAGE_END:			; the .CNV file ends here; what follows is zeroed RAM

	include "vm_ram.inc"
	include "cnv_ram.inc"

CNV_RAM_END:

; -----------------------------------------------------------------------------
; Buffers
; -----------------------------------------------------------------------------
PALETTE_BUF	EQU (CNV_RAM_END + 0FFh) & 0FFFF00h
BYTECODE_BUF	EQU (PALETTE_BUF + CNV_MAX_PALETTE + 0FFh) & 0FFFF00h
VIDEO1_BUF	EQU (BYTECODE_BUF + CNV_MAX_BYTECODE + 0FFh) & 0FFFF00h
VIDEO1_END	EQU VIDEO1_BUF + CNV_MAX_VIDEO1
VIDEO2_BUF	EQU PAGE_BITMAP_3 + 64000
SCREEN_BUF	EQU (VIDEO2_BUF + CNV_SIZE_VIDEO2 + 0FFh) & 0FFFF00h
SCREEN_END	EQU SCREEN_BUF + 32000

	if CNV_IMAGE_END > 0B0000h
	error "AW.CNV is larger than the 192 KB the firmware loads"
	endif
	if VIDEO1_END > PAGE_BITMAP_0
	error "the part buffers run into the page buffers"
	endif
	if SCREEN_END > CNV_SONG_END
	error "the screen buffer runs past the song memory"
	endif

	end
