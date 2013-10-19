-----------------------------------------------
----Lua Lag Compensation version 5 by FlooD----
-----------------------------------------------
--[[       latest version always at
raw.github.com/FloooD/C_lag_comp/master/llc.lua
---------------------------------------------]]
math.randomseed(os.time())

local offscreen_no_comp = false
if offscreen_no_comp then parse("mp_shotweakening 0") end

local glock_burst, famas_burst, zoom, no_lc = {}, {}, {}, {}
local disabled_weapons = {}
for _, v in ipairs{0, 47, 48, 49, 51, 52, 72, 73, 75, 76, 77, 86, 87, 88, 89, 253, 254, 255} do disabled_weapons[v] = true end
local special_armor = {}
for i, v in ipairs{25, 50, 75, 50, 95} do special_armor[200 + i] = 1 - (v / 100) end

--totally pointless "optimizations"
local parse, player = parse, player
local abs, floor, ceil, random, sin, cos, rad = math.abs, math.floor, math.ceil, math.random, math.sin, math.cos, math.rad

local buf_x, buf_y = {}, {} --circular buffer
local buf_size = 16
local buf_index = buf_size
for i = 1, buf_size do
	buf_x[i] = {}
	buf_y[i] = {}
end

local function get_past_pos(id, frames)
	if frames < 1 then return player(id, "x"), player(id, "y") end
	if frames >= buf_size then frames = 0 end --0 == buf_size mod buf_size
	local ind = (buf_index - frames) % buf_size + 1
	return buf_x[ind][id], buf_y[ind][id]
end
LC_get_past_pos = get_past_pos --for other scripts to use.

function lc_reset(id)
	glock_burst[id] = 0
	famas_burst[id] = 0
	zoom[id] = 0
	for i = 1, buf_size do
		buf_x[i][id] = -1
		buf_y[i][id] = -1
	end
end
addhook("die", "lc_reset")

function lc_clear(id)
	lc_reset(id)
	no_lc[id] = false
end
for id = 1, 32 do lc_clear(id) end
addhook("leave", "lc_clear")

function lc_update_buf()
	buf_index = (buf_index % buf_size) + 1
	for id = 1, 32 do
		buf_x[buf_index][id], buf_y[buf_index][id] = player(id, "x") or -1, player(id, "y") or -1
	end
end
addhook("always", "lc_update_buf")

local function off_screen(a, b)
	return (abs(player(a, "x") - player(b, "x")) > 352) or (abs(player(a, "y") - player(b, "y")) > 272)
end

function lc_hit_bypass(v, id, wpn)
	return (offscreen_no_comp and off_screen(v, id) or disabled_weapons[wpn] or id == 0 or no_lc[id]) and 0 or 1
end
addhook("hit", "lc_hit_bypass", 9001)

local function intersect(ex, ey, bx, by, bl)
	if not (bx and by) then return end
	local cx, cy = (abs(bx) <= bl), (abs(by) <= bl)
	if cx and cy then
		if abs(ex - bx) <= bl and abs(ey - by) <= bl then
			return ex, ey
		end
		bl = -bl
	end
	local ox = (ex >= 0) and bx - bl or bx + bl
	local oy = (ey >= 0) and by - bl or by + bl
	local flip = false
	if (ex == 0 or (cx ~= cy or ((abs(ey * ox) >= abs(ex * oy)) == (bl < 0)))) and ((not cy) or cx) then
		if ey == 0 then return end
		ex, ey, bx, by, ox, oy = ey, ex, by, bx, oy, ox
		flip = true
	end
	if (ox * ex) >= 0 and abs(ox) <= abs(ex) then
		oy = ox * ey / ex
		if abs(oy - by) <= abs(bl) then
			if flip then return oy, ox end
			return ox, oy
		end
	end
end

local function simulate_attack(id, wpn, dmg, rot)
	local victims = {}
	if game("sv_friendlyfire") == "0" and game("sv_gamemode") ~= "1" then
		victims = player(0, (player(id, "team") == 1) and "team2living" or "team1living")
	else
		victims = player(0, "tableliving")
	end
	if #victims == 0 then return end

	local range = itemtype(wpn, "range")
	local start_x = player(id, "x")
	local start_y = player(id, "y")
	local end_x = (3 * range) * sin(rad(rot))
	local end_y = -(3 * range) * cos(rad(rot))
	local tile_x = floor(start_x / 32)
	local tile_y = floor(start_y / 32)
	local inc_x = (end_x > 0 and 1) or (end_x < 0 and -1) or 0
	local inc_y = (end_y > 0 and 1) or (end_y < 0 and -1) or 0

	while true do
		if tile(tile_x, tile_y, "wall") then
			end_x, end_y = intersect(end_x, end_y, 16 + 32 * (tile_x) - start_x, 16 + 32 * (tile_y) - start_y, 16)
			break
		else
			local temp_x, temp_y = tile_x, tile_y
			if inc_x ~= 0 and intersect(end_x, end_y, 16 + 32 * (temp_x + inc_x) - start_x, 16 + 32 * (temp_y) - start_y, 16) then
				tile_x = temp_x + inc_x
			end
			if inc_y ~= 0 and intersect(end_x, end_y, 16 + 32 * (temp_x) - start_x, 16 + 32 * (temp_y + inc_y) - start_y, 16) then
				tile_y = temp_y + inc_y
			end
			if tile_x == temp_x and tile_y == temp_y then
				break
			end
		end
	end

	local frames = ceil(player(id, "ping") / 20)
	local wpn_name = itemtype(wpn, "name")
	local wpn_img = "gfx/weapons/"..wpn_name:lower():gsub("[ %-]","").."_k.bmp"
	local mp_kevlar = game("mp_kevlar")

	for i = 1, #victims do
		local v = victims[i]
		if (not offscreen_no_comp or not off_screen(v, id)) and v ~= id then
			local v_x, v_y = get_past_pos(v, frames)
			if intersect(end_x, end_y, v_x - start_x, v_y - start_y, 12) then
				local rand = ceil(3 * random())
				parse("sv_sound2 "..id.." player/hit"..rand..".wav")
				parse("sv_sound2 "..v.." player/hit"..rand..".wav")
				local old_armor = player(v, "armor")
				local new_armor, new_health
				if old_armor <= 200 then
					new_armor = old_armor - dmg
					if new_armor < 0 then new_armor = 0 end
					new_health = player(v, "health") - dmg + floor(mp_kevlar * (old_armor - new_armor))
					parse("setarmor "..v.." "..new_armor)
				else
					new_health = player(v, "health") - floor(dmg * (special_armor[new_armor] or 1))
				end
				if new_health > 0 then
					parse("sethealth "..v.." "..new_health)
				else
					parse("customkill "..id.." \""..wpn_name..","..wpn_img.."\" "..v)
					parse("sv_sound2 "..id.." player/die"..rand..".wav")
					parse("sv_sound2 "..v.." player/die"..rand..".wav")
				end
			end
		end
	end
end

function lc_on_attack(id)
	local wpn = player(id, "weapon")
	if disabled_weapons[wpn] or no_lc[id] then return end
	local dmg_factor = game("mp_damagefactor")
	local dmg = itemtype(wpn, "dmg") * dmg_factor
	local rot = player(id, "rot")
	if (wpn == 2 and glock_burst[id] == 1) or (wpn == 39 and famas_burst[id] == 1) then
		dmg = floor(dmg * 0.64 + 0.5)
		simulate_attack(id, wpn, dmg, rot - 6 + 12 * random())
		simulate_attack(id, wpn, dmg, rot + 6 + 8 * random())
		simulate_attack(id, wpn, dmg, rot - 6 - 8 * random())
		return
	elseif wpn == 10 or wpn == 11 then
		for _ = 1, 5 do
			simulate_attack(id, wpn, dmg, rot - 20 + 40 * random())
		end
		return
	end
	if zoom[id] == 1 then
		dmg = itemtype(wpn, "dmg_z1") * dmg_factor
	elseif zoom[id] == 2 then
		dmg = itemtype(wpn, "dmg_z2") * dmg_factor
	end
	rot = rot + itemtype(wpn, "dispersion") * (2 * random() - 1)
	simulate_attack(id, wpn, dmg, rot)
end
addhook("attack", "lc_on_attack")

function lc_on_attack2(id, m)
	local wpn = player(id, "weapon")
	if wpn == 50 or wpn == 69 then
		if no_lc[id] then return end
		simulate_attack(id, wpn, itemtype(wpn, "dmg_z1") * game("mp_damagefactor"), player(id, "rot"))
	elseif wpn == 2 then
		glock_burst[id] = m
	elseif wpn == 39 then
		famas_burst[id] = m
	elseif wpn ~= 32 and wpn >= 31 and wpn <= 37 then
		zoom[id] = m
	end	
end
addhook("attack2", "lc_on_attack2")

function lc_on_unzoom(id)
	zoom[id] = 0
end
addhook("reload", "lc_on_unzoom")
addhook("select", "lc_on_unzoom")

function lc_on_drop(id, iid, wpn)
	zoom[id] = 0
	if wpn == 2 then
		glock_burst[id] = 0
	elseif wpn == 39 then
		famas_burst[id] = 0
	end
end
addhook("drop", "lc_on_drop")

function lc_on_collect(id, _, wpn, _, _, m)
	if wpn == 2 then
		glock_burst[id] = m
	elseif wpn == 39 then
		famas_burst[id] = m
	end
end
addhook("collect", "lc_on_collect")

function lc_on_serveract(id, action)
	if action == 1 then
		msg2(id, string.char(169).."255255255Lua Lag Comp v5 by FlooD")
		msg2(id, "Your latency: "..player(id, "ping"))
		if no_lc[id] then
			msg2(id, "LC is off for yourself.")
		else
			msg2(id, "LC is on for yourself.")
			msg2(id, "Off-screen shots are "..(offscreen_no_comp and "not" or "").."lag compensated.")
		end
	elseif action == 2 then
		no_lc[id] = not no_lc[id]
		msg2(id, "LC toggled "..(no_lc[id] and "off" or "on").." for yourself.")
		msg2(id, "Press the same button to toggle again.")
	end
end
addhook("serveraction", "lc_on_serveract")
