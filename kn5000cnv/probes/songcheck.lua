-- songcheck.lua -- at each time in SONG_T (comma list), compare DRAM 0xB0000-0xFDFFF with the state the
-- KN5000 firmware leaves its song memory in with no song (the model in src/cnv_platform.asm, measured
-- on a booted v10 in kn5000cnv/README.md). Prints SONGCHECK t= bad_bytes= first_bad=.
local mac = manager.machine
local mem = mac.devices[":maincpu"].spaces["program"]
local times = {}
for t in string.gmatch(os.getenv("SONG_T") or "30", "[^,]+") do times[#times + 1] = tonumber(t) end
local function expected(addr)
	if addr >= 0xfd800 then return 0 end
	local n = ((addr - 0xb0000) >> 8) + 1
	local o = (addr - 0xb0000) & 0xff
	local prev = (n <= 3) and 0 or (n - 1)
	local nxt = (n <= 2 or n == 0x4d8) and 0xffff or (n + 1)
	if o == 0 then return (n <= 2) and 0x80 or 0 end
	if o == 1 then return prev & 0xff end
	if o == 2 then return prev >> 8 end
	if o == 3 then return nxt & 0xff end
	if o == 4 then return nxt >> 8 end
	if o == 5 then return 0x82 end
	return 0
end
_G.SC = { i = 1 }
_G.SC.h = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	local due = times[_G.SC.i]
	if not due or t < due then return end
	_G.SC.i = _G.SC.i + 1
	local bad, first = 0, nil
	for a = 0xb0000, 0xfdfff do
		if mem:read_u8(a) ~= expected(a) then bad = bad + 1; first = first or a end
	end
	emu.print_error(string.format("SONGCHECK t=%.1f bad_bytes=%d first_bad=%s", t, bad, first and string.format("%06x", first) or "-"))
end)
