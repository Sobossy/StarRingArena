extends "res://scripts/skills/skill_base.gd"
## Melee, timed barrier and non-recursive counterattack in one reusable kit.

@export var melee_range: float = 100.0
@export var melee_damage_multiplier: float = 1.45
@export var shield_amount: float = 115.0
@export var shield_interval: float = 5.5
@export var shield_duration: float = 3.8
@export var counter_multiplier: float = 0.65
@export var counter_interval: float = 0.55

var shield_timer: float = 0.0
var counter_timer: float = 0.0


func setup(owner_fighter, battle_arena) -> void:
	super.setup(owner_fighter, battle_arena)
	shield_timer = 0.3
	counter_timer = 0.0
	cooldown_remaining = 0.3


func tick(delta: float) -> void:
	super.tick(delta)
	if not can_act():
		return
	shield_timer = maxf(0.0, shield_timer - delta)
	counter_timer = maxf(0.0, counter_timer - delta)
	if shield_timer <= 0.0:
		arena.add_shield(fighter, shield_amount, shield_duration)
		shield_timer = maxf(0.1, shield_interval)
	var target = arena.opponent(fighter)
	if target == null or not target.alive or cooldown_remaining > 0.0:
		return
	if fighter.position.distance_to(target.position) <= melee_range:
		activate(target)


func activate(target) -> void:
	if not can_act() or target == null:
		return
	arena.apply_damage(fighter, target, fighter.definition.attack * melee_damage_multiplier, skill_id)
	var direction: Vector2 = fighter.position.direction_to(target.position)
	target.knockback += direction * 95.0
	arena.emit_effect("slash", fighter.position.lerp(target.position, 0.5), fighter.definition.theme_color, {
		"angle": direction.angle(), "radius": 65.0,
	})
	restart_cooldown()


func on_damage_received(event: Dictionary) -> void:
	if not can_act() or counter_timer > 0.0 or not event.get("allow_reaction", true):
		return
	var source = event.get("source")
	if source == null or source == fighter or not source.alive:
		return
	# This reflected damage cannot trigger another reaction, including another guard.
	arena.apply_damage(fighter, source, fighter.definition.attack * counter_multiplier, skill_id + "_counter", false)
	arena.emit_effect("burst", source.position, fighter.definition.theme_color, {"radius": 42.0})
	counter_timer = maxf(0.05, counter_interval)


func get_visuals() -> Array:
	if not can_act() or fighter.shield <= 0.0:
		return []
	return [{
		"kind": "ring", "position": fighter.position,
		"radius": fighter.definition.radius + 17.0,
		"color": Color(1.0, 0.78, 0.3, 0.55),
	}]
