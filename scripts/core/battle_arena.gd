class_name BattleArena
extends Node
## Fixed-step battle rules. No drawing, wall-clock timers, or global random state.

const FighterScript = preload("res://scripts/core/fighter.gd")
const MOVEMENTS: Dictionary = {
	"bounce": preload("res://scripts/movement/bounce.gd"),
	"chase": preload("res://scripts/movement/chase.gd"),
	"kite": preload("res://scripts/movement/kite.gd"),
	"wander": preload("res://scripts/movement/wander.gd"),
}
const MAX_PROJECTILES: int = 512
const MAX_EVENTS: int = 512
const MAX_LOG_ENTRIES: int = 4096
const MAX_DAMAGE_EVENTS_PER_STEP: int = 256

signal battle_ended(result: int)

var fighters: Array = []
var projectiles: Array = []
var elapsed: float = 0.0
var duration: float = 90.0
var running: bool = false
var winner: int = -2
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var bounds: Rect2 = Rect2(48.0, 48.0, 664.0, 664.0)
var events: Array = []
var event_log: Array = []
var tick_count: int = 0
var seed_value: int = 42
var _damage_queue: Array = []
var _next_projectile_id: int = 1

func start_battle(definitions: Array, movement_ids: Array, new_seed: int = 42) -> void:
	clear_battle()
	if definitions.size() != 2 or definitions[0] == null or definitions[1] == null:
		push_error("A battle requires exactly two valid CharacterDefinition resources.")
		return
	seed_value = new_seed
	rng.seed = new_seed
	for side in range(2):
		var fighter = FighterScript.new()
		fighter.initialize(definitions[side], side)
		fighter.position = Vector2(228.0 if side == 0 else 532.0, 380.0)
		if side < movement_ids.size() and MOVEMENTS.has(str(movement_ids[side])):
			fighter.movement_id = str(movement_ids[side])
		elif not MOVEMENTS.has(fighter.movement_id):
			fighter.movement_id = "bounce"
		fighters.append(fighter)
	running = true
	for fighter in fighters:
		fighter.movement = MOVEMENTS[fighter.movement_id].new()
		fighter.movement.setup(fighter, self)
		for packed_scene in fighter.definition.skill_scenes:
			if packed_scene == null:
				continue
			var skill = packed_scene.instantiate()
			if not skill.has_method("setup") or not skill.has_method("tick"):
				push_warning("Ignored skill scene without setup/tick: " + packed_scene.resource_path)
				skill.free()
				continue
			add_child(skill)
			fighter.skills.append(skill)
			skill.setup(fighter, self)
	_log({"kind": "start", "seed": seed_value})

func step(delta: float) -> void:
	if not running or delta <= 0.0 or not is_finite(delta):
		return
	tick_count += 1
	var step_delta: float = minf(delta, maxf(0.0, duration - elapsed))
	elapsed = minf(duration, elapsed + step_delta)
	for fighter in fighters:
		if not fighter.alive:
			continue
		_update_timers(fighter, step_delta)
		_move_fighter(fighter, step_delta)
	_separate_fighters()
	for fighter in fighters:
		if fighter.alive:
			for skill in fighter.skills:
				if is_instance_valid(skill) and skill.active:
					skill.tick(step_delta)
	_update_projectiles(step_delta)
	_resolve_damage()
	_resolve_deaths_and_result()

func opponent(fighter):
	for other in fighters:
		if other != fighter and other.alive:
			return other
	return null

func get_targets(fighter) -> Array:
	var targets: Array = []
	for other in fighters:
		if other != fighter and other.alive:
			targets.append(other)
	return targets

func apply_damage(source, target, amount: float, skill_id: String, allow_reaction: bool = true) -> void:
	if not running or target == null or not target.alive or amount <= 0.0 or not is_finite(amount):
		return
	if source != null and not source.alive:
		return
	if _damage_queue.size() >= MAX_DAMAGE_EVENTS_PER_STEP:
		return
	_damage_queue.append({
		"source": source, "target": target, "amount": amount,
		"skill_id": skill_id, "allow_reaction": allow_reaction,
	})

func heal(target, amount: float) -> void:
	if not running or target == null or not target.alive or not is_finite(amount):
		return
	var actual: float = minf(maxf(0.0, amount), target.definition.max_health - target.health)
	if actual <= 0.0:
		return
	target.health += actual
	target.healing_done += actual
	emit_effect("heal", target.position, Color("8cebb6"), {"amount": actual, "side": target.side})
	_log({"kind": "heal", "target": target.side, "amount": actual})

func add_shield(target, amount: float, duration_seconds: float = 4.0) -> void:
	if not running or target == null or not target.alive or amount <= 0.0 or duration_seconds <= 0.0:
		return
	if target.shield <= 0.0:
		# A depleted shield must not lend its old expiry time to a new barrier.
		target.shield_remaining = 0.0
	target.shield = minf(target.definition.max_health, target.shield + amount)
	target.shield_remaining = maxf(target.shield_remaining, duration_seconds)
	emit_effect("shield", target.position, Color("a1ddff"), {"amount": amount, "side": target.side})
	_log({"kind": "shield", "target": target.side, "amount": target.shield})

func apply_status(source, target, id: String, duration_seconds: float, power: float) -> void:
	if not running or target == null or not target.alive or duration_seconds <= 0.0 or id.is_empty():
		return
	if not is_finite(duration_seconds) or not is_finite(power):
		return
	if target.statuses.has(id):
		var existing: Dictionary = target.statuses[id]
		existing["remaining"] = maxf(float(existing["remaining"]), duration_seconds)
		existing["duration"] = maxf(float(existing["duration"]), duration_seconds)
		existing["power"] = maxf(float(existing["power"]), power)
		existing["source"] = source
	else:
		target.statuses[id] = {
			"remaining": duration_seconds, "duration": duration_seconds, "power": power,
			"source": source, "tick_accumulator": 0.0,
		}
	_log({"kind": "status", "target": target.side, "id": id, "power": power})

func spawn_projectile(source, options: Dictionary) -> void:
	if not running or source == null or not source.alive or projectiles.size() >= MAX_PROJECTILES:
		return
	var projectile: Dictionary = options.duplicate()
	projectile["id"] = _next_projectile_id
	_next_projectile_id += 1
	projectile["source"] = source
	projectile["position"] = options.get("position", source.position)
	projectile["previous_position"] = projectile["position"]
	projectile["velocity"] = options.get("velocity", Vector2.RIGHT * 300.0)
	projectile["radius"] = maxf(1.0, float(options.get("radius", 8.0)))
	projectile["damage"] = maxf(0.0, float(options.get("damage", source.definition.attack)))
	projectile["lifetime"] = maxf(0.05, float(options.get("lifetime", 3.0)))
	projectile["color"] = options.get("color", source.definition.theme_color)
	projectile["skill_id"] = str(options.get("skill_id", "projectile"))
	projectiles.append(projectile)

func emit_effect(kind: String, at: Vector2, color: Color, extra: Dictionary = {}) -> void:
	var event: Dictionary = extra.duplicate()
	event["kind"] = kind
	event["position"] = at
	event["color"] = color
	event["time"] = elapsed
	events.append(event)
	if events.size() > MAX_EVENTS:
		events.pop_front()

func drain_events() -> Array:
	var collected: Array = events
	events = []
	return collected

func get_visuals() -> Array:
	var visuals: Array = []
	for fighter in fighters:
		if fighter.alive:
			for skill in fighter.skills:
				if is_instance_valid(skill) and skill.has_method("get_visuals"):
					visuals.append_array(skill.get_visuals())
	return visuals

func clear_battle() -> void:
	running = false
	_damage_queue.clear()
	projectiles.clear()
	events.clear()
	event_log.clear()
	for fighter in fighters:
		for skill in fighter.skills:
			if is_instance_valid(skill):
				skill.free()
		fighter.clear_runtime()
	fighters.clear()
	elapsed = 0.0
	tick_count = 0
	winner = -2
	_next_projectile_id = 1

func _exit_tree() -> void:
	# Children are freed by Godot; explicitly break RefCounted owner/source cycles.
	for fighter in fighters:
		fighter.clear_runtime()
	_damage_queue.clear()
	projectiles.clear()

func _update_timers(fighter, delta: float) -> void:
	fighter.hit_flash = maxf(0.0, fighter.hit_flash - delta)
	if fighter.shield_remaining > 0.0:
		fighter.shield_remaining = maxf(0.0, fighter.shield_remaining - delta)
		if fighter.shield_remaining == 0.0:
			fighter.shield = 0.0
	for id in fighter.statuses.keys():
		var status: Dictionary = fighter.statuses[id]
		var status_delta: float = minf(delta, float(status["remaining"]))
		status["remaining"] = maxf(0.0, float(status["remaining"]) - delta)
		if id == "burn":
			status["tick_accumulator"] = float(status["tick_accumulator"]) + status_delta
			while float(status["tick_accumulator"]) >= 0.5 - 0.00001:
				status["tick_accumulator"] = maxf(0.0, float(status["tick_accumulator"]) - 0.5)
				apply_damage(status["source"], fighter, float(status["power"]) * 0.5, "burn", false)
		if float(status["remaining"]) <= 0.00001:
			fighter.statuses.erase(id)

func _move_fighter(fighter, delta: float) -> void:
	var desired: Vector2 = fighter.movement.desired_velocity(delta)
	if fighter.statuses.has("slow"):
		desired *= clampf(1.0 - float(fighter.statuses["slow"]["power"]), 0.05, 1.0)
	if fighter.dash_remaining > 0.0:
		desired = fighter.dash_velocity
		fighter.dash_remaining = maxf(0.0, fighter.dash_remaining - delta)
	fighter.velocity = desired + fighter.knockback
	fighter.position += fighter.velocity * delta
	fighter.knockback *= exp(-8.0 * delta)
	_constrain_fighter(fighter)

func _constrain_fighter(fighter) -> void:
	var radius: float = fighter.definition.radius
	var minimum: Vector2 = bounds.position + Vector2.ONE * radius
	var maximum: Vector2 = bounds.end - Vector2.ONE * radius
	var normal: Vector2 = Vector2.ZERO
	if fighter.position.x < minimum.x:
		fighter.position.x = minimum.x
		normal.x = 1.0
	elif fighter.position.x > maximum.x:
		fighter.position.x = maximum.x
		normal.x = -1.0
	if fighter.position.y < minimum.y:
		fighter.position.y = minimum.y
		normal.y = 1.0
	elif fighter.position.y > maximum.y:
		fighter.position.y = maximum.y
		normal.y = -1.0
	if normal != Vector2.ZERO:
		# Reflect each axis at corners instead of reflecting around a diagonal normal.
		if normal.x != 0.0:
			fighter.movement.on_collision(Vector2(normal.x, 0.0))
		if normal.y != 0.0:
			fighter.movement.on_collision(Vector2(0.0, normal.y))
		if fighter.knockback.dot(normal) < 0.0:
			fighter.knockback = fighter.knockback.slide(normal.normalized())

func _separate_fighters() -> void:
	if fighters.size() != 2 or not fighters[0].alive or not fighters[1].alive:
		return
	var first = fighters[0]
	var second = fighters[1]
	var minimum_distance: float = first.definition.radius + second.definition.radius + 0.05
	for iteration in range(4):
		var offset: Vector2 = first.position - second.position
		var distance: float = offset.length()
		if distance >= minimum_distance:
			break
		var normal: Vector2 = offset / distance if distance > 0.001 else Vector2.LEFT
		var correction: Vector2 = normal * (minimum_distance - distance) * 0.5
		first.position += correction
		second.position -= correction
		_constrain_fighter(first)
		_constrain_fighter(second)
		# If one fighter is pinned to a wall, give the other the unused separation.
		# This also resolves an exact spawn overlap at a corner in the same step.
		var remaining_distance: float = minimum_distance - first.position.distance_to(second.position)
		if remaining_distance > 0.00001:
			var old_first_position: Vector2 = first.position
			first.position += normal * remaining_distance
			_constrain_fighter(first)
			var moved: float = maxf(0.0, (first.position - old_first_position).dot(normal))
			second.position -= normal * maxf(0.0, remaining_distance - moved)
			_constrain_fighter(second)
		if iteration == 0:
			first.movement.on_collision(normal)
			second.movement.on_collision(-normal)

func _update_projectiles(delta: float) -> void:
	var remaining: Array = []
	for projectile in projectiles:
		var source = projectile["source"]
		if not source.alive:
			continue
		var travel_delta: float = minf(delta, float(projectile["lifetime"]))
		if travel_delta <= 0.0:
			continue
		projectile["lifetime"] = maxf(0.0, float(projectile["lifetime"]) - delta)
		var start: Vector2 = projectile["position"]
		var destination: Vector2 = start + projectile["velocity"] * travel_delta
		projectile["previous_position"] = start
		projectile["position"] = destination
		var impacted = null
		var closest_t: float = 2.0
		for target in get_targets(source):
			var radius: float = float(projectile["radius"]) + target.definition.radius
			var contact: float = _segment_circle_contact(start, destination, target.position, radius)
			if contact >= 0.0 and contact < closest_t:
				impacted = target
				closest_t = contact
		if impacted != null:
			projectile["position"] = start.lerp(destination, closest_t)
			_projectile_impact(projectile, impacted)
		elif float(projectile["lifetime"]) > 0.0 and bounds.grow(40.0).has_point(destination):
			remaining.append(projectile)
	projectiles = remaining

func _projectile_impact(projectile: Dictionary, direct_target) -> void:
	var source = projectile["source"]
	var hit_position: Vector2 = projectile["position"]
	var blast_radius: float = float(projectile.get("blast_radius", 0.0))
	var targets: Array = [direct_target]
	if blast_radius > 0.0:
		for target in get_targets(source):
			# The directly struck target always receives impact damage, even when
			# the configurable explosion is smaller than the projectile itself.
			if target != direct_target and target.position.distance_to(hit_position) <= blast_radius + target.definition.radius:
				targets.append(target)
	for target in targets:
		apply_damage(source, target, float(projectile["damage"]), projectile["skill_id"])
		var status_id: String = str(projectile.get("status_id", ""))
		if not status_id.is_empty():
			apply_status(source, target, status_id, float(projectile.get("status_duration", 2.0)), float(projectile.get("status_power", 0.0)))
	emit_effect("burst", hit_position, projectile["color"], {"radius": maxf(24.0, blast_radius)})

func _segment_circle_contact(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> float:
	var offset: Vector2 = start - center
	var direction: Vector2 = finish - start
	var c: float = offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var a: float = direction.length_squared()
	if a <= 0.000001:
		return -1.0
	var b: float = 2.0 * offset.dot(direction)
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var contact: float = (-b - sqrt(discriminant)) / (2.0 * a)
	return contact if contact >= 0.0 and contact <= 1.0 else -1.0

func _resolve_damage() -> void:
	var processed: int = 0
	while not _damage_queue.is_empty() and processed < MAX_DAMAGE_EVENTS_PER_STEP:
		var event: Dictionary = _damage_queue.pop_front()
		processed += 1
		var target = event["target"]
		var source = event["source"]
		if not target.alive:
			continue
		var incoming: float = float(event["amount"])
		var absorbed: float = minf(target.shield, incoming)
		target.shield -= absorbed
		if target.shield <= 0.0:
			target.shield_remaining = 0.0
		var actual: float = minf(target.health, incoming - absorbed)
		target.health = maxf(0.0, target.health - actual)
		target.hit_flash = 0.14
		target.damage_taken += actual + absorbed
		if source != null:
			source.damage_dealt += actual + absorbed
		event["amount"] = actual
		event["absorbed"] = absorbed
		var hit_color: Color = Color("ffe18c") if absorbed == 0.0 else Color("9fddff")
		emit_effect("hit", target.position, hit_color, {
			"amount": actual + absorbed, "absorbed": absorbed,
			"side": target.side, "skill_id": event["skill_id"],
		})
		_log({"kind": "damage", "source": source.side if source != null else -1,
			"target": target.side, "amount": actual, "absorbed": absorbed, "skill_id": event["skill_id"]})
		if event["allow_reaction"]:
			for skill in target.skills:
				if is_instance_valid(skill) and skill.active and skill.has_method("on_damage_received"):
					skill.on_damage_received(event)
	if not _damage_queue.is_empty():
		_log({"kind": "diagnostic", "message": "Damage reaction budget exceeded; remaining events discarded."})
		_damage_queue.clear()

func _resolve_deaths_and_result() -> void:
	for fighter in fighters:
		if fighter.alive and fighter.health <= 0.0:
			fighter.alive = false
			fighter.velocity = Vector2.ZERO
			fighter.dash_remaining = 0.0
			for skill in fighter.skills:
				skill.active = false
			emit_effect("death", fighter.position, fighter.definition.theme_color, {"side": fighter.side})
			_log({"kind": "death", "side": fighter.side})
	if not fighters[0].alive and not fighters[1].alive:
		_finish(-1)
	elif not fighters[0].alive:
		_finish(1)
	elif not fighters[1].alive:
		_finish(0)
	elif elapsed >= duration - 0.00001:
		var difference: float = fighters[0].health_ratio() - fighters[1].health_ratio()
		_finish(-1 if absf(difference) <= 0.000001 else (0 if difference > 0.0 else 1))

func _finish(result: int) -> void:
	running = false
	winner = result
	projectiles.clear()
	for fighter in fighters:
		fighter.velocity = Vector2.ZERO
		fighter.dash_remaining = 0.0
		for skill in fighter.skills:
			skill.active = false
	emit_effect("end", bounds.get_center(), Color.WHITE, {"winner": result})
	_log({"kind": "end", "winner": result})
	battle_ended.emit(result)

func _log(entry: Dictionary) -> void:
	entry["tick"] = tick_count
	entry["time"] = elapsed
	event_log.append(entry)
	if event_log.size() > MAX_LOG_ENTRIES:
		event_log.pop_front()
