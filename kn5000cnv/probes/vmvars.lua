-- vmvars.lua -- the VM's input variables every VV_PERIOD seconds from VV_FROM (VMVARS lines):
-- 0xE5 up/down, 0xFB jump/down, 0xFC left/right, 0xFD direction mask, 0xFE action+mask, 0xFA action.
-- VM_VARIABLES from SYM; each variable is a 16-bit word at VM_VARIABLES + 2*index.
local mac = manager.machine
local mem = mac.devices[":maincpu"].spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM")) do
	local n, v = line:match("^(%S+) (%x+)$")
	if n then S[n] = tonumber(v, 16) end
end
local P = tonumber(os.getenv("VV_PERIOD")) or 0.5
_G.VV = { next = tonumber(os.getenv("VV_FROM")) or 40 }
local function v(i) local x = mem:read_u16(S.VM_VARIABLES + 2 * i); if x >= 0x8000 then x = x - 0x10000 end; return x end
_G.VV.h = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if t < _G.VV.next then return end
	_G.VV.next = t + P
	emu.print_error(string.format("VMVARS t=%.1f ud=%d jd=%d lr=%d mask=%02x actmask=%02x act=%d",
		t, v(0xE5), v(0xFB), v(0xFC), v(0xFD) & 0xff, v(0xFE) & 0xff, v(0xFA)))
end)
