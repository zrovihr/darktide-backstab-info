local mod = get_mod("BackstabHitboxDisplay")

return {
	name = "Backstab Hitbox Display",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				-- Master switch. Off = nothing at all (no cone, no counter).
				setting_id = "enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				-- The backstab cone(s) drawn in the world. Independent of the counter.
				setting_id = "show_cone",
				type = "checkbox",
				default_value = true,
			},
			{
				-- Only draw on enemies worth backstabbing: elites, specials, ogryns,
				-- monsters/bosses. Trash hordes are skipped. Off = draw on everything.
				setting_id = "only_special_enemies",
				type = "checkbox",
				default_value = true,
			},
			{
				-- Master performance lever: enemies further than this are skipped entirely.
				-- ~18m is roughly a few seconds of sprint -- close-range, not across the map.
				setting_id = "max_distance",
				type = "numeric",
				default_value = 18,
				range = { 5, 60 },
				decimals_number = 0,
				unit_text = " m",
			},
			{
				-- Hard cap on how many wedges we draw per frame, nearest-first.
				setting_id = "max_enemies",
				type = "numeric",
				default_value = 15,
				range = { 1, 50 },
				decimals_number = 0,
			},
			{
				-- Recompute throttle. 0 = every frame. Higher = cheaper but laggier visuals.
				setting_id = "update_interval",
				type = "numeric",
				default_value = 0.1,
				range = { 0, 0.5 },
				decimals_number = 2,
				unit_text = " s",
			},
			{
				-- Full cone width centered directly behind the enemy.
				-- CONFIRMED from game source (scripts/utilities/attack/attack_positioning):
				-- backstab when dot(dir_to_enemy, enemy_forward) > 0.5  ->  acos(0.5)=60 deg
				-- half-angle, i.e. a 120 deg cone. Leave at 120 for accuracy.
				setting_id = "backstab_arc",
				type = "numeric",
				default_value = 120,
				range = { 30, 180 },
				decimals_number = 0,
				unit_text = " deg",
			},
			{
				setting_id = "wedge_radius",
				type = "numeric",
				default_value = 1.5,
				range = { 0.5, 3.0 },
				decimals_number = 1,
				unit_text = " m",
			},
			{
				setting_id = "opacity",
				type = "numeric",
				default_value = 120,
				range = { 20, 255 },
				decimals_number = 0,
			},
			{
				setting_id = "show_facing_arrow",
				type = "checkbox",
				default_value = true,
			},
			{
				-- 3D sphere marker on the enemy's head -- where to aim for the one-shot.
				setting_id = "show_head_marker",
				type = "checkbox",
				default_value = true,
			},
			{
				-- Head sphere auto-scales per enemy size; this multiplies it to taste.
				setting_id = "head_marker_scale",
				type = "numeric",
				default_value = 1.0,
				range = { 0.5, 2.0 },
				decimals_number = 1,
			},
			{
				-- Head markers draw ON TOP of bodies, so keep their range short to avoid
				-- clutter. Separate from the cone distance.
				setting_id = "head_marker_distance",
				type = "numeric",
				default_value = 12,
				range = { 3, 40 },
				decimals_number = 0,
				unit_text = " m",
			},
			{
				-- Fake line thickness by stacking this many copies of the cone.
				setting_id = "cone_thickness",
				type = "numeric",
				default_value = 3,
				range = { 1, 5 },
				decimals_number = 0,
			},
			{
				-- Second cone floating above the enemy's head (no need to look down).
				setting_id = "draw_overhead",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "overhead_height",
				type = "numeric",
				default_value = 2.3,
				range = { 1.0, 3.5 },
				decimals_number = 1,
				unit_text = " m",
			},
			{
				-- Backstab counter / combo near the crosshair (shows "Backstab", "Backstab x2", ...).
				setting_id = "show_combo",
				type = "checkbox",
				default_value = true,
			},
			{
				-- Counter hides (and the streak ends) this long after your last backstab.
				setting_id = "combo_timeout",
				type = "numeric",
				default_value = 3.5,
				range = { 1.0, 10.0 },
				decimals_number = 1,
				unit_text = " s",
			},
			{
				-- Subtle size "pop" on the counter each backstab. Off = static text.
				setting_id = "pulse_animation",
				type = "checkbox",
				default_value = true,
			},
			{
				-- Killshot icon left of the counter when a backstab also hit a weakspot.
				setting_id = "show_weakspot_icon",
				type = "checkbox",
				default_value = true,
			},
			{
				-- Debug only: periodic diagnostics + measured head radii to the console log.
				-- Off by default; flip on only when troubleshooting. (Renamed from the old
				-- enable_logger so any leftover "on" saved value is reset to off.)
				setting_id = "debug_logging",
				type = "checkbox",
				default_value = false,
			},
		},
	},
}
