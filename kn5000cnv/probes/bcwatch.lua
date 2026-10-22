-- bcwatch.lua -- the part's bytecode in RAM against its file (BC_FILE): at BW_CHECK times (comma list) print the
-- differing offsets (BCDIFF); and, when BW_HI is set, every write to BYTECODE_BUF+BW_LO..BW_HI (hex) after
-- BW_FROM s with PC (BCWRITE)
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S, syms = {}, {}
for line in io.lines(os.getenv("SYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then S[n] = tonumber(v, 16); syms[#syms + 1] = { tonumber(v, 16), n } end end
table.sort(syms, function(a, b) return a[1] < b[1] end)
local function name(pc)
	if pc < 0x80000 or pc >= 0xb0000 then return "(outside)" end
	local best
	for _, s in ipairs(syms) do if s[1] <= pc then best = s else break end end
	return best and string.format("%s+%x", best[2], pc - best[1]) or "?"
end
local f = io.open(os.getenv("BC_FILE"), "rb"); local file = f:read("*a"); f:close()
local base = S.BYTECODE_BUF
local checks = {}
for t in string.gmatch(os.getenv("BW_CHECK") or "", "[^,]+") do checks[#checks + 1] = tonumber(t) end
local ci = 1
_G.BW = { n = 0 }
_G.BW.h = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if not checks[ci] or t < checks[ci] then return end
	ci = ci + 1
	local diffs, first = 0, nil
	for i = 1, #file do
		if mem:read_u8(base + i - 1) ~= file:byte(i) then diffs = diffs + 1; first = first or (i - 1) end
	end
	emu.print_error(string.format("BCDIFF t=%.2f differing=%d first=%s", t, diffs, first and string.format("%04x", first) or "-"))
end)
if not os.getenv("BW_HI") then return end	-- no write watch, only the BW_CHECK comparisons
local LO, HI, FROM = tonumber(os.getenv("BW_LO"), 16), tonumber(os.getenv("BW_HI"), 16) | 1, tonumber(os.getenv("BW_FROM")) or 0
_G.BW.tap = mem:install_write_tap(base + LO, base + HI, "bcwatch", function(off, data, mask)
	if mac.time:as_double() < FROM or _G.BW.n >= 60 then return end
	_G.BW.n = _G.BW.n + 1
	local pc = cpu.state["PC"].value
	emu.print_error(string.format("BCWRITE t=%.5f off=%04x data=%08x mask=%08x pc=%06x %s xssp=%08x vmpc=%04x", mac.time:as_double(),
		off - base, data, mask, pc, name(pc), cpu.state["XSSP"].value, mem:read_u16(S.VM_PC)))
end)
