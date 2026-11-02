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
-- given, where it was given it:
--   * the input: at ReadInput's last write (var 0xFE, recognised by the return address in MDR: WriteVar calls
--     nothing), the mask of the log's last I record up to this frame is written, and the variables its mode writes
--     (intro: var 0xFA; play: 0xFC, 0xE5, 0xFB, 0xFD, 0xFA); an R record at this frame sets REQ_NEXT_PART there;
--   * the music's sync marks: the module player's own (MusicEvent writes AU_MARK, then var 0xF4) are undone, and
--     each M record is written to var 0xF4 when NextThread picks a thread at or after the record's in that frame
--     (any write of CURRENT_THREAD: the ones that pick no thread can only find marks already written).
-- At the log's E frame it quits (EXIT held), so the replay's own log can be checked against the one replayed: its
-- I, P and R records must be the same (the marks are not: the live ones are logged before they are undone).
--
-- Env: AWCK_BIN, AWCK_IDX (the capture), AWCK_VARS (optional: the 256 VM variables at each capture, int16 LE), AW_REPLAY, AW_INTRO_FRAMES, AW_MAP (build/kn7app.map: ReadInput's range).
-- Addresses: src/platformcnv.inc, src/vm.inc, src/cnv_main.s, src/audio.s.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local CV, INTERP, MISC = 0x502DF000, 0x502E1000, 0x502E3000
local CV_STATE, CV_QUIT, CV_DONE, CV_TASK, CV_ENDED, LD_CUR = CV, CV + 4, CV + 8, CV + 0x1C, CV + 0x30, CV + 0x44
local PART, CUR_PAGE_2, REQ_NEXT_PART, CURRENT_THREAD = INTERP + 0x102A, INTERP + 0x100C, INTERP + 0x102C, INTERP + 0x1000
local FRAME_NO, AU_MARK, IL_STATE = MISC + 0x7C, 0x502DA038, 0x50372000
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
local INP, REQ, MARKS, END = {}, {}, {}, nil
if REPLAY then
  for line in io.lines(REPLAY) do
    local k, rest = line:match("^(%a) (.*)$")
    if k == "I" then
      local f, mode, mask = rest:match("^(%d+) (%a+) 0x(%x+)$")
      INP[#INP + 1] = { tonumber(f), mode == "intro", tonumber(mask, 16) }
    elseif k == "R" then
      local f, p = rest:match("^(%d+) 0x(%x+)$"); REQ[tonumber(f)] = tonumber(p, 16)
    elseif k == "M" then
      local f, t, v = rest:match("^(%d+) (%d+) (%-?%d+)$"); MARKS[#MARKS + 1] = { tonumber(f), tonumber(t), tonumber(v) }
    elseif k == "E" then
      END = tonumber(rest:match("^(%d+)"))
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
    if REQ[f] then sp:write_u16(REQ_NEXT_PART, REQ[f]); stats.reqs = stats.reqs + 1; REQ[f] = nil end
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
local varf = os.getenv("AWCK_VARS") and os.getenv("AWCK_VARS") ~= "" and io.open(os.getenv("AWCK_VARS"), "wb")
local captured, capturing, chi, clast = 0, true, 0, 0
AWIL_FRAME = sp:install_write_tap(FRAME_NO, FRAME_NO + 3, "awil_frame", function(offset, data, mask)
  if not capturing or offset ~= FRAME_NO then return end
  local v = data & 0xffff
  if v == 0 then return end
  if v < clast then chi = chi + 0x10000 end
  clast = v
  local tick = chi + v - 1                                   -- the frame just ended (awcnv_cksum.lua's tick)
  local front = sp:read_u32(CUR_PAGE_2)
  binf:write(sp:read_range(front, front + 63999, 8))
  if varf then varf:write(sp:read_range(INTERP, INTERP + 511, 8)) end
  idxf:write(string.format("%d %08X\n", tick, front))
  captured = captured + 1
end)
local function stop_capture()
  if capturing then capturing = false; binf:close(); idxf:close(); if varf then varf:close() end; log(string.format("captured %d frames", captured)) end
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

local co = coroutine.create(session)
AWIL_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then log("ERROR " .. tostring(err)); stop_capture(); M:exit() end
  else
    stop_capture(); M:exit()
  end
end)
