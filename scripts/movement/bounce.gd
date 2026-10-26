extends "res://scripts/movement/movement_base.gd"

var direction: Vector2 = Vector2.RIGHT

func setup(owner_fighter, battle_arena) -> void:
	super.setup(owner_fighter, battle_arena)
	var angle: float = arena.rng.randf_range(-0.8, 0.8)
	direction = Vector2.RIGHT.rotated(angle)
	if fighter.side == 1:
		direction.x *= -1.0

func desired_velocity(_delta: float) -> Vector2:
	return direction * fighter.movement_speed()

func on_collision(normal: Vector2) -> void:
	if direction.dot(normal) < 0.0:
		direction = direction.bounce(normal).normalized()
