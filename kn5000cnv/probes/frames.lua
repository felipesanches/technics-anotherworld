-- frames.lua -- every frame from FR_FROM to FR_TO: the main CPU's PC (named by SYM), its stack pointer and the VM's PC
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local syms, S = {}, {}
for line in io.lines(os.getenv("SYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then syms[#syms + 1] = { tonumber(v, 16), n }; S[n] = tonumber(v, 16) end end
table.sort(syms, function(a, b) return a[1] < b[1] end)
local function name(pc)
	if pc < 0x80000 or pc >= 0xb0000 then return "(outside)" end
	local best
	for _, s in ipairs(syms) do if s[1] <= pc then best = s else break end end
	return best and string.format("%s+%x", best[2], pc - best[1]) or "?"
end
local A, B = tonumber(os.getenv("FR_FROM")), tonumber(os.getenv("FR_TO"))
_G.FR = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if t < A or t > B then return end
	local pc = cpu.state["PC"].value
	emu.print_error(string.format("FRAME t=%.3f pc=%06x %s xssp=%08x vmpc=%04x", t, pc, name(pc), cpu.state["XSSP"].value, mem:read_u16(S.VM_PC)))
end)
