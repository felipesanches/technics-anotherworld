-- multi.lua -- run several probe scripts in one MAME session: PROBES="a.lua b.lua" (paths).
for p in string.gmatch(os.getenv("PROBES") or "", "%S+") do dofile(p) end
