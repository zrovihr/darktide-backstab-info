# Dev Reference — Backstab Hitbox Display

Quick index for working on this mod: where each function lives, and the exact Darktide
game-API facts we verified (so you don't have to re-fetch the datamine every time).

Line numbers drift as code changes — search by the function name if they're stale.
Datamine repo for all game-side lookups: **`Aussiemon/Darktide-Source-Code`**
(`gh api repos/Aussiemon/Darktide-Source-Code/contents/<path> --jq .content | base64 -d`).

---

## Files
```
BackstabHitboxDisplay.mod                              -- entry point (new_mod registration)
scripts/mods/BackstabHitboxDisplay/
  BackstabHitboxDisplay.lua            -- main: enemy enum, world draw (cones/spheres),
                                          occlusion, backstab detection, crosshair flash
  BackstabHitboxDisplay_data.lua       -- in-game settings (DMF options widgets)
  BackstabHitboxDisplay_localization.lua -- setting labels + *_description tooltips
  HudElementBackstab.lua               -- "Backstab" counter HUD element (text near crosshair)
```

## Source map — BackstabHitboxDisplay.lua
| Area | Function / symbol | ~Line | Notes |
|------|-------------------|-------|-------|
| Shared state | `mod.bs_combo/bs_best/bs_flash/bs_kill/bs_weak/bs_cross_flash` | 4–9 | written by hooks, read by HUD/crosshair |
| Enemy enum | `get_enemy_units()` | 62 | side_system → `side_by_unit` → `relation_units("enemy")` |
| Cone geometry | `add_wedge_layer` / `draw_backstab_wedge` / `draw_facing_arrow` | 101 / 119 / 127 | flat wedge behind enemy; z-up |
| Head sphere | `draw_circle` / `draw_head_marker` | 140 / 160 | 3 great circles = wireframe sphere |
| Head position | `head_position(unit)` | 166 | `HitZone.hit_zone_center_of_mass(unit,"head")` |
| Head size | `measure_head_radius` / `head_radius` | 199 / 252 | real raycast measure, cached per breed |
| Enemy filter | `enemy_category(unit)` / `is_enemy_shown(...)` / `is_target_alive(unit)` | 275 | 3 buckets: boss(monster/captain) / elite(elite/special/ogryn) / small(trash); each toggled by show_bosses/show_elites/show_small_mobs. `is_target_alive` = `health_system:is_alive()` so the overlay drops the instant a target dies (Unit.alive lingers on the corpse) |
| **Occlusion** | `LOS_FILTER` / `eye_position` / `head_visible` | 301 / 303 / 332 | see Occlusion section below |
| Draw pass | `rebuild(lo_cone, lo_top, world)` | 381 | throttled; collects, sorts, culls, draws |
| Update/self-heal | `invalidate_line_objects` / `update_impl` / `mod.update` | 567 / 575 / 630 | recovers from stale line objects |
| Backstab math | `compute_backstab` | 692 | `dot(dir_to_enemy, enemy_fwd) > 0.5` |
| Combo hook | `register_melee_hit` / `on_attack_result` + `hook_safe` | 716 / 737 / 759 | AttackReportManager |
| **Crosshair flash** | `CROSSHAIR_COLORS` / `is_color_pass` / `crosshair_apply_tint` / `crosshair_restore` / `crosshair_flash_update` + `hook_safe` | 781 / 797 / 801 / 829 / 843 / 872 | see Crosshair section |
| HUD register | `mod:register_hud_element{...}` | 881 | registers HudElementBackstab |

## Source map — HudElementBackstab.lua
`init` (50) · `_update_impl` (60, consumes bs_flash/bs_kill, `show_t` HIDE-only timeout) ·
`update` (105, pcall-guarded) · `draw` (113, pcall-guarded, self-disables on draw error).

---

## Game-API reference (verified this project)

### Backstab rule — CONFIRMED
`scripts/utilities/attack/attack_positioning.lua`: melee only;
`dir = normalize(flat(enemy_pos - attacker_pos))`; backstab when
`dot(dir, enemy_flat_forward) > 0.5` (= rear **120°** cone). Location-independent;
attacker facing is NOT used. See memory [[backstab-mechanic-confirmed]].

### Occlusion / line-of-sight raycast
- Filter: **`"filter_minion_line_of_sight_check"`** — hits world/static geometry, IGNORES
  all character bodies (minions + the player). Source: `scripts/extension_systems/cover/utilities/cover_slots.lua`.
- DO NOT use `"filter_player_character_shooting_raycast"` for camera→world LOS: it hits the
  player, and the eye sits inside the player capsule, so `"closest"` returns your own body
  at ~0m forever. (That filter is fine for head measurement, which rays from outside the head.)
- **Raycast return for `"closest"`:** `hit(bool), position(Vector3), distance(number), normal, actor`.
  First return is a BOOLEAN, not the position. `local hit, position, distance = PhysicsWorld.raycast(...)`.
- Form: `PhysicsWorld.raycast(pw, origin, dir, len, "closest", "collision_filter", filter)`.
- Eye origin: `ScriptUnit.extension(player_unit,"first_person_system"):first_person_unit()`
  → `Unit.world_position(fp_unit,1)`. Source: `.../weapon/actions/action_throw_grenade.lua`.
- See memory [[occlusion-los-raycast]].

### Head hitbox measurement
Raycast the head collision actor with `"filter_player_character_shooting_raycast"`;
actors via `unit_data_system:hit_zone_actors("head")`; "all" mode hit tuple is
`{position, distance, normal, actor}` (hit[1]=pos, hit[4]=actor). Memory [[head-hitbox-measurement]].

### Backstab detection hook
`CLASS.AttackReportManager.add_attack_result(self, damage_profile, attacked_unit,
attacking_unit, attack_direction, hit_world_position, hit_weakspot, damage, attack_result,
attack_type, damage_efficiency, ...)`. `attack_result` is `"damaged"`/`"died"`; `attack_type` `"melee"`.

### Crosshair recolor
- Class `HudElementCrosshair` — `scripts/ui/hud/elements/crosshair/hud_element_crosshair.lua`;
  per-weapon templates in `templates/crosshair_template_*.lua` (NO `_melee`; melee uses `dot`).
- Reticle color passes use `color = UIHudSettings.color_tint_main_1` (SHARED global); the
  template `update_function` does NOT reassign reticle color each frame. Swap in your own
  table for the flash and restore — never mutate the shared one. The `dot` template's only
  reticle pass is the centre dot; directional `hit_*` passes are the hit-feedback ticks.
- See memory [[crosshair-tint-shared-colors]].

### Enemy / breed / side
- `Managers.state.extension:system("side_system")`; `side_system.side_by_unit[player_unit]`;
  `side:relation_units("enemy")`.
- Breed tags: `unit_data_system:breed().tags` → `elite/special/ogryn/monster/captain`
  (`scripts/utilities/breed.lua`).

### Line drawing
`World.create_line_object(world[, true])` (2nd arg = no depth test) · `LineObject.add_line`
· `LineObject.reset` · `LineObject.dispatch(world, lo)` each frame. Line objects go stale
when their world is torn down → `LineObject.*` throws "got userdata"; recreate, don't latch off.

## DMF API gotchas
- **Hook unloaded classes by STRING name** for delayed hooks: `mod:hook_safe("HudElementCrosshair","update",fn)`.
  Engine globals present at boot (e.g. `CLASS.AttackReportManager`) can be passed directly.
  `dmf/scripts/mods/dmf/modules/core/hooks.lua` (~L319).
- **Tooltips auto-resolve** from `<setting_id>_description` localization (no widget field
  needed); explicit `tooltip = "<key>"` also works. `.../core/options.lua` (~L100–103).
- Widget types used: `checkbox`, `numeric`, `dropdown` (options `{text="loc_key", value=...}`), `group`.

## Dev workflow
- Edit in `C:\DEV\Mods\Darktide\Backstab Hitbox Display\`, deploy to
  `E:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\BackstabHitboxDisplay\scripts\mods\BackstabHitboxDisplay\`.
  Must be in `<game>\mods\mod_load_order.txt`. **Restart** game for script/data changes (no hot reload).
- Console logs: `%APPDATA%\Fatshark\Darktide\console_logs\*.log`; mod logs via `mod:info`
  (gated behind the `debug_logging` setting). Read newest log off disk to test.
- Package (Nexus): zip `BackstabHitboxDisplay/` (the `.mod` + `scripts/`) → `dist/BackstabHitboxDisplay.zip`
  (no `zip` binary on PATH; use PowerShell `Compress-Archive`). Version is set in the Nexus UI.
- See memory [[backstab-mod-dev-workflow]] and [[patch-safety-design-goal]].

---

## Session history & decisions
Running log of what was changed and WHY — the parts that aren't obvious from the code, plus
dead-ends so they aren't repeated. Newest first.

### 2026-06-25 session
- **Self-heal for stale line objects.** Root cause of "mod stopped rendering then never came
  back": on a level transition the cached `line_object` goes stale; `LineObject.reset` threw
  "got userdata", and the old code set `cone_dead = true` PERMANENTLY for the session. Fixed:
  on a draw error, drop the cached objects and rebuild next frame; only latch off after
  `CONE_FAIL_LIMIT` (30) consecutive failures. (The crash that session was a *different* mod,
  Healthbars — not us.)
- **Separate render distances.** Split the single "Max render distance" into cone /
  overhead-cone / head-marker distances (head already had its own). `collect_distance` =
  max of the enabled ones. Renamed the misleading "Max render distance" label → "Backstab
  cone distance" but KEPT setting id `max_distance` so saved values carry over. Overhead cone
  draws on its own distance, decoupled from the ground cone.
- **Occlusion cull — the big one. Long debug saga; key dead-ends:**
  1. First attempt read the raycast's 1st return as the hit position → it's a BOOLEAN → threw
     every frame → pcall swallowed it → everything fell to "visible". Lesson: `"closest"`
     returns `hit(bool), position, distance, ...`.
  2. Tried the gun filter `filter_player_character_shooting_raycast` to "guarantee" hitting
     walls → it hits the PLAYER; eye is inside the player capsule so `"closest"` returned our
     own body at ~0m every time → everything occluded. A forward "look-ray" probe printing
     `hit=true dist=0.0m` exposed this instantly.
  3. Final: `filter_minion_line_of_sight_check` (ignores ALL characters, hits world only) +
     correct return parsing. This also matches the user's "walls only, not other enemies"
     preference. Tiny `START_OFFSET` (0.1m) off the camera; `TARGET_CLEAR` (1.0m) ignores a
     wall flush behind the head. Off by default. Point→head-center ray (no sphere math).
  - Testing note: Psykhanium dummies are often out of range or in open LOS — needs a dummy
    within range with a pillar genuinely on the eye→head line. `[cull]`/`[probe]` debug lines
    (gated by `debug_logging`) were the key instrument.
- **Crosshair backstab flash.** Tints the game reticle a preset color on a backstab; separate
  toggle, "Backstab" text untouched. Gotchas hit: (1) must hook by string name (class not in
  CLASS at boot); (2) reticle colors are shared globals — swap/restore, don't mutate; (3) the
  melee/`dot` crosshair's only reticle pass is the centre dot, so tint ALL color passes
  (incl. `hit_*` ticks, re-applied each frame) to color the whole crosshair, not just the dot.
- **Combo counter now persists.** `combo_timeout` HIDES the counter instead of resetting the
  streak; a later backstab continues the count. Only a non-backstab melee hit breaks it.
- **Cone-angle info.** Label shows "(default 120)"; `backstab_arc_description` adds a hover
  tooltip explaining 120° is the accurate game value and the slider is visual-only.
- **Packaging.** `dist/BackstabHitboxDisplay.zip` rebuilt with all of the above (the old zip
  was the pre-session build). Suggested Nexus version bump to 1.1.0 (changelog drafted in chat).
- Memories written/updated: [[occlusion-los-raycast]], [[crosshair-tint-shared-colors]].
