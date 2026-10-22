-- ramuse.lua -- which 4 KB blocks of DRAM 0x80000-0xFFFFF and VRAM 0x1A0000-0x1DFFFF does the KN5000
-- firmware write, by phase? Phases: boot (t < P1), menus (P1..P2), converter (t >= P2, after OK).
-- Writes whose PC is inside the converter (0x80000-0xAFFFF) are counted as "cnv", not firmware.
-- Prints RAMUSE lines at QUIT seconds: phase, block, writes. Run with seq.lua's SEQ for the presses.
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local P1 = tonumber(os.getenv("P1")) or 25
local P2 = tonumber(os.getenv("P2")) or 33.5
local QUIT = tonumber(os.getenv("QUIT")) or 48
_G.RU = { c = {} }
local function bump(off)
	local t = mac.time:as_double()
	local pc = cpu.state["PC"].value
	local ph = (pc >= 0x80000 and pc < 0xb0000) and "cnv" or (t < P1 and "boot" or (t < P2 and "menu" or "conv"))
	local k = ph .. string.format(" %06x", off & 0xfff000)
	_G.RU.c[k] = (_G.RU.c[k] or 0) + 1
end
_G.RU.t1 = mem:install_write_tap(0x080000, 0x0fffff, "ru_dram", function(off, data, mask) bump(off) end)
_G.RU.t2 = mem:install_write_tap(0x1a0000, 0x1dffff, "ru_vram", function(off, data, mask) bump(off) end)
_G.RU.h = emu.add_machine_frame_notifier(function()
	if _G.RU.done or mac.time:as_double() < QUIT then return end
	_G.RU.done = true
	local ks = {}
	for k, _ in pairs(_G.RU.c) do ks[#ks + 1] = k end
	table.sort(ks)
	for _, k in ipairs(ks) do emu.print_error(string.format("RAMUSE %s %d", k, _G.RU.c[k])) end
end)
