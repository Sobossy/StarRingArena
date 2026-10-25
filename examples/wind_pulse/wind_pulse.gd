extends "res://scripts/skills/skill_base.gd"
## Example: a new skill implemented without modifying BattleArena or Fighter.

@export var pulse_radius: float = 200.0
@export var damage_multiplier: float = 1.3
@export var push_strength: float = 230.0
@export var recovery: float = 12.0


func setup(owner_fighter, battle_arena) -> void:
	super.setup(owner_fighter, battle_arena)
	cooldown_remaining = 0.7


func tick(delta: float) -> void:
	super.tick(delta)
	if not can_act() or cooldown_remaining > 0.0:
		return
	var target = arena.opponent(fighter)
	if target != null and fighter.position.distance_to(target.position) <= pulse_radius:
		activate(target)


func activate(_target) -> void:
	if not can_act():
		return
	for target in arena.get_targets(fighter):
		if fighter.position.distance_to(target.position) <= pulse_radius:
			arena.apply_damage(fighter, target, fighter.definition.attack * damage_multiplier, skill_id, true, fighter.position.direction_to(target.position) * push_strength)
	arena.heal(fighter, recovery)
	arena.emit_effect("burst", fighter.position, fighter.definition.theme_color, {"radius": pulse_radius})
	restart_cooldown()
