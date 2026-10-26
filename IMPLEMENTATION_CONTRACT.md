# Implementation contract — v0.8.0

## Local defaults and publishing policy

Only commit, push or publish when explicitly requested by the user. Daily updates edit the local source only: do not export Windows/APK or regenerate archives per change. Ensure StartGame.cmd runs the current source; package when the user explicitly requests a package or GitHub publication. Built-in resources snapshot the current Windows character settings as of this update (including numeric skill parameters); retired overrides remain excluded. Existing authored overrides continue to take precedence. Destruction collision defaults: damage80, knockback2400, rehit0.1. Bat: distance500, outgoing/return80 each, radius30, knockback1000. Sparkle defaults: damage180, reload0.1, shot interval1.6. Yunli retains its existing configuration.

The editor no longer exposes base attack. Retain the underlying legacy attack field and serialization for compatibility with older skill templates; editing a role must not change it. Description is a wrapping TextEdit, preserving newline characters through draft, persistence and preview.


## Match history and automatic seeds

History is local only, unlimited retention, manual single delete/confirmed clear. MatchHistory begins after configuration validation and old-session discard/arena clear, before the new start, so initial skill/item events are captured. Snapshot character data, effective numeric skill defaults and saved overrides/names/labels; later library/default edits cannot rewrite history. Only battle_ended with elimination/timeout commits, including draws, immediately before the4-real-second result wait. Restart/selection/crash before completion produces no record. Preview arenas are not subscribed. QA uses separate storage.

BattleArena.combat_event is an independent unbounded semantic stream; preserve4096 debug cap and512 effect cap. record_event adds tick/time without RNG or gameplay changes; _log forwards while phase/state/projectile/item/shrink/mark/airborne events supplement missing transitions. No per-frame trajectories or decorative particles. Start precedes initialization events; end is last. History assigns sequence numbers and converts vectors/rects/colours to JSON values, never runtime object references. Snapshot final stats (damage includes shields), outcome, timestamps, config/seed, version and final field. Do not record post-result movement.

Store individual version1 JSON files under user://match_history with atomic temp/rename and a lightweight index. Read summaries first, full records on demand; rebuild missing/broken index entries from complete files. Aborted temporary files are not history. A failed completion stays in a separate pending dictionary across rematches for explicit retry; never drop it when starting a new session. Safe owned IDs bound deletion to this store, no automatic eviction or remote operations. HistoryPanel lists20/page and events100/page, actor/type filters; missing art falls back to icon, snapshot text remains. Desktop header/mobile config entries are disabled during combat and result waiting; result opens its record. Mobile back: confirmation -> detail -> list -> previous page. Preserve original config/result beneath panel and protect active games from shortcuts.


## Acheron warning, cut walls and forfeits

Acheron charges7s, initially centres the warning on a selected enemy and then tracks at a limited480 units/s. Translation limit and60-degree/s rotation limit diminish by(1-progress)^2; seeded base angle,20-degree wobble and0.25s jitter remain. At7s retain the current actual centre/angle (no snap back) and lock1.5s before10000 ordinary damage to each collidable enemy along the field line (target radius plus12 half-width). Default movement/stats remain bounce/160/1000. Charge/recovery and random choices use fixed battle time/seed.

BattleArena retains cut_walls across caster death and match end, clears on restart. Every cut is a two-sided strip (half-width7) blocking all grounded actors; per-fighter side records prevent solver corrections crossing old cuts. Ordinary motion uses swept circle/line contacts and reflects remaining travel, velocity and knockback. Aglaea/Feiying clip their movement before swept dash damage and terminate overrides on seam contact. Airborne retains existing no-collision behavior but legal-side projection applies on landing. Projectiles and weapon effects do not collide with seams. When shrinking, wall origins and strip widths scale about the original centre along with the complete decorated board, no camera zoom.

Every physical outer/seam contact gives Acheron a1.5 percent seeded loss roll; deduplicate combined corners/solver contacts within a fixed step. forfeit_outside has an optional trailing exit_velocity, immediately defeats the fighter and emits a lost departure with confused image261 and complete pre-reflection velocity. Board uses origin+velocity*age, no acceleration/hold/spin; clean up only once outside the visible viewport, not at a fixed0.95s. Winner is resolved independently of animation.

Original PNG262 is never rewritten. Board caches one192-pixel SubViewport per Acheron for red/white transformation. A root CanvasLayer screen-reading shader covers the whole viewport including UI, expands from the release's screen position over0.5s, then holds1.5s. Restore colour and restart charging at the combined2s. Keep red highlights; brighten arena panels without brightening the transparent corners/background rectangle. Waves remain independent of active skills after a winning slash; freeze on pause/source time stop and follow display speed. The same controller selects editor preview waves. colour_hold_time replaces the old total colour_recovery_time: old default1 upgrades to1.5 hold; custom total converts to max(0,total-expand), idempotently without changing other parameters.

## Complete board plates and result presentation

board_backdrop caches the full decorated arena to a transparent texture (max1024px). board_plates clips the complete outer rectangle into convex pieces using wall strips. Each cut adds4 units of normal offset per side, accumulated offset clamped to12 units. Each leaf uses separately mixed SHA256-derived phases/frequencies (adjacent String.hash values were nearly identical and caused synchronized motion). Smooth bounded drift max1.5, x0.08–0.12Hz/y0.06–0.10Hz, never cumulative or battle-RNG dependent. Scale offsets with arena shrinking. Piece rendering, actor/bar/mark/item transforms and split world-space trails use the same mapping; physics positions never wobble. Shrink the whole backdrop/frame/decorations and hand sprites around the original centre; keep actor size and original camera framing.



## Memory, time stop and Castorice

Roster adds memory_trailblazer, castorice (speed50) and acheron, for eight built-ins. Mimi is a following skill/sprite, never another participant:13 punches/s, damage10, edge-gap range21; own settled punch grants3.5 percent, other allied effective damage5, never both. SkillBase.on_battle_damage observes accepted damage after settlement; stop requests activate at end of a fixed step in deterministic order. Stop7 seconds, only its owner acts, no charging during any stop, end resets charge0. damage_type is an optional trailing apply_damage argument; true is currently a visual tag using ordinary shields/mitigation. Defense numbers remain ordinary; frozen targets do not react or cast.

Mimi has an instance-local display position: move toward the selected eligible enemy at800 units/s, return above its owner at650 when no target; both speeds are editable. Travel is presentation only and does not gate or extend damage range/cadence. Draw the summon after actor bodies so it remains visible beside the target. Board renders one ashen-hand sprite per actual aura stack in a head-top fan, separate rows for independent sources; use the existing aura ledger so icons clear with gameplay marks without maintaining duplicate state.

Arena owns time_stop_owner/remaining/pending, world_elapsed, immutable initial_bounds, mutable bounds and shrink state. Battle elapsed continues through time stop, world and other actor clocks do not. Skip frozen movement, timers, contact, skill ticks, projectiles, pickup refresh and shrinking. Reject damage/status/projectile/pickup actions from frozen sources. Incoming owner damage may still affect frozen HP/shields. Active caster passes through frozen actors. End/death/restart releases stop and clears references. Board uses actor local clocks for idle/sprite animation and projectile/world clocks for items; hit feedback may animate.

Castorice aura radius180, per-enemy one-second damage25/one mark, max9; total slow=(6+stacks) percent,9=>15 percent, not cumulative layer sums. Separate source ledgers, strongest slow, clear immediately on leaving/airborne/death; cleanup_spatial_effects is a deactivation-only hook even during stop. Chase only current aura members, else restore configured movement. At9 marks, physical contact executes once for100000 per entry cycle. Accepted damage adds retreat impulse based on configured distance18; frozen target cannot recoil.


## Portrait softness and hit squash

ArenaBoard alone owns hit_reactions and bounded dash_ghosts; no combat/schema/skill parameter changes. Valid hit events (amount>0 or absorbed>0) drive local Y scale: start/current ->0.84 at0.04s ->1.02 at0.12s ->1 at0.18s, smoothstep each leg. Retrigger from current scale, never multiply. Width keeps only existing idle breathing; remove flash-driven uniform enlargement while preserving flash tint. Apply squash around the authored PNG center with its configured offset stable; placeholders use the same local Y scale. Bars, labels, weapons, projectiles and collision remain independent. Lethal hit squashes during the departure hold and restores before ejection.


## Ordinary contact reflection


## Feiying pickups, ram and airborne state

Roster includes feiying. Arena owns one global toast and one coalesced refresh timer. Spawn one initial toast even with several Feiying; never expire it or periodically add more. Consuming it waits for Dayun completion, then refreshes at1s by default. A surviving Feiying can continue the shared cycle after another dies; none alive/end/restart clears all pending state. Only normal grounded Feiying picks toast up. Heal125, charge1.5 using image042, snapshot the enemy direction at release, then ram straight to the exact ray/wall intersection, ignoring knockback while still taking damage. Hit each eligible enemy at most once per rush for150 plus accepted-hit airborne payload; hits never end the rush. At the wall stop and return to image039. No fixed distance limit. After5 normal seconds desired_velocity_override seeks nearest toast. toast_respawn_delay replaces obsolete spawn interval/count/lifetime exports; ram_max_distance is obsolete. Other skill numbers remain exported/localized.


## Aglaea threads and runtime movement

Roster now includes aglaea. Fighter.movement_speed() returns configured base speed plus instance-only movement_speed_bonus, used by all four strategies. Wall constraints notify active skills once per combined corner contact; Aglaea deduplicates the same tick/anchor. First contact plants an anchor, each subsequent wall completes a segment. Required segments = ceil(initial_thread_count + max(0,current normal speed - configured starting speed)*threads_per_speed). Default1, coefficient0.05; each completed dash adds20 for the current match only.


## Yunli and settled damage observation

Lao Tie snapshots the nearest enemy position at release and flies along that fixed direction through enemies until entirely outside the map. Each projectile hits each enemy at most once, never teammates. Arena supports optional piercing projectiles with a per-instance hit ledger and ordered segment contacts; normal projectiles retain first-hit removal. Yunli computes a map-sized safety lifetime and uses an 84-unit minimum exit margin for the spinning weapon visual; legacy sword_lifetime is no longer exposed or used.

Roster adds yunli, default HP1000/speed160/bounce. Yunli heals30 per full second only in eating state. The first effective settled hit triggers a four-second guard after that hit; it is neither reduced nor accumulated. Subsequent damage is reduced20%, counted as actual HP lost after shields, and never refreshes the guard timer. Guard ends with an independent spinning Lao Tie projectile (150 + 0.4 * stored HP loss), then immediately returns to eating. Projectile damage is snapshotted; death/end cancels pending guard. All numeric exports are editable per role.


## Current roster, numeric authoring and Sparkle

Production built-ins are destruction_trailblazer, sparkle, yunli, aglaea, feiying, memory_trailblazer and castorice. Retired sword/mage/guard/assassin overrides must not re-register those roles; retain old files for recovery. Missing selection IDs fall back to current roles with their default movement. New definitions default to HP1000, speed160, bounce and no skills/contact damage. Legacy default destruction overrides 1100/158 migrate to 1000/160; preserve other authored values.

Skill slots now optionally carry a parameters dictionary. SkillCatalog introspects exported SCRIPT_VARIABLE numeric/bool properties only, reads export-range metadata, validates values and applies only these properties to a fresh skill instance. Never expose Node process configuration or arbitrary saved property paths. Character editor generates numeric fields, saves them per role and snapshots them at match start. Future exported numeric fields appear automatically; register Chinese labels in PARAMETER_NAMES.

Bat snapshots a launch direction, then targets hand_origin + direction * throw_distance (default500). It does not stop at the enemy position. Reset hit_targets only at the outbound-to-return transition so each enemy can be hit once on each leg, with independent absolute outbound_damage/return_damage (default80 each). Collision smash uses independent damage80 and contact_extra24; the arena collects owner-specific extended proximity before skill ticks without changing body separation or adding generic contact damage.


## Android and iterative mobile testing

Windows retains its desktop layout. OS.has_feature("android"), a mobile_mode override or --mobile enables the shared portrait presentation: 720x1280 logical viewport with expand aspect, sensor portrait, safe-area padding, config/battle pages, touch toolbar, paged character editor and a 3-column art picker. Normal game controls and model instances are shared, not duplicated. Opening config pauses a running battle; starting opens battle; back follows popup/editor/config/exit ordering. Android background saves settings and pauses combat/audio. Foreground restores audio but never silently resumes combat. Native PNG selection uses ACCESS_FILESYSTEM + image/png MIME and copies bytes into app-owned storage. Windows and phone data are intentionally independent.


## Impact, audio and elimination presentation

MatchConfig and selection default to a 500 by 500 playable rectangle, excluding the 48-unit frame. settings_migration changes only the legacy 664-square default before the persisted map_default_500 marker; custom maps remain intact.


Death affects combat eligibility and results immediately. The death event contains its origin, last hit direction and angle; ArenaBoard owns a separate departure timeline (0.5-second hold, 0.45-second outward flight), independent of arena.running. The final overlay waits for all departures; pause and playback speed affect their clock. Board emits death_ejected once at flight start; simultaneous cheers merge. New match/selection clears these visuals and cheer playback. Default stationary character circles and overhead actor labels are removed; functional skill visuals remain.


## Destruction Trailblazer

The built-in roster now has five characters. destruction_trailblazer declares two explicit skill slots: bat_throw (default six seconds, editable up to sixty), collision_smash (passive).

BattleArena collects enemy-only body contacts during separation and delivers on_enemy_contact once per enemy per simulation step, before skill timers advance. Clear contact arrays on every step and on Fighter teardown to break reference cycles. Sustained touching is debounced by the collision skill; a real separation is needed before another contact entry can damage.

Returning bat owns its charge and flight phases. It snapshots the nearest enemy position only at launch, travels to that point, then returns to the current owner hand position. It holds the release image and the active-cast lock throughout both legs; fixed release_time must not end this image. Catch/death/end resets to held/normal. One bat exists per skill instance. Damage is swept and limited to once per enemy for the full trip. Collision resets pending charge without canceling an already airborne bat.


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

## UI and delivery

main.gd owns orchestration; match_panel.gd owns roster slots and config persistence; character_editor.gd owns drafts and import/browser UI; arena_board.gd is presentation only. Main advances arena at fixed 1/60 simulation steps. Per-fighter visual state follows simulation time, hit flashes decay in the presentation layer.

settings.cfg configuration_v2 stores stable character IDs and map/slots. Legacy two-index selections migrate once. qa_mode isolates preferences and character files during tests.


Version0.8.0 removes the automated test files/runners and validation reports from the repository and distributions. Build.ps1/BuildAndroid.ps1 import and export directly; Package.ps1 includes runtime source/assets/docs only. InstallAndroid.ps1 retains USB installation. Source baseline before cleanup is kept locally under ignored build/baselines.
