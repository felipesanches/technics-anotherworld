-- bcread.lua -- every read of the part's bytecode (BYTECODE_BUF..+0x8000) from BC_FROM to BC_TO s: BC lines (offset, byte), up to BC_MAX
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then S[n] = tonumber(v, 16) end end
local A, B, MAX = tonumber(os.getenv("BC_FROM")), tonumber(os.getenv("BC_TO")), tonumber(os.getenv("BC_MAX")) or 3000
local base = S.BYTECODE_BUF
_G.BC = { n = 0 }
_G.BC.tap = mem:install_read_tap(base, base + 0x7fff, "bcread", function(off, data, mask)
	local t = mac.time:as_double()
	if t < A or t > B or _G.BC.n >= MAX then return end
	for lane = 0, 3 do
		if (mask >> (8 * lane)) & 0xff ~= 0 then
			_G.BC.n = _G.BC.n + 1
			emu.print_error(string.format("BC %.5f %04x %02x", t, off + lane - base, (data >> (8 * lane)) & 0xff))
		end
	end
end)
