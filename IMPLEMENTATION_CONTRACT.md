# Implementation contract — v0.3.0

## Destruction Trailblazer

The built-in roster now has five characters. destruction_trailblazer declares two explicit skill slots: bat_throw (default six seconds, editable up to sixty), collision_smash (passive).

BattleArena collects enemy-only body contacts during separation and delivers on_enemy_contact once per enemy per simulation step, before skill timers advance. Clear contact arrays on every step and on Fighter teardown to break reference cycles. Sustained touching is debounced by the collision skill; a real separation is needed before another contact entry can damage.

Returning bat owns its charge and flight phases. It snapshots the nearest enemy position only at launch, travels to that point, then returns to the current owner hand position. It holds the release image and the active-cast lock throughout both legs; fixed release_time must not end this image. Catch/death/end resets to held/normal. One bat exists per skill instance. Damage is swept and limited to once per enemy for the full trip. Collision resets pending charge without canceling an already airborne bat.

Rendering supports bat, charge_meter and smash effects. Fighter.lift_time is visual feedback only and is cleared at match end. destruction_tests.gd covers behavior; destruction_visual.gd captures five actual render stages. Legacy tests retain the original mechanics and now include all 25 ordered pairings.

Godot 4.7.2, GDScript, compatibility rendering. Version 0.1.0 is recoverable with Git tag baseline-v0.1.0; packaged baselines live in build/baselines/.

## Content

CharacterDefinition contains immutable authoring data, optional legacy skill_scenes, and skill_slots. CharacterLibrary overlays versioned user://characters JSON on built-in resources. PNG imports are verified and copied into characters/images. SkillCatalog is the code-only registry for saved template IDs; saves never contain executable scene paths. Slot IDs distinguish multiple instances of the same template. Do not store timers or health on shared resources.

Built-in character IDs remain sword/mage/guard/assassin, displayed with supplied Yanqing/Himeko/Gepard/Blade sticker art. assets/stickers/manifest.json indexes 416 PNGs for the searchable browser. Export must include JSON and all textures.

## Skills

SkillBase.request_cast(target) owns real charge and release phases. activate(target) is the concrete effect hook; tick(delta) uses simulation time. One active cast per fighter, passives and sustained effects run independently. Movement locking stops desired velocity but not knockback. Targets may be reacquired at release. Missing state textures fall back to normal. Death/end cancels casts.

Guardian is decomposed into melee, shield, counter templates. The legacy guardian scene remains supported for prior extensions. Sustained orbit blades do not acquire charge phases. Counter damage uses allow_reaction=false. Per-target blade cooldowns and per-dash target sets prevent repeated damage.

## Matches

MatchConfig contains dimensions (480–2400 each), mode (ffa/teams), seed, duration and 2–8 participant dictionaries (definition/movement/team). start_match returns an error string without replacing a current match when validation fails. start_battle wraps legacy definitions and movements into a default FFA config.

Fighter.fighter_id is unique, side remains a legacy alias, team_id controls allegiance. is_enemy/get_targets/nearest_enemy centrally define enemy selection. opponent is a nearest-enemy alias. Friendly damage and hostile status are rejected centrally; allied bodies do not block projectiles. All live bodies participate in deterministic separation.

World bounds start at (48,48), rendering includes a 48-unit decorative margin. PNG dimensions never change collision or actual world speed. Rendering fits the entire rectangle. Spawn validation prevents overlapping starts.

winner_team and result expose team/draw/reason. winner remains a representative actor index for old 1v1 callers. Final team survives to win; simultaneous elimination draws. At 90s compare remaining HP / starting maximum HP per team, counting dead members in the denominator.

## UI and tests

main.gd owns orchestration; match_panel.gd owns roster slots and config persistence; character_editor.gd owns drafts and import/browser UI; arena_board.gd is presentation only. Main advances arena at fixed 1/60 simulation steps. Per-fighter visual state follows simulation time, hit flashes decay in the presentation layer.

settings.cfg configuration_v2 stores stable character IDs and map/slots. Legacy two-index selections migrate once. qa_mode isolates preferences and character files during tests.

Run Test.ps1 for legacy, editor/multiplayer and UI headless tests plus cross-process persistence. Native ui_smoke.gd verifies rendering, performance_smoke.gd checks 8 sustained actors at 2x. Build.ps1 runs required checks before exporting. Pack source via Git archive and distribute the entire Windows directory, including PCK and notices.
