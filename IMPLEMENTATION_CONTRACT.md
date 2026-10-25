# Implementation contract

Godot 4.x, GDScript; all coordinates use a 760 x 760 arena. Rendering is external to simulation. Avoid circular class-name type annotations: use dynamic parameters for core/skill cross-references.

## Core (scripts/core)
- `character_definition.gd`: `class_name CharacterDefinition extends Resource`. Exports `id:String`, `display_name:String`, `description:String`, `portrait:Texture2D`, `portrait_size:float=82`, `portrait_offset:Vector2`, `theme_color:Color`, `max_health:float=1000`, `attack:float=38`, `speed:float=150`, `radius:float=28`, `default_movement:String`, `skill_scenes:Array[PackedScene]`.
- `fighter.gd`: `class_name Fighter extends RefCounted`. Fields `definition`, `side:int`, `position:Vector2`, `velocity:Vector2`, `health:float`, `shield:float`, `alive:bool`, `skills:Array`, `statuses:Dictionary`, `movement_id:String`, `hit_flash:float`, `dash_velocity:Vector2`, `dash_remaining:float`, `knockback:Vector2`. Runtime state never stored in definition. Getter `health_ratio()`.
- `battle_arena.gd`: `class_name BattleArena extends Node`. `fighters:Array`, `projectiles:Array` (dictionaries), `elapsed:float`, `duration:float=90`, `running:bool`, `winner:int` (-2 ongoing, -1 draw, 0/1 winner), `rng:RandomNumberGenerator`, `bounds:Rect2 = Rect2(48,48,664,664)`, `events:Array` (drainable presentation event queue), `event_log:Array` (bounded concise simulation log).
- API: `start_battle(definitions:Array, movement_ids:Array, seed_value:int=42)`, `step(delta:float)`, `opponent(fighter)`, `get_targets(fighter)->Array`, `apply_damage(source,target,amount:float,skill_id:String,allow_reaction:bool=true)`, `heal(target,amount:float)`, `add_shield(target,amount:float,duration_seconds:float=4)`, `apply_status(source,target,id:String,duration_seconds:float,power:float)`, `spawn_projectile(source,options:Dictionary)`, `emit_effect(kind:String,position:Vector2,color:Color,extra:Dictionary={})`, `drain_events()->Array`, `get_visuals()->Array` (collect skills' visuals), `clear_battle()`.
- All skills tick on fixed simulation steps, before deferred damage/death resolution so simultaneous death can draw. Damage events: dictionary `{source,target,amount,skill_id,allow_reaction}`. Skills do not call recursive damage directly; core queues it. Death halts future ticks and projectiles from that fighter. World bounds and body separation handled centrally.
- Projectile options: `position`, `velocity`, `radius`, `damage`, `lifetime`, `color`, `skill_id`, optional `blast_radius`, `status_id`, `status_duration`, `status_power`; core assigns `source`. Projectile hit calls common damage and optional status; radial hits once per target.
- Visual event kinds: `hit` (`position`,`amount`,`color`,`side`), `shield`, `heal`, `burst`, `slash`, `dash`, `death`, `end`; all carry position/color when relevant. Root visual renderer ignores unknown events safely.
- Movement strategies in scripts/movement: IDs `bounce`, `chase`, `kite`, `wander`; `MovementBase extends RefCounted`, `setup(fighter,arena)`, `desired_velocity(delta)->Vector2`. Per-fighter instances. No rendering.

## Skills/content (scripts/skills, data, scenes/skills)
- `skill_base.gd`: `class_name SkillBase extends Node`, fields `fighter`, `arena`, `cooldown_remaining:float`, `active:bool`; methods `setup(fighter,arena)`, `tick(delta)`, `activate(target)`, `on_damage_received(event:Dictionary)`, `get_visuals()->Array`.
- Built-in registry `data/roster.gd`: `extends RefCounted`, static `get_all()->Array` returns CharacterDefinition resources in fixed order sword, mage, guard, assassin. A fifth extension example lives in examples and is not in default roster.
- Four data resources and independent skill scenes. Orbit visual dictionary: `{kind:'sword',position:Vector2,angle:float,color:Color}`. Other visual kinds may use `ring` with position/radius/color. Event effects use core emit_effect.
- Four intended kits: orbit blades; fireball + burn; melee + timed shield + non-recursive counter; dash slash + slow. Skill scenes export tuning values; attack scales from fighter.definition.attack. Any state belongs to skill instance.

## UI/root ownership
Root owns project.godot, main.tscn, scripts/ui, assets/fonts, README and docs, scripts/assets visuals. UI uses `load('res://data/roster.gd').get_all()`, and core APIs above. It drives arena.step at 1/60 with accumulator; pause/speed only affect accumulator. Board preserves square aspect ratio; PNG images optional, explicit vector placeholder labels otherwise.

## Tooling/testing ownership
Tooling agent owns tools/, *.ps1, *.cmd, tests/, build/export config (coordinate project.godot with root). Download official Godot 4.7.2 and matching export templates; if official version cannot be fetched, report evidence before substituting. Tools/install caches are ignored and not source. Tests can preload APIs above and run via headless Godot --script.
