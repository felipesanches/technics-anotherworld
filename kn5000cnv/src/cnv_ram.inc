; =============================================================================
; cnv_ram.inc - cnv_platform.asm's variables (no initial data: the firmware zeroes
; the 192 KB at 0x80000 before it loads the converter)
; =============================================================================

CNV_STATE:		DB ?		; 0 until the first call has started
CNV_EXIT_COUNT:		DB ?		; 1 while EXIT is held
CNV_VIDEO2_LOADED:	DB ?		; the shared polygons are in VIDEO2_BUF
CNV_CUR_ID:		DB ?		; resource being read
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
CNV_SAVE_DAC:		DB 48 DUP (?)	; DAC entries 0-15 (R, G, B) as the firmware set them
CNV_NAME:		DB 16 DUP (?)	; "AWnn.BIN"
CNV_DBG_REPLY:		DB 4 DUP (?)	; the last EXIT query's four reply bytes (probes)
