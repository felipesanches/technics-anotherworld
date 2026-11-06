-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_inplog.lua -- the input log (src/inplog.s) in MAME: record a session, or replay one, capturing the front page
-- at every VM frame as awcnv_cksum.lua does (AWCK_BIN, AWCK_IDX: "tick frontaddr" lines; probes/cksum_pages.py and
-- probes/compare_frames.py compare two runs, or a run and rustyworld). The game starts as a player starts it: DISK
-- MENU, STYLE CONVERT, OK (the owner's loader floppy, KN7APP.BIN and the game's files in the card's root), with
-- the splash, as on the instrument.
--
-- Record (AW_REPLAY unset): a scripted session on the keybed: the splash to its end, AW_INTRO_FRAMES frames of the
-- intro (its music's sync marks: default 300), C4 held to skip to the lake, then a sequence of moves (up, action,
-- left, right, down, diagonals, nothing), then EXIT held: the game writes its log, AWIN00.BIN ..., to the card
-- (run with a card image kept: tools/aw_inplog.py on the files fatget.py takes out of it).
--
-- Replay (AW_REPLAY=SESSION.awr, tools/aw_inplog.py's): no key is touched; what the log says the VM was given, it is
-- given, where it was given it (and a "V frame 0xVAR value" record sets a VM variable at that frame, as the code
-- screen sets var 0x00 before it asks for a part: for sessions that start a part at a checkpoint):
--   * the input: at ReadInput's last write (var 0xFE, recognised by the return address in MDR: WriteVar calls
--     nothing), the mask of the log's last I record up to this frame is written, and the variables its mode writes
--     (intro: var 0xFA; play: 0xFC, 0xE5, 0xFB, 0xFD, 0xFA); an R record at this frame sets REQ_NEXT_PART there, a G
--     record the code wheel setting, START_SEED and RESTART_REQ (the game's start again at the frame's end);
--   * the music's sync marks: the module player's own (MusicEvent writes AU_MARK, then var 0xF4) are undone, and
--     each M record is written to var 0xF4 when NextThread picks a thread at or after the record's in that frame
--     (any write of CURRENT_THREAD: the ones that pick no thread can only find marks already written).
-- At the log's E frame it quits (EXIT held), so the replay's own log can be checked against the one replayed: its
-- I, P and R records must be the same (the marks are not: the live ones are logged before they are undone).
--
-- Env: AWCK_BIN, AWCK_IDX (the capture), AWCK_VARS (optional: the 256 VM variables at each capture, int16 LE),
-- AW_LEDLOG (optional: the LED effects' state at each frame, a line each: src/leds.s), AW_REPLAY, AW_INTRO_FRAMES, AW_MAP (build/kn7app.map: ReadInput's range).
-- Addresses: src/platformcnv.inc, src/vm.inc, src/cnv_main.s, src/audio.s.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local CV, INTERP, MISC = 0x502DF000, 0x502E1000, 0x502E3000
local CV_STATE, CV_QUIT, CV_DONE, CV_TASK, CV_ENDED, LD_CUR = CV, CV + 4, CV + 8, CV + 0x1C, CV + 0x30, CV + 0x44
local PART, CUR_PAGE_2, REQ_NEXT_PART, CURRENT_THREAD = INTERP + 0x102A, INTERP + 0x100C, INTERP + 0x102C, INTERP + 0x1000
local FRAME_NO, AU_MARK, IL_STATE = MISC + 0x7C, 0x502DA038, 0x5031C000  -- inplog.inc IL_STATE (INPLOG_AT)
local START_SEED, RESTART_REQ, PR_WHEEL = MISC + 0x254, MISC + 0x258, 0x502DF900 + 10  -- vm.inc (a G record)
local function VAR(i) return INTERP + 2 * i end
local V_ACT, V_LR, V_UD, V_JMP, V_PMASK, V_AMASK, V_MARK = VAR(0xFA), VAR(0xFC), VAR(0xE5), VAR(0xFB), VAR(0xFD), VAR(0xFE), VAR(0xF4)

local OUTBIN = os.getenv("AWCK_BIN") or "build/inplog_pages.bin"
local OUTIDX = os.getenv("AWCK_IDX") or "build/inplog_pages.idx"
local REPLAY = os.getenv("AW_REPLAY"); if REPLAY == "" then REPLAY = nil end
local INTRO_FRAMES = tonumber(os.getenv("AW_INTRO_FRAMES") or "300")
local function log(s) print("awcnv_inplog: " .. s) end
local function now() return M.time:as_double() end

-- ReadInput's range, from the map (to its next routine, NotesInit)
local RI_LO, RI_HI
for line in io.lines(os.getenv("AW_MAP") or "build/kn7app.map") do
  local a, n = line:match("^0x(%x+)%s+(%S+)")
  if n == "ReadInput" then RI_LO = tonumber(a, 16) elseif n == "NotesInit" then RI_HI = tonumber(a, 16) end
end
assert(RI_LO and RI_HI, "ReadInput / NotesInit not in the map")

-- the frame as the game's log counts it: FRAME_NO counted on past 65535
local fhi, flast = 0, 0
local function frame()
  local v = sp:read_u16(FRAME_NO)
  if v < flast then fhi = fhi + 0x10000 end
  flast = v
  return fhi + v
end

-- ---- the log to replay --------------------------------------------------------------------------------
local INP, REQ, MARKS, END, VSET, RESTART = {}, {}, {}, nil, {}, {}
if REPLAY then
  for line in io.lines(REPLAY) do
    local k, rest = line:match("^(%a) (.*)$")
    if k == "I" then
      local f, mode, mask = rest:match("^(%d+) (%a+) 0x(%x+)$")
      INP[#INP + 1] = { tonumber(f), mode == "intro", tonumber(mask, 16) }
    elseif k == "R" then
      local f, p = rest:match("^(%d+) 0x(%x+)$"); REQ[tonumber(f)] = tonumber(p, 16)
    elseif k == "G" then                                    -- "G frame wheel 0xSEED": the game started again there
      local f, w, s = rest:match("^(%d+) (%d) 0x(%x+)$"); RESTART[tonumber(f)] = { tonumber(w), tonumber(s, 16) }
    elseif k == "M" then
      local f, t, v = rest:match("^(%d+) (%d+) (%-?%d+)$"); MARKS[#MARKS + 1] = { tonumber(f), tonumber(t), tonumber(v) }
    elseif k == "E" then
      END = tonumber(rest:match("^(%d+)"))
    elseif k == "V" then                                    -- "V frame 0xVAR value": a variable set there (with
      local f, v, x = rest:match("^(%d+) 0x(%x+) (%-?%w+)$")  -- an R record: the code screen's start of a part)
      f = tonumber(f); VSET[f] = VSET[f] or {}
      VSET[f][#VSET[f] + 1] = { tonumber(v, 16), x:match("^0x") and tonumber(x:sub(3), 16) or tonumber(x) }
    end
  end
  log(string.format("replaying %s: %d input changes, %d marks, end at frame %s", REPLAY, #INP, #MARKS, tostring(END)))
end
local ii, mi, stats = 1, 1, { inputs = 0, marks = 0, undone = 0, reqs = 0, modes = 0 }
local function s16(v) return v & 0xffff end
if REPLAY then
  AWIL_IN = sp:install_write_tap(V_AMASK, V_AMASK + 3, "awil_in", function(offset, data, mask)
    if offset ~= V_AMASK or (mask & 0xffff) == 0 then return end
    local mdr = cpu.state["MDR"].value
    if mdr < RI_LO or mdr >= RI_HI then return end          -- the bytecode's own use of var 0xFE
    local f = frame()
    while INP[ii + 1] and INP[ii + 1][1] <= f do ii = ii + 1 end
    local r = INP[ii]
    local intro, m = false, 0
    if r and r[1] <= f then intro, m = r[2], r[3] end
    if intro ~= (sp:read_u16(PART) == 0x3E81) then stats.modes = stats.modes + 1 end
    sp:write_u16(V_ACT, (m & 0x80) ~= 0 and 1 or 0)
    if not intro then
      local lr = (m & 1) ~= 0 and 1 or ((m & 2) ~= 0 and -1 or 0)
      local ud = (m & 4) ~= 0 and 1 or ((m & 8) ~= 0 and -1 or 0)
      sp:write_u16(V_LR, s16(lr)); sp:write_u16(V_UD, s16(ud)); sp:write_u16(V_JMP, s16(ud)); sp:write_u16(V_PMASK, m)
    end
    if VSET[f] then for _, w in ipairs(VSET[f]) do sp:write_u16(VAR(w[1]), s16(w[2])) end; VSET[f] = nil end
    if REQ[f] then sp:write_u16(REQ_NEXT_PART, REQ[f]); stats.reqs = stats.reqs + 1; REQ[f] = nil end
    if RESTART[f] then                                       -- the setting and the seed it had; GameStart at the frame's end
      sp:write_u8(PR_WHEEL, RESTART[f][1]); sp:write_u32(START_SEED, RESTART[f][2]); sp:write_u32(RESTART_REQ, 1)
      stats.reqs = stats.reqs + 1; RESTART[f] = nil
    end
    stats.inputs = stats.inputs + 1
    return (data & ~0xffff) | m                              -- the write in flight is var 0xFE's
  end)
  local undo = false
  AWIL_AUM = sp:install_write_tap(AU_MARK, AU_MARK + 3, "awil_aum", function(offset, data, mask) undo = true end)
  AWIL_MARK = sp:install_write_tap(V_MARK, V_MARK + 3, "awil_mark", function(offset, data, mask)
    if not undo or offset ~= V_MARK or (mask & 0xffff) == 0 then return end
    undo = false
    stats.undone = stats.undone + 1
    return (data & ~0xffff) | sp:read_u16(V_MARK)            -- the module player's mark: as it was
  end)
  AWIL_THR = sp:install_write_tap(CURRENT_THREAD & ~3, (CURRENT_THREAD & ~3) + 3, "awil_thr", function(offset, data, mask)
    if (mask & 0xff) == 0 then return end
    local t, f = data & 0xff, frame()
    -- thread 0 is written at the frame's end (NextThread, before FRAME_NO counts on): no more of frame f's threads
    -- run, and the end-of-frame yield comes next, where the log's thread-0 marks of frame f+1 appeared
    if t == 0 then f, t = f + 1, 0 end
    while MARKS[mi] and (MARKS[mi][1] < f or (MARKS[mi][1] == f and MARKS[mi][2] <= t)) do
      sp:write_u16(V_MARK, s16(MARKS[mi][3])); mi = mi + 1; stats.marks = stats.marks + 1
    end
  end)
end

-- ---- the capture: the front page at every FRAME_NO write (awcnv_cksum.lua's) ---------------------------------
local binf, idxf = io.open(OUTBIN, "wb"), io.open(OUTIDX, "w")
local ledf = os.getenv("AW_LEDLOG") and os.getenv("AW_LEDLOG") ~= "" and io.open(os.getenv("AW_LEDLOG"), "w")
local varf = os.getenv("AWCK_VARS") and os.getenv("AWCK_VARS") ~= "" and io.open(os.getenv("AWCK_VARS"), "wb")
local captured, capturing, chi, clast = 0, true, 0, 0
-- AW_TXTRACE=FIRST,LAST (optional; program 893): from tick FIRST to LAST, every write to the panel's SIO0 TX data
-- register (0x34000808: the bytes MAME's panel receives), to the firmware's panel TX FIFO header (0x5006BD88-
-- 0x5006BD9B: base, end, read, write, free count) and to the LED shadow and mirror (0x50150A18-0x50150A57), a line
-- each to AW_TXTRACE_OUT: "us tick what offset data mask pc".
local cur_tick = 0
local txf, tx_first, tx_last = nil, 0, -1
if os.getenv("AW_TXTRACE") and os.getenv("AW_TXTRACE") ~= "" then
  tx_first, tx_last = os.getenv("AW_TXTRACE"):match("(%d+),(%d+)")
  tx_first, tx_last = tonumber(tx_first), tonumber(tx_last)
  txf = io.open(os.getenv("AW_TXTRACE_OUT"), "w")
  local cpu = M.devices[":maincpu"]
  local function tap(lo, hi, what)
    return sp:install_write_tap(lo, hi, "awil_tx_" .. what, function(offset, data, mask)
      if cur_tick >= tx_first and cur_tick <= tx_last then
        txf:write(string.format("%d %d %s %08X %08X %08X %08X\n", math.floor(M.time:as_double() * 1e6), cur_tick, what,
          offset, data, mask, cpu.state["PC"].value))
      end
    end)
  end
  AWIL_TX1 = tap(0x34000808, 0x3400080B, "sio")
  AWIL_TX2 = tap(0x5006BD88, 0x5006BD9B, "fifo")
  AWIL_TX3 = tap(0x50150A18, 0x50150A57, "led")
end
AWIL_FRAME = sp:install_write_tap(FRAME_NO, FRAME_NO + 3, "awil_frame", function(offset, data, mask)
  if not capturing or offset ~= FRAME_NO then return end
  local v = data & 0xffff
  if v == 0 then return end
  if v < clast then chi = chi + 0x10000 end
  clast = v
  local tick = chi + v - 1                                   -- the frame just ended (awcnv_cksum.lua's tick)
  cur_tick = tick + 1
  local front = sp:read_u32(CUR_PAGE_2)
  binf:write(sp:read_range(front, front + sp:read_u32(MISC + 0x6C) - 1, 8))  -- PG_SIZE: 64000 or 92160
  if varf then varf:write(sp:read_range(INTERP, INTERP + 511, 8)) end
  if ledf then
    -- AW_LEDLOG: the LED effects at every frame (src/leds.s): active, charge, red / all until (ms left), blinks to go,
    -- the shadow and the mirror (sent) bytes, the panel's LED outputs MAME has lit, the kernel ms, the pulse's start, the panel's registers, the TX FIFO's free count,
    -- then the mega-blast flag, the random LEDs' chance (the waterfall), the left / right red and the green (ms left), VM var 0x04 (Lester's facing),
    -- the shield's flash (ms left), and 1 while the battle tank's panel shows (part 0x3E85, thread 59 running)
    local LV, sh = 0x502DAD00, sp:read_u32(0x502DAD00)
    local ms = sp:read_u32(sp:read_u32(MISC + 0x200))
    local lit = 0
    for _, side in ipairs({ "cpl_led", "cpr_led" }) do
      for i = 0, 127 do if (M.output:get_value(side .. i) or 0) ~= 0 then lit = lit + 1 end end
    end
    local function hex(a) local t = {}; for i = 0, 19 do t[#t + 1] = string.format("%02X", sp:read_u8(a + i)) end; return table.concat(t) end
    -- the panel's view of the 20 registers, rebuilt from the outputs (cpl: register r = wire C0+r, output r*8+bit;
    -- cpr: registers 8-13 = wires 00-05, 14-19 = wires 08-0D, output wire*8+bit), and the panel TX FIFO's free
    -- count (893: the FIFO at 0x5006BD88, its free count u16 at +0x10)
    local pv = {}
    for r = 0, 19 do
      local side, w = "cpl_led", r
      if r >= 14 then side, w = "cpr_led", r - 14 + 8 elseif r >= 8 then side, w = "cpr_led", r - 8 end
      local v = 0
      for b = 0, 7 do if (M.output:get_value(side .. (w * 8 + b)) or 0) ~= 0 then v = v | (1 << b) end end
      pv[#pv + 1] = string.format("%02X", v)
    end
    local function left(o) return math.max(0, sp:read_u32(LV + o) - ms) end
    ledf:write(string.format("%d %d %d %d %d %d %s %s %d %d %d %s %d %d %d %d %d %d %04X %d %d\n", tick, sp:read_u32(LV + 8), sp:read_u32(LV + 0xC),
      left(0x10), left(0x14), sp:read_u32(LV + 0x18),
      sh ~= 0 and hex(sh) or "-", sh ~= 0 and hex(sh + 0x20) or "-", lit, ms, sp:read_u32(LV + 0x20), table.concat(pv), sp:read_u16(0x5006BD98),
      sp:read_u32(LV + 0x30), sp:read_u32(LV + 0x34), left(0x24), left(0x28), left(0x2C), sp:read_u16(VAR(0x04)), left(0xA0),
      (sp:read_u16(PART) == 0x3E85 and sp:read_u16(INTERP + 0x400 + 59 * 4) ~= 0xFFFF) and 1 or 0))
  end
  idxf:write(string.format("%d %08X\n", tick, front))
  captured = captured + 1
end)
-- AW_TIMELOG (optional): the timing of the picture and of the music (probes/musictiming.py reads it), a line each:
--   F tick kms pause blits us   a VM frame ended (FRAME_NO written, before its pacing yield): the kernel's ms counter,
--                               var 0xFF, the BLIT_FRAMEBUFFERs it ran (each writes CUR_PAGE_2), MAME's time in us
--   K tick kms row due value us the module player wrote a sync mark (AU_MARK): its module row (AU_ROWS, rows played
--                               so far, this one included), the kernel ms the row was due (AU_NEXT), the mark
--   S tick kms rows per us      a module started (AU_MOD written non-zero): AU_ROWS before its first row, AU_PER
--   P tick kms per us          AU_PER written (a module's start, or PLAY_MUSIC retiming the one playing)
-- AU_ROWS, AU_NEXT, AU_PER, AU_MOD: src/audio.s (AUDIO_VARS 0x502DA000 + 0x30, 0x1C, 0x24, 0x14).
local timef = os.getenv("AW_TIMELOG") and os.getenv("AW_TIMELOG") ~= "" and io.open(os.getenv("AW_TIMELOG"), "w")
if timef then
  local AU = 0x502DA000
  local blits = 0
  local function kms() return sp:read_u32(sp:read_u32(MISC + 0x200)) end
  local function us() return math.floor(M.time:as_double() * 1e6) end
  AWIL_TBLIT = sp:install_write_tap(CUR_PAGE_2, CUR_PAGE_2 + 3, "awil_tblit", function(offset, data, mask)
    if offset == CUR_PAGE_2 then blits = blits + 1 end
  end)
  AWIL_TFRAME = sp:install_write_tap(FRAME_NO & ~3, (FRAME_NO & ~3) + 3, "awil_tframe", function(offset, data, mask)
    if (FRAME_NO & 3) == 0 and (mask & 0xffff) == 0 then return end
    if (FRAME_NO & 3) == 2 and (mask & 0xffff0000) == 0 then return end
    timef:write(string.format("F %d %d %d %d %d\n", frame(), kms(), sp:read_u16(VAR(0xFF)), blits, us()))
    blits = 0
  end)
  AWIL_TMARK = sp:install_write_tap(AU + 0x38, AU + 0x3B, "awil_tmark", function(offset, data, mask)
    timef:write(string.format("K %d %d %d %d %d %d\n", frame(), kms(), sp:read_u32(AU + 0x30), sp:read_u32(AU + 0x1C),
      data & 0xffff, us()))
  end)
  AWIL_TPER = sp:install_write_tap(AU + 0x24, AU + 0x27, "awil_tper", function(offset, data, mask)
    timef:write(string.format("P %d %d %d %d\n", frame(), kms(), data, us()))
  end)
  AWIL_TMOD = sp:install_write_tap(AU + 0x14, AU + 0x17, "awil_tmod", function(offset, data, mask)
    if data ~= 0 then
      timef:write(string.format("S %d %d %d %d %d\n", frame(), kms(), sp:read_u32(AU + 0x30), sp:read_u32(AU + 0x24), us()))
    end
  end)
end
local function stop_capture()
  if capturing then capturing = false; if txf then txf:close() end; binf:close(); idxf:close(); if varf then varf:close() end; if ledf then ledf:close() end; if timef then timef:close(); timef = nil end; log(string.format("captured %d frames", captured)) end
end

-- ---- inputs --------------------------------------------------------------------------------------------------
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local KEY = {}
for _, tag in ipairs({ ":KEYS0", ":KEYS1", ":KEYS2", ":KEYS3" }) do
  local p = M.ioport.ports[tag]
  if p then for _, f in pairs(p.fields) do KEY[f.name] = f end end
end
local NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local function keyfield(n)
  local nm, o = NAMES[n % 12 + 1], n // 12 - 1
  return KEY[nm:sub(2, 2) == "#" and (nm:sub(1, 1) .. o .. "#") or (nm .. o)]
end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(cond, s) local t = now() + s; while now() < t do if cond() then return true end; coroutine.yield() end; return cond() end
local function press(tag, mask, hold) local f = field(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end
local function hold_keys(notes, s)
  for _, n in ipairs(notes) do keyfield(n):set_value(1) end
  wait(s)
  for _, n in ipairs(notes) do keyfield(n):set_value(0) end
end
local C3, C4, F5, A5, AB5, C6 = 48, 60, 77, 81, 80, 84

local function session()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)                          -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)                          -- STYLE CONVERT
  for i = 1, 8 do                                           -- OK (KN7LOAD.CNV), until the game runs
    press("CPR_SEG6", 0x01)
    if wait_until(function() return sp:read_u32(CV_STATE) >= 2 end, 12) then break end
  end
  -- the pages at 320x200, as rustyworld's (vm.inc DISP_ORIG; the game reads it when its task starts), unless
  -- AW_HIRES=1: the game's own default, 384x240 pages (then the pages compare with nothing)
  if not os.getenv("AW_HIRES") then sp:write_u32(MISC + 0x60, 0x0A1D0320) end
  if not wait_until(function() return sp:read_u32(CV_STATE) == 3 and sp:read_u32(CV_TASK) ~= 0 end, 120) then
    log("the game did not start"); return
  end
  log(string.format("game task %d at t=%.1f s", sp:read_u32(CV_TASK), now()))
  if REPLAY then
    wait_until(function() return END and frame() >= END end, 7200)
    log(string.format("frame %d reached; inputs applied %d, marks written %d, module marks undone %d, requests %d, mode mismatches %d",
      frame(), stats.inputs, stats.marks, stats.undone, stats.reqs, stats.modes))
  else
    wait_until(function() return sp:read_u16(PART) == 0x3E81 end, 300)   -- the splash ends by itself
    local f0 = frame()
    log(string.format("intro at frame %d, t=%.1f s", f0, now()))
    wait_until(function() return frame() >= f0 + INTRO_FRAMES end, 600)
    keyfield(C4):set_value(1)                               -- skip to the lake
    wait_until(function() return sp:read_u16(PART) == 0x3E82 end, 60)
    keyfield(C4):set_value(0)
    wait_until(function() return sp:read_u32(LD_CUR) == 0x3E82 end, 60)
    wait(3)
    log(string.format("lake at frame %d", frame()))
    hold_keys({ AB5 }, 2.0); wait(0.5)                      -- up
    hold_keys({ C3 }, 1.0); wait(0.5)                       -- action
    hold_keys({ F5 }, 2.0)                                  -- left
    hold_keys({ C6 }, 2.0)                                  -- right
    hold_keys({ A5 }, 1.0)                                  -- down
    hold_keys({ AB5, C6 }, 1.5)                             -- up and right
    wait(2.0)
    hold_keys({ C3, F5 }, 1.0)                              -- action and left
    hold_keys({ AB5 }, 1.5)
    wait(1.0)
  end
  stop_capture()
  log(string.format("quitting at frame %d", frame()))
  press("CPC_SEG11", 0x80, 2.0)                             -- EXIT held: the task ends, the log is written
  wait_until(function() return sp:read_u32(CV_DONE) == 1 end, 20)
  wait_until(function() return sp:read_u32(IL_STATE) == 0 end, 20)
  wait(3)
  log(string.format("log closed: files written %d, failed %d, records %d, dropped %d",
    sp:read_u32(IL_STATE + 0x24), sp:read_u32(IL_STATE + 0x28), sp:read_u32(IL_STATE + 0x3C), sp:read_u32(IL_STATE + 0x18)))
end

-- AW_LEDFINE (optional): the LED shadow at every MAME frame (60 a second, finer than the VM's frames), a line each
-- while the capture runs: "the VM tick, the kernel ms, the shadow's 20 bytes" (probes/liftcheck.py --fine reads it);
-- with AW_LEDFINE_THREAD=n, thread n's pc after them.
local finef = os.getenv("AW_LEDFINE") and os.getenv("AW_LEDFINE") ~= "" and io.open(os.getenv("AW_LEDFINE"), "w")
local co = coroutine.create(session)
AWIL_TICK = emu.add_machine_frame_notifier(function()
  if finef and capturing then
    local sh = sp:read_u32(0x502DAD00)
    if sh ~= 0 then
      local t = {}
      for i = 0, 19 do t[#t + 1] = string.format("%02X", sp:read_u8(sh + i)) end
      local th = tonumber(os.getenv("AW_LEDFINE_THREAD") or "")  -- (optional: that thread's pc too, a 4th field)
      finef:write(string.format("%d %d %s%s\n", cur_tick, sp:read_u32(sp:read_u32(MISC + 0x200)), table.concat(t),
        th and string.format(" %04X", sp:read_u16(INTERP + 0x400 + th * 4)) or ""))
    end
  elseif finef then
    finef:close(); finef = nil
  end
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then log("ERROR " .. tostring(err)); stop_capture(); M:exit() end
  else
    stop_capture(); M:exit()
  end
end)
