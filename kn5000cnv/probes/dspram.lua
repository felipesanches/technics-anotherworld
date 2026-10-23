-- dspram.lua -- IC311's I-RAM (384 words of 5 bytes) and C-RAM (256 cells) at each time in DR_AT (seconds, comma-
-- separated): DSPRAM lines with a hash of each and, from the second time on, every I-RAM word and C-RAM cell that
-- differs from the first time. Does leaving the DSP sound put IC311 back as it was?
local mac = manager.machine
local dsp = mac.devices[":dsp1"]
local sp = {}
for name, s in pairs(dsp.spaces) do sp[name] = s end
local times = {}
for t in string.gmatch(os.getenv("DR_AT") or "", "[^,]+") do times[#times + 1] = tonumber(t) end
local function snap()
	local i, c = {}, {}
	local ip, cp = sp["iram"], sp["cram"]
	for a = 0, 384 * 5 - 1 do i[a] = ip:read_u8(a) end
	for a = 0, 255 do c[a] = cp:read_u32(a) & 0xffffff end
	return i, c
end
local first, k = nil, 1
_G.DSPRAM = emu.add_machine_frame_notifier(function()
	if k > #times or mac.time:as_double() < times[k] then return end
	local i, c = snap()
	local hi, hc = 0, 0
	for a = 0, 384 * 5 - 1 do hi = (hi * 31 + i[a]) % 4294967291 end
	for a = 0, 255 do hc = (hc * 31 + c[a]) % 4294967291 end
	emu.print_error(string.format("DSPRAM t=%.1f iram=%08x cram=%08x", mac.time:as_double(), hi, hc))
	if first then
		local nw, nc = 0, 0
		for w = 0, 383 do
			local d = false
			for b = 0, 4 do if i[w * 5 + b] ~= first[1][w * 5 + b] then d = true end end
			if d then nw = nw + 1; if nw <= 12 then emu.print_error(string.format("DSPRAM   iram %3d differs: %010x", w, (function() local v = 0; for b = 0, 4 do v = v * 256 + i[w * 5 + b] end; return v end)())) end end
		end
		for a = 0, 255 do if c[a] ~= first[2][a] then nc = nc + 1; if nc <= 12 then
			emu.print_error(string.format("DSPRAM   cram %02x %06x -> %06x", a, first[2][a], c[a])) end end end
		emu.print_error(string.format("DSPRAM   %d I-RAM words and %d C-RAM cells differ from t=%.1f", nw, nc, times[1]))
	else
		first = { i, c }
	end
	k = k + 1
end)
