-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_crumb.lua -- does the code wheel page's trail of steps (src/wheel.s WheelMark, WH_CRUMB in the input log's
-- room) survive a restart of the instrument in the middle of the page's load, and does the next start write it to the
-- card as AWWHLOG.TXT (WheelCrumbLog)? HELP at the code wheel's question, then, once the main task has been asked for
-- piece AWTC_PIECE (default 6), MAME's soft reset (the firmware boots again; the DRAM is not cleared by MAME); then
-- DISK MENU, STYLE CONVERT, OK again, the game's start, EXIT held. run_crumb.sh reads AWWHLOG.TXT off the card.
-- Prints "awtc: ..." lines: the trail before the reset and as found after it.
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local CV, VI = 0x502DF000, 0x502E1000
local CV_ENDED = CV + 0x30
local PART = VI + 0x102A
local WV = 0x502DFA00
local CRUMB = 0x5031C000 + 0xC0
local PIECE = tonumber(os.getenv("AWTC_PIECE") or "6")
local function wv(o) return sp:read_u32(WV + o) end
local function log(s) print("awtc: " .. s) end
local function now() return M.time:as_double() end
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(c, s) local t = now() + s; while now() < t do if c() then return true end; coroutine.yield() end; return c() end
local function press(tag, mask, hold) local f = field(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end
local function var(i) return sp:read_u16(VI + 2 * i) end
local function asking() local t = sp:read_u16(VI + 0x400 + 80); return sp:read_u16(PART) == 0x3E80 and t >= 0x02CE and t <= 0x0D7F and (var(0xBC) & 0x10) == 0 end
local function trail()
  local t = { string.format("magic %08X count %d ms %d:", sp:read_u32(CRUMB), sp:read_u32(CRUMB + 4), sp:read_u32(CRUMB + 8)) }
  for i = 0, 12 do t[#t + 1] = string.format("%08X", sp:read_u32(CRUMB + 12 + 4 * i)) end
  return table.concat(t, " ")
end
local function start()
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  press("CPR_SEG6", 0x01)             -- OK (KN7LOAD.CNV)
end
local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  start()
  log("the question " .. tostring(wait_until(asking, 240)))
  wait(3)
  press("CPC_SEG5", 0x02)             -- HELP
  local at = wait_until(function() return wv(0x54) == PIECE + 1 end, 60)
  log(string.format("piece %d asked for: %s; the trail: %s", PIECE, tostring(at), trail()))
  local before = trail()
  M:soft_reset()
  wait(1)
  log("after the reset: " .. trail())
  wait_until(function() return now() > 30 end, 60)
  wait(25)
  start()
  local run = wait_until(function() return sp:read_u32(CV) == 3 end, 120)
  log(string.format("the game started again %s; the trail now (InpLogInit zeroed it after writing it): %s", tostring(run), trail()))
  wait(5)
  press("CPC_SEG11", 0x80, 2.0)       -- EXIT held: quit
  wait_until(function() return sp:read_u32(CV_ENDED) == 1 end, 30)
  wait(2)
  M:exit()
  while true do coroutine.yield() end
end)
AWTC_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awtc: ERROR " .. tostring(err)); M:exit() end
  end
end)
