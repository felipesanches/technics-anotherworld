-- sndstate.lua -- AW.CNV's sound state every SS_PERIOD s (SNDSTATE: SND_READY, MUS_MOD, the slots), and every
-- read of a PLAY_SOUND operand byte by CNV_SND_PLAY's first read (+4, the channel): SNDPLAY lines with the operands
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then S[n] = tonumber(v, 16) end end
local P, nxt = tonumber(os.getenv("SS_PERIOD")) or 10, tonumber(os.getenv("SS_FROM")) or 35
_G.SS = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if t < nxt then return end
	nxt = t + P
	local sl = ""
	for i = 0, 7 do sl = sl .. string.format(" %02x:%02x", mem:read_u8(S.SND_SLOTS + 4 * i), mem:read_u8(S.SND_SLOTS + 4 * i + 1)) end
	emu.print_error(string.format("SNDSTATE t=%.1f ready=%d mus=%d loaded=%04x vmpc=%04x%s", t, mem:read_u8(S.SND_READY),
		mem:read_u8(S.MUS_MOD), mem:read_u16(S.MUS_LOADED), mem:read_u16(S.VM_PC), sl))
end)
