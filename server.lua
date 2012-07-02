local clc_load = assert(package.loadlib("sys/lua/clc.so", "luaopen_clc"))
clc_load()

addhook("serveraction", "clc.sa_msg")
