; =============================================================================
; vm_ram.inc - the VM's RAM variables (no initial data)
; =============================================================================
; Included by main.asm (after its target-specific ORG) and by the KN5000 style-converter
; build (kn5000cnv/src/aw_cnv.asm).
; =============================================================================

VM_VARIABLES:	DW	256 DUP (?)

THREADS_DATA:	DW	64*2 DUP (?)  ; For each of the 64 threads:

VM_IS_CHANNEL_ACTIVE:	DB	64*2 DUP (?)   ; For each of the 64 threads:

CURRENT_THREAD: DB ?
VM_PC:				DW ?
VM_STACK_POINTER: DD ?
VM_STACK: DW 256 DUP (?)

POLYGON_NUM_POINTS:	DB ?
POLYGON_BBOX_W:		DW ?					; uint16_t
POLYGON_BBOX_H:		DW ?					; uint16_t
POLYGON_POINTS:		DW	50 DUP (?, ?, ?)
POLYGON_XMIN:	DW ?						; int16_t
POLYGON_XMAX:	DW ?						; int16_t
POLYGON_YMIN:	DW ?						; int16_t
POLYGON_YMAX:	DW ?						; int16_t
HLINEY:		DW ?							; int16_t
CUR_LINE:			; uint32_t
CUR_LINE_LOW:	DW ?
CUR_LINE_HIGH:	DW ?

CPT1:				; uint32_t
CPT1_LOW:	DW ?
CPT1_HIGH:	DW ?

CPT2:				; uint32_t
CPT2_LOW:	DW ?
CPT2_HIGH:	DW ?

STEP1:				; int32_t
STEP1_LOW:	DW ?
STEP1_HIGH:	DW ?

STEP2:				; int32_t
STEP2_LOW:	DW ?
STEP2_HIGH:	DW ?

; int16_t x1, x2;
X1:			DW ?
X2:			DW ?

; 	uint16_t h;
POLYGON_H:	DW ?
DX:			DW ?	; int16_t

;	int16_t xmax, xmin
LINE_XMIN:	DW ?
LINE_XMAX:	DW ?
CUR_PAGE_PTR_1: DD ?
CUR_PAGE_PTR_2: DD ?
CUR_PAGE_PTR_3: DD ?
CUR_VIDEO_DATA: DD ?			; Pointer to current video polygon data (video1 or video2)
CUR_VIDEO_1: DD ?				; Pointer to current part's video1 data (for reset after video2 use)
CUR_VIDEO_2: DD ?				; Pointer to current part's video2 data (0 if none)
CUR_BYTECODE: DD ?				; Pointer to current part's bytecode
CUR_PALETTES: DD ?				; Pointer to current part's palette data
CUR_ZOOM: DW ?					; uint16_t zoom for polygon scaling (default 0x40)

STRING_X0: DW ?

SYSTEM_TICKS:        DD ?		; 32-bit tick counter (ISR-incremented, 12500 Hz)
FRAME_START_TICKS:   DD ?		; Tick count at frame start
LAST_FRAME_TICKS:    DW ?		; Elapsed ticks of last frame (for diagnostics)
FRAME_OVERRAN:       DB ?		; 1 if last frame exceeded budget, 0 otherwise

REQUESTED_NEXT_PART: DW ?		; Part switch request (0 = no request)
CURRENT_PART_ID: DW ?			; Current game part ID

BMP_SRC_PTR: DD ?				; Temp: LOAD_SCREEN source pointer during 4bpp conversion

LAST_PALETTE_INDEX: DW ?		; Last palette index passed to SETUP_PALETTE (for restore after help screen)
HELP_PAGE:          DB ?		; Current help screen page (0=controls, 1=codes)
