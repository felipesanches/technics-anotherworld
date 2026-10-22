-- songsame.lua -- copy DRAM 0xB0000-0xFDFFF at SS_T1 seconds and compare it at SS_T2 (SONGSAME line): the song
-- memory must be given back exactly as found, whichever empty state the firmware version leaves.
local mac = manager.machine
local mem = mac.devices[":maincpu"].spaces["program"]
local T1, T2 = tonumber(os.getenv("SS_T1")) or 32, tonumber(os.getenv("SS_T2")) or 60
_G.SS = {}
_G.SS.h = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if not _G.SS.copy and t >= T1 then
		_G.SS.copy = {}
		for a = 0xb0000, 0xfdfff do _G.SS.copy[a] = mem:read_u8(a) end
	elseif _G.SS.copy and not _G.SS.done and t >= T2 then
		_G.SS.done = true
		local bad, first, zero = 0, nil, 0
		for a = 0xb0000, 0xfdfff do
			if mem:read_u8(a) ~= _G.SS.copy[a] then bad = bad + 1; first = first or a end
			if _G.SS.copy[a] == 0 then zero = zero + 1 end
		end
		emu.print_error(string.format("SONGSAME t1=%.1f t2=%.1f differing=%d first=%s (zero bytes at t1: %d of %d)", T1, t,
			bad, first and string.format("%06x", first) or "-", zero, 0xfe000 - 0xb0000))
	end
end)
