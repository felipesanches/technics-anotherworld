-- frametime.lua -- one FT line per VM frame pause (the write to FRAME_OVERRAN, one byte, right after LAST_FRAME_TICKS)
-- from FT_FROM to FT_TO s: the VM part, the pause the script asked for (var 0xFF, slices of 20 ms), the 488 Hz
-- ticks the pause counted, whether the frame overran, and the emulated time since the previous pause in ms.
-- tools/ftsum.py summarises them.
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then S[n] = tonumber(v, 16) end end
local A, B = tonumber(os.getenv("FT_FROM")) or 0, tonumber(os.getenv("FT_TO")) or 1e9
local function r16(a) return mem:read_u8(a) | (mem:read_u8(a + 1) << 8) end
_G.FT = { last = nil }
_G.FT.tap = mem:install_write_tap(S.FRAME_OVERRAN & ~1, S.FRAME_OVERRAN | 1, "frametime", function(off, data, mask)
	local t = mac.time:as_double()
	if t < A or t > B then return end
	if (mask >> (8 * (S.FRAME_OVERRAN - off))) & 0xff == 0 then return end	-- the other byte of the word
	local dt = _G.FT.last and (t - _G.FT.last) * 1000 or 0
	_G.FT.last = t
	local sh = 8 * (S.FRAME_OVERRAN - off)
	emu.print_error(string.format("FT t=%.3f part=%04x slices=%d ticks=%d overran=%d dt=%.1f", t,
		mem:read_u16(S.CURRENT_PART_ID), r16(S.VM_VARIABLES + 2 * 0xff), r16(S.LAST_FRAME_TICKS),
		(data >> sh) & 0xff, dt))
end)
