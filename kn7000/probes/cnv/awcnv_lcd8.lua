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
--   table    the look-up table as the controller holds it (a copy kept here from every write of REG[1E2h] and REG[1E4h],
--            as kn7000_mame and the S1D13506's specification take them: the entry, then red, green, blue, then the
--            next entry): entries 0-15 the palette last loaded (PF_PAL), 16-255 what the game last wrote to each
--            (AMB_LUT, but where that says unknown)
-- AWL_PRESS="T:UP,T:DOWN,..." presses PAGE UP or PAGE DOWN (0.3 s) once the game has reached tick T. AWL_DUMPAT="T,..":
-- the screen MAME draws, at the first moment after tick T when the game has shown nothing new for 3 of MAME's frames,
-- to AWL_OUT/screen_TTTT.bin (640 x 240 32-bit pixels), for the eye. (It is not compared: the screen a script reads,
-- screen_device::pixels, is the bitmap being drawn into next, a frame or two behind; comparing it, 4 of 145 samples
-- differed so on 2026-11-02, and up to 44 of 96 when waiting for a still display.) Prints "awlcd8: ..." lines.
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
local LCD8 = 0x502DAA00                              -- platformcnv.inc LCD8_VARS (vm.inc AMB_*, LCD_*)
local AMB_LUT, AMB_GEOM, LCD_OWNED = LCD8 + 0x60, LCD8 + 0x284, LCD8 + 0x288
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
-- the look-up table as the controller holds it: entry = r << 8 | g << 4 | b, 4 bits each
local LUT, lut_at, lut_part = {}, 0, 0
for i = 0, 255 do LUT[i] = 0 end
AWL_LUT = sp:install_write_tap(LCDC + 0x1E0, LCDC + 0x1E7, "awl8_lut", function(offset, data, mask)
  for lane = 0, 3 do
    if ((mask >> (8 * lane)) & 0xff) ~= 0 then
      local r, v = ((offset & ~3) + lane) & 0xfff, (data >> (8 * lane)) & 0xff
      if r == 0x1e2 then lut_at, lut_part = v, 0
      elseif r == 0x1e4 then
        local shift = 8 - 4 * lut_part
        LUT[lut_at] = (LUT[lut_at] & ~(15 << shift)) | ((v >> 4) << shift)
        lut_part = lut_part + 1
        if lut_part == 3 then lut_part = 0; lut_at = (lut_at + 1) & 255 end
      end
    end
  end
end)
local pending, lastsig, still = nil, -1, 0
-- blits, skipped blits and palettes loaded so far (vm.inc PF_BLITS, PF_SKIPS, PF_PAIR_N): what the game has shown
local function shown() return sp:read_u32(PERF + 0x38) + sp:read_u32(PERF + 0x3C) + sp:read_u32(PERF + 0x88) end
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
  local lbad = 0
  for i = 0, 15 do
    local v = sp:read_u16(PERF + 0x520 + 2 * i)
    if v ~= 0xFFFF and LUT[i] ~= (((v >> 12) & 15) << 8 | ((v >> 7) & 15) << 4 | ((v >> 1) & 15)) then lbad = lbad + 1 end
  end
  for i = 0, 239 do
    local v = sp:read_u16(AMB_LUT + 2 * i)
    if v ~= 0xFFFF and LUT[16 + i] ~= v then lbad = lbad + 1 end
  end
  if lbad > 0 then
    S.lutbad = (S.lutbad or 0) + 1
    if #S.first < 8 then S.first[#S.first + 1] = string.format("tick %d table: %d entries", tick, lbad) end
  end
  if DUMPAT[tick] then pending = { tick = tick } end
end
local function shot(req)
  local px = screen:pixels()
  local f = io.open(string.format("%s/screen_%04d.bin", OUT, req.tick), "wb"); f:write(px); f:close()
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
  -- a sample once nothing has been shown (no blit, skipped blit or palette loaded) for 3 of MAME's frames: the screen
  -- read then is surely one drawn after the last change (the one a frame notifier reads may be a frame old)
  local sig = shown()
  if sig == lastsig then still = still + 1 else still = 0; lastsig = sig end
  if pending and still >= 3 then local p = pending; pending = nil; shot(p) end
  if finish and (not pending or still > 600) then
    local m = {}
    for k, v in pairs(S.modes) do m[#m + 1] = string.format("%dx: %d", k, v) end
    print(string.format("awlcd8: ticks 0-%d: %d checked (%s); window wrong at %d (%d pixels); border changed between fills %d times, %d fills, %d border bytes not ambilight entries; controller not as set %d times",
      lasttick, S.ticks, table.concat(m, ", "), S.winbad, S.winpx, S.bordchg, S.fills, S.notamb, S.lcdc))
    print(string.format("awlcd8: the look-up table not as the game set it at %d ticks%s", S.lutbad or 0,
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
