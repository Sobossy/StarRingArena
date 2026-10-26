extends "res://scripts/skills/skill_base.gd"
@export_range(0,100000,1) var damage: float = 80.0
@export_range(0,500,1) var contact_extra: float = 24.0
@export var knockback_strength: float = 2400.0
@export var rehit_interval: float = 0.1
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
	arena.apply_damage(fighter,enemy,damage,skill_id,true,direction * knockback_strength)
	target_cooldowns[enemy.fighter_id] = rehit_interval
	arena.emit_effect("smash",(fighter.position + enemy.position) * 0.5,fighter.definition.theme_color,{"angle":direction.angle(),"radius":85.0})

func tick(delta: float) -> void:
	super.tick(delta)
	previous_contacts = current_contacts
	current_contacts = {}
	for id in target_cooldowns:
		target_cooldowns[id] = maxf(0,float(target_cooldowns[id]) - delta)

func contact_distance_bonus() -> float:
	return contact_extra
