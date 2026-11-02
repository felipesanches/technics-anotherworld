-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_lcd8.lua -- does the LCD show the game's frame as it should, since the game drives it at 8 bits a pixel
-- with the ambilight around the window (src/lcd8.s; README-CNV.md, "The screen")? awcnv_lcd.lua checked the 16-bit
-- frame of the builds before.
--
-- Starts the game as a player does (DISK MENU, STYLE CONVERT, OK on KN7LOAD.CNV), the intro at tick 0 (NO_SPLASH),
-- and lets it run with no input into the lake. At every VM tick (FRAME_NO written, just after the end-of-frame blit):
--   window   FB8's window bytes (display memory 0x9CE50000, lines of 640 bytes; 384x240 at x 128, or 320x200 at
--            160, 20, as PG_W says) are the front page's (CUR_PAGE_2) colour indices, each & 15
--   border   FB8's bytes outside the window are those of the last time the border was drawn (lcd8.s AmbiFill, which
--            sets AMB_GEOM to the window's width): never written otherwise; and every one of them is an ambilight
--            entry, 16-255
--   lcdc     the controller at 8 bits a pixel (REG[040h] bits 2-0 = 3) and on FB8 (REG[042h]-[044h] = 0x03ABFF)
-- and every AWL_SHOTS-th tick (default 25), at the next frame MAME draws, the screen itself (the KN7000 driver's
-- screen_update: controller, look-up table, SwivelView): every window pixel the palette's colour of the page's index
-- (4 bits a channel, as the look-up table holds them), every border pixel the colour the game last wrote to its
-- ambilight entry (AMB_LUT), and how many of the border's pixels are not black (a sample is dropped when the game's
-- next tick came first). AWL_PRESS="T:UP,T:DOWN,..." presses
-- PAGE UP or PAGE DOWN (0.3 s) once the game has reached tick T. AWL_DUMPAT="T,T,...": the screen at those ticks to
-- AWL_OUT/screen_TTTT.bin (640 x 240 x 4 bytes, the screen's 32-bit pixels). Prints "awlcd8: ..." lines.
--   AWL_PAL=0x$(grep ' palette$' build/kn7app.map | cut -c3-10) probes/cnv/run_perf.sh OUT probes/cnv/awcnv_lcd8.lua
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local OUT = os.getenv("AWL_OUT") or "."
local PAL = tonumber(os.getenv("AWL_PAL") or "")
local MAXTICK = tonumber(os.getenv("AWL_MAX") or "3600")
local SHOTS = tonumber(os.getenv("AWL_SHOTS") or "25")
local CV = 0x502DF000
local MISC, PERF = 0x502E3000, 0x502E6000
local CUR_PAGE_2, FRAME_NO, NO_SPLASH, PART = 0x502E1000 + 0x100C, MISC + 0x7C, MISC + 0x58, 0x502E1000 + 0x102A
local PG_W = MISC + 0x64
local AMB_LUT, AMB_GEOM, LCD_OWNED = PERF + 0x600 + 0x60, PERF + 0x600 + 0x284, PERF + 0x600 + 0x288
local FB8, LCDC = 0x9CE50000, 0x9CC00000
local screen = M.screens[":screen"]
if not PAL then print("awlcd8: AWL_PAL (the build's palette label) is required"); M:exit() end
local PRESSES = {}
for t, b in (os.getenv("AWL_PRESS") or ""):gmatch("(%d+):(%a+)") do PRESSES[#PRESSES + 1] = { tonumber(t), b } end
local DUMPAT = {}
for t in (os.getenv("AWL_DUMPAT") or ""):gmatch("(%d+)") do DUMPAT[tonumber(t)] = true end
local function press(tag, mask, v)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then f:set_value(v) end end
end
local STEPS = { { 30, "CPR_SEG1", 0x04, "DISK MENU" }, { 36, "CPL_SEG0", 0x20, "STYLE CONVERT" }, { 44, "CPR_SEG6", 0x01, "OK (KN7LOAD.CNV)" } }
local function window(pgw) if pgw == 384 then return 128, 0, 384, 240 end return 160, 20, 320, 200 end

local S = { ticks = 0, winbad = 0, winpx = 0, bordchg = 0, fills = 0, notamb = 0, lcdc = 0, shots = 0, shotbad = 0,
            shotwin = 0, shotbord = 0, lit = 0, modes = {}, first = {} }
local border, bgeom = nil, -1
local function borderof(lcd, x0, y0, w, h)
  local t = {}
  for y = 0, 239 do
    local r = y * 640
    if y >= y0 and y < y0 + h then
      t[#t + 1] = lcd:sub(r + 1, r + x0); t[#t + 1] = lcd:sub(r + x0 + w + 1, r + 640)
    else
      t[#t + 1] = lcd:sub(r + 1, r + 640)
    end
  end
  return table.concat(t)
end
local function argb4(r, g, b) return 0xFF000000 | ((r * 17) << 16) | ((g * 17) << 8) | (b * 17) end
local pending = nil
local function check(tick)
  S.ticks = S.ticks + 1
  local pgw = sp:read_u32(PG_W)
  local x0, y0, w, h = window(pgw)
  S.modes[pgw] = (S.modes[pgw] or 0) + 1
  local page = sp:read_u32(CUR_PAGE_2)
  local pix = sp:read_range(page, page + w * h - 1, 8)
  local lcd = sp:read_range(FB8, FB8 + 640 * 240 - 1, 8)
  local bad = 0
  for y = 0, h - 1 do
    local got = lcd:sub((y0 + y) * 640 + x0 + 1, (y0 + y) * 640 + x0 + w)
    local want = pix:sub(y * w + 1, (y + 1) * w)
    if got ~= want then
      for x = 1, w do
        if got:byte(x) ~= (want:byte(x) & 15) then
          bad = bad + 1
          if #S.first < 8 then S.first[#S.first + 1] = string.format("tick %d window (%d,%d)", tick, x - 1, y) end
        end
      end
    end
  end
  if bad > 0 then S.winbad = S.winbad + 1; S.winpx = S.winpx + bad end
  local geom = sp:read_u32(AMB_GEOM)
  local b = borderof(lcd, x0, y0, w, h)
  if geom ~= bgeom then
    border, bgeom = b, geom
    S.fills = S.fills + 1
    for i = 1, #b do if b:byte(i) < 16 then S.notamb = S.notamb + 1 end end
  elseif b ~= border then
    S.bordchg = S.bordchg + 1
    if #S.first < 8 then S.first[#S.first + 1] = string.format("tick %d border changed", tick) end
    border = b
  end
  if (sp:read_u8(LCDC + 0x40) & 7) ~= 3 or (sp:read_u16(LCDC + 0x42) | (sp:read_u8(LCDC + 0x44) << 16)) ~= 0x3ABFF
     or sp:read_u32(LCD_OWNED) ~= 1 then
    S.lcdc = S.lcdc + 1
    if S.lcdc <= 2 then
      print(string.format("awlcd8: tick %d: REG[040h] %02X, REG[042h]-[044h] %02X %02X %02X, owned %d", tick, sp:read_u8(LCDC + 0x40),
        sp:read_u8(LCDC + 0x42), sp:read_u8(LCDC + 0x43), sp:read_u8(LCDC + 0x44), sp:read_u32(LCD_OWNED)))
    end
  end
  if tick % SHOTS == 0 or DUMPAT[tick] then
    local pal = {}
    for i = 0, 15 do
      local v = sp:read_u16(PAL + 2 * i)
      pal[i] = argb4((v >> 12) & 15, (v >> 7) & 15, (v >> 1) & 15)
    end
    local amb = {}
    for i = 0, 239 do
      local v = sp:read_u16(AMB_LUT + 2 * i)
      amb[16 + i] = argb4((v >> 8) & 15, (v >> 4) & 15, v & 15)
    end
    pending = { tick = tick, frame = sp:read_u16(FRAME_NO), pix = pix, lcd = lcd, pal = pal, amb = amb, x0 = x0, y0 = y0, w = w, h = h, dump = DUMPAT[tick] }
  end
end
local function shot(p)
  if sp:read_u16(FRAME_NO) ~= p.frame then S.stale = (S.stale or 0) + 1; return end  -- the game went on before the screen was drawn
  local px, sw, sh = screen:pixels()
  if sw ~= 640 or sh ~= 240 then print(string.format("awlcd8: the screen is %dx%d", sw, sh)); return end
  S.shots = S.shots + 1
  local wbad, bbad, lit = 0, 0, 0
  for y = 0, 239 do
    for x = 0, 639 do
      local o = (y * 640 + x) * 4
      local got = string.unpack("<I4", px, o + 1)
      local want
      if x >= p.x0 and x < p.x0 + p.w and y >= p.y0 and y < p.y0 + p.h then
        want = p.pal[p.pix:byte((y - p.y0) * p.w + (x - p.x0) + 1) & 15]
        if got ~= want then wbad = wbad + 1 end
      else
        want = p.amb[p.lcd:byte(y * 640 + x + 1)]
        if want and got ~= want then bbad = bbad + 1 end
        if (got & 0xFFFFFF) ~= 0 then lit = lit + 1 end
      end
    end
  end
  if wbad + bbad > 0 then
    S.shotbad = S.shotbad + 1
    if #S.first < 8 then S.first[#S.first + 1] = string.format("tick %d screen: window %d, border %d pixels", p.tick, wbad, bbad) end
  end
  S.shotwin, S.shotbord, S.lit = S.shotwin + wbad, S.shotbord + bbad, S.lit + lit
  if p.dump then
    local f = io.open(string.format("%s/screen_%04d.bin", OUT, p.tick), "wb"); f:write(px); f:close()
  end
end

local lasttick, finish, nosplash = -1, false, false
AWL_TAP = sp:install_write_tap(FRAME_NO, FRAME_NO + 3, "awl8_frame", function(offset, data, mask)
  if finish or offset ~= FRAME_NO then return end
  local v = data & 0xffff
  if v == 0 then return end
  local tick = v - 1
  lasttick = tick
  check(tick)
  if tick >= MAXTICK then finish = true end
end)
AWL_FRAME = emu.add_machine_frame_notifier(function()
  if pending then local p = pending; pending = nil; shot(p) end
  if finish and not pending then
    local m = {}
    for k, v in pairs(S.modes) do m[#m + 1] = string.format("%dx: %d", k, v) end
    print(string.format("awlcd8: ticks 0-%d: %d checked (%s); window wrong at %d (%d pixels); border changed between fills %d times, %d fills, %d border bytes not ambilight entries; controller not as set %d times",
      lasttick, S.ticks, table.concat(m, ", "), S.winbad, S.winpx, S.bordchg, S.fills, S.notamb, S.lcdc))
    print(string.format("awlcd8: (%d samples dropped: the game's next tick came before MAME drew the screen)", S.stale or 0))
    print(string.format("awlcd8: the screen at %d ticks: %d with wrong pixels (window %d, border %d); border pixels lit %.1f%% on average%s",
      S.shots, S.shotbad, S.shotwin, S.shotbord, S.shots > 0 and S.lit / S.shots / (640 * 240) * 100 or 0,
      #S.first > 0 and ("; first: " .. table.concat(S.first, ", ")) or ""))
    M:exit()
  end
end)

local step = 1
AWL_TICK = emu.register_periodic(function()
  local t = M.time:as_double()
  local s = STEPS[step]
  if s and t > s[1] then press(s[2], s[3], 1); s.down = s.down or t end
  if s and s.down and t > s.down + 0.4 then press(s[2], s[3], 0); print("awlcd8: pressed " .. s[4]); step = step + 1 end
  if not nosplash and sp:read_u32(CV) >= 2 then sp:write_u32(NO_SPLASH, 0x5EED0FF0); nosplash = true end
  local pr = PRESSES[1]
  if pr and lasttick >= pr[1] then
    local mask = pr[2] == "UP" and 0x10 or 0x20
    if not pr.t then press("CPC_SEG11", mask, 1); pr.t = t
    elseif t > pr.t + 0.3 then press("CPC_SEG11", mask, 0); print(string.format("awlcd8: PAGE %s at tick %d", pr[2], lasttick)); table.remove(PRESSES, 1) end
  end
end)
