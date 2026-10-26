extends "res://scripts/movement/movement_base.gd"

func desired_velocity(_delta: float) -> Vector2:
	var target = arena.opponent(fighter)
	if target == null:
		return Vector2.ZERO
	var difference: Vector2 = target.position - fighter.position
	if difference.length_squared() < 0.0001:
		return Vector2.RIGHT if fighter.side == 0 else Vector2.LEFT
	return difference.normalized() * fighter.movement_speed()
