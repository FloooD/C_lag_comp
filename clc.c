#include <lua.h>
#include <lauxlib.h>

#define VERSION "1.0"
#define L_ARG(i) (lua_tonumber(L, (i)))

static int sa_msg(lua_State *L)
{
	if (L_ARG(2) == 1.0) {
		lua_getfield(L, LUA_GLOBALSINDEX, "msg2");
		lua_pushnumber(L, L_ARG(1));
		lua_pushstring(L, "C Lag Comp. v" VERSION);
		lua_call(L, 2, 0);
	}
	return 0;
}

static const struct luaL_Reg clc_lib[] = {
	{"sa_msg", sa_msg},
	{NULL, NULL}
};

int luaopen_clc(lua_State *L)
{
	luaL_register(L, "clc", clc_lib);
	return 1;
}
