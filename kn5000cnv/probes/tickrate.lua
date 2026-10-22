-- tickrate.lua -- the rate of the firmware's Timer 1 counter (32 bits at 0x0409, incremented by its
-- INTT1 handler in v5..v10): read it at T0 and T1 seconds, print TICKRATE ticks/s.
local mac = manager.machine
local mem = mac.devices[":maincpu"].spaces["program"]
local T0, T1 = tonumber(os.getenv("T0")) or 20, tonumber(os.getenv("T1")) or 30
_G.TR = {}
_G.TR.h = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if not _G.TR.a and t >= T0 then _G.TR.a = mem:read_u32(0x409); _G.TR.ta = t end
	if _G.TR.a and not _G.TR.done and t >= T1 then
		_G.TR.done = true
		local n = mem:read_u32(0x409) - _G.TR.a
		emu.print_error(string.format("TICKRATE %d ticks in %.3f s = %.1f /s", n, t - _G.TR.ta, n / (t - _G.TR.ta)))
	end
end)
