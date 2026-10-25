# Implementation contract — v0.6.0

## Current roster, numeric authoring and Sparkle

Production built-ins are destruction_trailblazer and sparkle only. Retired sword/mage/guard/assassin overrides must not re-register those roles; retain old files for recovery. Missing selection IDs fall back to current roles with their default movement. New definitions default to HP1000, speed160, bounce and no skills/contact damage. Legacy default destruction overrides 1100/158 migrate to 1000/160; preserve other authored values.

Skill slots now optionally carry a parameters dictionary. SkillCatalog introspects exported SCRIPT_VARIABLE numeric/bool properties only, reads export-range metadata, validates values and applies only these properties to a fresh skill instance. Never expose Node process configuration or arbitrary saved property paths. Character editor generates numeric fields, saves them per role and snapshots them at match start. Future exported numeric fields appear automatically; register Chinese labels in PARAMETER_NAMES.

Bat snapshots a launch direction, then targets hand_origin + direction * throw_distance (default360). It does not stop at the enemy position. Reset hit_targets only at the outbound-to-return transition so each enemy can be hit once on each leg, with independent absolute outbound_damage/return_damage (default60 each). Collision smash uses independent damage120 and contact_extra24; the arena collects owner-specific extended proximity before skill ticks without changing body separation or adding generic contact damage.

Sparkle has six chambers with exactly one uniformly random live chamber per completed reload (arena.rng). Fire sequentially from chamber0 at shot_interval until the live round, then reload. Defaults: reload1.2s, interval0.35s, damage200, speed1400. Empty shots emit dry_fire without a projectile; live rounds emit red projectiles and return to reload. Aim updates to nearest living enemy each step, fighter.facing mirrors body art, gun and rotating cylinder are drawn independently. Audio consumes dry_fire/revolver_shot/revolver_reload events through bounded players, independent from battle time. Current fast Test.ps1 runs current_rules/current_ui_smoke/mobile_tests and persistence; historical old-roster assertions remain references for their old tags.

## Android and iterative mobile testing

Windows retains its desktop layout. OS.has_feature("android"), a mobile_mode override or --mobile enables the shared portrait presentation: 720x1280 logical viewport with expand aspect, sensor portrait, safe-area padding, config/battle pages, touch toolbar, paged character editor and a 3-column art picker. Normal game controls and model instances are shared, not duplicated. Opening config pauses a running battle; starting opens battle; back follows popup/editor/config/exit ordering. Android background saves settings and pauses combat/audio. Foreground restores audio but never silently resumes combat. Native PNG selection uses ACCESS_FILESYSTEM + image/png MIME and copies bytes into app-owned storage. Windows and phone data are intentionally independent.

BuildAndroid uses matching APK templates, ARM64, SDK36 and a persistent local development key under ignored tools/android. The stable package ID is com.starringarena.game. TestOnPhone resolves the actual launcher activity and uses non-streaming adb install -r, preserving user data. Never auto-uninstall, clear app data or replace the signing key to work around update failures. Setup pins and verifies tool archives; Android helper modifies only named export settings after backing up the editor settings file. UpdatePhone is the quick debug loop; BuildAndroid defaults to full regression. Include Android tools helper in the source package, exclude SDK/JDK/key caches; include licenses in the APK. mobile_tests verifies shared layout/navigation/lifecycle; actual phone checks complement desktop previews.

## Impact, audio and elimination presentation

MatchConfig and selection default to a 500 by 500 playable rectangle, excluding the 48-unit frame. settings_migration changes only the legacy 664-square default before the persisted map_default_500 marker; custom maps remain intact.

BattleArena.apply_damage keeps allow_reaction as argument five and appends an optional Vector2 impulse. Accepted damage, including shield absorption, applies the impulse in _resolve_damage; invalid/friendly events never move the target. During impact, movement strategies and skill timers still advance but impulse overrides requested/dash velocity. Exponential decay remains 8 per second; end below speed 60 or after 0.6 seconds. Sprite rotation is negative 720 degrees per second, then continues negative to an upright equivalent over 0.12 seconds. Continuous hits redirect impulse without resetting angle. Board rendering leaves health bars and hitboxes upright.

Death affects combat eligibility and results immediately. The death event contains its origin, last hit direction and angle; ArenaBoard owns a separate departure timeline (0.5-second hold, 0.45-second outward flight), independent of arena.running. The final overlay waits for all departures; pause and playback speed affect their clock. Board emits death_ejected once at flight start; simultaneous cheers merge. New match/selection clears these visuals and cheer playback. Default stationary character circles and overhead actor labels are removed; functional skill visuals remain.

GameAudio owns one looping OGG music player and a bounded cheer player. Load saved enabled/volume before starting music; mute changes gain without stopping playback. Audio is independent from battle pause/speed. Master gain remains global. Assets and third-party credits ship in source and runtime packages. feedback_tests covers 100 complete eight-player matches on the 500-square map, migrations, impacts, audio preferences and death timelines; feedback_visual verifies real playback, looping and rendered stages.

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
