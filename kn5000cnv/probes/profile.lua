-- profile.lua -- PC samples of the main CPU, one per video frame from PF_FROM to PF_TO s, counted by the nearest
-- AW.CNV symbol (SYM); firmware PCs (outside 0x80000..0xAFFFF) by 4 KB page. PROFILE lines at PF_TO, most first.
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local syms = {}
for line in io.lines(os.getenv("SYM")) do local n, v = line:match("^(%S+) (%x+)$"); if n then syms[#syms + 1] = { tonumber(v, 16), n } end end
table.sort(syms, function(a, b) return a[1] < b[1] end)
local function name(pc)
	if pc < 0x80000 or pc >= 0xb0000 then return string.format("fw:%06x", pc & ~0xfff) end
	local lo, hi = 1, #syms
	while lo < hi do local mid = (lo + hi + 1) // 2; if syms[mid][1] <= pc then lo = mid else hi = mid - 1 end end
	return syms[lo][2]
end
local A, B = tonumber(os.getenv("PF_FROM")), tonumber(os.getenv("PF_TO"))
local count, total, done = {}, 0, false
_G.PF = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	if t < A or done then return end
	if t > B then
		done = true
		local list = {}
		for k, v in pairs(count) do list[#list + 1] = { k, v } end
		table.sort(list, function(x, y) return x[2] > y[2] end)
		for i = 1, math.min(40, #list) do
			emu.print_error(string.format("PROFILE %5.1f%% %5d %s", 100 * list[i][2] / total, list[i][2], list[i][1]))
		end
		return
	end
	local n = name(cpu.state["PC"].value)
	count[n] = (count[n] or 0) + 1
	total = total + 1
end)
