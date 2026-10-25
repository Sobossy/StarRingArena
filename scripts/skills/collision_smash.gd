extends "res://scripts/skills/skill_base.gd"
@export var damage_multiplier: float = 3.0
@export var knockback_strength: float = 1100.0
@export var rehit_interval: float = 0.65
var previous_contacts: Dictionary = {}
var current_contacts: Dictionary = {}
var target_cooldowns: Dictionary = {}

func on_enemy_contact(enemy) -> void:
	if not can_act() or not arena.is_enemy(fighter,enemy) or not enemy.alive:
		return
	current_contacts[enemy.fighter_id] = true
	for skill in fighter.skills:
		if skill.has_method("interrupt_charge"):
			skill.interrupt_charge()
	if previous_contacts.has(enemy.fighter_id) or float(target_cooldowns.get(enemy.fighter_id,0)) > 0:
		return
	var direction: Vector2 = fighter.position.direction_to(enemy.position)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT if fighter.fighter_id < enemy.fighter_id else Vector2.LEFT
	arena.apply_damage(fighter,enemy,fighter.definition.attack * damage_multiplier,skill_id)
	enemy.knockback += direction * knockback_strength
	enemy.lift_time = 0.28
	target_cooldowns[enemy.fighter_id] = rehit_interval
	arena.emit_effect("smash",(fighter.position + enemy.position) * 0.5,fighter.definition.theme_color,{"angle":direction.angle(),"radius":85.0})

func tick(delta: float) -> void:
	super.tick(delta)
	previous_contacts = current_contacts
	current_contacts = {}
	for id in target_cooldowns:
		target_cooldowns[id] = maxf(0,float(target_cooldowns[id]) - delta)
