-- seq.lua -- drive the KN5000 panel on a timed schedule; snapshot; report the converter's state.
--
-- SEQ (environment) is a list of "time:action" separated by ';'. Actions:
--   a button name below, held for 0.3 s, or NAME*SECONDS to hold it longer (EXIT*4); holds
--   overlap and do not delay later steps, which run in time order;
--   "snap" (a screenshot), "quit".
-- Example: SEQ="40:DISK;42:snap;44:R3;46:snap;50:EXIT*4;60:quit"
-- At every snap and at quit it prints a CNV line: the converter signature at 0xA0000 (hello.asm
-- writes "CNV5"), its call count at 0xA0004, the mailbox byte at 0xFFC00 and the current title
-- (DRAM 0x8D36, CURRENT_TITLE in the v7 disassembly).

local mac = manager.machine
local mem = mac.devices[":maincpu"].spaces["program"]
local function log(s) emu.print_error(s) end

local BUTTONS = {
	DISK = { "CPR_SEG10", 0x20 },
	L1 = { "CPL_SEG10", 0x02 }, L2 = { "CPL_SEG10", 0x01 },
	L3 = { "CPL_SEG9", 0x04 }, L4 = { "CPL_SEG9", 0x02 }, L5 = { "CPL_SEG9", 0x01 },
	R1 = { "CPL_SEG8", 0x04 }, R2 = { "CPL_SEG8", 0x02 }, R3 = { "CPL_SEG8", 0x01 },
	R4 = { "CPL_SEG7", 0x02 }, R5 = { "CPL_SEG7", 0x01 },
	EXIT = { "CPL_SEG7", 0x08 }, HELP = { "CPL_SEG10", 0x04 }, SPLIT = { "CPL_SEG4", 0x20 },
	-- Another World's controls (kn5000-docs another-world-vm.md)
	UP = { "CPR_SEG4", 0x02 }, LEFT = { "CPR_SEG4", 0x10 }, DOWN = { "CPR_SEG4", 0x20 },
	RIGHT = { "CPR_SEG4", 0x40 }, ACTION = { "CPL_SEG4", 0x08 },
}
local function field(tag, mask)
	local p = mac.ioport.ports[":cpanel:" .. tag] or mac.ioport.ports[":" .. tag]
	if not p then return nil end
	for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end

local steps = {}
for item in string.gmatch(os.getenv("SEQ") or "", "[^;]+") do
	local t, a = item:match("^%s*([%d%.]+)%s*:%s*(%S+)%s*$")
	if t then steps[#steps + 1] = { t = tonumber(t), a = a, k = #steps } end
end
table.sort(steps, function(x, y) if x.t ~= y.t then return x.t < y.t end return x.k < y.k end)

local function report(tag)
	local sig = ""
	for i = 0, 3 do
		local c = mem:read_u8(0xa0000 + i)
		sig = sig .. ((c >= 32 and c < 127) and string.char(c) or ".")
	end
	log(string.format("CNV %s t=%.2f sig=%s calls=%d mailbox=%02x title=%02x", tag, mac.time:as_double(),
		sig, mem:read_u32(0xa0004), mem:read_u8(0xffc00), mem:read_u16(0x8d36)))
end

_G.SQ = { i = 1, held = {} }
_G.SQ.h = emu.add_machine_frame_notifier(function()
	local S, t = _G.SQ, mac.time:as_double()
	for f, until_t in pairs(S.held) do
		if t >= until_t then f:set_value(0); S.held[f] = nil end
	end
	while true do
		local st = steps[S.i]
		if not st or t < st.t then return end
		S.i = S.i + 1
		if st.a == "snap" then
			mac.video:snapshot(); report("snap")
		elseif st.a == "quit" then
			report("quit"); mac:exit(); return
		else
			local name, secs = st.a:match("^(%w+)%*([%d%.]+)$")
			name = name or st.a
			local b = BUTTONS[name]
			local f = b and field(b[1], b[2])
			if not f then
				log("SEQ unknown button " .. st.a)
			else
				f:set_value(1); S.held[f] = t + (tonumber(secs) or 0.3)
				log(string.format("SEQ %.2f press %s", t, st.a))
			end
		end
	end
end)
