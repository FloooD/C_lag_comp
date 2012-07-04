#include <lua.h>
#include <lauxlib.h>
#include <math.h>

#define VERSION "1.0"
#define MAX_COMP 15 /* max compensated latency = MAX_COMP * 20ms. */
#define TOPIXEL(tile) ((32 * (tile)) + 16)

static int line_sq_col(double lx, double ly, double sx, double sy, double sh)
{
	double x, y;
	int cx = (fabs(sx) <= sh);
	int cy = (fabs(sy) <= sh);
	if (cx && cy) return 1;
	x = (lx >= 0) ? sx - sh : sx + sh;
	y = (ly >= 0) ? sy - sh : sy + sh;
	if ((lx != 0)
		&& (((cx == cy) && (fabs(ly * x) >= fabs(lx * y))) || (cy && !cx))
		&& (x * lx >= 0) && (fabs(x) <= fabs(lx))
		&& (fabs((x * ly / lx)- sy) <= fabs(sh)))
			return 1;
	if (ly == 0) return 0;
	return ((y * ly >= 0) && (fabs(y) <= fabs(ly))
		&& (fabs((y * lx / ly)- sx) <= fabs(sh)));
}

static int line_sq_col_out(double lx, double ly, double sx, double sy, double sh, double *ox, double *oy)
{
	int cx = (fabs(sx) <= sh);
	int cy = (fabs(sy) <= sh);
	if (cx && cy) {
		if (fabs(lx - sx) <= sh && fabs(ly - sy) <= sh) {
			*ox = lx; *oy = ly;
			return 1;
		}
		sh *= -1;
	}
	*ox = (lx >= 0) ? sx - sh : sx + sh;
	*oy = (ly >= 0) ? sy - sh : sy + sh;
	if ((lx != 0) && ((!(cx ^ cy) && ((fabs(ly * *ox) >= fabs(lx * *oy)) ^ (sh < 0))) || (cy && !cx)))
		goto collision;
	if (ly == 0) goto no_collision;
	double temp = lx; lx = ly, ly = temp;
	temp = sx; sx = sy; sy = temp;
	double *tptr; tptr = ox; ox = oy; oy = tptr;
	collision:
	if ((*ox * lx >= 0) && (fabs(*ox) <= fabs(lx))) {
		*oy = (*ox) * ly / lx;
		if (fabs(*oy - sy) <= fabs(sh))
			return 1;
	}
	no_collision:
	return (*ox = *oy = 0);
}

/* TODO: use array for tiles that are not dynamic walls/breakables/etc... */
static int iswall(lua_State *L, int tx, int ty)
{
	int ret;
	lua_getfield(L, LUA_GLOBALSINDEX, "tile");
	lua_pushnumber(L, tx);
	lua_pushnumber(L, ty);
	lua_pushstring(L, "wall");
	lua_call(L, 3, 1);
	ret = lua_toboolean(L, 1);
	lua_pop(L, 1);
	return ret;
}

static void simul_attack(lua_State *L, int id, int wpn, int dmg, int rangex3, double rot, double px, double py)
{
	double ex = rangex3 * sin(rot); /* rot in radians */
	double ey = -rangex3 * cos(rot);
	int tx = px / 32;
	int ty = py / 32;
	int ix = ex < 0 ? -1 : ex > 0;
	int iy = ey < 0 ? -1 : ey > 0;
	int tmpx, tmpy;
	while (!iswall(L, tx, ty)) {
		tmpx = tx;
		tmpy = ty;
		if (ix && line_sq_col(ex, ey, TOPIXEL(tmpx + ix) - px, TOPIXEL(tmpy) - py, 16))
			tx += ix;
		if (iy && line_sq_col(ex, ey, TOPIXEL(tmpx) - px, TOPIXEL(tmpy + iy) - py, 16))
			ty += iy;
		if (tx == tmpx && ty == tmpy)
			goto NO_WALL;
	}
	line_sq_col_out(ex, ey, TOPIXEL(tx) - px, TOPIXEL(ty) - py, 16, &ex, &ey);
NO_WALL:
	return;
	/* imcomplete */
}

static const struct luaL_Reg clc_lib[] = {
	{NULL, NULL}
};

int luaopen_clc(lua_State *L)
{
	luaL_register(L, "clc", clc_lib);
	return 1;
}
