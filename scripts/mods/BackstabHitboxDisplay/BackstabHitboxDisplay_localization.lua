return {
	mod_description = {
		en = "Draws the backstab cone behind nearby enemies so you can see where attacks count as backstabs. Cone angle is a configurable approximation until matched to the game's source value.",
	},
	enabled = {
		en = "Enabled (master)",
	},
	show_cone = {
		en = "Show backstab cone",
	},
	show_small_mobs = {
		en = "Show on small mobs (trash)",
	},
	show_elites = {
		en = "Show on elites / specials / ogryns",
	},
	show_bosses = {
		en = "Show on bosses (monstrosities / captains)",
	},
	occlusion_cull = {
		en = "Hide enemies behind walls (line-of-sight)",
	},
	max_distance = {
		en = "Backstab cone distance",
	},
	max_enemies = {
		en = "Max enemies drawn",
	},
	update_interval = {
		en = "Recompute interval",
	},
	backstab_arc = {
		en = "Backstab cone angle (default 120)",
	},
	backstab_arc_description = {
		en = "Leave at 120 for accuracy. 120 degrees is the real game value -- a backstab " ..
			"triggers anywhere in the enemy's rear 120-degree cone (confirmed from the game " ..
			"source). This slider only changes the on-screen wedge width, not the actual " ..
			"backstab rule, so only move it if you deliberately want a wider or narrower marker.",
	},
	wedge_radius = {
		en = "Cone radius",
	},
	opacity = {
		en = "Cone opacity",
	},
	show_facing_arrow = {
		en = "Show enemy facing arrow",
	},
	show_head_marker = {
		en = "Show head weakspot marker",
	},
	head_marker_scale = {
		en = "Head marker size",
	},
	head_marker_distance = {
		en = "Head marker distance",
	},
	cone_thickness = {
		en = "Cone line thickness",
	},
	draw_overhead = {
		en = "Show overhead cone (above head)",
	},
	overhead_height = {
		en = "Overhead cone height",
	},
	overhead_distance = {
		en = "Overhead cone distance",
	},
	show_combo = {
		en = "Show backstab counter / combo",
	},
	combo_timeout = {
		en = "Counter timeout",
	},
	pulse_animation = {
		en = "Counter pop animation",
	},
	show_weakspot_icon = {
		en = "Show weakspot \"+\" on counter",
	},
	color_crosshair = {
		en = "Flash crosshair on backstab",
	},
	crosshair_color = {
		en = "Crosshair flash color",
	},
	color_green = { en = "Green" },
	color_cyan = { en = "Cyan" },
	color_blue = { en = "Blue" },
	color_magenta = { en = "Magenta" },
	color_yellow = { en = "Yellow" },
	color_orange = { en = "Orange" },
	color_white = { en = "White" },
	color_red = { en = "Red" },
	debug_logging = {
		en = "Debug logging",
	},
}
