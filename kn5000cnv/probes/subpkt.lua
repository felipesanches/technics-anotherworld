-- subpkt.lua -- sub CPU -> main CPU packets: each header the INT0 handler keeps at 0x05E4 and each payload
-- byte the micro-DMA writes at 0x05E8.., from SP_FROM seconds (SUBPKT lines, up to 200).
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("SP_FROM")) or 24
_G.SP = { n = 0 }
local function on() return mac.time:as_double() >= FROM and _G.SP.n < 200 end
local function lanes(off, data, mask, lo, hi, tag)
	for lane = 0, 1 do
		local a = off + lane
		if a >= lo and a <= hi and (mask >> (8 * lane)) & 0xff ~= 0 then
			_G.SP.n = _G.SP.n + 1
			emu.print_error(string.format("SUBPKT %.5f %s [%04x]=%02x pc=%06x", mac.time:as_double(), tag, a, (data >> (8 * lane)) & 0xff, cpu.state["PC"].value))
		end
	end
end
_G.SP.h = mem:install_write_tap(0x05e4, 0x05e5, "subpkt_h", function(off, data, mask) if on() then lanes(off, data, mask, 0x5e4, 0x5e4, "HDR") end end)
_G.SP.p = mem:install_write_tap(0x05e8, 0x0607, "subpkt_p", function(off, data, mask) if on() then lanes(off, data, mask, 0x5e8, 0x607, "PAY") end end)
