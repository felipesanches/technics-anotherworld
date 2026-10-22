-- poke.lua -- at POKE_T seconds write byte POKE_V at address POKE_A (hex), to make the song memory look in
-- use (POKE lines).
local mac = manager.machine
local mem = mac.devices[":maincpu"].spaces["program"]
local T, A, V = tonumber(os.getenv("POKE_T")) or 30, tonumber(os.getenv("POKE_A") or "b0010", 16), tonumber(os.getenv("POKE_V") or "55", 16)
_G.PK = {}
_G.PK.h = emu.add_machine_frame_notifier(function()
	if _G.PK.done or mac.time:as_double() < T then return end
	_G.PK.done = true
	mem:write_u8(A, V)
	emu.print_error(string.format("POKE t=%.2f %06x <- %02x", mac.time:as_double(), A, V))
end)
