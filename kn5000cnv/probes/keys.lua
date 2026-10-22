-- keys.lua -- hold keybed keys on a schedule: KEYS="t:Key C4*0.5;t:Key F5*1" (MAME field names, ports :KEYS0..).
local mac = manager.machine
local function find(name)
	for tag, p in pairs(mac.ioport.ports) do
		for fname, f in pairs(p.fields) do if fname == name then return f end end
	end
end
local steps = {}
for item in string.gmatch(os.getenv("KEYS") or "", "[^;]+") do
	local t, n, d = item:match("^%s*([%d%.]+)%s*:%s*(.-)%*([%d%.]+)%s*$")
	if t then steps[#steps + 1] = { t = tonumber(t), name = n, dur = tonumber(d) } end
end
table.sort(steps, function(a, b) return a.t < b.t end)
_G.KY = { i = 1, held = {} }
_G.KY.h = emu.add_machine_frame_notifier(function()
	local t = mac.time:as_double()
	for f, u in pairs(_G.KY.held) do if t >= u then f:set_value(0); _G.KY.held[f] = nil end end
	while steps[_G.KY.i] and t >= steps[_G.KY.i].t do
		local st = steps[_G.KY.i]; _G.KY.i = _G.KY.i + 1
		local f = find(st.name)
		if f then f:set_value(1); _G.KY.held[f] = t + st.dur; emu.print_error(string.format("KEY %.2f %s", t, st.name))
		else emu.print_error("KEY unknown " .. st.name) end
	end
end)
