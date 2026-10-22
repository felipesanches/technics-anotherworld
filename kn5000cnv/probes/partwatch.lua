-- partwatch.lua -- every PERIOD seconds: the VM's current part and PC (PARTWATCH lines), from SYM; for the
-- standalone ROM build and AW.CNV alike.
local mac = manager.machine
local mem = mac.devices[":maincpu"].spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM")) do
	local n, v = line:match("^(%S+) (%x+)$")
	if n then S[n] = tonumber(v, 16) end
end
local PERIOD = tonumber(os.getenv("PERIOD")) or 10
_G.PW = { next = tonumber(os.getenv("PW_FROM")) or 0 }
_G.PW.h = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if t < _G.PW.next then return end
	_G.PW.next = t + PERIOD
	emu.print_error(string.format("PARTWATCH t=%.1f part=%04x pc=%04x", t, mem:read_u16(S.CURRENT_PART_ID), mem:read_u16(S.VM_PC)))
end)
