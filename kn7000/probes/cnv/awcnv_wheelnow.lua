-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_wheelnow.lua -- the code wheel setting applied at once (README-CNV.md, "Settings"; src/prefs.s PrefsWheelNow,
-- src/interp.s GameStart): does a change on the help screen's settings page take effect when the help screen closes
-- while the game has not gone past its intro, and wait for the next start once play has begun?
-- From a card without AWPREFS.CFG (the code wheel off), the splash running:
--   1 "on at splash":   settings, CODE WHEEL on, EXIT: part 0x3E80 again from its start, thread 20 asking for the
--                       symbols (pc 0x02CE-0x0D7F), var 0xBC without the bypass's 0x10, var 0x3C = the seed (START_SEED)
--   2 "off at question": CODE WHEEL off, EXIT: the splash (thread 0 in the logo sequence, thread 20 inactive, var 0xBC
--                       0x10), still part 0x3E80
--   3 "on in intro":    the splash left to its end (part 0x3E81), CODE WHEEL on, EXIT: the question again (part 0x3E80)
--   4 "off again":      CODE WHEEL off at the question: the splash; then the intro skipped with C4 (part 0x3E82, play)
--   5 "in play":        CODE WHEEL on: the row reads "ON, next start" (its item points at prv_on_next, AW_MAP), EXIT:
--                       no restart (the part, GAME_WHEEL 0, RESTART_REQ 0), the VM's frames going on
-- Then EXIT held: the game writes its input log (run_wheelnow.sh replays it: the G records reproduce each restart).
-- Screens (MAME's own PNG snapshots, AWWN_OUT/snap): the question after 1 and 3, the splash after 2, the settings
-- page in play. Prints "awwn: ..." lines.
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local CV, VI, MISC, PREFS = 0x502DF000, 0x502E1000, 0x502E3000, 0x502DF900
local CV_ENDED = CV + 0x30
local FRAME_NO, HELP_PAGE = MISC + 0x7C, MISC + 0x5C
local START_SEED, RESTART_REQ, GAME_WHEEL = MISC + 0x254, MISC + 0x258, MISC + 0x25C
local PR_WHEEL, PR_SEL = PREFS + 10, PREFS + 0x14
local PART = VI + 0x102A
local PF_ITEMS = 0x502E6000 + 0xA40
local screen = M.screens[":screen"]
local function log(s) print("awwn: " .. s) end
local function now() return M.time:as_double() end
local SYM = {}
for line in io.lines(os.getenv("AW_MAP") or "build/kn7app.map") do
  local a, n = line:match("^0x(%x+)%s+(%S+)")
  if n then SYM[n] = tonumber(a, 16) end
end
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local KEY = {}
for _, tag in ipairs({ ":KEYS0", ":KEYS1", ":KEYS2", ":KEYS3" }) do
  local p = M.ioport.ports[tag]
  if p then for _, f in pairs(p.fields) do KEY[f.name] = f end end
end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(c, s) local t = now() + s; while now() < t do if c() then return true end; coroutine.yield() end; return c() end
local function press(tag, mask, hold) local f = field(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end
local function key(name, hold) local f = KEY[name]; f:set_value(1); wait(hold or 0.3); f:set_value(0); wait(0.8) end
local function var(i) return sp:read_u16(VI + 2 * i) end
local function thr(t) return sp:read_u16(VI + 0x400 + 4 * t) end
local function asking() local t = thr(20); return sp:read_u16(PART) == 0x3E80 and t >= 0x02CE and t <= 0x0D7F and (var(0xBC) & 0x10) == 0 end
local function splash() return sp:read_u16(PART) == 0x3E80 and thr(20) == 0xFFFF and (var(0xBC) & 0x10) ~= 0 end
local function state()
  return string.format("part %04X, thread 0 at %04X, thread 20 at %04X, var 0xBC %04X, var 0x3C %04X, seed %04X, setting %d, game %d, request %d",
    sp:read_u16(PART), thr(0), thr(20), var(0xBC), var(0x3C), sp:read_u32(START_SEED) & 0xFFFF, sp:read_u8(PR_WHEEL),
    sp:read_u32(GAME_WHEEL), sp:read_u32(RESTART_REQ))
end
local results = {}
local function result(name, ok, detail) results[#results + 1] = ok; log(string.format("%-16s %s  %s", name, ok and "PASS" or "FAIL", detail)) end

-- HELP, PAGE DOWN three times (the settings page), the code wheel's row, then LEFT or RIGHT; returns with the page up
local function settings_toggle(right)
  press("CPC_SEG5", 0x02); wait(1.5)                     -- HELP
  for _ = 1, 6 do                                         -- PAGE DOWN / UP to page 4 (index 3)
    local pg = sp:read_u32(HELP_PAGE)
    if pg == 3 then break end
    press("CPC_SEG11", pg < 3 and 0x20 or 0x10); wait(1.0)
  end
  local guard = 0
  while sp:read_u32(PR_SEL) ~= 5 and guard < 8 do key("A5"); guard = guard + 1 end
  key(right and "C6" or "F5")
end
local function close() press("CPC_SEG11", 0x80); wait(0.3) end   -- EXIT: back to the game

local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  press("CPR_SEG6", 0x01)             -- OK (KN7LOAD.CNV)
  wait_until(function() return (sp:read_u32(FRAME_NO) & 0xffff) > 60 end, 240)
  wait(1)
  log("at the start: " .. state())
  -- 1: on at the splash
  local was = splash()
  settings_toggle(true)
  close()
  local ok = wait_until(asking, 5)
  wait(1.5)
  result("on at splash", was and ok and sp:read_u32(GAME_WHEEL) == 1 and var(0x3C) == (sp:read_u32(START_SEED) & 0xFFFF),
    string.format("splash before %s; then %s", tostring(was), state()))
  screen:snapshot("wheelnow_1_question.png")
  -- 2: off at the question
  settings_toggle(false)
  close()
  ok = wait_until(splash, 5)
  wait(1.5)
  result("off at question", ok and sp:read_u32(GAME_WHEEL) == 0, state())
  screen:snapshot("wheelnow_2_splash.png")
  -- 3: on in the intro
  local intro = wait_until(function() return sp:read_u16(PART) == 0x3E81 end, 90)
  wait(2)
  settings_toggle(true)
  close()
  ok = wait_until(asking, 8)
  wait(1.5)
  result("on in intro", intro and ok and sp:read_u32(GAME_WHEEL) == 1, string.format("intro reached %s; then %s", tostring(intro), state()))
  screen:snapshot("wheelnow_3_question.png")
  -- 4: off again, then into play
  settings_toggle(false)
  close()
  ok = wait_until(splash, 5)
  local intro2 = wait_until(function() return sp:read_u16(PART) == 0x3E81 end, 90)
  wait(3)
  key("C4", 0.5)                      -- skip the intro: the lake
  local play = wait_until(function() return sp:read_u16(PART) == 0x3E82 end, 20)
  wait(3)
  result("off again", ok and intro2 and play, state())
  -- 5: in play: waits for the next start
  local part0 = sp:read_u16(PART)
  settings_toggle(true)
  wait(0.5)
  local item = 0                      -- the row's value item: the 6th row's value text pointer, among PF_ITEMS
  for i = 0, 30 do
    local p = PF_ITEMS + 12 * i
    if sp:read_u16(p) == 0xFFFF then break end
    local t = sp:read_u32(p + 8)
    if t == SYM["prv_on_next"] then item = t end
  end
  screen:snapshot("wheelnow_5_settings.png")
  close()
  local f0 = sp:read_u32(FRAME_NO) & 0xffff
  wait(3)
  result("in play", item ~= 0 and sp:read_u16(PART) == part0 and sp:read_u32(GAME_WHEEL) == 0 and sp:read_u32(RESTART_REQ) == 0
    and (sp:read_u32(FRAME_NO) & 0xffff) ~= f0, string.format("the row reads \"ON, next start\" %s; %s; frames %d -> %d",
      tostring(item ~= 0), state(), f0, sp:read_u32(FRAME_NO) & 0xffff))
  press("CPC_SEG11", 0x80, 2.0)       -- EXIT held: quit (the input log onto the card)
  wait_until(function() return sp:read_u32(CV_ENDED) == 1 end, 30)
  local all = true
  for _, r in ipairs(results) do all = all and r end
  log(string.format("%d checks, %s", #results, all and "all pass" or "SOME FAIL"))
  M:exit()
  while true do coroutine.yield() end
end)
AWWN_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awwn: ERROR " .. tostring(err)); M:exit() end
  end
end)
