-- foreign.lua -- writes into AW.CNV's RAM (0x80000..VIDEO1_END) and its song-memory buffers (0xB0000..SCREEN_END)
-- from code outside AW.CNV (PC not in 0x80000..CNV_IMAGE_END), from FW_FROM s: FOREIGN lines, up to FW_MAX.
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then S[n] = tonumber(v, 16) end end
local FROM, MAX = tonumber(os.getenv("FW_FROM")) or 64, tonumber(os.getenv("FW_MAX")) or 40
_G.FW = { n = 0 }
local function tap(off, data, mask)
	if mac.time:as_double() < FROM or _G.FW.n >= MAX then return end
	local pc = cpu.state["PC"].value
	if pc >= 0x80000 and pc < S.CNV_IMAGE_END then return end
	_G.FW.n = _G.FW.n + 1
	emu.print_error(string.format("FOREIGN t=%.4f pc=%06x off=%06x data=%08x mask=%08x vmpc=%04x",
		mac.time:as_double(), pc, off, data, mask, mem:read_u16(S.VM_PC)))
end
_G.FW.t1 = mem:install_write_tap(0x80000, S.VIDEO1_END | 3, "foreign1", tap)
_G.FW.t2 = mem:install_write_tap(0xb0000, S.SCREEN_END | 3, "foreign2", tap)
