; hello.asm -- the smallest KN5000 style converter (.CNV) that shows it runs.
;
; DISK MENU > STYLE CONVERT loads a .CNV whole at 0x80000 (after zeroing 192 KB there) and calls
; its first byte. It returns to the firmware after each step, leaving a request in the mailbox
; at 0xFFC00: request 1 (copy the string at 0xFFC01, then call again at once) parks the firmware
; without a repaint; request 0xFE ends the run with the firmware's own message.
;
; Each call: count the call, fill rows 100..139 of the LCD with the count's low byte as the colour
; index, leave "CNV5" and the count where a probe can read them. After 600 calls: request 0xFE.

	cpu 96c141
	page 0
	maxmode on

MAILBOX		equ 0FFC00h
SIGNATURE	equ 0A0000h		; "CNV5", inside the zeroed load area
CALLS		equ 0A0004h		; 32-bit call count
VRAM		equ 01A0000h		; 320 x 240, one byte per pixel

	org 080000h

ENTRY:
	push	xwa
	push	xbc
	push	xhl

	ld	xwa, 'C' | ('N' << 8) | ('V' << 16) | ('5' << 24)
	ld	(SIGNATURE), xwa
	ld	xwa, (CALLS)
	inc	1, xwa
	ld	(CALLS), xwa

	ld	xhl, VRAM + 100*320
	ld	bc, 40*320
FILL:
	ld	(xhl), a
	inc	1, xhl
	djnz	bc, FILL

	ld	xwa, (CALLS)
	cp	xwa, 600
	jr	nc, FINISH
	ld	a, 0
	ld	(MAILBOX+1), a		; request 1's string: empty
	ld	a, 1
	ld	(MAILBOX), a
	jr	DONE
FINISH:
	ld	a, 0FEh
	ld	(MAILBOX), a
DONE:
	pop	xhl
	pop	xbc
	pop	xwa
	ret

	end
