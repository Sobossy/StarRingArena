extends "res://scripts/skills/skill_base.gd"

@export var projectile_speed: float = 390.0
@export var projectile_radius: float = 12.0
@export var projectile_lifetime: float = 2.8
@export var damage_multiplier: float = 1.65
@export var explosion_radius: float = 68.0
@export var burn_duration: float = 2.5
@export var burn_damage_per_second: float = 13.0


func setup(owner_fighter, battle_arena) -> void:
	super.setup(owner_fighter, battle_arena)
	cooldown_remaining = 0.45


func tick(delta: float) -> void:
	super.tick(delta)
	if not can_act() or cooldown_remaining > 0.0:
		return
	var target = arena.opponent(fighter)
	if target != null and target.alive:
		activate(target)


func activate(target) -> void:
	if not can_act() or target == null:
		return
	# A short prediction makes ranged attacks useful without perfect homing.
	var distance: float = fighter.position.distance_to(target.position)
	var lead_time: float = minf(0.33, distance / maxf(1.0, projectile_speed))
	var target_position: Vector2 = target.position + target.velocity * lead_time
	var direction: Vector2 = fighter.position.direction_to(target_position)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	arena.spawn_projectile(fighter, {
		"position": fighter.position + direction * (fighter.definition.radius + 12.0),
		"velocity": direction * projectile_speed,
		"radius": projectile_radius,
		"damage": fighter.definition.attack * damage_multiplier,
		"lifetime": projectile_lifetime,
		"color": fighter.definition.theme_color,
		"skill_id": skill_id,
		"blast_radius": explosion_radius,
		"status_id": "burn",
		"status_duration": burn_duration,
		"status_power": burn_damage_per_second,
	})
	arena.emit_effect("burst", fighter.position + direction * 32.0, fighter.definition.theme_color, {"radius": 17.0})
	restart_cooldown()
