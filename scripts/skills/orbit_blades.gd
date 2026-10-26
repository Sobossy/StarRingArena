extends "res://scripts/skills/skill_base.gd"
## Sustained orbit skill; each blade owns a separate contact cooldown.

@export_range(1, 12, 1) var blade_count: int = 3
@export var orbit_radius: float = 73.0
@export var angular_speed: float = 3.8
@export var blade_radius: float = 15.0
@export var damage_multiplier: float = 0.9
@export var hit_interval: float = 0.38

var orbit_angle: float = 0.0
var blade_hit_timers: Array[float] = []
var target_timers: Dictionary = {}


func setup(owner_fighter, battle_arena) -> void:
	super.setup(owner_fighter, battle_arena)
	orbit_angle = float(fighter.side) * PI
	blade_hit_timers.clear()
	for _index in range(blade_count):
		blade_hit_timers.append(0.0)


func tick(delta: float) -> void:
	super.tick(delta)
	if not can_act():
		return
	orbit_angle = fmod(orbit_angle + angular_speed * delta, TAU)
	for key in target_timers.keys():
		target_timers[key] = maxf(0, target_timers[key] - delta)
	for index in range(blade_count):
		blade_hit_timers[index] = maxf(0.0, blade_hit_timers[index] - delta)
		for target in arena.get_collision_targets(fighter):
			var key := str(index) + "_" + str(target.fighter_id)
			if float(target_timers.get(key, 0)) > 0:
				continue
			var blade_position: Vector2 = _blade_position(index)
			var contact_distance: float = blade_radius + target.definition.radius
			if blade_position.distance_squared_to(target.position) <= contact_distance * contact_distance:
				arena.apply_damage(fighter, target, fighter.definition.attack * damage_multiplier, skill_id)
				target_timers[key] = maxf(0.05, hit_interval)
				blade_hit_timers[index] = maxf(0.05, hit_interval)
				arena.emit_effect("slash", blade_position, fighter.definition.theme_color, {"angle":orbit_angle, "radius":35.0})


func _blade_position(index: int) -> Vector2:
	var angle: float = orbit_angle + TAU * float(index) / float(blade_count)
	return fighter.position + Vector2.from_angle(angle) * orbit_radius


func get_visuals() -> Array:
	if not can_act():
		return []
	var visuals: Array = []
	for index in range(blade_count):
		var angle: float = orbit_angle + TAU * float(index) / float(blade_count)
		visuals.append({
			"kind": "sword",
			"position": _blade_position(index),
			"angle": angle + PI / 2.0,
			"color": fighter.definition.theme_color,
		})
	return visuals
