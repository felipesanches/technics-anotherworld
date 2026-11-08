-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_tickgap.lua -- does the code wheel page keep the firmware's tasks from running for long? (the zoomed page,
-- KN7APP c707af6e, restarted the owner's KN7000 while "Loading the wheel" showed, 2026-11-08; the first page,
-- aafd752e, ran there on 2026-11-06.) Two signals, both measured from the converter's first call to the quit:
--   * the firmware's TickJobsTask inverts GPIO 0x36008004 (P04) bit 5 every 96 ms (the panel's pump and service run
--     in the same loop): every change of that bit is timed, and the longest gaps listed, with what the page was doing
--     (WH_LOADREQ, WH_ON, WH_INRAM, the help page);
--   * the converter's calls: the time between two of them (CV_CALLS changing), the firmware's main task's turn.
-- Steps: the code wheel's question, HELP (the page: its first load from the card), a detent, EXIT, HELP (again: from
-- display memory), soft button 3 (the zoomed page's MIDDLE; nothing on the first page), EXIT, then 10 s of play.
-- Run through run_perf.sh with a card with the code wheel on (as run_wheel.sh makes it):
--   AWTG_CARD=1 probes/cnv/run_tickgap.sh OUT
-- Also: the LCD's ink layer registers at the question, and the highest write near the user pools while the page
-- loads. Prints "awtg: ..." lines.
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local CV, VI, MISC = 0x502DF000, 0x502E1000, 0x502E3000
local CV_CALLS, CV_ENDED = CV + 0x10, CV + 0x30
local HELP_PAGE = MISC + 0x5C
local PART = VI + 0x102A
local WV = 0x502DFA00
local function wv(o) return sp:read_u32(WV + o) end
local function log(s) print("awtg: " .. s) end
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
local phase = "boot"
local on = false
local function state()
  return string.format("%s page %d loadreq %d on %d inram %d", phase, sp:read_u32(HELP_PAGE) + 1, wv(0x54), wv(0x04), wv(0x4C))
end
-- P04 bit 5
local last5, t5, gaps = nil, nil, {}
AWTG_P04 = sp:install_write_tap(0x36008004, 0x36008007, "awtg_p04", function(offset, data, mask)
  if (mask & 0xFF) == 0 then return end
  local b = (data >> 5) & 1
  if b ~= last5 then
    local t = now()
    if on and t5 then gaps[#gaps + 1] = { t - t5, t5, state() } end
    last5, t5 = b, t
  end
end)
-- writes near the user pools' start (0x50180000) while the page loads: the end of the read scratch in ARENA6
-- (0x50177000-0x5017FFFF in c707af6e) and the pools' first 4 KB, the highest address written there by any PC
local hi_near, near_pc = 0, 0
AWTG_NEAR = sp:install_write_tap(0x5017F000, 0x50180FFF, "awtg_near", function(offset, data, mask)
  if phase ~= "load" and phase ~= "again" then return end
  if offset > hi_near then hi_near = offset; near_pc = M.devices[":maincpu"].state["PC"].value end
end)
-- the converter's calls
local lastc, tc, cgaps = nil, nil, {}
local function poll_calls()
  local c = sp:read_u32(CV_CALLS)
  if c ~= lastc then
    local t = now()
    if on and tc then cgaps[#cgaps + 1] = { t - tc, tc, state() } end
    lastc, tc = c, t
  end
end
local function report(name, list, n)
  table.sort(list, function(a, b) return a[1] > b[1] end)
  local per = {}
  for _, g in ipairs(list) do
    local k = g[3]:match("^(%S+)")
    per[k] = math.max(per[k] or 0, g[1])
  end
  local ks = {}
  for k, v in pairs(per) do ks[#ks + 1] = string.format("%s %.0f ms", k, v * 1000) end
  table.sort(ks)
  log(string.format("%s: %d gaps; the longest per phase: %s", name, #list, table.concat(ks, ", ")))
  for i = 1, math.min(n, #list) do
    log(string.format("  %s %2d: %.1f ms from %.3f s (%s)", name, i, list[i][1] * 1000, list[i][2], list[i][3]))
  end
end
local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  press("CPR_SEG6", 0x01)             -- OK (KN7LOAD.CNV)
  on = true; phase = "start"
  local q = wait_until(asking, 240)
  wait(3)
  log(string.format("KN7APP: the question %s; LCD REG[070h] %02X REG[071h] %02X (the ink layer)", tostring(q),
    sp:read_u8(0x9CC00070), sp:read_u8(0x9CC00071)))
  phase = "load"
  press("CPC_SEG5", 0x02)             -- HELP: the page, its first load
  wait_until(function() return wv(0x04) == 1 and wv(0x8C) >= 1 and wv(0xB4) >= 240 and wv(0xB0) == 0 end, 40)
  wait(1)
  phase = "turn"
  local knob
  for _, f in pairs(M.ioport.ports[":TEMPO_KNOB"].fields) do knob = f end
  knob.user_value = 51
  wait(3)
  phase = "exit"
  press("CPC_SEG11", 0x80); wait(3)   -- EXIT
  phase = "again"
  local nr = wv(0x8C)
  press("CPC_SEG5", 0x02)             -- HELP: the page from display memory
  wait_until(function() return wv(0x04) == 1 and wv(0x8C) > nr and wv(0xB4) >= 240 and wv(0xB0) == 0 end, 40)
  wait(1)
  phase = "region"
  press("CPR_SEG7", 0x01, 0.3)        -- LCDR 3
  wait(4)
  phase = "exit2"
  press("CPC_SEG11", 0x80); wait(3)
  phase = "play"
  wait(10)
  on = false
  log(string.format("near the pools while the page loaded: the highest write 0x%08X (pc %08X)", hi_near, near_pc))
  report("tick", gaps, 12)
  report("calls", cgaps, 12)
  M:exit()
  while true do coroutine.yield() end
end)
AWTG_TICK = emu.add_machine_frame_notifier(function()
  poll_calls()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awtg: ERROR " .. tostring(err)); M:exit() end
  end
end)
