-- qheaders.lua -- the distinct reply headers the VM's panel queries receive (CNV_Q_HEADER writes), with
-- counts, printed as QHEADER lines at QH_T seconds. Symbols from SYM.
local mac = manager.machine
local mem = mac.devices[":maincpu"].spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM")) do
	local n, v = line:match("^(%S+) (%x+)$")
	if n then S[n] = tonumber(v, 16) end
end
_G.QH = { c = {} }
local a = S.CNV_Q_HEADER
_G.QH.tap = mem:install_write_tap(a & ~3, a | 3, "qh", function(off, data, mask)
	local sh = (a - off) * 8		-- the byte's lane in this access (16-bit bus: off is even)
	if sh < 0 or sh > 24 or (mask >> sh) & 0xff == 0 then return end
	local h = (data >> sh) & 0xff
	_G.QH.c[h] = (_G.QH.c[h] or 0) + 1
end)
_G.QH.h = emu.add_machine_frame_notifier(function()
	if _G.QH.done or mac.time:as_double() < (tonumber(os.getenv("QH_T")) or 60) then return end
	_G.QH.done = true
	local ks = {}
	for k, _ in pairs(_G.QH.c) do ks[#ks + 1] = k end
	table.sort(ks)
	for _, k in ipairs(ks) do emu.print_error(string.format("QHEADER %02x %d", k, _G.QH.c[k])) end
end)
