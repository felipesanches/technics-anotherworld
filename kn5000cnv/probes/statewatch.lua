-- statewatch.lua -- every write to CNV_STATE (written once, on the first call) with time and PC, and any
-- machine reset (STATEWATCH lines). Symbols from SYM.
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM")) do
	local n, v = line:match("^(%S+) (%x+)$")
	if n then S[n] = tonumber(v, 16) end
end
_G.SW = { n = 0 }
_G.SW.tap = mem:install_write_tap(S.CNV_STATE & ~3, S.CNV_STATE | 3, "statewatch", function(off, data, mask)
	if _G.SW.n >= 10 then return end
	local sh = (S.CNV_STATE - off) * 8	-- the byte's lane in this access (16-bit bus: off is even)
	if sh < 0 or sh > 24 or (mask >> sh) & 0xff == 0 then return end
	_G.SW.n = _G.SW.n + 1
	emu.print_error(string.format("STATEWATCH t=%.4f write pc=%06x data=%02x part=%04x vmpc=%04x",
		mac.time:as_double(), cpu.state["PC"].value, (data >> sh) & 0xff, mem:read_u16(S.CURRENT_PART_ID), mem:read_u16(S.VM_PC)))
end)
_G.SW.r = emu.add_machine_reset_notifier(function()
	emu.print_error(string.format("STATEWATCH t=%.4f machine reset", mac.time:as_double()))
end)
