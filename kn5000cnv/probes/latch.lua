-- latch.lua -- every byte the main CPU writes to the inter-CPU latch (0x140000) from LT_FROM s: LATCH lines with
-- time, byte and PC; and every MIDI byte the main CPU receives on SC0 (SC0BUF 0xD0 reads) as MIDIRX lines
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("LT_FROM")) or 30
_G.LT = {}
_G.LT.t1 = mem:install_write_tap(0x140000, 0x140001, "latch", function(off, data, mask)
	local t = mac.time:as_double()
	if t < FROM then return end
	local b = (mask & 0xff) ~= 0 and (data & 0xff) or ((data >> 8) & 0xff)
	emu.print_error(string.format("LATCH %.4f %02x pc=%06x", t, b, cpu.state["PC"].value))
end)
_G.LT.t2 = mem:install_read_tap(0xd0, 0xd1, "sc0rx", function(off, data, mask)
	local t = mac.time:as_double()
	if t < FROM or (mask & 0xff) == 0 then return end
	emu.print_error(string.format("MIDIRX %.4f %02x pc=%06x", t, data & 0xff, cpu.state["PC"].value))
end)
