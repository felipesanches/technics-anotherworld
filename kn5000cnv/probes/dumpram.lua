-- dumpram.lua -- at DUMP_T seconds write DRAM 0x80000-0xFFFFF to OUT_DIR/dram_hi.bin (and the boot
-- writers' PCs, per 4 KB block, as WRITER lines), then let seq.lua carry on.
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local T = tonumber(os.getenv("DUMP_T")) or 24
_G.DR = { pcs = {} }
_G.DR.tap = mem:install_write_tap(0x0b0000, 0x0fefff, "dr", function(off, data, mask)
	local k = string.format("%06x %06x", off & 0xff000, cpu.state["PC"].value)
	_G.DR.pcs[k] = (_G.DR.pcs[k] or 0) + 1
end)
_G.DR.h = emu.add_machine_frame_notifier(function()
	if _G.DR.done or mac.time:as_double() < T then return end
	_G.DR.done = true
	local f = io.open((os.getenv("OUT_DIR") or ".") .. "/dram_hi.bin", "wb")
	for a = 0x80000, 0xfffff, 4096 do
		local t = {}
		for i = 0, 4095 do t[#t + 1] = string.char(mem:read_u8(a + i)) end
		f:write(table.concat(t))
	end
	f:close()
	local ks = {}
	for k, _ in pairs(_G.DR.pcs) do ks[#ks + 1] = k end
	table.sort(ks)
	for _, k in ipairs(ks) do emu.print_error(string.format("WRITER %s %d", k, _G.DR.pcs[k])) end
end)
