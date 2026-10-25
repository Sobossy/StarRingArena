extends "res://scripts/movement/movement_base.gd"

var direction: Vector2 = Vector2.RIGHT
var turn_remaining: float = 0.0
var orbit_sign: float = 1.0

func setup(owner_fighter, battle_arena) -> void:
	super.setup(owner_fighter, battle_arena)
	orbit_sign = 1.0 if arena.rng.randf() > 0.5 else -1.0

func desired_velocity(delta: float) -> Vector2:
	turn_remaining -= delta
	if turn_remaining <= 0.0:
		turn_remaining = arena.rng.randf_range(0.65, 1.3)
		var target = arena.opponent(fighter)
		if target != null:
			var toward: Vector2 = (target.position - fighter.position).normalized()
			var distance: float = fighter.position.distance_to(target.position)
			var approach: float = 0.85 if distance > 150.0 else -0.15
			direction = (toward * approach + toward.orthogonal() * orbit_sign * 0.7).normalized()
			direction = direction.rotated(arena.rng.randf_range(-0.28, 0.28))
		else:
			direction = Vector2.RIGHT.rotated(arena.rng.randf_range(-PI, PI))
	return direction * fighter.definition.speed

func on_collision(normal: Vector2) -> void:
	if direction.dot(normal) < 0.0:
		direction = direction.bounce(normal).normalized()
	turn_remaining = minf(turn_remaining, 0.35)
