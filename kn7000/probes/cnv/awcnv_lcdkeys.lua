-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_lcdkeys.lua -- the ten LCD soft buttons while the game runs as a converter (README-CNV.md, "The code wheel
-- page"): where does each show in the firmware's debounced button bitmap (0x5006BE40-0x5006BEBF), what frame does it
-- put into the panel's receive ring (the 92-byte ring whose read index fwfind.s finds, WH_RXRD), and does the firmware
-- do anything with it on the converter's screen? For each button: a baseline window of WIN seconds with nothing pressed,
-- then the button held 0.3 s and WIN seconds in all; every write in the firmware's RAM (0x50000000-0x5017FFFF, the user
-- pools 0x50180000-0x50297FFF), IC23 (CS1, both views, its first 256 KB) and display memory (0x9CE00000-0x9CF3FFFF) by a
-- PC outside the converter's code is recorded in both windows; a written address (by PC) seen only in the press window,
-- and in no baseline window of any button, is the firmware's reaction ("react"). Run through run_perf.sh (a card with
-- build/sdcard/), program 893 by default:
--   probes/cnv/run_perf.sh ~/compartilhado/tmp/aw-codewheel-zoom/lcdkeys probes/cnv/awcnv_lcdkeys.lua
-- Prints "awlk: ..." lines: per button the bitmap bits that went 1, the ring frames, and the reaction writes.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local WIN = 1.2
local CV = 0x502DF000
local CV_CALLS, CV_ENDED = CV + 0x10, CV + 0x30
local WV = 0x502DFA00
local function log(s) print("awlk: " .. s) end
local function now() return M.time:as_double() end
local function field(tag, name)
  local p = M.ioport.ports[":cpanel:" .. tag]
  for _, f in pairs(p.fields) do if f.name == name then return f end end
  error("no field " .. tag .. " " .. name)
end
local function fmask(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local KEYS = {
  { "LCDL 1", "CPL_SEG0", "LCDL 1 (SW1)" }, { "LCDL 2", "CPL_SEG0", "LCDL 2 (SW3)" }, { "LCDL 3", "CPL_SEG0", "LCDL 3 (SW5)" },
  { "LCDL 4", "CPL_SEG0", "LCDL 4 (SW0)" }, { "LCDL 5", "CPL_SEG0", "LCDL 5 (SW2)" },
  { "LCDR 1", "CPR_SEG5", "LCDR 1 (SW4)" }, { "LCDR 2", "CPR_SEG5", "LCDR 2 (SW5)" }, { "LCDR 3", "CPR_SEG7", "LCDR 3 (SW0)" },
  { "LCDR 4", "CPR_SEG6", "LCDR 4 (SW0)" }, { "LCDR 5", "CPR_SEG5", "LCDR 5 (SW0)" } }
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(c, s) local t = now() + s; while now() < t do if c() then return true end; coroutine.yield() end; return c() end
local function press(tag, mask, hold) local f = fmask(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end
-- the recording: written[key] = count, key = "pc addr"
local rec = nil
local function ours(pc) return pc >= 0x502B8000 and pc < 0x502E8000 end
local function tap(lo, hi, name)
  return sp:install_write_tap(lo, hi, name, function(offset, data, mask)
    if not rec then return end
    local pc = cpu.state["PC"].value
    if ours(pc) then return end
    local k = string.format("%08X %08X", pc, offset)
    rec[k] = (rec[k] or 0) + 1
  end)
end
local taps = {}
-- the ring's frames: every byte written into the ring while recording (the panel's receive interrupt)
local ringlog = nil
local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  press("CPR_SEG6", 0x01)             -- OK (KN7LOAD.CNV)
  wait_until(function() return sp:read_u32(CV) == 3 end, 120)
  wait(25)                            -- the game running (the intro)
  local rxrd = sp:read_u32(WV)
  log(string.format("the panel's ring: read index at %08X; converter calls so far %d", rxrd, sp:read_u32(CV_CALLS)))
  if rxrd ~= 0 then
    taps[#taps + 1] = sp:install_write_tap(rxrd + 4, rxrd + 4 + 0x5B, "awlk_ring", function(offset, data, mask)
      if not ringlog then return end
      local b = offset & 3
      for i = 0, 3 do if (mask >> (8 * i)) & 0xFF ~= 0 then ringlog[#ringlog + 1] = string.format("%02X", (data >> (8 * i)) & 0xFF) end end
    end)
  end
  taps[#taps + 1] = tap(0x50000000, 0x5017FFFF, "awlk_fw")
  taps[#taps + 1] = tap(0x50180000, 0x50297FFF, "awlk_pools")
  taps[#taps + 1] = tap(0x44000000, 0x4403FFFF, "awlk_ic23")
  taps[#taps + 1] = tap(0x84000000, 0x8403FFFF, "awlk_ic23u")
  taps[#taps + 1] = tap(0x9CE00000, 0x9CF3FFFF, "awlk_vram")
  local base_all, results = {}, {}
  for _, k in ipairs(KEYS) do
    rec = {}
    wait(WIN)
    for a, n in pairs(rec) do base_all[a] = true end
    local bm0 = sp:read_range(0x5006BE40, 0x5006BEBF, 8)
    local calls0 = sp:read_u32(CV_CALLS)
    rec, ringlog = {}, {}
    local f = field(k[2], k[3])
    f:set_value(1); wait(0.3)
    local bm1 = sp:read_range(0x5006BE40, 0x5006BEBF, 8)
    f:set_value(0); wait(WIN - 0.3)
    local bits = {}
    for i = 1, #bm1 do
      local a, b = bm0:byte(i), bm1:byte(i)
      if a ~= b then bits[#bits + 1] = string.format("%08X:%02X->%02X", 0x5006BE40 + i - 1, a, b) end
    end
    results[#results + 1] = { k[1], rec, table.concat(bits, " "), table.concat(ringlog, " "), sp:read_u32(CV_CALLS) - calls0 }
    rec, ringlog = nil, nil
  end
  rec = {}
  wait(WIN)                           -- one more baseline, after the last button
  for a in pairs(rec) do base_all[a] = true end
  rec = nil
  for _, r in ipairs(results) do
    local react, pcs = {}, {}
    for a, n in pairs(r[2]) do
      if not base_all[a] then react[#react + 1] = a .. "x" .. n; pcs[a:sub(1, 8)] = (pcs[a:sub(1, 8)] or 0) + 1 end
    end
    table.sort(react)
    local pl = {}
    for p, n in pairs(pcs) do pl[#pl + 1] = p .. ":" .. n end
    table.sort(pl)
    log(string.format("%s: bitmap %s; ring bytes written [%s]; converter calls in the window %d; writes seen only now: %d at %d PCs %s",
      r[1], r[3] ~= "" and r[3] or "(none)", r[4], r[5], #react, #pl, table.concat(pl, " ")))
    for i = 1, math.min(#react, 40) do log("   " .. r[1] .. " " .. react[i]) end
  end
  log(string.format("game still running: state %d, ended %d, calls %d", sp:read_u32(CV), sp:read_u32(CV_ENDED), sp:read_u32(CV_CALLS)))
  M:exit()
  while true do coroutine.yield() end
end)
AWLK_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awlk: ERROR " .. tostring(err)); M:exit() end
  end
end)
