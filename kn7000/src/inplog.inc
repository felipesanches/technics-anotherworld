# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# inplog.inc -- the input log's constants and variables (inplog.s says what the log is). INPLOG_AT: platformcnv.inc.

.equ IL_MAGIC,      0x00494C47      # "GLI" (a value no address check mistakes for one): IL_STATE while the log is kept
.equ IL_VERSION,    1
.equ IL_HDR_LOW,    0x0148          # 'H' | IL_VERSION << 8
.equ IL_MAX_FILES,  100
.equ IL_STATE,      INPLOG_AT + 0x00
.equ IL_HALF,       INPLOG_AT + 0x04    # the half being filled (0, 1)
.equ IL_N,          INPLOG_AT + 0x08    # its records
.equ IL_FULL0,      INPLOG_AT + 0x0C    # records of half 0 waiting to be written (0: none)
.equ IL_FULL1,      INPLOG_AT + 0x10
.equ IL_FILE,       INPLOG_AT + 0x14    # the next file's number
.equ IL_DROPPED,    INPLOG_AT + 0x18    # records that found no room
.equ IL_LASTIN,     INPLOG_AT + 0x1C    # the last 'I' logged: mode << 16 | mask (-1: none yet)
.equ IL_INYIELD,    INPLOG_AT + 0x20    # 1 during NextThread's end-of-frame yield
.equ IL_WROTE,      INPLOG_AT + 0x24    # files written
.equ IL_FAILS,      INPLOG_AT + 0x28    # files not written (open or write failed, or no write routine)
.equ IL_SESSION,    INPLOG_AT + 0x2C    # the kernel's ms when the log started
.equ IL_FRAMEHI,    INPLOG_AT + 0x30    # FRAME_NO's wraps, << 16
.equ IL_LASTF16,    INPLOG_AT + 0x34    # FRAME_NO as last read
.equ IL_LASTN,      INPLOG_AT + 0x38    # what the last write returned
.equ IL_RECS,       INPLOG_AT + 0x3C    # records logged
.equ IL_SEQ,        INPLOG_AT + 0x40    # halves started
.equ IL_NAME,       INPLOG_AT + 0x50    # 16 bytes: AWINnn.BIN
.equ IL_BUF0,       INPLOG_AT + 0x100
.equ IL_HALF_BYTES, 0x3F80
.equ IL_HALF_RECS,  IL_HALF_BYTES / 8
.equ IL_BUF1,       IL_BUF0 + IL_HALF_BYTES

