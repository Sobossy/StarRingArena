class_name SkillBase
extends Node
## A fresh skill node is instantiated for every fighter, every battle.
## Override tick/activate or the damage hook to add arbitrary mechanics.

@export var skill_id: String = "skill"
@export var cooldown: float = 1.0

var fighter
var arena
var cooldown_remaining: float = 0.0
var active: bool = true


func setup(owner_fighter, battle_arena) -> void:
	fighter = owner_fighter
	arena = battle_arena
	cooldown_remaining = 0.0
	active = true


func tick(delta: float) -> void:
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)


func activate(_target) -> void:
	pass


func on_damage_received(_event: Dictionary) -> void:
	pass


func get_visuals() -> Array:
	return []


func can_act() -> bool:
	return active and fighter != null and fighter.alive and arena != null


func restart_cooldown() -> void:
	cooldown_remaining = maxf(0.05, cooldown)
