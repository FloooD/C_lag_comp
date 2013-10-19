-----------------------------------------------
----Lua Lag Compensation version 5 by FlooD----
-----------------------------------------------
--[[       latest version always at
raw.github.com/FloooD/C_lag_comp/master/llc.lua
---------------------------------------------]]

parse("mp_shotweakening 0")
math.randomseed(os.time())

LC = {}
LC.VERSION = 5

local disabled_weapons = {}
for _, v in ipairs({0, 47, 48, 49, 51, 52, 72, 73, 75, 76, 77, 86, 87, 88, 89, 253, 254, 255}) do disabled_weapons[v] = true end
local special_armor = {}
for i, v in ipairs({25, 50, 75, 50, 95}) do special_armor[200 + i] = 1 - (v / 100) end

local buf = {x = {}, y = {}} --circular buffer of players' past positions
local buf_size = 16 --max compensated latency is 16 * 20 = 320
local buf_start_index = buf_size
for i = 1, buf_size do
	buf.x[i] = {}
	buf.y[i] = {}
end

local mode = {glock_burst = {}, famas_burst = {}, zoom = {}, no_lc = {}}

function lc_reset(id)
	mode.glock_burst[id] = 0
	mode.famas_burst[id] = 0
	mode.zoom[id] = 0
	for i = 1, buf_size do
		buf.x[i][id] = -1
		buf.y[i][id] = -1
	end
end
addhook("die", "lc_reset")
--addhook("spawn", "lc_reset")

function lc_clear(id)
	lc_reset(id)
	mode.no_lc[id] = false
end
for id = 1, 32 do lc_clear(id) end
addhook("leave", "lc_clear")

function lc_update_buf()
	buf_start_index = (buf_start_index % buf_size) + 1
	for id = 1, 32 do
		buf.x[buf_start_index][id], buf.y[buf_start_index][id] = player(id, "x"), player(id, "y")
	end
end
addhook("always", "lc_update_buf")

function lc_hit_bypass(v, id, wpn)
	return (disabled_weapons[wpn] or id == 0 or mode.no_lc[id]) and 0 or 1
end
addhook("hit", "lc_hit_bypass", 9001)

local function intersect(ex, ey, bx, by, bl)
	if not (bx and by) then return end
	local cx, cy = (math.abs(bx) <= bl), (math.abs(by) <= bl)
	if cx and cy then
		if math.abs(ex - bx) <= bl and math.abs(ey - by) <= bl then
			return ex, ey
		end
		bl = -bl
	end
	local ox = (ex >= 0) and bx - bl or bx + bl
	local oy = (ey >= 0) and by - bl or by + bl
	local flip
	if (ex == 0 or (cx ~= cy or ((math.abs(ey * ox) >= math.abs(ex * oy)) == (bl < 0)))) and ((not cy) or cx) then
		if ey == 0 then return end
		ex, ey, bx, by, ox, oy = ey, ex, by, bx, oy, ox
		flip = true
	end
	if (ox * ex) >= 0 and math.abs(ox) <= math.abs(ex) then
		oy = ox * ey / ex
		if math.abs(oy - by) <= math.abs(bl) then
			if flip then return oy, ox end
			return ox, oy
		end
	end
end

local function simulate_attack(id, wpn, dmg, rot)
	local range = itemtype(wpn, "range")
	local start_x = player(id, "x")
	local start_y = player(id, "y")
	local end_x = (3 * range) * math.sin(math.rad(rot))
	local end_y = -(3 * range) * math.cos(math.rad(rot))
	local tile_x = math.floor(start_x / 32)
	local tile_y = math.floor(start_y / 32)
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

	local victims = {}
	if game("sv_friendlyfire") == "0" and game("sv_gamemode") ~= "1" then
		victims = player(0, "team"..((player(id, "team") == 1) and 2 or 1).."living")
	else
		victims = player(0, "tableliving")
	end
	if #victims < 1 then return end

	local frames = math.ceil(player(id, "ping") / 20)
	if frames > buf_size then frames = buf_size end
	if frames ~= 0 then frames = (buf_start_index - frames) % buf_size + 1 end

	local wpn_name = itemtype(wpn, "name")
	local wpn_img = "gfx/weapons/"..wpn_name:lower():gsub("[ %-]","").."_k.bmp"
	local mp_kevlar = game("mp_kevlar")

	for i = 1, #victims do
		local v = victims[i]
		if v ~= id then
			local v_x, v_y
			if frames == 0 then
				v_x, v_y = player(v, "x"), player(v, "y")
			else
				v_x, v_y = buf.x[frames][v], buf.y[frames][v]
			end
			if intersect(end_x, end_y, v_x - start_x, v_y - start_y, 12) then
				parse("sv_sound2 "..id.." player/hit"..math.ceil(3 * math.random())..".wav")
				parse("sv_sound2 "..v.." player/hit"..math.ceil(3 * math.random())..".wav")
				local old_armor = player(v, "armor")
				local new_armor, new_health
				if old_armor <= 200 then
					new_armor = old_armor - dmg
					if new_armor < 0 then new_armor = 0 end
					new_health = player(v, "health") - dmg + math.floor(mp_kevlar * (old_armor - new_armor))
					parse("setarmor "..v.." "..new_armor)
				else
					new_health = player(v, "health") - math.floor(dmg * (special_armor[new_armor] or 1))
				end
				if new_health > 0 then
					parse("sethealth "..v.." "..new_health)
				else
					parse("customkill "..id.." \""..wpn_name..","..wpn_img.."\" "..v)
					parse("sv_sound2 "..id.." player/die"..math.ceil(3 * math.random())..".wav")
					parse("sv_sound2 "..v.." player/die"..math.ceil(3 * math.random())..".wav")
				end
			end
		end
	end
end


function lc_on_attack(id)
	local wpn = player(id, "weapon")	
	if disabled_weapons[wpn] or mode.no_lc[id] then return end
	local dmg_factor = game("mp_damagefactor")
	local dmg = itemtype(wpn, "dmg") * dmg_factor
	local rot = player(id, "rot")
	if (wpn == 2 and mode.glock_burst[id] == 1) or (wpn == 39 and mode.famas_burst[id] == 1) then
		dmg = math.floor(dmg * 0.64 + 0.5)
		simulate_attack(id, wpn, dmg, rot - 6 + 12 * math.random())
		simulate_attack(id, wpn, dmg, rot + 6 + 8 * math.random())
		simulate_attack(id, wpn, dmg, rot - 6 - 8 * math.random())
		return
	elseif wpn == 10 or wpn == 11 then
		for _ = 1, 5 do
			simulate_attack(id, wpn, dmg, rot - 20 + 40 * math.random())
		end
		return
	end
	if mode.zoom[id] == 1 then
		dmg = itemtype(wpn, "dmg_z1") * dmg_factor
	elseif mode.zoom[id] == 2 then
		dmg = itemtype(wpn, "dmg_z2") * dmg_factor
	end
	rot = rot + itemtype(wpn, "dispersion") * (2 * math.random() - 1)
	simulate_attack(id, wpn, dmg, rot)
end
addhook("attack", "lc_on_attack")

function lc_on_attack2(id, m)
	local wpn = player(id, "weapon")
	if wpn == 50 or wpn == 69 then
		if mode.no_lc[id] then return end
		simulate_attack(id, wpn, itemtype(wpn, "dmg_z1") * game("mp_damagefactor"), player(id, "rot"))
	elseif wpn == 2 then
		mode.glock_burst[id] = m
	elseif wpn == 39 then
		mode.famas_burst[id] = m
	elseif wpn ~= 32 and wpn >= 31 and wpn <= 37 then
		mode.zoom[id] = m
	end	
end
addhook("attack2", "lc_on_attack2")

function lc_on_unzoom(id)
	mode.zoom[id] = 0
end
addhook("reload", "lc_on_unzoom")
addhook("select", "lc_on_unzoom")

function lc_on_drop(id, iid, wpn)
	mode.zoom[id] = 0
	if wpn == 2 then
		mode.glock_burst[id] = 0
	elseif wpn == 39 then
		mode.famas_burst[id] = 0
	end
end
addhook("drop", "lc_on_drop")

function lc_on_collect(id, _, wpn, _, _, m)
	if wpn == 2 then
		mode.glock_burst[id] = m
	elseif wpn == 39 then
		mode.famas_burst[id] = m
	end
end
addhook("collect", "lc_on_collect")

function lc_on_serveract(id, action)
	if action == 1 then
		msg2(id, string.char(169).."255255255".."Lua Lag Comp v5 by FlooD")
		msg2(id, "Your latency: "..player(id, "ping"))
		msg2(id, "LC is "..(mode.no_lc[id] and "off" or "on").." for yourself.")
	elseif action == 2 then
		mode.no_lc[id] = not mode.no_lc[id]
		msg2(id, "LC toggled "..(mode.no_lc[id] and "off" or "on").." for yourself.")
		msg2(id, "Press the same button to toggle again.")
	end
end
addhook("serveraction", "lc_on_serveract")
