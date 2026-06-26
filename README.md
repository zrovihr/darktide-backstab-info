# Backstab Hitbox Display

A Darktide (DMF) mod that draws the **backstab cone** behind nearby enemies — the
angular region where your attacks register as backstabs.

## Status: scaffold / approximation

This works as a visual tool but is **not yet confirmed accurate**. See open questions.

## Files

```
BackstabHitboxDisplay.mod                  -- mod definition (entry point)
scripts/mods/BackstabHitboxDisplay/
  BackstabHitboxDisplay.lua                -- main logic: enumerate enemies + draw cones
  BackstabHitboxDisplay_data.lua           -- in-game mod menu settings
  BackstabHitboxDisplay_localization.lua   -- setting/label strings
```

## In-game settings (performance levers)

- **Backstab cone distance** — how far the ground red cone (and its facing arrow) draws.
- **Overhead cone distance** — independent distance for the overhead cone, so you can keep
  it visible further out without cluttering the ground.
- **Head marker render distance** — independent distance for the head sphere.
- **Flash crosshair on backstab** + **Crosshair flash color** — briefly tints the in-game
  crosshair a preset colour when a backstab connects. Separate toggle; the "Backstab"
  counter text is unaffected. Swaps the reticle's colour table for the flash and restores
  the original after, so the game's shared HUD colours are never mutated.
- **Max enemies drawn** — hard cap, nearest-first.
- **Recompute interval** — throttle the enemy scan (0 = every frame).
- **Backstab cone angle** — the approximation knob (see below).
- **Cone radius / opacity** — visuals.
- **Show enemy facing arrow** — debug aid for verifying facing math.
- **Hide enemies behind walls (line-of-sight)** — off by default. Culls the cone +
  head marker for enemies whose head is occluded by world geometry. Casts one
  line-of-sight ray (game filter `filter_minion_line_of_sight_check`) per drawn
  enemy from the first-person camera; it ignores other enemies, so they never count
  as occluders. Costs more at large render distance / enemy caps, hence opt-in.

## Backstab mechanic — CONFIRMED from source

Source: `scripts/utilities/attack/attack_positioning.lua` in
[Aussiemon/Darktide-Source-Code](https://github.com/Aussiemon/Darktide-Source-Code)
(function `AttackPositioning.is_backstabbing`). Verified against in-game logger data.

- **Melee only.** Ranged uses `is_flanking` (threshold `0` = full rear hemisphere).
- `dir = normalize(flat(enemy_pos - attacker_pos))` — direction from attacker to enemy.
- `fwd = normalize(flat(Quaternion.forward(Unit.world_rotation(enemy, 1))))` (minions);
  players use the first-person look rotation.
- **Backstab when `dot(dir, fwd) > 0.5`** → `acos(0.5)` = 60 deg half-angle =
  **120 deg cone centered directly behind the enemy.** This is `backstab_arc`'s default.
- Independent of hit location. Weakspot (head etc.) is the separate `hit_zone_name`
  system; the one-shot combo is backstab (angle) + weakspot (location) + crit/talents.
- `can_outmanoeuvre` (whether the bonus actually applies) additionally needs the weapon's
  damage profile to have `backstab_bonus`, or the attacker to have the
  `allow_backstabbing` buff keyword. The cone shows the *geometry*; whether your build
  benefits is weapon/talent dependent.

## Resolved / verified API

- `Attack.execute(target_unit, damage_profile, ...k/v pairs...)` — keys include
  `hit_zone_name`, `attack_direction`, `attacking_unit`, `is_critical_strike`,
  `attack_type` ("melee"/"buff"/...). Decoded from logs.
- Enemy facing via `Unit.world_rotation(unit, 1)` -> `Quaternion.forward` — matches source.

## Still to verify

- The side-system enumeration in `get_enemy_units()` (`get_side_from_unit`,
  `relation_units("enemy")`) — confirm cones actually render in a live mission.

## Build & install

1. Install the **Warhammer 40,000: DARKTIDE Mod SDK** (Steam library tools).
2. Build with the SDK's `vmb` bundler, or for quick local testing copy this folder
   into `<Darktide>/mods/BackstabHitboxDisplay/` and add `BackstabHitboxDisplay`
   to `<Darktide>/mods/mod_load_order.txt`.
3. Requires **Darktide Mod Loader (DML)** + **Darktide Mod Framework (DMF)** installed.
4. Visual mod → puts you in the modded realm (no official progression). Expected.
