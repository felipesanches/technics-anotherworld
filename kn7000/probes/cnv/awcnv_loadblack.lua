-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_loadblack.lua -- is the screen black while a part loads, and does the firmware draw nothing while the game
-- runs? (src/fwdraw.s; README-CNV.md, "The firmware's screen"). Felipe saw the firmware's screen during part loads
-- on the instrument (2026-11-02).
--
-- Starts the game as a player does (DISK MENU, STYLE CONVERT, OK on KN7LOAD.CNV), the intro at tick 0 (NO_SPLASH),
-- and lets the intro run into the lake (its load at tick 2612), then holds EXIT. At every MAME frame while a part
-- loads (LD_REQ != LD_CUR, the game task running) it counts the LCD frame's pixels that are not black; all along it
-- counts the stores into the LCD frame from outside KN7APP.BIN's code (the firmware's), during loads and during play
-- apart. At the end: fwdraw.s's variables, and after the quit the firmware's class table entry and DrawEnable as they
-- must be again (0x48724914, 1, 1). Snapshots: the middle of each load, 3 s into the lake, the "Continue Next?" box.
-- Lines "awlb: ..." and AWLB_OUT/loadblack.txt.
--   probes/cnv/run_perf.sh OUT probes/cnv/awcnv_loadblack.lua      (AWLB_OUT=OUT)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local OUT = os.getenv("AWLB_OUT") or "."
local CV = 0x502DF000
local CV_STATE, CV_CALLS, CV_ENDED, LD_REQ, LD_CUR = CV, CV + 0x10, CV + 0x30, CV + 0x40, CV + 0x44
local FRAME_NO, NO_SPLASH = 0x502E3000 + 0x7C, 0x502E3000 + 0x58
local FD = 0x502E0400                 -- fwdraw.s FWDRAW_AT: hooked, quiet, skipped, reasserts, lastcalls, lastms, watched
local GROUP4_RECS, DRAW_ENABLE, DRAW_KEEP = 0x5011FAD4, 0x5002A018, 0x5002A01C
local CODE_LO, CODE_HI = 0x502BA000, 0x502C8000
local FB, FB_LEN = 0x9CE00000, 0x140000          -- all of display memory (the firmware's frame, the game's FB8)
local LCDC, LCD_SAVE, LCD_OWNED = 0x9CC00000, 0x502DAA00 + 0x28C, 0x502DAA00 + 0x288   -- vm.inc LCD8_VARS
local screen = M.screens[":screen"]
local function now() return M.time:as_double() end
local outf = io.open(OUT .. "/loadblack.txt", "w")
local function log(s) print("awlb: " .. s); outf:write(s .. "\n"); outf:flush() end
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end

local loading, load = false, nil
local fw = { load = 0, play = 0, pcs = {}, phase = {} }
local phase = "start"            -- start (to the first VM frame), play, quit (from EXIT held)
local running = false
AWLB_TAP = sp:install_write_tap(FB, FB + FB_LEN - 1, "awlb_lcd", function(offset, data, mask)
  if not running then return end
  local p = cpu.state["PC"].value
  if p >= CODE_LO and p < CODE_HI then return end
  if loading then fw.load = fw.load + 1 else fw.play = fw.play + 1 end
  local k = loading and "load" or phase
  fw.phase[k] = (fw.phase[k] or 0) + 1
  fw.pcs[p] = (fw.pcs[p] or 0) + 1
end)

-- the pixels MAME's screen shows that are not black (since 2026-11-02 the game's frame is 8 bits a pixel through the
-- look-up table, src/lcd8.s: the screen, not display memory, says what is seen)
local function nonblack()
  local px = screen:pixels()
  local n = 0
  for i = 1, #px - 3, 4 do
    if (string.unpack("<I4", px, i) & 0xFFFFFF) ~= 0 then n = n + 1 end
  end
  return n
end
local function fdvars()
  return string.format("fwdraw: hooked %d quiet %d skipped %d reasserts %d watched %d; class table 0x%08X, DrawEnable %d, keep %d",
    sp:read_u32(FD), sp:read_u32(FD + 4), sp:read_u32(FD + 8), sp:read_u32(FD + 12), sp:read_u32(FD + 0x18),
    sp:read_u32(GROUP4_RECS), sp:read_u32(DRAW_ENABLE), sp:read_u32(DRAW_KEEP))
end

local loads = {}
local function watch_load()
  local now_loading = running and sp:read_u32(LD_REQ) ~= sp:read_u32(LD_CUR)
  if now_loading and not loading then
    load = { part = sp:read_u32(LD_REQ), frames = 0, maxnb = 0, sum = 0, fw0 = fw.load, t0 = now(), shot = false }
  end
  loading = now_loading
  if loading then
    local nb = nonblack()
    load.frames = load.frames + 1
    if nb > 0 then load.lit = (load.lit or "") .. string.format(" %d:%d", load.frames, nb) end
    load.sum = load.sum + nb
    if nb > load.maxnb then load.maxnb = nb end
    if not load.shot and now() - load.t0 > 0.3 then M.video:snapshot(); load.shot = true end
  elseif load then
    loads[#loads + 1] = load
    log(string.format("load of part 0x%04X: %.2f s, %d frames; pixels not black: max %d, mean %.0f (of 153600); firmware stores %d",
      load.part, now() - load.t0, load.frames, load.maxnb, load.sum / math.max(1, load.frames), fw.load - load.fw0))
    log("  frames not black (n:pixels; MAME's screen is drawn once a frame, so the first can still be the picture before): " .. (load.lit or "none"))
    load = nil
  end
end

local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(c, s) local t = now() + s; while now() < t do if c() then return true end; coroutine.yield() end; return c() end
local function press(tag, mask, hold) local f = field(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end

local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  for i = 1, 8 do                     -- OK (KN7LOAD.CNV), until the game runs
    press("CPR_SEG6", 0x01)
    if wait_until(function() return sp:read_u32(CV_STATE) >= 2 end, 12) then break end
  end
  wait_until(function() return sp:read_u32(CV_STATE) >= 2 end, 60)
  sp:write_u32(NO_SPLASH, 0x5EED0FF0)
  wait_until(function() return sp:read_u32(CV_STATE) == 3 end, 120)
  running = true
  log(string.format("game task running at t=%.1f s", now()))
  wait_until(function() return (sp:read_u32(FRAME_NO) & 0xffff) > 0 end, 300)
  phase = "play"
  wait_until(function() return (sp:read_u32(FRAME_NO) & 0xffff) > 100 end, 300)
  log("tick 100: " .. fdvars())
  local c0, t0 = sp:read_u32(CV_CALLS), now()
  wait_until(function() return (sp:read_u32(FRAME_NO) & 0xffff) > 2650 end, 900)
  log(string.format("converter calls in the intro: %.1f a second", (sp:read_u32(CV_CALLS) - c0) / (now() - t0)))
  wait(3); M.video:snapshot()
  log("the lake: " .. fdvars())
  phase = "quit"
  press("CPC_SEG11", 0x80, 2.0)       -- EXIT held: quit
  wait_until(function() return sp:read_u32(CV_ENDED) == 1 end, 30)
  running = false
  wait(3); M.video:snapshot()
  log("after the quit: " .. fdvars())
  log(string.format("the LCD after the quit: REG[040h] %02X, REG[042h]-[044h] %02X %02X %02X, REG[046h]-[047h] %02X %02X; the firmware's: %02X, %02X %02X %02X, %02X %02X; the game's owned %d",
    sp:read_u8(LCDC + 0x40), sp:read_u8(LCDC + 0x42), sp:read_u8(LCDC + 0x43), sp:read_u8(LCDC + 0x44), sp:read_u8(LCDC + 0x46),
    sp:read_u8(LCDC + 0x47), sp:read_u8(LCD_SAVE), sp:read_u8(LCD_SAVE + 1), sp:read_u8(LCD_SAVE + 2), sp:read_u8(LCD_SAVE + 3),
    sp:read_u8(LCD_SAVE + 4), sp:read_u8(LCD_SAVE + 5), sp:read_u32(LCD_OWNED)))
  local pcs = {}
  for p, c in pairs(fw.pcs) do pcs[#pcs + 1] = string.format("%08X:%d", p, c) end
  table.sort(pcs)
  log(string.format("firmware stores into the LCD while the game ran: %d during loads, %d outside them; pcs %s",
    fw.load, fw.play, table.concat(pcs, " ")))
  log(string.format("  by phase: start (to the first VM frame, loads apart) %d, play %d, quit (from EXIT held to the end) %d, loads %d",
    fw.phase.start or 0, fw.phase.play or 0, fw.phase.quit or 0, fw.phase.load or 0))
  outf:close()
  M:exit()
  while true do coroutine.yield() end
end)
AWLB_FRAME = emu.add_machine_frame_notifier(function()
  watch_load()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awlb: ERROR " .. tostring(err)); M:exit() end
  end
end)
