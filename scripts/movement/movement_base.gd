class_name MovementBase
extends RefCounted
## A strategy requests velocity; the arena owns actual movement and collisions.

var fighter
var arena

func setup(owner_fighter, battle_arena) -> void:
	fighter = owner_fighter
	arena = battle_arena

func desired_velocity(_delta: float) -> Vector2:
	return Vector2.ZERO

func on_collision(_normal: Vector2) -> void:
	pass
