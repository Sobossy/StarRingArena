extends "res://scripts/skills/skill_base.gd"

@export var dash_speed: float = 800.0
@export var dash_duration: float = 0.30
@export var dash_trigger_range: float = 420.0
@export var slash_radius: float = 36.0
@export var damage_multiplier: float = 2.5
@export var slow_duration: float = 1.6
@export_range(0.0, 0.95, 0.05) var slow_power: float = 0.35

var strike_remaining: float = 0.0
var strike_hit: bool = false
var previous_position: Vector2 = Vector2.ZERO
var dash_start: Vector2 = Vector2.ZERO


func setup(owner_fighter, battle_arena) -> void:
	super.setup(owner_fighter, battle_arena)
	previous_position = fighter.position
	strike_remaining = 0.0
	strike_hit = false
	cooldown_remaining = 0.9


func tick(delta: float) -> void:
	super.tick(delta)
	if not can_act():
		return
	var target = arena.opponent(fighter)
	if strike_remaining > 0.0:
		if target != null and target.alive and not strike_hit:
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(target.position, previous_position, fighter.position)
			var hit_distance: float = slash_radius + target.definition.radius
			if closest.distance_squared_to(target.position) <= hit_distance * hit_distance:
				_hit_target(target)
		strike_remaining = maxf(0.0, strike_remaining - delta)
	if target != null and target.alive and cooldown_remaining <= 0.0 and strike_remaining <= 0.0:
		if fighter.position.distance_to(target.position) <= dash_trigger_range:
			activate(target)
	previous_position = fighter.position


func activate(target) -> void:
	if not can_act() or target == null:
		return
	var direction: Vector2 = fighter.position.direction_to(target.position + target.velocity * 0.1)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	fighter.dash_velocity = direction * dash_speed
	fighter.dash_remaining = dash_duration
	strike_remaining = dash_duration + 0.05
	strike_hit = false
	dash_start = fighter.position
	previous_position = fighter.position
	arena.emit_effect("dash", fighter.position, fighter.definition.theme_color, {
		"from": fighter.position,
		"to": fighter.position + direction * dash_speed * dash_duration,
		"angle": direction.angle(),
	})
	restart_cooldown()


func _hit_target(target) -> void:
	strike_hit = true
	arena.apply_damage(fighter, target, fighter.definition.attack * damage_multiplier, skill_id)
	arena.apply_status(fighter, target, "slow", slow_duration, slow_power)
	var direction: Vector2 = fighter.dash_velocity.normalized()
	target.knockback += direction * 120.0
	arena.emit_effect("slash", target.position, fighter.definition.theme_color, {
		"angle": direction.angle(), "radius": 83.0,
	})


func get_visuals() -> Array:
	if not can_act() or strike_remaining <= 0.0:
		return []
	return [{
		"kind": "ring", "position": fighter.position,
		"radius": slash_radius, "color": Color(0.72, 0.53, 1.0, 0.65),
	}]
