-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_nmitest.lua -- the code wheel page's NMI screen (src/wheel.s WheelNmi), with a KN7APP.BIN built with
-- -D WHEEL_NMI_SELFTEST (a load the unit faults on, Pinball's PFT7 kind, right after the stub is armed): does the
-- system-error NMI (modelled since kn7000_mame a582ec5) reach WheelNmi, which shows "NMI PC ..." and "PSW ..." on the
-- frame the LCD shows and puts EE / EF into the trail, and does the instrument stay there instead of restarting?
-- Run through run_perf.sh with that card (run_nmitest.sh). Prints "awnm: ..." lines; snap/codewheel_nmi.png.
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local CV, VI = 0x502DF000, 0x502E1000
local PART = VI + 0x102A
local WV = 0x502DFA00
local CRUMB = 0x5031C000 + 0xC0
local function log(s) print("awnm: " .. s) end
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
local resets = 0
local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)
  press("CPL_SEG0", 0x20); wait(8)
  press("CPR_SEG6", 0x01)
  log("the question " .. tostring(wait_until(asking, 240)))
  wait(3)
  local c0 = sp:read_u32(CV + 0x10)
  press("CPC_SEG5", 0x02)             -- HELP
  wait(8)
  local c1 = sp:read_u32(CV + 0x10)
  local t = {}
  for i = 0, 12 do t[#t + 1] = string.format("%08X", sp:read_u32(CRUMB + 12 + 4 * i)) end
  log(string.format("8 s after HELP: stub armed %d, the PC caught %08X, PSW %08X; converter calls %d -> %d; the trail: count %d %s",
    sp:read_u32(WV + 0x3D4), sp:read_u32(WV + 0x3E4 + 16), sp:read_u32(WV + 0x3E4 + 20), c0, c1,
    sp:read_u32(CRUMB + 4), table.concat(t, " ")))
  M.screens[":screen"]:snapshot("codewheel_nmi.png")
  wait(1)
  M:exit()
  while true do coroutine.yield() end
end)
AWNM_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awnm: ERROR " .. tostring(err)); M:exit() end
  end
end)
