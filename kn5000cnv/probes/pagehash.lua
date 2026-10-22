-- pagehash.lua -- a hash of every page the VM shows: at the first VRAM write of each UPDATE_DISPLAY copy
-- (0x1A0000 + 20*320), an FNV-1a hash of the 64,000 bytes at CUR_PAGE_PTR_2 (SYM), from PH_FROM to PH_TO s:
-- PAGEHASH lines, numbered. Two builds that draw alike give the same sequence once repeats are dropped
-- (tools/pagehash_cmp.py), whatever their speed.
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then S[n] = tonumber(v, 16) end end
local A, B = tonumber(os.getenv("PH_FROM")) or 0, tonumber(os.getenv("PH_TO")) or 1e9
local VADDR = 0x1a0000 + 20 * 320
_G.PH = { n = 0 }
_G.PH.tap = mem:install_write_tap(VADDR, VADDR + 1, "pagehash", function(off, data, mask)
	local t = mac.time:as_double()
	if t < A or t > B then return end
	local page = mem:read_u32(S.CUR_PAGE_PTR_2)
	local h = 0x811c9dc5
	for a = page, page + 63996, 4 do
		h = ((h ~ mem:read_u32(a)) * 0x01000193) & 0xffffffff
	end
	_G.PH.n = _G.PH.n + 1
	emu.print_error(string.format("PAGEHASH %d t=%.3f %08x", _G.PH.n, t, h))
end)
