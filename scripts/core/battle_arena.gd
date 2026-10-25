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
var winner_team: int = -2
var result: Dictionary = {}
var mode: String = "ffa"
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var bounds: Rect2 = Rect2(48.0, 48.0, 500.0, 500.0)
var events: Array = []
var event_log: Array = []
var tick_count: int = 0
var seed_value: int = 42
var _damage_queue: Array = []
var _next_projectile_id: int = 1

func start_battle(definitions: Array, movement_ids: Array, new_seed: int = 42) -> void:
	var config = load("res://scripts/core/match_config.gd").new()
	config.seed_value = new_seed
	config.duration = duration
	for i in range(definitions.size()):
		config.participants.append({"definition": definitions[i], "movement": movement_ids[i] if i < movement_ids.size() else definitions[i].default_movement, "team": i})
	start_match(config)

func validate_config(config) -> String:
	if config.participants.size() < 2 or config.participants.size() > 8:
		return "参战人数应为 2～8。"
	if not is_finite(config.width) or not is_finite(config.height) or config.width < 480 or config.height < 480 or config.width > 2400 or config.height > 2400:
		return "地图宽高应为 480～2400。"
	if config.mode not in ["ffa", "teams"]:
		return "请选择有效的对战模式。"
	var teams: Dictionary = {}
	for slot in config.participants:
		var definition = slot.get("definition")
		if definition == null or definition.max_health <= 0 or not is_finite(definition.max_health):
			return "请选择有效角色。"
		var team: int = int(slot.get("team", 0))
		if config.mode == "teams" and (team < 0 or team > 3):
			return "队伍编号应为 A～D。"
		teams[team] = true
	if config.mode == "teams" and teams.size() < 2:
		return "组队对战至少需要两个有成员的队伍。"
	if _spawn_layout(config).size() != config.participants.size():
		return "当前地图无法无重叠地容纳这些角色，请增大地图或减小碰撞半径。"
	return ""

func _spawn_layout(config) -> Array:
	var count: int = config.participants.size()
	var positions: Array = []
	var team_groups: Dictionary = {}
	for i in range(count):
		var team: int = i if config.mode == "ffa" else int(config.participants[i].get("team", 0))
		if not team_groups.has(team):
			team_groups[team] = []
		team_groups[team].append(i)
	var keys: Array = team_groups.keys()
	keys.sort()
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = config.seed_value
	var rotation: int = local_rng.randi_range(0, maxi(0, keys.size() - 1))
	positions.resize(count)
	var center := Vector2(48 + config.width * 0.5, 48 + config.height * 0.5)
	for group_index in range(keys.size()):
		var members: Array = team_groups[keys[group_index]]
		var angle: float = PI + TAU * float((group_index + rotation) % keys.size()) / float(keys.size())
		var base := center + Vector2(cos(angle) * config.width * 0.30, sin(angle) * config.height * 0.30)
		if config.mode == "teams" and keys.size() >= 3:
			var corners := [Vector2(0.23, 0.23),Vector2(0.77, 0.77),Vector2(0.77, 0.23),Vector2(0.23, 0.77)]
			base = Vector2(48,48) + corners[(group_index + rotation) % 4] * Vector2(config.width, config.height)
		var largest: float = 0
		for member in members:
			largest = maxf(largest, config.participants[member].definition.radius)
		var spacing: float = largest * 2 + 12
		var columns: int = ceili(sqrt(float(members.size())))
		var rows: int = ceili(float(members.size()) / columns)
		for j in range(members.size()):
			var offset := Vector2(float(j % columns) - float(columns - 1) * 0.5, float(j / columns) - float(rows - 1) * 0.5) * spacing
			positions[members[j]] = base + offset
	var playfield := Rect2(48,48,config.width,config.height)
	for i in range(count):
		var radius: float = config.participants[i].definition.radius
		if not playfield.grow(-radius - 1).has_point(positions[i]):
			return []
		for j in range(i):
			if positions[i].distance_to(positions[j]) < radius + config.participants[j].definition.radius + 2:
				return []
	return positions

func start_match(config) -> String:
	var error := validate_config(config)
	if not error.is_empty():
		return error
	var positions := _spawn_layout(config)
	clear_battle()
	mode = config.mode
	bounds = Rect2(48,48,config.width,config.height)
	duration = config.duration
	seed_value = config.seed_value
	rng.seed = seed_value
	for i in range(config.participants.size()):
		var slot: Dictionary = config.participants[i]
		var fighter = FighterScript.new()
		fighter.initialize(slot.definition.duplicate(true), i)
		fighter.team_id = i if mode == "ffa" else int(slot.get("team", 0))
		fighter.position = positions[i]
		var movement_id: String = str(slot.get("movement", fighter.definition.default_movement))
		fighter.movement_id = movement_id if MOVEMENTS.has(movement_id) else "bounce"
		fighters.append(fighter)
	running = true
	var catalog = load("res://scripts/core/skill_catalog.gd")
	for fighter in fighters:
		fighter.movement = MOVEMENTS[fighter.movement_id].new()
		fighter.movement.setup(fighter, self)
		if not fighter.definition.skill_slots.is_empty():
			for slot in fighter.definition.skill_slots:
				var skill = catalog.instantiate(slot)
				if skill != null:
					_attach_skill(fighter, skill)
		else:
			for packed_scene in fighter.definition.skill_scenes:
				if packed_scene != null:
					_attach_skill(fighter, packed_scene.instantiate())
	_log({"kind":"start", "seed":seed_value})
	return ""

func _attach_skill(fighter, skill) -> void:
	if not skill.has_method("setup") or not skill.has_method("tick"):
		skill.free()
		return
	add_child(skill)
	fighter.skills.append(skill)
	skill.setup(fighter, self)

func step(delta: float) -> void:
	if not running or delta <= 0.0 or not is_finite(delta):
		return
	tick_count += 1
	var step_delta: float = minf(delta, maxf(0.0, duration - elapsed))
	elapsed = minf(duration, elapsed + step_delta)
	for fighter in fighters:
		fighter.contact_enemies.clear()
		if not fighter.alive:
			continue
		_update_timers(fighter, step_delta)
		_move_fighter(fighter, step_delta)
	_separate_fighters()
	# Contact events are delivered once per pair before charge timers advance.
	for fighter in fighters:
		if fighter.alive:
			for skill in fighter.skills:
				if is_instance_valid(skill) and skill.active and skill.has_method("on_enemy_contact"):
					for enemy in fighter.contact_enemies:
						skill.on_enemy_contact(enemy)
	for fighter in fighters:
		if fighter.alive:
			for skill in fighter.skills:
				if is_instance_valid(skill) and skill.active:
					skill.tick(step_delta)
	_update_projectiles(step_delta)
	_resolve_damage()
	_resolve_deaths_and_result()

func is_enemy(first, second) -> bool:
	return first != null and second != null and first != second and first.team_id != second.team_id

func opponent(fighter):
	return nearest_enemy(fighter)

func nearest_enemy(fighter):
	var closest = null
	var closest_distance: float = INF
	for other in get_targets(fighter):
		var distance: float = fighter.position.distance_squared_to(other.position)
		if distance < closest_distance:
			closest = other
			closest_distance = distance
	return closest

func get_targets(fighter) -> Array:
	var targets: Array = []
	for other in fighters:
		if is_enemy(fighter, other) and other.alive:
			targets.append(other)
	return targets

func apply_damage(source, target, amount: float, skill_id: String, allow_reaction: bool = true, impulse: Vector2 = Vector2.ZERO) -> void:
	if not running or target == null or not target.alive or amount <= 0.0 or not is_finite(amount):
		return
	if source != null and (not source.alive or not is_enemy(source, target)):
		return
	if _damage_queue.size() >= MAX_DAMAGE_EVENTS_PER_STEP:
		return
	if not impulse.is_finite():
		return
	_damage_queue.append({
		"source": source, "target": target, "amount": amount,
		"skill_id": skill_id, "allow_reaction": allow_reaction, "impulse": impulse,
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
	if source != null and id in ["burn", "slow"] and not is_enemy(source, target):
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
	winner_team = -2
	result = {}
	_next_projectile_id = 1

func _exit_tree() -> void:
	# Children are freed by Godot; explicitly break RefCounted owner/source cycles.
	for fighter in fighters:
		fighter.clear_runtime()
	_damage_queue.clear()
	projectiles.clear()

func _update_timers(fighter, delta: float) -> void:
	fighter.lift_time = maxf(0, fighter.lift_time - delta)
	if fighter.visual_remaining > 0 and (fighter.casting_skill == null):
		fighter.visual_remaining = maxf(0, fighter.visual_remaining - delta)
		if fighter.visual_remaining <= 0:
			fighter.visual_texture = null
			fighter.visual_phase = "normal"
			fighter.visual_skill = null
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
	if fighter.casting_skill != null and fighter.casting_skill.phase == "charge" and not fighter.casting_skill.charge_can_move:
		desired = Vector2.ZERO
	if fighter.statuses.has("slow"):
		desired *= clampf(1.0 - float(fighter.statuses["slow"]["power"]), 0.05, 1.0)
	if fighter.dash_remaining > 0.0:
		desired = fighter.dash_velocity
		fighter.dash_remaining = maxf(0.0, fighter.dash_remaining - delta)
	if fighter.impact_remaining > 0.0:
		desired = Vector2.ZERO
	fighter.velocity = desired + fighter.knockback
	fighter.position += fighter.velocity * delta
	fighter.knockback *= exp(-8.0 * delta)
	_constrain_fighter(fighter)
	_update_impact(fighter, delta)

func _apply_impact(fighter, impulse: Vector2) -> void:
	fighter.knockback = impulse
	fighter.last_hit_direction = impulse.normalized()
	fighter.impact_remaining = 0.6
	fighter.impact_recovery = 0.0
	fighter.lift_time = 0.28
	emit_effect("impact", fighter.position, Color("ffe4a0"), {"side":fighter.side, "angle":impulse.angle()})

func _update_impact(fighter, delta: float) -> void:
	if fighter.impact_remaining > 0.0:
		fighter.impact_angle -= deg_to_rad(720.0) * delta
		fighter.impact_remaining = maxf(0.0, fighter.impact_remaining - delta)
		if fighter.knockback.length() < 60.0 or fighter.impact_remaining <= 0.0:
			fighter.knockback = Vector2.ZERO
			fighter.impact_remaining = 0.0
			fighter.impact_recovery = 0.12
			fighter.impact_recovery_start = fighter.impact_angle
			fighter.impact_recovery_target = floorf(fighter.impact_angle / TAU) * TAU
	elif fighter.impact_recovery > 0.0:
		fighter.impact_recovery = maxf(0.0, fighter.impact_recovery - delta)
		var progress: float = 1.0 - fighter.impact_recovery / 0.12
		fighter.impact_angle = lerpf(fighter.impact_recovery_start, fighter.impact_recovery_target, smoothstep(0.0,1.0,progress))
		if fighter.impact_recovery <= 0.0:
			fighter.impact_angle = 0.0

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
	# Stable pair order with multiple solver passes for crowded corners.
	for _pass in range(8):
		for i in range(fighters.size()):
			if not fighters[i].alive:
				continue
			for j in range(i + 1, fighters.size()):
				if fighters[j].alive:
					_separate_pair(fighters[i], fighters[j])

func _separate_pair(first, second) -> void:
	var minimum_distance: float = first.definition.radius + second.definition.radius + 0.05
	for iteration in range(2):
		var offset: Vector2 = first.position - second.position
		var distance: float = offset.length()
		if is_enemy(first, second):
			if distance <= minimum_distance + 0.05 + _contact_bonus(first) and not first.contact_enemies.has(second):
				first.contact_enemies.append(second)
			if distance <= minimum_distance + 0.05 + _contact_bonus(second) and not second.contact_enemies.has(first):
				second.contact_enemies.append(first)
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

func _contact_bonus(fighter) -> float:
	var extra: float = 0.0
	for skill in fighter.skills:
		if skill.active and skill.has_method("contact_distance_bonus"):
			extra = maxf(extra,float(skill.contact_distance_bonus()))
	return extra

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
		apply_damage(source, target, float(projectile["damage"]), projectile["skill_id"], true, projectile["velocity"].normalized() * float(projectile.get("knockback",0.0)))
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
		if actual + absorbed > 0.0:
			var impulse: Vector2 = event.get("impulse", Vector2.ZERO)
			if not impulse.is_zero_approx():
				_apply_impact(target, impulse)
			elif source != null:
				target.last_hit_direction = source.position.direction_to(target.position)
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
	var alive_teams: Dictionary = {}
	for fighter in fighters:
		if fighter.alive and fighter.health <= 0:
			fighter.alive = false
			fighter.velocity = Vector2.ZERO
			fighter.dash_remaining = 0
			for skill in fighter.skills:
				if skill.has_method("cancel_cast"):
					skill.cancel_cast()
				skill.active = false
			emit_effect("death", fighter.position, fighter.definition.theme_color, {"side":fighter.side, "direction":fighter.last_hit_direction, "angle":fighter.impact_angle})
			_log({"kind":"death", "side":fighter.side})
		if fighter.alive:
			alive_teams[fighter.team_id] = true
	if alive_teams.is_empty():
		_finish_team(-1, "elimination")
	elif alive_teams.size() == 1:
		_finish_team(int(alive_teams.keys()[0]), "elimination")
	elif elapsed >= duration - 0.00001:
		var totals: Dictionary = {}
		for fighter in fighters:
			if not totals.has(fighter.team_id):
				totals[fighter.team_id] = Vector2.ZERO
			totals[fighter.team_id] += Vector2(fighter.health, fighter.definition.max_health)
		var best_team: int = -1
		var best_ratio: float = -1
		var tied: bool = false
		for team in totals:
			var ratio: float = totals[team].x / totals[team].y
			if ratio > best_ratio + 0.000001:
				best_team = int(team)
				best_ratio = ratio
				tied = false
			elif absf(ratio - best_ratio) <= 0.000001:
				tied = true
		_finish_team(-1 if tied else best_team, "timeout")

func _finish_team(team: int, reason: String) -> void:
	running = false
	winner_team = team
	winner = -1
	if team >= 0:
		for fighter in fighters:
			if fighter.team_id == team:
				winner = fighter.fighter_id
				break
	result = {"winning_team":team, "draw":team < 0, "reason":reason}
	projectiles.clear()
	for fighter in fighters:
		fighter.velocity = Vector2.ZERO
		fighter.dash_remaining = 0
		fighter.lift_time = 0
		fighter.knockback = Vector2.ZERO
		fighter.impact_remaining = 0.0
		fighter.impact_recovery = 0.0
		fighter.impact_angle = 0.0
		for skill in fighter.skills:
			if skill.has_method("cancel_cast"):
				skill.cancel_cast()
			skill.active = false
	emit_effect("end", bounds.get_center(), Color.WHITE, {"winner":winner, "team":team})
	_log({"kind":"end", "winner":winner, "team":team})
	battle_ended.emit(winner)

func _log(entry: Dictionary) -> void:
	entry["tick"] = tick_count
	entry["time"] = elapsed
	event_log.append(entry)
	if event_log.size() > MAX_LOG_ENTRIES:
		event_log.pop_front()
