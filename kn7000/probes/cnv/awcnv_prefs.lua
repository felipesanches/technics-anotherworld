-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_prefs.lua -- the loading screen and the settings (README-CNV.md, "Settings"; src/prefs.s, src/lcd8.s):
-- does the game take the LCD at once and count its loading up to 100 %, and do the settings change with the keybed
-- on the help screen's fourth page, apply at once, go to the card and come back on the next run?
--
-- AWPR_PHASE=1 (the card without AWPREFS.CFG): from STYLE CONVERT's OK, every MAME frame until the game's first
-- picture: the percentage the loading screen shows (vm.inc LOAD_PCT), whether the game owns the LCD (LCD_OWNED) and
-- the controller is at 8 bits a pixel; the screen MAME draws at about 0, 30, 60, 85 and 95 % to AWPR_OUT/load_PP.bin.
-- Then, the game running: HELP, PAGE DOWN three times (page 4, the settings); A5 (down), C6 (right): the ambilight
-- off; Ab5 (up), C6: the resolution 320x200; A5 twice, C6: the light scatter one more (long to very long); A5, C6: the keybed sound off;
-- A5, C6: the LED effects off; each checked in RAM (PREFS_AT) and in effect (PG_W, AMB_LUT all black, AU_KEYWANT);
-- the page dumped (settings.bin). EXIT: back to the game; 3 s; AWPREFS.CFG written (PR_WROTE, PR_DIRTY); then EXIT
-- held: the quit. run_perf.sh brings AWPREFS.CFG back.
-- AWPR_PHASE=2 (the card with that AWPREFS.CFG): the settings read (PR_STATUS 1) and in effect from the start.
-- Prints "awpr: ..." lines.
--   probes/cnv/run_prefs.sh OUT
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local OUT = os.getenv("AWPR_OUT") or "."
local PHASE = tonumber(os.getenv("AWPR_PHASE") or "1")
local CV, MISC, PERF = 0x502DF000, 0x502E3000, 0x502E6000
local CV_STATE, CV_ENDED = CV, CV + 0x30
local FRAME_NO, PG_W, HELP_PAGE = MISC + 0x7C, MISC + 0x64, MISC + 0x5C
local LCD8 = 0x502DAA00
local AMB_LUT, LCD_OWNED, LOAD_ON, LOAD_PCT = LCD8 + 0x60, LCD8 + 0x288, LCD8 + 0x2C0, LCD8 + 0x2C4
local PREFS = 0x502DF900
local PR_DIRTY, PR_SEL, PR_STATUS, PR_WROTE, PR_FAILS = PREFS + 0x10, PREFS + 0x14, PREFS + 0x18, PREFS + 0x1C, PREFS + 0x20
local AU_KEYWANT = 0x502DA000 + 0x50
local LCDC = 0x9CC00000
local screen = M.screens[":screen"]
local function log(s) print("awpr: " .. s) end
local function now() return M.time:as_double() end
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
local function key(name) local f = KEY[name]; f:set_value(1); wait(0.3); f:set_value(0); wait(0.8) end
local function prefs()
  return string.format("res %d ambi %d scatter %d keys %d leds %d", sp:read_u8(PREFS + 4), sp:read_u8(PREFS + 5),
    sp:read_u8(PREFS + 6), sp:read_u8(PREFS + 7), sp:read_u8(PREFS + 8))
end
local function amb_black()
  for i = 0, 239 do if sp:read_u16(AMB_LUT + 2 * i) ~= 0 then return false end end
  return true
end
local function dump(name) local f = io.open(OUT .. "/" .. name, "wb"); f:write((screen:pixels())); f:close() end
local results = {}
local function result(name, ok, detail) results[#results + 1] = ok; log(string.format("%-10s %s  %s", name, ok and "PASS" or "FAIL", detail)) end

-- the loading screen, sampled every frame (phase 1)
local L = { samples = 0, owned_at = nil, pcts = {}, back = 0, last = -1, dumped = {}, lcd8 = true }
local watching = false
AWPR_FRAME = emu.add_machine_frame_notifier(function()
  if not watching then return end
  local st = sp:read_u32(CV_STATE)
  if st < 1 or (sp:read_u32(FRAME_NO) & 0xffff) > 0 then return end
  L.samples = L.samples + 1
  if sp:read_u32(LCD_OWNED) == 1 then
    L.owned_at = L.owned_at or now()
    if (sp:read_u8(LCDC + 0x40) & 7) ~= 3 then L.lcd8 = false end
    local p = sp:read_u32(LOAD_PCT)
    if p ~= 0xFFFFFFFF and p ~= L.last then
      if p < L.last then L.back = L.back + 1 end
      L.pcts[#L.pcts + 1] = p
      L.last = p
      for _, at in ipairs({ 0, 30, 60, 85, 95 }) do
        if p >= at and not L.dumped[at] then L.dumped[at] = true; dump(string.format("load_%02d.bin", at)) end
      end
    end
  end
end)

local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  local t_ok = now()
  watching = true
  press("CPR_SEG6", 0x01)             -- OK (KN7LOAD.CNV)
  wait_until(function() return (sp:read_u32(FRAME_NO) & 0xffff) > 60 end, 240)
  watching = false
  if PHASE == 1 then
    result("loading", L.owned_at ~= nil and L.back == 0 and L.lcd8 and #L.pcts > 5 and L.pcts[#L.pcts] >= 90,
      string.format("LCD taken %.1f s after OK, 8 bits a pixel throughout %s; %d percentages shown, %d going back: %s",
        (L.owned_at or 0) - t_ok, tostring(L.lcd8), #L.pcts, L.back, table.concat(L.pcts, " ")))
    log("at the start: " .. prefs() .. string.format("; read %d", sp:read_u32(PR_STATUS)))
    result("defaults", sp:read_u32(PR_STATUS) == 2 and prefs() == "res 0 ambi 1 scatter 2 keys 1 leds 1", prefs())
    press("CPC_SEG5", 0x02); wait(2)  -- HELP
    for i = 1, 3 do press("CPC_SEG11", 0x20); wait(1.2) end  -- PAGE DOWN x3: the settings
    local pg = sp:read_u32(HELP_PAGE)
    key("A5"); key("C6")              -- row 1: the ambilight off
    local ambi_off = sp:read_u8(PREFS + 5) == 0 and amb_black()
    key("G5#"); key("C6")             -- row 0: the resolution 320x200
    local res = sp:read_u8(PREFS + 4) == 1 and sp:read_u32(PG_W) == 320
    key("A5"); key("A5"); key("C6")   -- row 2: the scatter one more
    local scat = sp:read_u8(PREFS + 6) == 3
    key("A5"); key("C6")              -- row 3: the keybed sound off
    local keys = sp:read_u8(PREFS + 7) == 0 and sp:read_u32(AU_KEYWANT) == 1
    key("A5"); key("C6")              -- row 4: the LED effects off
    local leds = sp:read_u8(PREFS + 8) == 0
    wait(1); dump("settings.bin")
    result("page", pg == 3 and sp:read_u32(PR_SEL) == 4, string.format("help page %d, row %d", pg, sp:read_u32(PR_SEL)))
    result("apply", ambi_off and res and scat and keys and leds, string.format("ambilight off and black %s, 320x200 %s, scatter %s, keybed off %s, LEDs off %s",
      tostring(ambi_off), tostring(res), tostring(scat), tostring(keys), tostring(leds)))
    press("CPC_SEG11", 0x80); wait(3) -- EXIT: the game again; the main task saves
    local f0 = sp:read_u32(FRAME_NO) & 0xffff
    wait(2)
    result("saved", sp:read_u32(PR_WROTE) >= 1 and sp:read_u32(PR_DIRTY) == 0 and sp:read_u32(PR_FAILS) == 0
      and (sp:read_u32(FRAME_NO) & 0xffff) ~= f0, string.format("written %d, failed %d, dirty %d; the game running %s; %s",
        sp:read_u32(PR_WROTE), sp:read_u32(PR_FAILS), sp:read_u32(PR_DIRTY), tostring((sp:read_u32(FRAME_NO) & 0xffff) ~= f0), prefs()))
  else
    local ok = sp:read_u32(PR_STATUS) == 1 and sp:read_u8(PREFS + 4) == 1 and sp:read_u8(PREFS + 5) == 0
      and sp:read_u8(PREFS + 6) == 3 and sp:read_u8(PREFS + 7) == 0 and sp:read_u8(PREFS + 8) == 0
    result("read", ok, string.format("status %d; %s", sp:read_u32(PR_STATUS), prefs()))
    result("effect", sp:read_u32(PG_W) == 320 and amb_black() and sp:read_u32(AU_KEYWANT) == 1,
      string.format("PG_W %d, ambilight black %s, keybed muted %d", sp:read_u32(PG_W), tostring(amb_black()), sp:read_u32(AU_KEYWANT)))
    wait(1); dump("phase2.bin")
  end
  press("CPC_SEG11", 0x80, 2.0)       -- EXIT held: quit
  wait_until(function() return sp:read_u32(CV_ENDED) == 1 end, 30)
  local all = true
  for _, r in ipairs(results) do all = all and r end
  log(string.format("phase %d: %d checks, %s", PHASE, #results, all and "all pass" or "SOME FAIL"))
  M:exit()
  while true do coroutine.yield() end
end)
AWPR_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awpr: ERROR " .. tostring(err)); M:exit() end
  end
end)
