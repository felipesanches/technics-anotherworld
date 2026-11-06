-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_wheel.lua -- the code wheel help page (README-CNV.md, "The code wheel page"; src/wheel.s): does HELP at the code
-- wheel's question open it, does the TEMPO/PROGRAM wheel turn the upper disk a number a detent with pictures in between,
-- does the arrow always come to rest on a number (every picture on the way onwards, never back), do PAGE UP / DOWN reach the other pages and back, and does closing
-- the help screen leave the game as it was (its pages 2 and 3, the screen)?
-- The card has AWPREFS.CFG with the code wheel on (run_wheel.sh). Steps (each a "awwl: NAME PASS|FAIL detail" line):
--   open     HELP at the question: page 5 (index 4) shown, the converter calls taking the wheel's frames (WH_ON), the
--            blob read from the card once (WH_LOADS 1), the arrow at number 1 at rest (bilinear)
--   turn +1, +3 (three detents 50 ms apart: they pile up), -5 (through 1 to 20), -1, +2: each ends at rest at the
--            number turned to, WH_ANG = that number's angle (WB_ANGLES), with pictures in between (WH_TURNF > 0; every
--            angle drawn while turning lies strictly between the start's and the end's, the way the detents went)
--   pages    PAGE UP: the settings (page 4), the ambilight's border pattern drawn again (AMB_GEOM = PG_W); up to page 1;
--            PAGE DOWN four times: the code wheel again, at the same number, from display memory (WH_LOADS still 1)
--   close    EXIT: pages 2 and 3 byte-identical to before HELP, the LCD as MAME shows it identical to before HELP
--            (the question's screen is still), the question still asked
--   again    HELP: the page again, from display memory (WH_LOADS 1, WH_SAVES 2); EXIT
--   tempo    the firmware's own count of the wheel: frames taken, of them decoded by the firmware first and undone
--   elsewhere  the code wheel off on the settings page (the splash at once, src/prefs.s PrefsWheelNow), HELP: page 1;
--            PAGE DOWN four times: the code wheel's page; EXIT
--   320x200  PAGE DOWN (the original resolution), HELP, PAGE DOWN four times: the page; EXIT: the border's pattern for
--            the 320x200 window (AMB_GEOM 320), the LCD as before HELP outside the window
-- Dumps (AWWL_OUT): each picture checked, the wheel's 256 x 240 entries of FB8 (x 192-447), "name angle smooth" in
-- index.txt (probes/cnv/codewheel_check.py compares them with codewheel_render.py's render()); MAME snapshots
-- codewheel_rest.png and codewheel_turning.png (snap/).
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local OUT = os.getenv("AWWL_OUT") or "."
local CV, VI, MISC = 0x502DF000, 0x502E1000, 0x502E3000
local CV_ENDED = CV + 0x30
local FRAME_NO, HELP_PAGE, PG_W = MISC + 0x7C, MISC + 0x5C, MISC + 0x64
local PREFS = 0x502DF900
local PR_SEL = PREFS + 0x14
local AMB_GEOM = 0x502DAA00 + 0x284
local PART = VI + 0x102A
local WV = 0x502DFA00
local W = { RXRD = 0, ON = 4, STEPS = 0x10, TAKEN = 0x14, FRAMES = 0x18, LATE = 0x1C, UNDONE = 0x20, BORROW = 0x48,
  INRAM = 0x4C, CACHED = 0x50, FAIL = 0x5C, POS = 0x60, ANG = 0x64, MOVING = 0x78, SHOWN = 0x7C, SEQ = 0x80,
  SMOOTH = 0x84, NFRAMES = 0x88, NREST = 0x8C, TURNF = 0x90, TLAST = 0x94, TMAX = 0x98, TREST = 0x9C, LOADMS = 0xA4,
  LOADS = 0xA8, SAVES = 0xAC, BUSY = 0xB0, SROW = 0xB4, STORES = 0xC0, SSTORES = 0xC4 }
local function wv(k) return sp:read_u32(WV + W[k]) end
local WRAM, WRAM_LEN = 0x5034D000, 0x2D000
local WB_ANGLES = WRAM + 0x22600
local FB8 = 0x9CE00000 + 0x50000
local screen = M.screens[":screen"]
local function log(s) print("awwl: " .. s) end
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
local knob
for _, f in pairs(M.ioport.ports[":TEMPO_KNOB"].fields) do knob = f end
local knobAt = 50
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(c, s) local t = now() + s; while now() < t do if c() then return true end; coroutine.yield() end; return c() end
local function press(tag, mask, hold) local f = field(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end
local function key(name, hold) local f = KEY[name]; f:set_value(1); wait(hold or 0.3); f:set_value(0); wait(0.8) end
local function var(i) return sp:read_u16(VI + 2 * i) end
local function asking() local t = sp:read_u16(VI + 0x400 + 80); return sp:read_u16(PART) == 0x3E80 and t >= 0x02CE and t <= 0x0D7F and (var(0xBC) & 0x10) == 0 end
local function angle_of(n) return sp:read_u16(WB_ANGLES + 2 * n) end
local results = {}
local function result(name, ok, detail) results[#results + 1] = ok; log(string.format("%-10s %s  %s", name, ok and "PASS" or "FAIL", detail)) end
local index = io.open(OUT .. "/index.txt", "w")
-- the wheel's area of FB8 into OUT/name.bin, with its angle and kind in index.txt
local function dump(name, ang, sm)
  local rows = {}
  for y = 0, 239 do rows[#rows + 1] = sp:read_range(FB8 + y * 640 + 192, FB8 + y * 640 + 192 + 255, 8) end
  local f = io.open(OUT .. "/" .. name .. ".bin", "wb"); f:write(table.concat(rows)); f:close()
  index:write(string.format("%s %d %d\n", name, ang, sm)); index:flush()
end
-- read while no picture is being made (WH_BUSY 0, WH_SEQ the same before and after)
local function grab(name)
  for _ = 1, 100 do
    local s0 = wv("SEQ")
    if wv("BUSY") == 0 then
      local ang, sm = wv("ANG"), wv("SMOOTH")
      if wv("SEQ") == s0 then dump(name, ang, sm); return ang, sm end
    end
    coroutine.yield()
  end
  return nil
end
-- every picture finished (WH_SEQ + 2, written last): its angle and kind; the first turning one at least a quarter of the
-- way from a turn's start and before its end is dumped there and then (the game is still inside the store)
local ptimes = io.open(OUT .. "/pictimes.txt", "w")   -- each turning picture: its time (1/2001 ms), its LCD stores
local pics, want_mid, mid_from, mid_total, mid_dir = {}, nil, 0, 0, 1
AWWL_SEQ = sp:install_write_tap(WV + W.SEQ, WV + W.SEQ + 3, "awwl_seq", function(offset, data, mask)
  if offset ~= WV + W.SEQ then return end
  local a, sm = wv("ANG"), wv("SMOOTH")
  pics[#pics + 1] = { a, sm }
  if sm == 0 and wv("ON") == 1 then ptimes:write(string.format("%d %d\n", wv("TLAST"), wv("STORES"))) end
  if want_mid and sm == 0 then
    local d = (mid_dir > 0) and ((a - mid_from) % 65536) or ((mid_from - a) % 65536)
    if d >= mid_total // 4 and d < mid_total then         -- (a quarter of the way at least: a picture in mid-turn)
      dump(want_mid, a, 0)
      if not turnshot then turnshot = true; screen:snapshot("codewheel_turning.png") end
      want_mid = nil
    end
  end
end)
-- pages 2 and 3 as WheelEnsure saved them (WH_BORROW written 1 just after) and as WheelRestore put them back (0)
local saved_pages, back_pages = {}, {}
AWWL_BOR = sp:install_write_tap(WV + W.BORROW, WV + W.BORROW + 3, "awwl_bor", function(offset, data, mask)
  if offset ~= WV + W.BORROW then return end
  local v = data & mask
  if v == 1 then saved_pages[#saved_pages + 1] = sp:read_range(WRAM, WRAM + WRAM_LEN - 1, 8)
  elseif v == 0 then
    back_pages[#back_pages + 1] = sp:read_range(WRAM, WRAM + WRAM_LEN - 1, 8)
  end
end)
local function pixels() return screen:pixels() end
local function diff(a, b)            -- 32-bit pixels that differ
  local n = 0
  for i = 1, #a, 4 do if a:sub(i, i + 3) ~= b:sub(i, i + 3) then n = n + 1 end end
  return n
end

-- one move of the TEMPO/PROGRAM wheel: detents (signed), each `gap` s apart; then the turn followed MAME frame by
-- MAME frame until it rests: the angles drawn on the way, one picture dumped half way
turnshot = false
local timing = {}
local function turn(name, n, gap)
  local pos0, ang0 = wv("POS"), wv("ANG")
  local want = (pos0 + n) % 20
  local total = (angle_of(want) - ang0) % 65536
  if n < 0 then total = (ang0 - angle_of(want)) % 65536 end
  if total == 0 then total = 65536 end
  pics = {}
  want_mid, mid_from, mid_total, mid_dir = name .. "_mid", ang0, total, n
  for k = 1, math.abs(n) do
    knobAt = (knobAt + (n > 0 and 1 or -1)) % 101   -- (the panel model: a jump over 50 is a wrap)
    knob.user_value = knobAt
    wait(gap)
  end
  local rest = wait_until(function() return wv("POS") == want and wv("MOVING") == 0 and wv("SROW") == 240 and wv("SMOOTH") == 1 and wv("BUSY") == 0 end, 8)
  wait(0.2)
  want_mid = nil
  local ang, sm = grab(name)
  -- the turning pictures: every angle strictly between the start's and the end's, the way the detents went, but the
  -- last, the end's own; then the one at rest
  local between, nturn, last, prev = 0, 0, nil, 0
  local ok = true
  for i, p in ipairs(pics) do
    if p[2] == 0 then
      nturn = nturn + 1
      local d = (n > 0) and ((p[1] - ang0) % 65536) or ((ang0 - p[1]) % 65536)
      if p[1] == angle_of(want) then last = i; d = total
      elseif d > 0 and d < total then between = between + 1 else ok = false end
      if d < prev or last and last < i then ok = false end   -- always onwards, and the end's own picture the last
      prev = d
    end
  end
  ok = ok and between > 0 and last ~= nil and pics[#pics][2] == 1 and pics[#pics][1] == angle_of(want)
  timing[#timing + 1] = { wv("TLAST"), wv("STORES"), wv("TREST"), wv("SSTORES") }
  result("turn " .. name, rest and ang == angle_of(want) and sm == 1 and ok,
    string.format("number %d -> %d (%d detents): at rest %s, angle %d (number's %d), bilinear %s; pictures: %d turning (%d between, then the end's own %s), then at rest; last turning picture %.1f ms, %d stores; at rest %.1f ms, %d stores (MAME time)",
      pos0 + 1, wv("POS") + 1, n, tostring(rest), ang or -1, angle_of(want), tostring(sm == 1), nturn, between,
      tostring(last ~= nil), wv("TLAST") / 2001, wv("STORES"), wv("TREST") / 2001, wv("SSTORES")))
end

local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  press("CPR_SEG6", 0x01)             -- OK (KN7LOAD.CNV)
  local q = wait_until(asking, 240)
  wait(3)
  log(string.format("the question: %s (part %04X); the panel's ring %08X", tostring(q), sp:read_u16(PART), wv("RXRD")))
  -- open
  local px0 = pixels()
  saved_pages, back_pages = {}, {}    -- (the loader's and the firmware's zeroing of the area at the start are not ours)
  press("CPC_SEG5", 0x02)             -- HELP
  local shown = wait_until(function() return wv("ON") == 1 and wv("NREST") >= 1 and wv("BUSY") == 0 end, 20)
  wait(0.5)
  local ang, sm = grab("open")
  screen:snapshot("codewheel_rest.png")
  result("open", shown and sp:read_u32(HELP_PAGE) == 4 and wv("LOADS") == 1 and wv("POS") == 0 and ang == angle_of(0) and sm == 1,
    string.format("page %d, shown %s, read from the card %d time(s) in %d ms, number %d, angle %s (number 1's %d), bilinear %s, failure %02X",
      sp:read_u32(HELP_PAGE) + 1, tostring(shown), wv("LOADS"), wv("LOADMS"), wv("POS") + 1, tostring(ang), angle_of(0), tostring(sm == 1), wv("FAIL")))
  turn("p1", 1, 0.6)
  turn("p3", 3, 0.05)
  turn("m5", -5, 0.6)
  turn("m1", -1, 0.6)
  turn("p2", 2, 0.05)
  -- pages
  press("CPC_SEG11", 0x10); wait(1.2) -- PAGE UP: the settings
  local set_ok = sp:read_u32(HELP_PAGE) == 3 and wv("ON") == 0 and wv("SHOWN") == 0 and sp:read_u32(AMB_GEOM) == sp:read_u32(PG_W)
  local seen = { sp:read_u32(HELP_PAGE) }
  for _ = 1, 3 do press("CPC_SEG11", 0x10); wait(1.2); seen[#seen + 1] = sp:read_u32(HELP_PAGE) end
  for _ = 1, 4 do press("CPC_SEG11", 0x20); wait(1.2); seen[#seen + 1] = sp:read_u32(HELP_PAGE) end
  wait_until(function() return wv("ON") == 1 end, 5)
  wait(0.3)
  ang, sm = grab("back")
  for i, v in ipairs(seen) do seen[i] = tostring(v + 1) end
  result("pages", set_ok and table.concat(seen, " ") == "4 3 2 1 2 3 4 5" and wv("POS") == 0 and ang == angle_of(0) and wv("LOADS") == 1,
    string.format("PAGE UP from the wheel: settings shown, wheel page off, border pattern for %d %s; pages %s; the wheel again at number %d, angle %s, loads %d",
      sp:read_u32(PG_W), tostring(set_ok), table.concat(seen, " "), wv("POS") + 1, tostring(ang), wv("LOADS")))
  -- close
  press("CPC_SEG11", 0x80); wait(0.3) -- EXIT
  wait_until(function() return wv("BORROW") == 0 end, 5)
  wait(0.5)
  local same_pages = #saved_pages == 1 and #back_pages == 1 and saved_pages[1] == back_pages[1]
  local dpx = diff(pixels(), px0)
  result("close", same_pages and dpx == 0 and asking() and wv("ON") == 0,
    string.format("pages 2 and 3 put back as they were saved: %s (%d saved, %d put back); LCD pixels differing from before HELP: %d; the question still asked: %s",
      tostring(same_pages), #saved_pages, #back_pages, dpx, tostring(asking())))
  -- again: from display memory
  press("CPC_SEG5", 0x02)
  local again = wait_until(function() return wv("ON") == 1 and wv("SAVES") == 2 end, 10)
  wait(0.5)
  ang, sm = grab("again")
  result("again", again and wv("LOADS") == 1 and ang == angle_of(0), string.format("shown %s, loads %d, borrows %d, angle %s",
    tostring(again), wv("LOADS"), wv("SAVES"), tostring(ang)))
  press("CPC_SEG11", 0x80); wait(1.5)
  log(string.format("tempo: wheel frames taken %d, decoded by the firmware first and undone %d (frames put back %d); detents counted %d",
    wv("FRAMES"), wv("LATE"), wv("UNDONE"), wv("STEPS")))
  local tl, ts, rl, rs = {}, {}, {}, {}
  for _, t in ipairs(timing) do tl[#tl + 1] = string.format("%.1f", t[1] / 2001); ts[#ts + 1] = t[2]; rl[#rl + 1] = string.format("%.1f", t[3] / 2001); rs[#rs + 1] = t[4] end
  log(string.format("times (MAME): each turn's last turning picture %s ms (%s stores into the LCD), longest %.1f ms; each picture at rest %s ms (%s stores); pictures turning %d, at rest %d",
    table.concat(tl, " "), table.concat(ts, " "), wv("TMAX") / 2001, table.concat(rl, " "), table.concat(rs, " "), wv("NFRAMES"), wv("NREST")))
  -- elsewhere: the code wheel off (the splash at once), HELP opens page 1
  press("CPC_SEG5", 0x02); wait(1.5)
  for _ = 1, 6 do
    local pg = sp:read_u32(HELP_PAGE)
    if pg == 3 then break end
    press("CPC_SEG11", pg < 3 and 0x20 or 0x10); wait(1.0)
  end
  local guard = 0
  while sp:read_u32(PR_SEL) ~= 5 and guard < 8 do key("A5"); guard = guard + 1 end
  key("F5")                           -- off
  press("CPC_SEG11", 0x80); wait(3)
  local off = not asking() and sp:read_u16(PART) == 0x3E80
  press("CPC_SEG5", 0x02); wait(1.5)
  local p1 = sp:read_u32(HELP_PAGE)
  for _ = 1, 4 do press("CPC_SEG11", 0x20); wait(1.2) end
  local w = wait_until(function() return wv("ON") == 1 end, 5)
  press("CPC_SEG11", 0x80); wait(1.5)
  result("elsewhere", off and p1 == 0 and w, string.format("the splash after the setting went off %s; HELP opened page %d; PAGE DOWN x4: the wheel %s",
    tostring(off), p1 + 1, tostring(w)))
  -- 320x200
  wait_until(function() return sp:read_u16(PART) == 0x3E81 end, 90)
  wait(2)
  press("CPC_SEG11", 0x20); wait(2)   -- PAGE DOWN in the game: 320x200
  local pw = sp:read_u32(PG_W)
  press("CPC_SEG5", 0x02); wait(1.5)
  for _ = 1, 4 do press("CPC_SEG11", 0x20); wait(1.2) end
  local w2 = wait_until(function() return wv("ON") == 1 end, 5)
  wait(0.5)
  screen:snapshot("codewheel_320.png")
  press("CPC_SEG11", 0x80); wait(0.3)
  wait_until(function() return wv("BORROW") == 0 end, 5)
  wait(1)
  result("320x200", pw == 320 and w2 and sp:read_u32(AMB_GEOM) == 320 and sp:read_u32(PG_W) == 320,
    string.format("PG_W %d, the wheel shown %s, after EXIT the border's pattern for %d", pw, tostring(w2), sp:read_u32(AMB_GEOM)))
  press("CPC_SEG11", 0x80, 2.0)       -- EXIT held: quit
  wait_until(function() return sp:read_u32(CV_ENDED) == 1 end, 30)
  index:close()
  ptimes:close()
  local all = true
  for _, r in ipairs(results) do all = all and r end
  log(string.format("%d checks, %s", #results, all and "all pass" or "SOME FAIL"))
  M:exit()
  while true do coroutine.yield() end
end)
AWWL_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awwl: ERROR " .. tostring(err)); M:exit() end
  end
end)
