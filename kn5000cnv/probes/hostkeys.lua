-- hostkeys.lua -- which PC keys MAME sees held, printed whenever the set changes (HOSTKEYS lines): does the
-- keyboard report a combination such as LEFT + UP + SPACE at all? Keyboards that cannot (ghosting) drop the
-- last key pressed. HK_KEYS (comma list of MAME key tokens) chooses the keys; default arrows, space, ctrls, shifts.
local mac = manager.machine
local inp = mac.input
local names = {}
for k in string.gmatch(os.getenv("HK_KEYS") or "LEFT,RIGHT,UP,DOWN,SPACE,LCONTROL,RCONTROL,LSHIFT,RSHIFT", "[^,]+") do
	names[#names + 1] = k
end
local codes = {}
for i, k in ipairs(names) do codes[i] = inp:code_from_token("KEYCODE_" .. k) end
local last = nil
_G.HK = emu.add_machine_frame_notifier(function()
	local held = {}
	for i, c in ipairs(codes) do if inp:code_pressed(c) then held[#held + 1] = names[i] end end
	local now = table.concat(held, " + ")
	if now ~= last then
		last = now
		emu.print_error(string.format("HOSTKEYS t=%.2f %s", mac.time:as_double(), now == "" and "(none)" or now))
	end
end)
