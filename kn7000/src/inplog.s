# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# inplog.s -- the input log: what the VM was given from outside, frame by frame, saved on the SD card, so that a
# session played on the instrument can be played again exactly, in MAME (probes/cnv/awcnv_replay.lua) and in the
# reference VM (rustyworld: research-scratch kn7000-aw-reference/replay-mods), and the two compared frame by frame
# (README-CNV.md, "Replaying a session"). The KN7APP.BIN build's; the SP7001 build has inplog_stub.s.
#
# All that reaches the VM from outside (it is otherwise deterministic: GameReset fixes the random seed):
#   * the input ReadInput applies at the start of each frame: in the intro var 0xFA and 0xFE, in every other part
#     the six hero variables, which all follow from the mask it writes to var 0xFE (interp.s ReadInput);
#   * a part asked for from the panel (OTHER PART & FR: the level-code screen);
#   * the music's sync marks (var 0xF4), which the module player writes on the kernel's clock, not the VM's: between
#     two threads (NextThread's AudioPoll: the threads after the one that just ran see it) or in the yield at the
#     end of a frame (the next frame's threads all see it). The intro waits for them.
# A record is 8 bytes, little-endian: u32 frame (FRAME_NO, counted on past 65535), u8 kind, u8 a, u16 b:
#   'H'  a = IL_VERSION, b = the half's number (0, 1, ...: its file's); frame = the kernel's ms at the start
#   'I'  a = 1 in the intro's mode (only var 0xFA, 0xFE written), 0 otherwise; b = the mask (var 0xFE); logged when
#        either changes, at the frame ReadInput ran in
#   'P'  b = the part now running (InitForPart, which a switch runs after that frame's ReadInput)
#   'R'  b = the part ReadInput asked for (REQ_NEXT_PART)
#   'M'  a = the first thread to see it (0-64), b = the mark
#   'E'  frame = the last frame; b = the records that found no room (0: none lost)
# The game task appends to one half of the buffer; when the half is full the other takes over, and the main task
# (CnvEntry, between part loads, while no panel button is down) writes the full one to AWINnn.BIN in the SD card's
# root folder, nn = 00, 01, ... (at most IL_MAX_FILES); at quit it writes what is left, ending with 'E'. Each file
# is one half: an 'H' record first. A session writes over the last one's files.
# Convention as the rest of the port: d0, d1, a0, a1 scratch; d2, d3, a2, a3 kept.

# (the record kinds' and variables' equates: inplog.inc, included at the top of cnv_main.s)

# =================================================================================
# InpLogInit: a new log (the main task, StartTask, before the game task starts). Half 0 begins with 'H'.
InpLogInit:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     INPLOG_AT, a0
    mov     0x40, d1
    clr     d0
ili_zero:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     ili_zero
    mov     -1, d0
    mov     d0, (IL_LASTIN)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (IL_SESSION)
    clr     d0                      # half 0, its header
    call    IlHeader, 0, 0
    mov     IL_MAGIC, d0
    mov     d0, (IL_STATE)
    ret     [d2,d3,a2,a3], 0x20

# IlHeader(d0 = half): the half starts with 'H' (its number IL_SEQ, which then counts on); IL_N = 1.
IlHeader:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    IlHalfBase, 0, 0        # a0 = the half
    mov     (IL_SESSION), d0
    mov     d0, (a0)
    mov     (IL_SEQ), d0
    asl     16, d0
    or      IL_HDR_LOW, d0           # 'H', IL_VERSION
    mov     d0, (4, a0)
    mov     (IL_SEQ), d0
    inc     d0
    mov     d0, (IL_SEQ)
    mov     1, d0
    mov     d0, (IL_N)
    ret     [d2,d3,a2,a3], 0x20

# IlHalfBase(d0 = half) -> a0 = its records. Leaf.
IlHalfBase:
    mov     IL_BUF0, a0
    cmp     0, d0
    beq     ihb_ret
    mov     IL_BUF1, a0
ihb_ret:
    rets

# IlFrame -> d0 = the frame: FRAME_NO, counted on past 65535 (game task). Leaf; uses d1.
IlFrame:
    movhu   (FRAME_NO), d0
    mov     (IL_LASTF16), d1
    mov     d0, (IL_LASTF16)
    cmp     d1, d0
    bcc     ilf_same                # (unsigned: not below the last one)
    mov     (IL_FRAMEHI), d1
    add     0x10000, d1
    mov     d1, (IL_FRAMEHI)
ilf_same:
    mov     (IL_FRAMEHI), d1
    add     d1, d0
    rets

# IlSwitch: the half being filled is full: hand it to the main task (IL_FULLh) and fill the other, if the main task
# has written that one -> d0 = 0, or 1 when it has not (nothing changes; the next record tries again).
IlSwitch:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (IL_HALF), d2           # d2 = the full half
    mov     IL_FULL1, a2            # a2 = the other's IL_FULL
    cmp     0, d2
    beq     isw_other
    mov     IL_FULL0, a2
isw_other:
    mov     (a2), d0
    cmp     0, d0
    bne     isw_busy
    mov     d2, d0
    xor     1, d0
    mov     d0, d3                  # d3 = the other half
    mov     (IL_N), d1
    mov     IL_FULL0, a1            # the full one goes to the main task
    cmp     0, d2
    beq     isw_mark
    mov     IL_FULL1, a1
isw_mark:
    mov     d1, (a1)
    mov     d3, (IL_HALF)
    mov     d3, d0
    call    IlHeader, 0, 0
    clr     d0
    bra     isw_ret
isw_busy:
    mov     1, d0
isw_ret:
    ret     [d2,d3,a2,a3], 0x20

# IlPut(d0 = frame, d1 = b << 16 | a << 8 | kind): one record (game task; the main task at the end).
IlPut:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    mov     d1, d3
    mov     (IL_STATE), d0
    cmp     IL_MAGIC, d0
    bne     ilp_ret
    mov     (IL_N), d0
    cmp     IL_HALF_RECS, d0
    bcs     ilp_store               # room in this half
    call    IlSwitch, 0, 0
    cmp     0, d0
    bne     ilp_drop
ilp_store:
    mov     (IL_HALF), d0
    call    IlHalfBase, 0, 0
    mov     (IL_N), d0
    asl     3, d0
    add     d0, a0
    mov     d2, (a0)
    mov     d3, (4, a0)
    mov     (IL_RECS), d0
    inc     d0
    mov     d0, (IL_RECS)
    mov     (IL_N), d0
    inc     d0
    mov     d0, (IL_N)
    cmp     IL_HALF_RECS, d0
    bne     ilp_ret
    call    IlSwitch, 0, 0          # full: to the main task now (or at the next record)
    bra     ilp_ret
ilp_drop:
    mov     (IL_DROPPED), d0
    inc     d0
    mov     d0, (IL_DROPPED)
ilp_ret:
    ret     [d2,d3,a2,a3], 0x20

# =================================================================================
# The game task's records (interp.s, audio.s).
#
# InpLogInput: after ReadInput (NextThread): the mask it wrote to var 0xFE and its mode, when they changed.
InpLogInput:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     VAR_HERO_ACT_MASK, d0
    call    ReadVar, 0, 0
    and     0xffff, d0
    mov     d0, d2                  # d2 = mask
    clr     d3                      # d3 = mode: 1 in the intro (ReadInput decided by this part)
    movhu   (CURRENT_PART_ID), d1
    cmp     0x3E81, d1
    bne     ili_mode
    mov     1, d3
ili_mode:
    mov     d3, d0
    asl     16, d0
    or      d2, d0
    mov     (IL_LASTIN), d1
    cmp     d1, d0
    beq     ili_ret
    mov     d0, (IL_LASTIN)
    call    IlFrame, 0, 0
    mov     d2, d1
    asl     16, d1
    asl     8, d3
    or      d3, d1
    or      0x49, d1                # 'I'
    call    IlPut, 0, 0
ili_ret:
    ret     [d2,d3,a2,a3], 0x20

# InpLogRequest(d0 = part): ReadInput asked for that part (the panel's level-code button).
InpLogRequest:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    call    IlFrame, 0, 0
    mov     d2, d1
    asl     16, d1
    or      0x52, d1                # 'R'
    call    IlPut, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# InpLogPart(d0 = part): InitForPart has switched to it.
InpLogPart:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    call    IlFrame, 0, 0
    mov     d2, d1
    and     0xffff, d1
    asl     16, d1
    or      0x50, d1                # 'P'
    call    IlPut, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# InpLogMark(d0 = the mark): the module player wrote var 0xF4 (audio.s MusicEvent). The first thread to see it:
# thread 0 of this frame in the end-of-frame yield (FRAME_NO has counted on already), else the one after the
# thread that just ran (NextThread's AudioPoll runs before it picks the next).
InpLogMark:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    clr     d3
    mov     (IL_INYIELD), d0
    cmp     0, d0
    bne     ilm_thread
    movbu   (CURRENT_THREAD), d3
    inc     d3
ilm_thread:
    call    IlFrame, 0, 0
    mov     d2, d1
    and     0xffff, d1
    asl     16, d1
    asl     8, d3
    or      d3, d1
    or      0x4D, d1                # 'M'
    call    IlPut, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# InpLogYield(d0 = 1 entering NextThread's end-of-frame yield, 0 leaving it). Leaf.
InpLogYield:
    mov     d0, (IL_INYIELD)
    rets

# =================================================================================
# The main task's side (cnv_main.s).
#
# InpLogFlush: a half waiting to be written goes to the next AWINnn.BIN; not while a panel button is down (the
# main task decodes the panel: a file write keeps it busy, as a part's list does, cnv_main.s ce_load).
InpLogFlush:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (IL_STATE), d0
    cmp     IL_MAGIC, d0
    bne     ilfl_ret
    clr     d2                      # d2 = the half waiting, if any
    mov     (IL_FULL0), d0
    cmp     0, d0
    bne     ilfl_found
    mov     1, d2
    mov     (IL_FULL1), d0
    cmp     0, d0
    beq     ilfl_ret
ilfl_found:
    mov     d0, d3                  # d3 = its records
    call    PanelIdle, 0, 0
    cmp     0, d0
    bne     ilfl_ret
    mov     d2, d0
    mov     d3, d1
    call    IlWriteFile, 0, 0
    clr     d0
    mov     IL_FULL0, a0
    cmp     0, d2
    beq     ilfl_clear
    mov     IL_FULL1, a0
ilfl_clear:
    mov     d0, (a0)                # the half is free again
ilfl_ret:
    ret     [d2,d3,a2,a3], 0x20

# InpLogFinish: at quit, the game task gone: the half waiting, then the one being filled with 'E' at its end (in a
# file of its own when that half is full). Then the log is closed.
InpLogFinish:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (IL_STATE), d0
    cmp     IL_MAGIC, d0
    bne     ilfi_ret
    mov     (IL_FULL0), d1
    cmp     0, d1
    beq     ilfi_f1
    clr     d0
    call    IlWriteFile, 0, 0
    clr     d0
    mov     d0, (IL_FULL0)
ilfi_f1:
    mov     (IL_FULL1), d1
    cmp     0, d1
    beq     ilfi_last
    mov     1, d0
    call    IlWriteFile, 0, 0
    clr     d0
    mov     d0, (IL_FULL1)
ilfi_last:
    mov     (IL_N), d0
    cmp     IL_HALF_RECS, d0
    bcs     ilfi_end
    mov     (IL_HALF), d0           # full: written as it is, 'E' in a half of its own
    mov     (IL_N), d1
    call    IlWriteFile, 0, 0
    mov     (IL_HALF), d0
    call    IlHeader, 0, 0
ilfi_end:
    call    IlFrame, 0, 0
    mov     (IL_DROPPED), d1
    asl     16, d1
    or      0x45, d1                # 'E'
    call    IlPut, 0, 0
    mov     (IL_HALF), d0
    mov     (IL_N), d1
    call    IlWriteFile, 0, 0
    clr     d0
    mov     d0, (IL_STATE)
ilfi_ret:
    ret     [d2,d3,a2,a3], 0x20

# IlWriteFile(d0 = half, d1 = records): the half to AWINnn.BIN, nn = IL_FILE, which counts on; as ReportWrite
# (cnv_main.s) writes AWPERF.TXT: the drive switch to the card, open "wb" (relative to C:\), one write, close, the
# drive switch back.
IlWriteFile:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    IlHalfBase, 0, 0
    mov     a0, a2                  # a2 = the records
    mov     d1, d2
    asl     3, d2                   # d2 = bytes
    mov     (IL_FILE), d3
    cmp     IL_MAX_FILES, d3
    bcc     ilw_fail
    mov     (FW_WRITE), d0
    cmp     0, d0
    beq     ilw_fail
    inc     d3
    mov     d3, (IL_FILE)
    add     -1, d3                  # d3 = nn
    mov     inplog_name, a1
    mov     IL_NAME, a0
    call    StrPut, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     d3, d0
    mov     10, d1
    call    Div, 0, 0               # d0 = tens, d1 = units
    add     0x30, d0
    movbu   d0, (IL_NAME + 4)
    add     0x30, d1
    movbu   d1, (IL_NAME + 5)
    mov     1, d0                   # the file layer to the SD card
    mov     (FW_SETEXT), a3
    calls   (a3)
    mov     IL_NAME, a0
    mov     mode_wb, a1
    mov     (FW_OPEN), a3
    calls   (a3)
    exth    d0
    mov     d0, (IL_LASTN)
    cmp     0, d0
    blt     ilw_back_fail
    mov     a2, a0
    mov     d2, d0
    mov     (FW_WRITE), a3
    calls   (a3)                    # d0 = bytes written
    mov     d0, (IL_LASTN)
    mov     d0, d3
    mov     (FW_CLOSE), a3
    calls   (a3)
    mov     (FW_RESETEXT), a3
    calls   (a3)
    cmp     d2, d3
    bne     ilw_fail
    mov     (IL_WROTE), d0
    inc     d0
    mov     d0, (IL_WROTE)
    bra     ilw_ret
ilw_back_fail:
    mov     (FW_RESETEXT), a3
    calls   (a3)
ilw_fail:
    mov     (IL_FAILS), d0
    inc     d0
    mov     d0, (IL_FAILS)
ilw_ret:
    ret     [d2,d3,a2,a3], 0x20

inplog_name:
    .asciz  "AWIN00.BIN"
    .align  4
