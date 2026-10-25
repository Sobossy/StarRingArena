extends "res://scripts/movement/movement_base.gd"

var clockwise: float = 1.0

func setup(owner_fighter, battle_arena) -> void:
	super.setup(owner_fighter, battle_arena)
	clockwise = 1.0 if arena.rng.randf() > 0.5 else -1.0

func desired_velocity(_delta: float) -> Vector2:
	var target = arena.opponent(fighter)
	if target == null:
		return Vector2.ZERO
	var offset: Vector2 = target.position - fighter.position
	var distance: float = offset.length()
	var toward: Vector2 = offset.normalized() if distance > 0.01 else Vector2.RIGHT
	var radial: float = clampf((distance - 235.0) / 75.0, -1.0, 1.0)
	var direction: Vector2 = toward * radial + toward.orthogonal() * clockwise * 0.55
	# Gently turn back into the playfield instead of getting stuck backing into a wall.
	var inner: Rect2 = arena.bounds.grow(-fighter.definition.radius - 55.0)
	if fighter.position.x < inner.position.x:
		direction.x += 1.4
	if fighter.position.x > inner.end.x:
		direction.x -= 1.4
	if fighter.position.y < inner.position.y:
		direction.y += 1.4
	if fighter.position.y > inner.end.y:
		direction.y -= 1.4
	return direction.normalized() * fighter.definition.speed

func on_collision(_normal: Vector2) -> void:
	clockwise *= -1.0
