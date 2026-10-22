-- clobber.lua -- who writes AW.CNV's own variables (CNV_STATE .. CNV_DBG_REPLY+3) from code outside
-- cnv_platform.asm (CNV_CALL .. CNV_IMAGE_END)? Logs the first CLOBBER_MAX such writes with time, PC,
-- address and data, and the VM's part and PC at that moment. Symbols from SYM.
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM")) do
	local n, v = line:match("^(%S+) (%x+)$")
	if n then S[n] = tonumber(v, 16) end
end
local lo, hi = S.CNV_STATE, S.CNV_DBG_REPLY + 3
local MAX = tonumber(os.getenv("CLOBBER_MAX")) or 20
_G.CL = { n = 0 }
_G.CL.tap = mem:install_write_tap(lo & ~3, hi | 3, "clobber", function(off, data, mask)
	local pc = cpu.state["PC"].value
	if pc >= S.CNV_CALL and pc < S.CNV_IMAGE_END then return end
	if _G.CL.n >= MAX then return end
	_G.CL.n = _G.CL.n + 1
	emu.print_error(string.format("CLOBBER t=%.4f pc=%06x off=%06x data=%08x mask=%08x xsp=%08x part=%04x vmpc=%04x",
		mac.time:as_double(), pc, off, data, mask, cpu.state["XSSP"].value,
		mem:read_u16(S.CURRENT_PART_ID), mem:read_u16(S.VM_PC)))
end)
