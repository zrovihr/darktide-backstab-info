return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`BackstabHitboxDisplay` encountered an error loading the Darktide Mod Framework.")

		new_mod("BackstabHitboxDisplay", {
			mod_script       = "BackstabHitboxDisplay/scripts/mods/BackstabHitboxDisplay/BackstabHitboxDisplay",
			mod_data         = "BackstabHitboxDisplay/scripts/mods/BackstabHitboxDisplay/BackstabHitboxDisplay_data",
			mod_localization = "BackstabHitboxDisplay/scripts/mods/BackstabHitboxDisplay/BackstabHitboxDisplay_localization",
		})
	end,
	packages = {},
}
