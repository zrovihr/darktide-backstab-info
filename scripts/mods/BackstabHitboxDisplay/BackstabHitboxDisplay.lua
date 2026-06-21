local mod = get_mod("BackstabHitboxDisplay")

-- Shared backstab-combo state (read by the HUD element, written by the detection hook).
mod.bs_combo = mod.bs_combo or 0   -- current consecutive backstab count
mod.bs_best = mod.bs_best or 0     -- best this session
mod.bs_flash = mod.bs_flash or false   -- pulse request (any backstab hit)
mod.bs_kill = mod.bs_kill or false     -- red-flash request (backstab that killed)
mod.bs_weak = mod.bs_weak or false     -- latest backstab hit also hit a weakspot

-- =====================================================================================
-- Backstab Hitbox Display
-- -------------------------------------------------------------------------------------
-- Draws the angular "backstab" region behind nearby enemies.
--
-- IMPORTANT ACCURACY NOTE:
--   Backstab in Darktide is (almost certainly) an ANGLE test between the attacker's
--   position and the target's facing -- NOT a physical box. Weakspots (head etc.) are a
--   SEPARATE locational system. Whether backstab ALSO gates on hit location, and the
--   exact angle threshold, must be confirmed against the decompiled game script:
--       scripts/utilities/attack/backstab.lua
--   Until then the cone angle is the `backstab_arc` setting -- a tunable approximation.
-- =====================================================================================

local Unit = Unit
local Vector3 = Vector3
local Quaternion = Quaternion
local World = World
local LineObject = LineObject
local Color = Color
local Vector3_distance = Vector3.distance
local math_rad = math.rad
local math_cos = math.cos
local math_sin = math.sin
local math_atan2 = math.atan2
local math_pi = math.pi
local TWO_PI = math.pi * 2

-- Game utility for resolving a hit zone (e.g. "head") to a world position.
local HitZone
do
	local ok, hz = pcall(function()
		return mod:original_require("scripts/utilities/attack/hit_zone")
	end)
	if ok then
		HitZone = hz
	end
end

-- Persistent line object + throttle accumulator (created lazily once we have a world).
local line_object = nil      -- depth-tested (cones)
local line_object_top = nil  -- no depth test (head markers, drawn on top of bodies)
local line_world = nil
local accumulated_time = 0
local world_diag_time = 0

-------------------------------------------------------------------------------
-- Enemy enumeration
-- NOTE: Side-system API names below are best-recall and MUST be verified against a
-- script dump. If enemies don't appear, this is the first place to check.
-------------------------------------------------------------------------------
local function get_enemy_units()
	local extension_manager = Managers.state and Managers.state.extension
	if not extension_manager then
		return nil, nil, "no extension manager (not in a mission?)"
	end

	local side_system = extension_manager:system("side_system")
	if not side_system then
		return nil, nil, "no side_system"
	end

	local player = Managers.player and Managers.player:local_player(1)
	local player_unit = player and player.player_unit
	if not player_unit then
		return nil, nil, "no player_unit"
	end

	-- Unit -> side via the system's lookup table (confirmed in source: side_by_unit).
	local side = side_system.side_by_unit and side_system.side_by_unit[player_unit]
	if not side then
		return nil, nil, "no side for player unit"
	end

	-- relation_units("enemy") -> array of this side's enemy units (relation name "enemy").
	local enemy_units = side.relation_units and side:relation_units("enemy")
	if not enemy_units then
		return nil, nil, "no enemy relation units"
	end
	return enemy_units, player_unit, nil
end

-------------------------------------------------------------------------------
-- Geometry: draw a flat wedge on the ground behind the enemy.
-------------------------------------------------------------------------------
local SEGMENTS = 20
local GROUND_LIFT = 0.08   -- raise off the floor so the arc doesn't z-fight/clip
local THICK_STEP = 0.045   -- vertical gap between stacked copies (fakes line thickness)

-- One flat wedge (arc + two spokes) centered on the enemy's BACK, at height plane z.
local function add_wedge_layer(lo, cx, cy, z, base_yaw, half, radius, color)
	local prev_x, prev_y
	for i = 0, SEGMENTS do
		local yaw = base_yaw - half + (2 * half) * (i / SEGMENTS)
		local px = cx + radius * math_cos(yaw)
		local py = cy + radius * math_sin(yaw)
		if prev_x then
			LineObject.add_line(lo, color, Vector3(prev_x, prev_y, z), Vector3(px, py, z))
		end
		if i == 0 or i == SEGMENTS then
			LineObject.add_line(lo, color, Vector3(cx, cy, z), Vector3(px, py, z))
		end
		prev_x, prev_y = px, py
	end
end

-- Bitsquid is z-up: forward is the unit's local +Y, horizontal plane is X/Y.
-- Thickness is faked by stacking `layers` flat copies a few cm apart vertically.
local function draw_backstab_wedge(lo, center, forward, arc_deg, radius, color, base_z, layers)
	local base_yaw = math_atan2(-forward.y, -forward.x)
	local half = math_rad(arc_deg) * 0.5
	for k = 0, layers - 1 do
		add_wedge_layer(lo, center.x, center.y, base_z + k * THICK_STEP, base_yaw, half, radius, color)
	end
end

local function draw_facing_arrow(lo, center, forward, color, base_z, layers)
	for k = 0, layers - 1 do
		local z = base_z + k * THICK_STEP
		LineObject.add_line(lo, color,
			Vector3(center.x, center.y, z),
			Vector3(center.x + forward.x, center.y + forward.y, z))
	end
end

-- Wireframe sphere (3 great circles) around the head -- encloses it so it reads as the
-- head's volume and never gets buried inside the mesh when you're close.
local SPHERE_SEGS = 16

local function draw_circle(lo, c, r, color, plane)
	local prev
	for i = 0, SPHERE_SEGS do
		local a = (i / SPHERE_SEGS) * TWO_PI
		local u, v = math_cos(a) * r, math_sin(a) * r
		local p
		if plane == 1 then       -- horizontal (x/y)
			p = Vector3(c.x + u, c.y + v, c.z)
		elseif plane == 2 then   -- vertical (x/z)
			p = Vector3(c.x + u, c.y, c.z + v)
		else                     -- vertical (y/z)
			p = Vector3(c.x, c.y + u, c.z + v)
		end
		if prev then
			LineObject.add_line(lo, color, prev, p)
		end
		prev = p
	end
end

local function draw_head_marker(lo, c, r, color)
	draw_circle(lo, c, r, color, 1)
	draw_circle(lo, c, r, color, 2)
	draw_circle(lo, c, r, color, 3)
end

local function head_position(unit)
	if not HitZone then
		return nil
	end
	local ok, pos = pcall(HitZone.hit_zone_center_of_mass, unit, "head")
	if ok and pos then
		return pos
	end
	return nil
end

-- Fallback ONLY: rough estimate from bounding-box height, used if measurement fails.
local function head_radius_estimate(unit)
	local r = 0.16
	local ok, _pose, extents = pcall(Unit.box, unit)
	if ok and extents and extents.z and extents.z > 0 then
		r = extents.z * 0.16
	end
	if r < 0.1 then r = 0.1 end
	return r
end

-- REAL head size: raycast the actual head collision actor (the same filter guns use to
-- headshot) and read the surface distance from the head centre. This is measured from
-- the true physics shape, not guessed. Done once per breed and cached -- a breed's head
-- never changes size, so the cost is a handful of rays per mission.
local head_radius_cache = {}
local MEASURE_DIRS = {
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
	Vector3(0, 1, 0), Vector3(0, -1, 0),
	Vector3(0, 0, 1),
}

local function measure_head_radius(world, unit, center)
	local ok, result = pcall(function()
		local pw = World.physics_world(world)
		if not pw then
			return nil
		end
		local ude = ScriptUnit.has_extension(unit, "unit_data_system")
		local names = ude and ude.hit_zone_actors and ude:hit_zone_actors("head")
		if not names or #names == 0 then
			return nil
		end
		local actor_set = {}
		for i = 1, #names do
			local a = Unit.actor(unit, names[i])
			if a then
				actor_set[a] = true
			end
		end
		if not next(actor_set) then
			return nil
		end

		-- Take the MAX surface distance across directions = smallest sphere that fully
		-- encloses the head. (Averaging undershoots on narrow/elongated heads.)
		local maxr = 0
		for _, d in ipairs(MEASURE_DIRS) do
			local start = center + d * 0.6
			local hits = PhysicsWorld.raycast(pw, start, -d, 0.6, "all", "types", "both",
				"max_hits", 64, "collision_filter", "filter_player_character_shooting_raycast", "rewind_ms", 0)
			if hits then
				for i = 1, #hits do
					local hit = hits[i]
					if actor_set[hit[4]] then            -- hit[4] = actor (per hit_scan.lua)
						local r = Vector3.length(hit[1] - center)   -- hit[1] = position
						if r > 0.02 and r < 0.6 and r > maxr then
							maxr = r
						end
						break
					end
				end
			end
		end
		if maxr > 0 then
			return maxr
		end
		return nil
	end)
	if ok then
		return result
	end
	return nil
end

local function head_radius(world, unit, center, scale)
	local ude = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed = ude and ude:breed()
	local breed_name = breed and breed.name

	local r = breed_name and head_radius_cache[breed_name]
	if not r then
		r = measure_head_radius(world, unit, center)
		if r and breed_name then
			head_radius_cache[breed_name] = r
			if mod:get("debug_logging") then
				mod:info("[head] measured real head radius for '%s' = %.3f m", breed_name, r)
			end
		end
		r = r or head_radius_estimate(unit)   -- patch-safe fallback; not cached so we retry
	end
	return r * (scale or 1)
end

-------------------------------------------------------------------------------
-- Only worth showing cones on enemies you'd line up a backstab on. Trash (pure
-- "horde" breeds) dies to anything. Tags confirmed in scripts/utilities/breed.lua.
-------------------------------------------------------------------------------
local function is_important_enemy(unit)
	local ude = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed = ude and ude:breed()
	local tags = breed and breed.tags
	if not tags then
		return false
	end
	if tags.elite or tags.special or tags.ogryn or tags.monster or tags.captain then
		return true
	end
	return false
end

-------------------------------------------------------------------------------
-- Rebuild the whole line set (throttled).
-------------------------------------------------------------------------------
local rebuild_calls = 0

-- lo_cone = depth-tested (cones, occluded by world like normal geometry).
-- lo_top  = no depth test (head markers, drawn ON TOP of the enemy body).
local function rebuild(lo_cone, lo_top, world)
	LineObject.reset(lo_cone)
	if lo_top ~= lo_cone then
		LineObject.reset(lo_top)
	end

	rebuild_calls = rebuild_calls + 1
	local diag = mod:get("debug_logging") and (rebuild_calls % 20 == 0)

	local enemy_units, player_unit, err = get_enemy_units()
	if not enemy_units or not player_unit then
		if diag then
			mod:info("[cone] no draw: %s", tostring(err))
		end
		return
	end

	local player_pos = Unit.world_position(player_unit, 1)
	local show_cone = mod:get("show_cone")
	local show_head_marker = mod:get("show_head_marker")
	local cone_distance = mod:get("max_distance")
	local head_distance = mod:get("head_marker_distance")
	local max_enemies = mod:get("max_enemies")
	local arc_deg = mod:get("backstab_arc")
	local radius = mod:get("wedge_radius")
	local alpha = mod:get("opacity")
	local show_arrow = mod:get("show_facing_arrow")
	local thickness = mod:get("cone_thickness")
	local draw_overhead = mod:get("draw_overhead")
	local overhead_height = mod:get("overhead_height")
	local only_special = mod:get("only_special_enemies")
	local head_scale = mod:get("head_marker_scale")

	-- Collect out to whichever feature reaches furthest.
	local collect_distance = math.max(show_cone and cone_distance or 0, show_head_marker and head_distance or 0)
	if collect_distance <= 0 then
		return
	end

	local cone_color = Color(alpha, 255, 40, 40)
	local arrow_color = Color(alpha, 80, 160, 255)
	local head_color = Color(alpha, 255, 220, 40)

	-- Fresh list each rebuild -- a reused table would leave stale entries from a larger
	-- previous frame that table.sort would then mix in, dropping real enemies.
	local nearby = {}
	local count = 0
	for _, unit in ipairs(enemy_units) do
		if Unit.alive(unit) and (not only_special or is_important_enemy(unit)) then
			local pos = Unit.world_position(unit, 1)
			local dist = Vector3_distance(player_pos, pos)
			if dist <= collect_distance then
				count = count + 1
				nearby[count] = { unit = unit, dist = dist, pos = pos }
			end
		end
	end

	-- Nearest-first so the cap keeps the most relevant enemies.
	table.sort(nearby, function(a, b)
		return a.dist < b.dist
	end)

	local draw_n = math.min(count, max_enemies)
	if diag then
		mod:info("[cone] in_range=%d drawn=%d (cone<=%dm head<=%dm)",
			count, draw_n, cone_distance, head_distance)
	end
	for i = 1, draw_n do
		local e = nearby[i]
		local forward = Quaternion.forward(Unit.world_rotation(e.unit, 1))

		-- Cones (depth-tested), within the cone distance.
		if show_cone and e.dist <= cone_distance then
			local ground_z = e.pos.z + GROUND_LIFT
			draw_backstab_wedge(lo_cone, e.pos, forward, arc_deg, radius, cone_color, ground_z, thickness)
			if show_arrow then
				draw_facing_arrow(lo_cone, e.pos, forward, arrow_color, ground_z, thickness)
			end
			if draw_overhead then
				draw_backstab_wedge(lo_cone, e.pos, forward, arc_deg, radius, cone_color, e.pos.z + overhead_height, thickness)
			end
		end

		-- Head weakspot marker (drawn on top), within its own distance.
		if show_head_marker and e.dist <= head_distance then
			local hp = head_position(e.unit)
			if hp then
				draw_head_marker(lo_top, hp, head_radius(world, e.unit, hp, head_scale), head_color)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Update loop (DMF calls mod.update each frame automatically).
--
-- PATCH SAFETY: the whole world-drawing path is wrapped in a guard below. If any
-- game-side API this touches (World/LineObject/HitZone/side system/Color) is changed
-- or removed by a future patch, the cone simply switches itself off -- it must never
-- be the reason the game crashes.
-------------------------------------------------------------------------------
local cone_dead = false

local function update_impl(dt)
	if not mod:get("enabled") then
		return
	end

	world_diag_time = world_diag_time + dt
	local world_diag = mod:get("debug_logging") and world_diag_time >= 2.0
	if world_diag then
		world_diag_time = 0
	end

	local world = Managers.world and Managers.world:world("level_world")
	if not world then
		if world_diag then
			mod:info("[cone] update running but no 'level_world' (Managers.world=%s)", tostring(Managers.world ~= nil))
		end
		return
	end

	-- (Re)create the line objects if the world changed (e.g. new mission load).
	if line_object == nil or line_world ~= world then
		line_object = World.create_line_object(world)
		-- Second arg disables depth test -> head markers draw on top of bodies.
		-- Fall back to the depth-tested object if the engine rejects the flag.
		local ok_top, lo_top = pcall(World.create_line_object, world, true)
		line_object_top = (ok_top and lo_top) or line_object
		line_world = world
		accumulated_time = 0
	end

	-- Nothing to draw if both world features are off; clear any lingering lines.
	if not mod:get("show_cone") and not mod:get("show_head_marker") then
		LineObject.reset(line_object)
		LineObject.dispatch(world, line_object)
		if line_object_top ~= line_object then
			LineObject.reset(line_object_top)
			LineObject.dispatch(world, line_object_top)
		end
		return
	end

	accumulated_time = accumulated_time + dt
	local interval = mod:get("update_interval")
	if accumulated_time >= interval then
		accumulated_time = 0
		rebuild(line_object, line_object_top, world)
	end

	-- Submit every frame so the lines stay visible between rebuilds.
	LineObject.dispatch(world, line_object)
	if line_object_top ~= line_object then
		LineObject.dispatch(world, line_object_top)
	end
end

mod.update = function(dt)
	if cone_dead then
		return
	end
	local ok, err = pcall(update_impl, dt)
	if not ok then
		cone_dead = true
		-- Log once; never let the logging itself throw either.
		pcall(function()
			mod:info("[safety] world drawing disabled after error: %s", tostring(err))
		end)
	end
end

-- Drop the cached lines when the mod is toggled off so nothing lingers on screen.
mod.on_setting_changed = function(setting_id)
	if setting_id == "enabled" and not mod:get("enabled") and line_object and line_world then
		LineObject.reset(line_object)
		LineObject.dispatch(line_world, line_object)
		if line_object_top and line_object_top ~= line_object then
			LineObject.reset(line_object_top)
			LineObject.dispatch(line_world, line_object_top)
		end
	end
end

-- =====================================================================================
-- BACKSTAB GEOMETRY
-- -------------------------------------------------------------------------------------
-- The authoritative rule, from scripts/utilities/attack/attack_positioning.lua:
--   melee only; dir = normalize(flat(enemy_pos - attacker_pos));
--   backstab when dot(dir, enemy_flat_forward) > 0.5  (60 deg half-angle = 120 deg cone).
-- =====================================================================================
local Vector3_normalize = Vector3.normalize
local Vector3_dot = Vector3.dot
local Quaternion_forward = Quaternion.forward
local BACKSTAB_DOT_THRESHOLD = 0.5

local function flat_normalize(v)
	return Vector3_normalize(Vector3(v.x, v.y, 0))
end

local function clamp_unit(x)
	if x > 1 then return 1 elseif x < -1 then return -1 end
	return x
end

local function compute_backstab(attacked_unit, attacking_unit)
	if not (attacked_unit and attacking_unit and Unit.alive(attacked_unit) and Unit.alive(attacking_unit)) then
		return nil
	end
	local enemy_pos = Unit.world_position(attacked_unit, 1)
	local attacker_pos = Unit.world_position(attacking_unit, 1)
	local dir = flat_normalize(enemy_pos - attacker_pos)
	local fwd = flat_normalize(Quaternion_forward(Unit.world_rotation(attacked_unit, 1)))
	local dot = clamp_unit(Vector3_dot(dir, fwd))
	return dot > BACKSTAB_DOT_THRESHOLD, dot
end

-- =====================================================================================
-- BACKSTAB COMBO + CROSSHAIR INDICATOR (always on; independent of the debug logger)
-- -------------------------------------------------------------------------------------
-- Hook the post-resolution attack report (the same hook kill_tracker uses). For the
-- LOCAL player's connecting MELEE hits: a backstab extends the combo and raises a
-- "Backstab" flash; any non-backstab melee hit breaks the combo.
-- =====================================================================================
local function local_player_unit()
	local p = Managers.player and Managers.player:local_player(1)
	return p and p.player_unit
end

local function register_melee_hit(is_backstab, killed, weakspot)
	if is_backstab then
		mod.bs_combo = (mod.bs_combo or 0) + 1
		if mod.bs_combo > (mod.bs_best or 0) then
			mod.bs_best = mod.bs_combo
		end
		mod.bs_flash = true
		mod.bs_weak = weakspot and true or false
		if killed then
			mod.bs_kill = true
		end
	else
		mod.bs_combo = 0
		mod.bs_weak = false
	end
end

-- PATCH SAFETY: only hook if the class/method still exists, and pcall the body so a
-- future change to add_attack_result's argument order can't crash -- worst case the
-- combo just stops updating.
local function on_attack_result(attacked_unit, attacking_unit, hit_weakspot, attack_result, attack_type)
	if not mod:get("enabled") then
		return
	end
	-- Backstab is melee-only; only the local player's connecting hits affect the combo.
	if attack_type ~= "melee" then
		return
	end
	if attacking_unit ~= local_player_unit() then
		return
	end
	if not (attack_result == "damaged" or attack_result == "died") then
		return
	end
	register_melee_hit(compute_backstab(attacked_unit, attacking_unit) == true, attack_result == "died", hit_weakspot == true)
end

if CLASS and CLASS.AttackReportManager and CLASS.AttackReportManager.add_attack_result then
	mod:hook_safe(CLASS.AttackReportManager, "add_attack_result", function(self,
		damage_profile, attacked_unit, attacking_unit, attack_direction, hit_world_position,
		hit_weakspot, damage, attack_result, attack_type, damage_efficiency, ...)
		pcall(on_attack_result, attacked_unit, attacking_unit, hit_weakspot, attack_result, attack_type)
	end)
	mod:info("BackstabHitboxDisplay: hooked AttackReportManager.add_attack_result (combo)")
end

-- Register the crosshair HUD element (Backstab counter). PATCH SAFETY: pcall the
-- registration so a DMF/HUD API change disables only the counter, not the whole mod.
local ok_hud, err_hud = pcall(function()
	mod:register_hud_element({
		filename = "BackstabHitboxDisplay/scripts/mods/BackstabHitboxDisplay/HudElementBackstab",
		class_name = "HudElementBackstab",
		visibility_groups = {
			"alive",
			"communication_wheel",
		},
		use_hud_scale = true,
		validation_function = function()
			local gm = Managers.state and Managers.state.game_mode
			return not gm or gm:game_mode_name() ~= "hub"
		end,
	})
end)
if not ok_hud then
	pcall(function() mod:info("[safety] HUD element registration failed: %s", tostring(err_hud)) end)
end
