local mod = get_mod("BackstabHitboxDisplay")

local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local COMBO_SIZE = { 500, 60 }
local BASE_FONT = 26
local PULSE_DURATION = 0.22
local KILL_FLASH_DURATION = 0.6

local COLOR_AMBER = { 255, 255, 170, 40 }   -- {a, r, g, b} -- normal backstab
local COLOR_RED = { 255, 235, 45, 45 }       -- backstab kill

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,
	-- Above the crosshair (where the old flash used to pop in).
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
	text_color = { 255, 255, 170, 40 },   -- {a, r, g, b} -- amber
	text_horizontal_alignment = "center",
	text_vertical_alignment = "center",
	size = COMBO_SIZE,
	offset = { 0, 0, 1 },
}

-- The crosshair's own weakspot hit-marker. Crucially this material is loaded in the HUD
-- renderer context (a settings-menu icon is NOT, and renders blank in the HUD).
local WEAKSPOT_ICON = "content/ui/materials/hud/crosshairs/hit_marker_weakspot"
local icon_style = {
	horizontal_alignment = "center",
	vertical_alignment = "center",
	size = { 34, 14 },
	offset = { -100, 0, 2 },
	color = { 255, 255, 220, 60 },
}

local widget_definitions = {
	combo = UIWidget.create_definition({
		{
			value_id = "text",
			style_id = "text",
			pass_type = "text",
			value = "",
			style = combo_style,
		},
		{
			pass_type = "texture",
			style_id = "icon",
			value = WEAKSPOT_ICON,
			style = icon_style,
			visibility_function = function(content, style)
				-- mod._icon_disabled is set if the icon material ever fails to render.
				return content.show_weakspot_icon == true and not mod._icon_disabled
			end,
		},
	}, "bsCombo"),
}

local HudElementBackstab = class("HudElementBackstab", "HudElementBase")

HudElementBackstab.init = function(self, parent, draw_layer, start_scale)
	HudElementBackstab.super.init(self, parent, draw_layer, start_scale, {
		scenegraph_definition = scenegraph_definition,
		widget_definitions = widget_definitions,
	})
	self.pulse_t = 0
	self.kill_t = 0
	self.show_t = 0   -- display timeout: counter hides (and streak ends) when this runs out
end

HudElementBackstab._update_impl = function(self, dt, t, ui_renderer, render_settings, input_service)
	local combo_widget = self._widgets_by_name.combo

	-- Brief scale pop each time a backstab lands (request raised by the detection hook).
	if mod.bs_flash then
		mod.bs_flash = false
		self.pulse_t = PULSE_DURATION
		self.show_t = mod:get("combo_timeout")   -- refresh the display timeout on each hit
	end
	-- Red flash on a backstab KILL.
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
	-- Display timeout: after a few seconds with no backstab, end the streak and hide.
	if self.show_t > 0 then
		self.show_t = math.max(0, self.show_t - dt)
		if self.show_t == 0 then
			mod.bs_combo = 0
			mod.bs_weak = false
		end
	end

	local combo = mod.bs_combo or 0
	if mod:get("enabled") and mod:get("show_combo") and self.show_t > 0 and combo >= 1 then
		combo_widget.content.text = (combo >= 2) and ("Backstab x" .. tostring(combo)) or "Backstab"
		combo_widget.alpha_multiplier = 1
		combo_widget.style.text.text_color = (self.kill_t > 0) and COLOR_RED or COLOR_AMBER
		-- Killshot icon to the left when the latest backstab also hit a weakspot.
		combo_widget.content.show_weakspot_icon = mod:get("show_weakspot_icon") and mod.bs_weak == true
		if mod:get("pulse_animation") then
			local pulse = self.pulse_t / PULSE_DURATION   -- 1 -> 0
			combo_widget.style.text.font_size = BASE_FONT + pulse * 8
		else
			combo_widget.style.text.font_size = BASE_FONT
		end
	else
		combo_widget.content.text = ""
		combo_widget.content.show_weakspot_icon = false
	end
end

-- PATCH SAFETY: never let the HUD logic or (more importantly) a render error -- e.g. a
-- game material this references being renamed in a patch -- crash the game. On the first
-- draw error we drop the optional icon; if it still fails, we disable the element.
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
		if not mod._icon_disabled then
			-- Most likely the optional weakspot icon material; drop it and keep the text.
			mod._icon_disabled = true
			self._widgets_by_name.combo.content.show_weakspot_icon = false
			pcall(function() mod:info("[safety] disabled weakspot icon after draw error: %s", tostring(err)) end)
		else
			-- Still failing without the icon -> shut the whole element down, no crash.
			self._dead = true
			pcall(function() mod:info("[safety] disabled backstab counter after draw error: %s", tostring(err)) end)
		end
	end
end

return HudElementBackstab
