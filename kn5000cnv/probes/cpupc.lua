-- cpupc.lua -- the main CPU's PC every PC_PERIOD s from PC_FROM, named by the nearest AW.CNV symbol (SYM): where is it stuck?
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local syms = {}
for line in io.lines(os.getenv("SYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then syms[#syms + 1] = { tonumber(v, 16), n } end end
table.sort(syms, function(a, b) return a[1] < b[1] end)
local function name(pc)
	local best
	for _, s in ipairs(syms) do if s[1] <= pc then best = s else break end end
	if best and pc - best[1] < 0x2000 then return string.format("%s+%x", best[2], pc - best[1]) end
	return "?"
end
local P, nxt = tonumber(os.getenv("PC_PERIOD")) or 1, tonumber(os.getenv("PC_FROM")) or 60
_G.CP = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if t < nxt then return end
	nxt = t + P
	local pc = cpu.state["PC"].value
	emu.print_error(string.format("CPUPC t=%.1f pc=%06x %s", t, pc, (pc >= 0x80000 and pc < 0xb0000) and name(pc) or "(firmware)"))
end)
