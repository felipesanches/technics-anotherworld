-- awstate.lua -- report AW.CNV's state every PERIOD seconds (AWSTATE lines): the converter's state byte,
-- the part loaded and running, the last file read, the VM's PC, the firmware version the converter
-- matched, the mailbox byte. Symbols come from SYM (build/aw_cnv.sym, tools/lst2sym.py).
local mac = manager.machine
local mem = mac.devices[":maincpu"].spaces["program"]
local S = {}
for line in io.lines(os.getenv("SYM") or "build/aw_cnv.sym") do
	local n, v = line:match("^(%S+) (%x+)$")
	if n then S[n] = tonumber(v, 16) end
end
local PERIOD = tonumber(os.getenv("PERIOD")) or 2
_G.AS = { next = tonumber(os.getenv("AS_FROM")) or 30 }
_G.AS.h = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if t < _G.AS.next then return end
	_G.AS.next = t + PERIOD
	emu.print_error(string.format(
		"AWSTATE t=%.1f state=%d loaded=%04x part=%04x cur_id=%02x read=%d pc=%04x fw_open=%06x exit=%d text=%06x mailbox=%02x title=%02x",
		t, mem:read_u8(S.CNV_STATE), mem:read_u16(S.CNV_LOADED_PART), mem:read_u16(S.CURRENT_PART_ID),
		mem:read_u8(S.CNV_CUR_ID), mem:read_u32(S.CNV_LAST_READ), mem:read_u16(S.VM_PC),
		mem:read_u32(S.CNV_FW_OPEN), mem:read_u8(S.CNV_EXIT_COUNT), mem:read_u32(S.CNV_EXIT_TEXT),
		mem:read_u8(0xffc00), mem:read_u8(0x8d36)) .. string.format(" reply=%08x", S.CNV_DBG_REPLY and mem:read_u32(S.CNV_DBG_REPLY) or 0))
end)
