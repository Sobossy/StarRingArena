extends "res://scripts/skills/skill_base.gd"
@export var shield_amount: float = 115.0
@export var shield_interval: float = 5.5
@export var shield_duration: float = 3.8
var timer: float = 0.3

func tick(delta: float) -> void:
	super.tick(delta)
	if not can_act():
		return
	timer -= delta
	if timer <= 0:
		arena.add_shield(fighter, shield_amount, shield_duration)
		timer = shield_interval
		flash_release()
