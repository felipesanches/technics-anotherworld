-- subdump.lua -- the sub CPU's DRAM from SD_FROM to SD_TO (hex) written to the file SD_FILE at SD_AT seconds:
-- with tools/sbank_check.py, is a part's sound bank in the sub CPU what tools/aw_sbank.py says it should be?
local mac = manager.machine
local mem = mac.devices[":subcpu"].spaces["program"]
local at, a0, a1, path = tonumber(os.getenv("SD_AT")), tonumber(os.getenv("SD_FROM"), 16), tonumber(os.getenv("SD_TO"), 16),
	os.getenv("SD_FILE")
local done = false
_G.SUBDUMP = emu.add_machine_frame_notifier(function()
	if done or mac.time:as_double() < at then return end
	done = true
	local f = io.open(path, "wb")
	local t = {}
	for a = a0, a1 - 1 do t[#t + 1] = string.char(mem:read_u8(a)) end
	f:write(table.concat(t))
	f:close()
	emu.print_error(string.format("SUBDUMP t=%.1f %06x..%06x -> %s", mac.time:as_double(), a0, a1, path))
end)
