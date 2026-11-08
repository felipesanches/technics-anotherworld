-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_areas.lua -- which display memory and which of ARENA5 / ARENA6 does the firmware write while the game runs as
-- a converter? (README-CNV.md, "The code wheel page": the zoomed page keeps its frame, the VM's pages and its packed
-- pictures in display memory, and its copy of the LCD in ARENA5 0x50123000-0x50147FFF and ARENA6 0x50175000-0x5017FFFF.)
-- A write tap over display memory (0x9CE00000-0x9CF3FFFF) and both arenas records every write by a PC outside the
-- converter's code (0x502B8000-0x502E7FFF), per 8 KB block of display memory and per arena, from the converter's
-- first call to the quit, through: the game's intro, the help screen's five pages (the code wheel page among them),
-- the TEMPO/PROGRAM wheel turned, the ten LCD soft buttons, PAGE DOWN (320x200) and back, HELP again, the quit (EXIT
-- held) and 10 s of the firmware's own screen after it. Run through run_perf.sh (a card with build/sdcard/):
--   probes/cnv/run_perf.sh ~/compartilhado/tmp/aw-codewheel-zoom/areas probes/cnv/awcnv_areas.lua
-- Prints "awar: ..." lines: the phase, and per block / arena the writes and the PCs that made them.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local CV = 0x502DF000
local CV_ENDED = CV + 0x30
local function log(s) print("awar: " .. s) end
local function now() return M.time:as_double() end
local function fmask(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(c, s) local t = now() + s; while now() < t do if c() then return true end; coroutine.yield() end; return c() end
local function press(tag, mask, hold) local f = fmask(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end
local phase = "boot"
local rec = {}        -- rec[phase][region] = { n = writes, pcs = { pc = n } }
local on = false
local function note(region, pc)
  local p = rec[phase] or {}; rec[phase] = p
  local r = p[region] or { n = 0, pcs = {} }; p[region] = r
  r.n = r.n + 1
  r.pcs[pc] = (r.pcs[pc] or 0) + 1
end
local function ours(pc) return pc >= 0x502B8000 and pc < 0x502E8000 end
AWAR_VRAM = sp:install_write_tap(0x9CE00000, 0x9CF3FFFF, "awar_vram", function(offset, data, mask)
  if not on then return end
  local pc = cpu.state["PC"].value
  if ours(pc) then return end
  note(string.format("vram %06X", (offset - 0x9CE00000) & ~0x1FFF), pc)
end)
AWAR_A5 = sp:install_write_tap(0x50123000, 0x50147FFF, "awar_a5", function(offset, data, mask)
  if not on then return end
  local pc = cpu.state["PC"].value
  if ours(pc) then return end
  note("ARENA5", pc)
end)
AWAR_A6 = sp:install_write_tap(0x50175000, 0x5017FFFF, "awar_a6", function(offset, data, mask)
  if not on then return end
  local pc = cpu.state["PC"].value
  if ours(pc) then return end
  note("ARENA6", pc)
end)
local knob
for _, f in pairs(M.ioport.ports[":TEMPO_KNOB"].fields) do knob = f end
local knobAt = 50
local function report()
  for _, ph in ipairs({ "game", "quit" }) do
    local p = rec[ph] or {}
    local keys = {}
    for k in pairs(p) do keys[#keys + 1] = k end
    table.sort(keys)
    log(string.format("phase %s: %d regions written by the firmware", ph, #keys))
    for _, k in ipairs(keys) do
      local pl = {}
      for pc, n in pairs(p[k].pcs) do pl[#pl + 1] = string.format("%08X:%d", pc, n) end
      table.sort(pl)
      log(string.format("  %s phase %s: %d writes, PCs %s", k, ph, p[k].n, table.concat(pl, " ", 1, math.min(#pl, 8))))
    end
  end
end
local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  phase = "game"; on = true
  press("CPR_SEG6", 0x01)             -- OK (KN7LOAD.CNV)
  wait_until(function() return sp:read_u32(CV) == 3 end, 120)
  wait(30)
  log("help screen")
  press("CPC_SEG5", 0x02); wait(1.5)  -- HELP
  for _ = 1, 4 do press("CPC_SEG11", 0x20); wait(1.5) end
  wait(3)
  for _ = 1, 3 do knobAt = (knobAt + 1) % 101; knob.user_value = knobAt; wait(1.0) end
  local keys = { { "CPL_SEG0", 0x02 }, { "CPL_SEG0", 0x08 }, { "CPL_SEG0", 0x20 }, { "CPL_SEG0", 0x01 }, { "CPL_SEG0", 0x04 },
    { "CPR_SEG5", 0x10 }, { "CPR_SEG5", 0x20 }, { "CPR_SEG7", 0x01 }, { "CPR_SEG6", 0x01 }, { "CPR_SEG5", 0x01 } }
  for _, k in ipairs(keys) do press(k[1], k[2], 0.3); wait(0.7) end
  press("CPC_SEG11", 0x10); wait(1.5) -- PAGE UP: the settings
  press("CPC_SEG11", 0x80); wait(3)   -- EXIT
  log("the game again, the soft buttons in play")
  for _, k in ipairs(keys) do press(k[1], k[2], 0.3); wait(0.7) end
  press("CPC_SEG11", 0x20); wait(3)   -- PAGE DOWN: 320x200
  press("CPC_SEG11", 0x10); wait(3)   -- PAGE UP: 384x240
  press("CPC_SEG5", 0x02); wait(1.5)
  press("CPC_SEG11", 0x80); wait(3)
  log("quit")
  phase = "quit"
  press("CPC_SEG11", 0x80, 2.0)       -- EXIT held
  wait_until(function() return sp:read_u32(CV_ENDED) == 1 end, 30)
  wait(10)
  on = false
  report()
  M:exit()
  while true do coroutine.yield() end
end)
AWAR_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awar: ERROR " .. tostring(err)); M:exit() end
  end
end)
