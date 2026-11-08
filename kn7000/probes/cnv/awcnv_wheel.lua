-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_wheel.lua -- the code wheel help page, zoomed (README-CNV.md, "The code wheel page"; src/wheel.s): does HELP at
-- the code wheel's question open it, does the TEMPO/PROGRAM wheel turn the upper disk a number a detent with pictures
-- in between, does the arrow always come to rest on a number, do the LCD's soft buttons 1, 3 and 5 scroll the tall
-- frame to the TOP, MIDDLE and BOTTOM regions (the controller's start address on the region's row at the end, several
-- start addresses on the way), are the rows that scroll into view drawn at the disk's angle, do PAGE UP / DOWN reach the
-- other pages and back, and does closing the help screen leave the game as it was (its four pages, the screen)?
-- The card has AWPREFS.CFG with the code wheel on (run_wheel.sh). Steps (each a "awwl: NAME PASS|FAIL detail" line):
--   open     HELP at the question: page 5 shown, the blob read from the card once, the arrow at number 1 at rest, TOP
--   turn +1, +3 (three detents 50 ms apart: they pile up), -5 (through 1 to 20): each ends at rest at the number turned
--            to, with pictures in between (every angle drawn while turning strictly between the start's and the end's)
--   region   LCDR 3 (MIDDLE), a turn -1 there, LCDR 5 (BOTTOM), LCDL 1 (TOP: 240 rows), a turn +2 there, LCDL 5
--            (BOTTOM): each scroll ends on the region's start address after several, with the rows drawn first that
--            were stale; the region's rows at rest, bilinear at the number's angle; the soft buttons' frames taken from
--            the ring (the firmware's debounced bitmap never showing one down, but for a frame it decoded first)
--   pages    PAGE UP: the settings (page 4), the LCD on FB8; up to page 1; PAGE DOWN four times: the code wheel again,
--            at the same number and region, from display memory (loads still 1)
--   close    EXIT: the VM's four pages byte-identical to before HELP, the LCD as MAME shows it identical to before HELP
--   again    HELP: the page again, from display memory (loads 1, borrows 2), in the region it was left in (BOTTOM); EXIT
--   elsewhere  the code wheel off on the settings page, HELP: page 1; PAGE DOWN four times: the code wheel's page; EXIT
--   320x200  PAGE DOWN (the original resolution), HELP, PAGE DOWN four times: the page; EXIT: the border's pattern for
--            the 320x200 window (AMB_GEOM 320)
-- Dumps (AWWL_OUT): each picture checked, the region's 240 rows of the tall frame's wheel (480 entries each, columns
-- 80-559) as name.bin and each row's state (WT_ROWST: the angle | 0x10000 bilinear) as name.st, "name first-row kind"
-- in index.txt (kind: rest, turning, scroll; probes/cnv/codewheel_check.py renders every row at its own state);
-- pictimes.txt (each turning picture: its time in 1/2001 ms, its stores into the LCD); MAME snapshots (snap/).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local OUT = os.getenv("AWWL_OUT") or "."
local CV, VI, MISC = 0x502DF000, 0x502E1000, 0x502E3000
local CV_ENDED = CV + 0x30
local HELP_PAGE, PG_W = MISC + 0x5C, MISC + 0x64
local PREFS = 0x502DF900
local PR_SEL = PREFS + 0x14
local AMB_GEOM = 0x502DAA00 + 0x284
local PART = VI + 0x102A
local WV = 0x502DFA00
local W = { RXRD = 0, ON = 4, STEPS = 0x10, TAKEN = 0x14, FRAMES = 0x18, LATE = 0x1C, UNDONE = 0x20, BORROW = 0x48,
  INRAM = 0x4C, CACHED = 0x50, FAIL = 0x5C, POS = 0x60, ANG = 0x64, MOVING = 0x78, SHOWN = 0x7C, SEQ = 0x80,
  SMOOTH = 0x84, NFRAMES = 0x88, NREST = 0x8C, TURNF = 0x90, TLAST = 0x94, TMAX = 0x98, TREST = 0x9C, LOADMS = 0xA4,
  LOADS = 0xA8, SAVES = 0xAC, BUSY = 0xB0, SROW = 0xB4, STORES = 0xC0, SSTORES = 0xC4, REGION = 0xD0, RSEQ = 0xD8,
  SCROLL = 0xE0, SC_DUR = 0xF0, SC_ROW = 0xF4, SC_N = 0xF8, SCROLLS = 0xFC, TFOK = 0x100, INB = 0x104, SOFTN = 0x10C,
  SOFTLATE = 0x110, STALE = 0x118, SHOWMS = 0x11C }
local function wv(k) return sp:read_u32(WV + W[k]) end
local WRAM, WRAM_LEN = 0x50320000, 0x5A000
local WB_ANGLES = WRAM + 0x3EE00
local WT_ROWST = WRAM + 0x59000
local TF_OFS = 0x76000
local TF = 0x9CE00000 + TF_OFS
local LCDC = 0x9CC00000
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
local function start_of(row) return TF_OFS // 2 + (row + 239) * 320 + 319 end
local function lcd_start() return sp:read_u16(LCDC + 0x42) | (sp:read_u8(LCDC + 0x44) << 16) end
local results = {}
local function result(name, ok, detail) results[#results + 1] = ok; log(string.format("%-10s %s  %s", name, ok and "PASS" or "FAIL", detail)) end
local index = io.open(OUT .. "/index.txt", "w")
-- the region's rows of the tall frame's wheel into OUT/name.bin, their states into OUT/name.st
local function dump(name, kind)
  local r0 = wv("REGION") * 120
  local rows, st = {}, {}
  for y = r0, r0 + 239 do
    rows[#rows + 1] = sp:read_range(TF + y * 640 + 80, TF + y * 640 + 80 + 479, 8)
    st[#st + 1] = string.pack("<I4", sp:read_u32(WT_ROWST + 4 * y))
  end
  local f = io.open(OUT .. "/" .. name .. ".bin", "wb"); f:write(table.concat(rows)); f:close()
  f = io.open(OUT .. "/" .. name .. ".st", "wb"); f:write(table.concat(st)); f:close()
  index:write(string.format("%s %d %s\n", name, r0, kind)); index:flush()
end
-- the region's rows' states: all equal to want (angle | 0x10000 bilinear)?
local function rows_at(want)
  local r0 = wv("REGION") * 120
  for y = r0, r0 + 239 do if sp:read_u32(WT_ROWST + 4 * y) ~= want then return false end end
  return true
end
-- read while no picture is being made (WH_BUSY 0, WH_SEQ the same before and after)
local function grab(name, kind)
  for _ = 1, 100 do
    local s0 = wv("SEQ")
    if wv("BUSY") == 0 then
      local ang, sm = wv("ANG"), wv("SMOOTH")
      if wv("SEQ") == s0 then dump(name, kind); return ang, sm end
    end
    coroutine.yield()
  end
  return nil
end
-- every picture finished (WH_SEQ + 2, written last): its angle and kind; the first turning one at least a quarter of the
-- way from a turn's start and before its end is dumped there and then (the game is still inside the store)
local ptimes = io.open(OUT .. "/pictimes.txt", "w")   -- each turning picture: its time (1/2001 ms), its LCD stores, region
local pics, want_mid, mid_from, mid_total, mid_dir = {}, nil, 0, 0, 1
local turnshot = {}
AWWL_SEQ = sp:install_write_tap(WV + W.SEQ, WV + W.SEQ + 3, "awwl_seq", function(offset, data, mask)
  if offset ~= WV + W.SEQ then return end
  local a, sm = wv("ANG"), wv("SMOOTH")
  pics[#pics + 1] = { a, sm }
  if sm == 0 and wv("ON") == 1 then ptimes:write(string.format("%d %d %d\n", wv("TLAST"), wv("STORES"), wv("REGION"))) end
  if want_mid and sm == 0 then
    local d = (mid_dir > 0) and ((a - mid_from) % 65536) or ((mid_from - a) % 65536)
    if d >= mid_total // 4 and d < mid_total then         -- (a quarter of the way at least: a picture in mid-turn)
      dump(want_mid, "turning")
      local r = wv("REGION")
      if not turnshot[r] then turnshot[r] = true; screen:snapshot("codewheel_turning_" .. ({ "top", "middle", "bottom" })[r + 1] .. ".png") end
      want_mid = nil
    end
  end
end)
-- the VM's pages as WheelEnsure saved them (WH_BORROW written 1 just after) and as WheelRestore put them back (0)
local saved_pages, back_pages = {}, {}
AWWL_BOR = sp:install_write_tap(WV + W.BORROW, WV + W.BORROW + 3, "awwl_bor", function(offset, data, mask)
  if offset ~= WV + W.BORROW then return end
  local v = data & mask
  if v == 1 then saved_pages[#saved_pages + 1] = sp:read_range(WRAM, WRAM + WRAM_LEN - 1, 8)
  elseif v == 0 then back_pages[#back_pages + 1] = sp:read_range(WRAM, WRAM + WRAM_LEN - 1, 8) end
end)
-- the start addresses a scroll writes (the low 16 bits' store, REG[042h]): each with the row WH_SC_ROW then holds;
-- a snapshot once a scroll is under way
local starts, midshot = {}, {}
AWWL_LCD = sp:install_write_tap(LCDC + 0x40, LCDC + 0x43, "awwl_lcd", function(offset, data, mask)
  if offset == LCDC + 0x40 and (mask & 0xFFFF0000) ~= 0 and wv("SCROLL") == 1 then starts[#starts + 1] = wv("SC_ROW") end
end)
-- does the firmware see a soft button? Its debounced bitmap (program 893; awcnv_lcdkeys.lua): LCDR 1, 2, 5 at
-- 0x5006BE51 bits 0x10, 0x20, 0x01, LCDR 4 0x5006BE52 bit 0x01, LCDR 3 0x5006BE53 bit 0x01, LCDL 1-5 0x5006BE7C bits
-- 0x02 0x08 0x20 0x01 0x04
local function fw_soft()
  return (sp:read_u8(0x5006BE51) & 0x31) ~= 0 or (sp:read_u8(0x5006BE52) & 0x01) ~= 0
    or (sp:read_u8(0x5006BE53) & 0x01) ~= 0 or (sp:read_u8(0x5006BE7C) & 0x2F) ~= 0
end
local function pixels() return screen:pixels() end
local function diff(a, b)            -- 32-bit pixels that differ
  local n = 0
  for i = 1, #a, 4 do if a:sub(i, i + 3) ~= b:sub(i, i + 3) then n = n + 1 end end
  return n
end

-- one move of the TEMPO/PROGRAM wheel: detents (signed), each `gap` s apart; then the turn followed until it rests:
-- the angles drawn on the way, one picture dumped mid-way
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
  local rest = wait_until(function() return wv("POS") == want and wv("MOVING") == 0 and wv("SROW") == 240 and wv("SMOOTH") == 1 and wv("BUSY") == 0 end, 15)
  wait(0.2)
  want_mid = nil
  local ang, sm = grab(name, "rest")
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
  local allrest = rows_at(angle_of(want) | 0x10000)
  ok = ok and between > 0 and last ~= nil and pics[#pics][2] == 1 and pics[#pics][1] == angle_of(want) and allrest
  timing[#timing + 1] = { wv("TLAST"), wv("STORES"), wv("TREST"), wv("SSTORES"), wv("REGION") }
  result("turn " .. name, rest and ang == angle_of(want) and sm == 1 and ok,
    string.format("region %d, number %d -> %d (%d detents): at rest %s, angle %d (number's %d), every row bilinear there %s; pictures: %d turning (%d between, then the end's own %s), then at rest; last turning picture %.1f ms, %d stores; at rest %.1f ms, %d stores (MAME time)",
      wv("REGION"), pos0 + 1, wv("POS") + 1, n, tostring(rest), ang or -1, angle_of(want), tostring(allrest), nturn, between,
      tostring(last ~= nil), wv("TLAST") / 2001, wv("STORES"), wv("TREST") / 2001, wv("SSTORES")))
end

-- a soft button: the scroll to `region` followed to its end and the region's picture at rest
local NAMES = { [0] = "top", "middle", "bottom" }
local function region(name, tag, mask, want)
  local r0 = wv("REGION")
  local sc0, soft0, late0 = wv("SCROLLS"), wv("SOFTN"), wv("SOFTLATE")
  starts = {}
  local t0 = now()
  local f = field(tag, mask)
  f:set_value(1)                      -- held 0.3 s; a snapshot once the scroll is a third of the way (MAME's screen
  local shot, held = false, true      -- bitmap is 1-2 frames behind)
  local fwsaw = 0                     -- frames at which the firmware's debounced bitmap showed a soft button down
  local fin = wait_until(function()
    if fw_soft() then fwsaw = fwsaw + 1 end
    if held and now() - t0 >= 0.3 then f:set_value(0); held = false end
    if not shot and wv("SCROLL") == 1 and math.abs(wv("SC_ROW") - r0 * 120) * 3 >= math.abs(want - r0) * 120 then
      shot = true; screen:snapshot("codewheel_scroll_" .. NAMES[r0] .. "_" .. NAMES[want] .. ".png")
    end
    return not held and wv("SCROLLS") == sc0 + 1 and wv("SCROLL") == 0 and wv("SROW") == 240 and wv("SMOOTH") == 1 and wv("BUSY") == 0
  end, 15)
  wait(0.3)
  local ang = wv("ANG")
  grab(name, "rest")
  local allrest = rows_at(ang | 0x10000)
  local onwards = true
  for i = 2, #starts do
    if (want > r0 and starts[i] < starts[i - 1]) or (want < r0 and starts[i] > starts[i - 1]) then onwards = false end
  end
  local st = lcd_start()
  local ok = fin and wv("REGION") == want and wv("SC_ROW") == want * 120 and st == start_of(want * 120) and #starts >= 3
    and onwards and allrest and wv("SOFTN") > soft0 and (fwsaw == 0 or wv("SOFTLATE") > late0)
  result("region " .. name, ok,
    string.format("%s -> %s: %d start addresses written on the way (onwards %s), the last 0x%05X (row %d; the region's 0x%05X), in %d ms; rows drawn first %d; every row bilinear at the number's angle %s; soft button frames taken %d (decoded first by the firmware %d); MAME frames with a soft button down in the firmware's bitmap %d",
      NAMES[r0], NAMES[want], #starts, tostring(onwards), st, wv("SC_ROW"), start_of(want * 120), wv("SC_DUR"),
      wv("STALE"), tostring(allrest), wv("SOFTN") - soft0, wv("SOFTLATE") - late0, fwsaw))
  screen:snapshot("codewheel_" .. NAMES[want] .. ".png")
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
  saved_pages, back_pages = {}, {}
  press("CPC_SEG5", 0x02)             -- HELP
  local shown = wait_until(function() return wv("ON") == 1 and wv("NREST") >= 1 and wv("BUSY") == 0 and wv("SROW") == 240 end, 30)
  wait(0.5)
  local ang, sm = grab("open", "rest")
  screen:snapshot("codewheel_rest_top.png")
  result("open", shown and sp:read_u32(HELP_PAGE) == 4 and wv("LOADS") == 1 and wv("POS") == 0 and ang == angle_of(0) and sm == 1
    and wv("REGION") == 0 and lcd_start() == start_of(0) and rows_at(angle_of(0) | 0x10000),
    string.format("page %d, shown %s, read from the card %d time(s) in %d ms, region %d (start 0x%05X), number %d, angle %s (number 1's %d), bilinear %s, failure %02X; the showing %d ms",
      sp:read_u32(HELP_PAGE) + 1, tostring(shown), wv("LOADS"), wv("LOADMS"), wv("REGION"), lcd_start(), wv("POS") + 1, tostring(ang), angle_of(0),
      tostring(sm == 1), wv("FAIL"), wv("SHOWMS")))
  turn("p1", 1, 0.6)
  turn("p3", 3, 0.05)
  turn("m5", -5, 0.6)
  region("mid", "CPR_SEG7", 0x01, 1)  -- LCDR 3
  turn("m1", -1, 0.6)
  region("bot", "CPR_SEG5", 0x01, 2)  -- LCDR 5
  region("top", "CPL_SEG0", 0x02, 0)  -- LCDL 1 (240 rows)
  turn("p2", 2, 0.05)
  region("bot2", "CPL_SEG0", 0x04, 2) -- LCDL 5 (240 rows)
  -- pages
  press("CPC_SEG11", 0x10); wait(1.2) -- PAGE UP: the settings
  local set_ok = sp:read_u32(HELP_PAGE) == 3 and wv("ON") == 0 and wv("SHOWN") == 0 and (lcd_start() & 0xFFFF) == 0xABFF
  local seen = { sp:read_u32(HELP_PAGE) }
  for _ = 1, 3 do press("CPC_SEG11", 0x10); wait(1.2); seen[#seen + 1] = sp:read_u32(HELP_PAGE) end
  local nr = wv("NREST")               -- (WH_ON is 1 from the page's first moment: wait for its picture at rest)
  for _ = 1, 4 do press("CPC_SEG11", 0x20); wait(1.2); seen[#seen + 1] = sp:read_u32(HELP_PAGE) end
  wait_until(function() return wv("ON") == 1 and wv("NREST") > nr and wv("SROW") == 240 and wv("BUSY") == 0 end, 10)
  wait(0.3)
  ang, sm = grab("back", "rest")
  for i, v in ipairs(seen) do seen[i] = tostring(v + 1) end
  result("pages", set_ok and table.concat(seen, " ") == "4 3 2 1 2 3 4 5" and wv("POS") == 0 and ang == angle_of(0) and wv("LOADS") == 1
    and wv("REGION") == 2 and lcd_start() == start_of(240),
    string.format("PAGE UP from the wheel: settings shown, wheel page off, the LCD on FB8 %s; pages %s; the wheel again at number %d, angle %s, region %d, loads %d; the showing %d ms",
      tostring(set_ok), table.concat(seen, " "), wv("POS") + 1, tostring(ang), wv("REGION"), wv("LOADS"), wv("SHOWMS")))
  -- close
  press("CPC_SEG11", 0x80); wait(0.3) -- EXIT
  wait_until(function() return wv("BORROW") == 0 end, 5)
  wait(0.5)
  local same_pages = #saved_pages == 1 and #back_pages == 1 and saved_pages[1] == back_pages[1]
  local dpx = diff(pixels(), px0)
  result("close", same_pages and dpx == 0 and asking() and wv("ON") == 0,
    string.format("the VM's four pages put back as they were saved: %s (%d saved, %d put back); LCD pixels differing from before HELP: %d; the question still asked: %s",
      tostring(same_pages), #saved_pages, #back_pages, dpx, tostring(asking())))
  -- again: from display memory, in the region it was left in
  nr = wv("NREST")
  press("CPC_SEG5", 0x02)
  local again = wait_until(function() return wv("ON") == 1 and wv("SAVES") == 2 and wv("NREST") > nr and wv("SROW") == 240 and wv("BUSY") == 0 end, 15)
  wait(0.5)
  ang, sm = grab("again", "rest")
  result("again", again and wv("LOADS") == 1 and ang == angle_of(0) and wv("REGION") == 2 and lcd_start() == start_of(240),
    string.format("shown %s, loads %d, borrows %d, angle %s, region %d (start 0x%05X); the showing %d ms",
      tostring(again), wv("LOADS"), wv("SAVES"), tostring(ang), wv("REGION"), lcd_start(), wv("SHOWMS")))
  press("CPC_SEG11", 0x80); wait(1.5)
  log(string.format("tempo: wheel frames taken %d, decoded by the firmware first and undone %d; soft button frames %d, decoded first %d; frames put back %d; detents counted %d",
    wv("FRAMES"), wv("LATE"), wv("SOFTN"), wv("SOFTLATE"), wv("UNDONE"), wv("STEPS")))
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
  local w = wait_until(function() return wv("ON") == 1 end, 10)
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
  local w2 = wait_until(function() return wv("ON") == 1 end, 10)
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
