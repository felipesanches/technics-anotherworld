-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_crumb.lua -- does the code wheel page's trail of steps (src/wheel.s WheelMark, WH_CRUMB in the input log's
-- room) stay through a quit and a new start of the game, and does that start write it to the card as AWWHLOG.TXT
-- (WheelCrumbLog)? HELP at the code wheel's question (the page's first load), EXIT, EXIT held (quit), "Continue Next?"
-- YES (the loader reads KN7APP.BIN again, the game starts), then EXIT held. run_crumb.sh reads AWWHLOG.TXT off the card.
-- (Whether the owner's DRAM keeps the trail through the instrument's restart is the unit's to tell: MAME's soft reset
-- runs this script again from its start and its driver clears the RAM, so it cannot.)
-- Prints "awtc: ..." lines: the trail before the reset and as found after it.
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local CV, VI = 0x502DF000, 0x502E1000
local CV_ENDED = CV + 0x30
local PART = VI + 0x102A
local WV = 0x502DFA00
local CRUMB = 0x5031C000 + 0xC0
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
  press("CPC_SEG5", 0x02)             -- HELP: the page loads (its steps into the trail)
  wait_until(function() return wv(0x04) == 1 and wv(0x8C) >= 1 and wv(0xB4) >= 240 and wv(0xB0) == 0 end, 60)
  log("the page shown; the trail: " .. trail())
  press("CPC_SEG11", 0x80); wait(2)   -- EXIT: the help screen closes (steps 30, 3F)
  log("the help screen closed; the trail: " .. trail())
  local kept = trail()
  press("CPC_SEG11", 0x80, 2.0)       -- EXIT held: quit
  wait_until(function() return sp:read_u32(CV_ENDED) == 1 end, 30)
  wait(2)
  log("quit; the trail: " .. trail() .. " (" .. (trail() == kept and "kept" or "CHANGED") .. ")")
  press("CPC_SEG11", 0x80); wait(4)   -- EXIT: the message, then "Continue Next?"
  press("CPR_SEG7", 0x01)             -- YES: KN7APP.BIN read again, the game starts: WheelCrumbLog, InpLogInit
  local run = wait_until(function() return sp:read_u32(CV) == 3 end, 120)
  wait(3)
  log(string.format("the game started again %s; the trail now (InpLogInit zeroed it after writing it): %s", tostring(run), trail()))
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
