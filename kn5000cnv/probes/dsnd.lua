-- dsnd.lua -- the DSP sound's streamer (src/awsub.asm) as the sub CPU sees it, every DS_PERIOD s (default 2) from
-- DS_FROM (default 30): DSND lines with the two trampolines it rewrites (INTT1 0x464, INTT5 0x478), its magic,
-- SUB_STATE (0 not set up, 1 running, 2 stopped), SUB_TICKS and its rate since the last line, and channel 0's
-- record (seq, vol, active, pos); and on the main CPU, the sub program's image where CNV_DSND_INSTALL reads the
-- INTT1 trampoline (0x800064) and, with MAINSYM = build/aw_cnv.sym, DSND_ON. SUBSYM = build/awsub.sym.
local mac = manager.machine
local mem = mac.devices[":subcpu"].spaces["program"]
local S = {}
for line in io.lines(os.getenv("SUBSYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then S[n] = tonumber(v, 16) end end
local mmem = mac.devices[":maincpu"].spaces["program"]
local M = {}
if os.getenv("MAINSYM") then
	for line in io.lines(os.getenv("MAINSYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then M[n] = tonumber(v, 16) end end
end
local P, nxt = tonumber(os.getenv("DS_PERIOD")) or 2, tonumber(os.getenv("DS_FROM")) or 30
local last_t, last_ticks = nil, nil
local function hex(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02x", mem:read_u8(a + i)) end
	return s
end
_G.DSND = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if t < nxt then return end
	nxt = t + P
	local ticks = mem:read_u32(S.SUB_TICKS)
	local rate = (last_t and ticks >= last_ticks) and (ticks - last_ticks) / (t - last_t) or 0
	last_t, last_ticks = t, ticks
	local ch = S.CH0
	local mi = ""
	for i = 0, 4 do mi = mi .. string.format("%02x", mmem:read_u8(0x800064 + i)) end
	if M.DSND_ON then mi = mi .. string.format(" dsnd_on=%d", mmem:read_u8(M.DSND_ON)) end
	emu.print_error(string.format("DSND t=%.1f intt1=%s intt5=%s magic=%s state=%d ticks=%d rate=%.0f/s ch0 seq=%d vol=%d act=%d pos=%06x main800064=%s",
		t, hex(0x464, 5), hex(0x478, 5), hex(S.SUB_BASE, 4), mem:read_u8(S.SUB_STATE), ticks, rate,
		mem:read_u8(ch), mem:read_u8(ch + 1), mem:read_u8(ch + 29), mem:read_u32(ch + 22) & 0xffffff, mi))
end)
