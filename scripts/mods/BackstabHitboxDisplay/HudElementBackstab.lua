local mod = get_mod("BackstabHitboxDisplay")

local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local COMBO_SIZE = { 500, 60 }
local BASE_FONT = 26
local PULSE_DURATION = 0.22
local KILL_FLASH_DURATION = 0.6

local COLOR_AMBER = { 255, 255, 170, 40 }   -- {a, r, g, b} -- normal backstab
local COLOR_RED = { 255, 235, 45, 45 }       -- backstab kill

-- Weakspot backstab is shown as "Backstab+" (the + = also hit a weakspot). Plain text,
-- so it always renders -- a material icon needs its package loaded in this renderer,
-- which a custom HUD element doesn't have.

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,
	bsCombo = {
		parent = "screen",
		scale = "fit",
		vertical_alignment = "center",
		horizontal_alignment = "center",
		size = COMBO_SIZE,
		position = { 0, -150, 30 },
	},
}

local combo_style = {
	font_type = "machine_medium",
	font_size = BASE_FONT,
	drop_shadow = true,
	text_color = { 255, 255, 170, 40 },
	text_horizontal_alignment = "center",
	text_vertical_alignment = "center",
	size = COMBO_SIZE,
	offset = { 0, 0, 1 },
}

local widget_definitions = {
	combo = UIWidget.create_definition(
		{ { value_id = "text", style_id = "text", pass_type = "text", value = "", style = combo_style } },
		"bsCombo"
	),
}

local HudElementBackstab = class("HudElementBackstab", "HudElementBase")

HudElementBackstab.init = function(self, parent, draw_layer, start_scale)
	HudElementBackstab.super.init(self, parent, draw_layer, start_scale, {
		scenegraph_definition = scenegraph_definition,
		widget_definitions = widget_definitions,
	})
	self.pulse_t = 0
	self.kill_t = 0
	self.show_t = 0   -- display timeout: counter HIDES when this runs out (streak is NOT reset)
end

HudElementBackstab._update_impl = function(self, dt, t, ui_renderer, render_settings, input_service)
	local combo_widget = self._widgets_by_name.combo

	if mod.bs_flash then
		mod.bs_flash = false
		self.pulse_t = PULSE_DURATION
		self.show_t = mod:get("combo_timeout")   -- refresh display timeout on each hit
	end
	if mod.bs_kill then
		mod.bs_kill = false
		self.kill_t = KILL_FLASH_DURATION
	end
	if self.pulse_t > 0 then
		self.pulse_t = math.max(0, self.pulse_t - dt)
	end
	if self.kill_t > 0 then
		self.kill_t = math.max(0, self.kill_t - dt)
	end
	-- Counter just HIDES when this runs out; the streak is NOT reset. Only a non-backstab
	-- melee hit breaks it (see register_melee_hit), so a later backstab continues the count.
	if self.show_t > 0 then
		self.show_t = math.max(0, self.show_t - dt)
	end

	local combo = mod.bs_combo or 0
	if mod:get("enabled") and mod:get("show_combo") and self.show_t > 0 and combo >= 1 then
		-- "Backstab+" when the latest backstab also hit a weakspot, else "Backstab".
		local weak = mod:get("show_weakspot_icon") and mod.bs_weak == true
		local word = weak and "Backstab+" or "Backstab"
		combo_widget.content.text = (combo >= 2) and (word .. " x" .. tostring(combo)) or word
		combo_widget.alpha_multiplier = 1
		combo_widget.style.text.text_color = (self.kill_t > 0) and COLOR_RED or COLOR_AMBER

		if mod:get("pulse_animation") then
			local pulse = self.pulse_t / PULSE_DURATION   -- 1 -> 0
			combo_widget.style.text.font_size = BASE_FONT + pulse * 8
		else
			combo_widget.style.text.font_size = BASE_FONT
		end
	else
		combo_widget.content.text = ""
	end
end

-- PATCH SAFETY: never let HUD logic or a render error crash the game.
HudElementBackstab.update = function(self, dt, t, ui_renderer, render_settings, input_service)
	HudElementBackstab.super.update(self, dt, t, ui_renderer, render_settings, input_service)
	if self._dead then
		return
	end
	pcall(HudElementBackstab._update_impl, self, dt, t, ui_renderer, render_settings, input_service)
end

HudElementBackstab.draw = function(self, dt, t, ui_renderer, render_settings, input_service)
	if self._dead then
		return
	end
	local ok, err = pcall(HudElementBackstab.super.draw, self, dt, t, ui_renderer, render_settings, input_service)
	if not ok then
		self._dead = true
		pcall(function() mod:info("[safety] disabled backstab counter after draw error: %s", tostring(err)) end)
	end
end

return HudElementBackstab
