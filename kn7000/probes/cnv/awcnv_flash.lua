-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_flash.lua -- what does the LCD show between two of the game's pictures? Felipe saw "a brief flash of a
-- previous bitmap" at the splash's transitions on the instrument (2026-11-02). Starts the game as a player does (DISK
-- MENU, STYLE CONVERT, OK on KN7LOAD.CNV) and, from the game's first picture for AWF_SECS emulated seconds (default
-- 40: the splash and the intro's start), saves every MAME frame that differs from the one before as a PNG
-- (AWF_OUT/snap/..., screen:snapshot) and logs, per saved frame: the MAME frame number, the VM's frame (FRAME_NO) and
-- the palette the LCD has (PF_PAL, its first 4 entries). probes/flashfind.py then finds the frames that are neither
-- the picture before nor the one after.
-- Lines "awfl: ..." and AWF_OUT/flash.txt.
--   probes/cnv/run_perf.sh OUT probes/cnv/awcnv_flash.lua      (AWF_OUT=OUT)
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local OUT = os.getenv("AWF_OUT") or "."
local SECS = tonumber(os.getenv("AWF_SECS") or "40")
local MAXN = tonumber(os.getenv("AWF_MAX") or "1500")
local CV = 0x502DF000
local CV_ENDED = CV + 0x30
local FRAME_NO = 0x502E3000 + 0x7C
local PERF = 0x502E6000
local PF_PAL = PERF + 0x520                  -- vm.inc: the palette the LCD shows
local LOAD_ON = 0x502DAA00 + 0x2C0
local screen = M.screens[":screen"]
local function now() return M.time:as_double() end
local outf = io.open(OUT .. "/flash.txt", "w")
local function log(s) print("awfl: " .. s); outf:write(s .. "\n"); outf:flush() end
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(c, s) local t = now() + s; while now() < t do if c() then return true end; coroutine.yield() end; return c() end
local function press(tag, mask, hold) local f = field(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end

local watching, t0, mframe, prev, saved = false, 0, 0, nil, 0
AWF_FRAME = emu.add_machine_frame_notifier(function()
  if not watching then return end
  mframe = mframe + 1
  local px = screen:pixels()
  if px ~= prev and saved < MAXN then
    saved = saved + 1
    local name = string.format("f%05d.png", mframe)
    screen:snapshot(name)
    local pal = {}
    for i = 0, 3 do pal[#pal + 1] = string.format("%04X", sp:read_u16(PF_PAL + 2 * i)) end
    log(string.format("%s vmframe %d t %.3f pal %s", name, sp:read_u32(FRAME_NO) & 0xffff, now() - t0, table.concat(pal, " ")))
  end
  prev = px
end)

local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  press("CPR_SEG6", 0x01)             -- OK (KN7LOAD.CNV)
  wait_until(function() return (sp:read_u32(FRAME_NO) & 0xffff) > 0 and sp:read_u32(LOAD_ON) == 0 end, 240)
  t0 = now(); watching = true
  wait(SECS)
  watching = false
  log(string.format("%d frames saved", saved))
  press("CPC_SEG11", 0x80, 2.0)       -- EXIT held: quit
  wait_until(function() return sp:read_u32(CV_ENDED) == 1 end, 30)
  M:exit()
  while true do coroutine.yield() end
end)
AWF_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awfl: ERROR " .. tostring(err)); M:exit() end
  end
end)
