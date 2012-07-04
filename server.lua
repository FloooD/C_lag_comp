local clc_load = assert(package.loadlib("sys/lua/clc.so", "luaopen_clc"))
clc_load()

function clc_sa_msg(id, act)
	if act == 1 then msg2(id, "C Lag Comp. v1.0") end
end
addhook("serveraction", "clc_sa_msg")
