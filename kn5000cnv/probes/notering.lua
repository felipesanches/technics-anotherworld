-- notering.lua -- the bytes written into a KN5000 sequencer ring (buffer X, 256 bytes; NR_X, default
-- 0x202CB, the keybed note ring), from NR_FROM seconds, as NOTERING lines with time and PC; and the
-- ring's indices every NR_PERIOD seconds (X-10, X-8 read indices, X-4 write index, X-2 free count).
-- With SYM set, also AW.CNV's CNV_NOTERING and its held-key map CNV_KEYS.
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local X = tonumber(os.getenv("NR_X") or "202cb", 16)
local S = {}
if os.getenv("SYM") then for line in io.lines(os.getenv("SYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then S[n] = tonumber(v, 16) end end end
local FROM, P = tonumber(os.getenv("NR_FROM")) or 24, tonumber(os.getenv("NR_PERIOD")) or 1
-- The index words sit at odd addresses (X = 0x202CB), so they are read a byte at a time.
local function r16(a) return mem:read_u8(a) | (mem:read_u8(a + 1) << 8) end
_G.NR = { n = 0, next = FROM }
_G.NR.tap = mem:install_write_tap(X & ~1, (X + 255) | 1, "notering", function(off, data, mask)
	local t = mac.time:as_double()
	if t < FROM or _G.NR.n > 300 then return end
	for lane = 0, 1 do
		local a = off + lane
		if a >= X and a < X + 256 and (mask >> (8 * lane)) & 0xff ~= 0 then
			_G.NR.n = _G.NR.n + 1
			emu.print_error(string.format("NOTERING %.4f [%02x]=%02x pc=%06x", t, a - X, (data >> (8 * lane)) & 0xff, cpu.state["PC"].value))
		end
	end
end)
_G.NR.h = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if t < _G.NR.next then return end
	_G.NR.next = t + P
	local extra = ""
	if S.CNV_NOTERING then
		extra = string.format(" cnv_ring=%06x keys=", mem:read_u32(S.CNV_NOTERING))
		for i = 0, 15 do extra = extra .. string.format("%02x", mem:read_u8(S.CNV_KEYS + i)) end
	end
	emu.print_error(string.format("NRIDX %.2f r10=%d r8=%d w=%d free=%d%s", t, r16(X - 10), r16(X - 8),
		r16(X - 4), r16(X - 2), extra))
end)
