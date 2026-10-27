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
signal combat_event(event: Dictionary)

var fighters: Array = []
var projectiles: Array = []
var pickups: Array = []
var _next_pickup_id: int = 1
var toast_initialized: bool = false
var toast_refresh: Dictionary = {}
var elapsed: float = 0.0
var duration: float = 90.0
var running: bool = false
var winner: int = -2
var winner_team: int = -2
var result: Dictionary = {}
var mode: String = "ffa"
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var bounds: Rect2 = Rect2(48.0, 48.0, 500.0, 500.0)
var initial_bounds: Rect2 = Rect2(48.0,48.0,500.0,500.0)
var world_elapsed: float = 0.0
var shrink_scale: float = 1.0
var shrink_accumulator: float = 0.0
var time_stop_owner = null
var time_stop_remaining: float = 0.0
var pending_time_stop: Dictionary = {}
var events: Array = []
var event_log: Array = []
var tick_count: int = 0
var seed_value: int = 42
var _damage_queue: Array = []
var _next_projectile_id: int = 1
var cut_walls: Array = []
var _next_cut_id: int = 1

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
	initial_bounds = bounds
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
	_log({"kind":"start", "seed":seed_value})
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
	var stopped_at_start: bool = time_stop_remaining > 0
	if not stopped_at_start:
		world_elapsed += step_delta
		_update_pickups(step_delta)
		_update_shrink(step_delta)
	for fighter in fighters:
		if fighter.alive and not is_time_stopped(fighter):
			for skill in fighter.skills:
				if skill.active:
					skill.before_step(step_delta)
	for fighter in fighters:
		fighter.contact_enemies.clear()
		if not fighter.alive or is_time_stopped(fighter):
			continue
		fighter.local_time += step_delta
		_update_timers(fighter, step_delta)
		_move_fighter(fighter, step_delta)
	_separate_fighters()
	for fighter in fighters:
		if fighter.alive:
			for skill in fighter.skills:
				if skill.active:
					skill.cleanup_spatial_effects()
	# Contact events are delivered once per pair before charge timers advance.
	for fighter in fighters:
		if fighter.alive and not is_time_stopped(fighter):
			for skill in fighter.skills:
				if is_instance_valid(skill) and skill.active and skill.has_method("on_enemy_contact"):
					for enemy in fighter.contact_enemies:
						skill.on_enemy_contact(enemy)
	for fighter in fighters:
		if fighter.alive and not is_time_stopped(fighter):
			for skill in fighter.skills:
				if is_instance_valid(skill) and skill.active:
					skill.tick(step_delta)
	if not stopped_at_start:
		_update_projectiles(step_delta)
	_resolve_damage()
	_resolve_deaths_and_result()
	if stopped_at_start and time_stop_remaining > 0:
		time_stop_remaining = maxf(0,time_stop_remaining-step_delta)
		if time_stop_remaining <= 0.000001 or time_stop_owner == null or not time_stop_owner.alive:
			_end_time_stop()
	_activate_pending_time_stop()

func is_time_stopped(fighter) -> bool:
	return time_stop_remaining > 0 and fighter != time_stop_owner

func step_post_result_motion(delta: float) -> void:
	# Presentation movement only. Never advance combat clocks, skills, statuses,
	# damage queues, RNG, arena shrinking or the already committed match result.
	if running or result.is_empty() or delta <= 0 or not is_finite(delta):
		return
	for actor in fighters:
		if not actor.alive:
			continue
		actor.local_time += delta
		actor.velocity = actor.post_result_heading*actor.movement_speed()
		if cut_walls.is_empty():
			actor.position += actor.velocity*delta
		else:
			_move_with_cut_reflection(actor,actor.position+actor.velocity*delta)
		_constrain_fighter(actor)
	_separate_fighters()
	for actor in fighters:
		if actor.alive and not actor.velocity.is_zero_approx():
			actor.post_result_heading = actor.velocity.normalized()

func request_time_stop(fighter,seconds: float) -> bool:
	if not running or not fighter.alive or time_stop_remaining > 0 or not pending_time_stop.is_empty():
		return false
	pending_time_stop = {"owner":fighter,"duration":maxf(0.05,seconds)}
	return true

func _activate_pending_time_stop() -> void:
	if pending_time_stop.is_empty() or time_stop_remaining > 0:
		return
	var request: Dictionary = pending_time_stop.duplicate()
	pending_time_stop.clear()
	if not running or not request.owner.alive:
		return
	time_stop_owner = request.owner
	time_stop_remaining = float(request.duration)
	for skill in time_stop_owner.skills:
		if skill.active:
			skill.on_time_stop_started()
	emit_effect("time_stop_start",time_stop_owner.position,Color("fff2d1"),{"duration":time_stop_remaining,"side":time_stop_owner.side})
	record_event({"kind":"time_stop_start","source":time_stop_owner.side,"duration":time_stop_remaining})

func _end_time_stop() -> void:
	var owner = time_stop_owner
	time_stop_owner = null
	time_stop_remaining = 0
	if owner != null:
		record_event({"kind":"time_stop_end","source":owner.side})
		for skill in owner.skills:
			if is_instance_valid(skill):
				skill.on_time_stop_ended()

func _update_shrink(delta: float) -> void:
	var provider = null
	for fighter in fighters:
		if fighter.alive:
			for skill in fighter.skills:
				if skill.active and skill.skill_id == "castorice_aura":
					provider = skill
					break
		if provider != null:
			break
	if provider == null:
		return
	shrink_accumulator += delta
	while shrink_accumulator >= provider.shrink_interval - 0.000001:
		shrink_accumulator = maxf(0,shrink_accumulator-provider.shrink_interval)
		shrink_scale = maxf(minf(shrink_scale,provider.minimum_arena_scale),shrink_scale-provider.shrink_fraction)
	var size: Vector2 = initial_bounds.size * shrink_scale
	var next := Rect2(initial_bounds.get_center()-size*.5,size)
	if next == bounds:
		return
	var ratio: float = next.size.x/bounds.size.x
	for wall in cut_walls:
		wall.origin = initial_bounds.get_center()+(wall.origin-initial_bounds.get_center())*ratio
		wall.half_width *= ratio
	bounds = next
	record_event({"kind":"shrink","source":provider.fighter.side,"scale":shrink_scale,"bounds":bounds})
	for fighter in fighters:
		if not fighter.alive:
			continue
		var low: Vector2 = bounds.position+Vector2.ONE*fighter.definition.radius
		var high: Vector2 = bounds.end-Vector2.ONE*fighter.definition.radius
		if fighter.airborne_remaining > 0:
			fighter.airborne_origin = fighter.airborne_origin.clamp(low,high)
			fighter.airborne_destination = fighter.airborne_destination.clamp(low,high)
			fighter.position = fighter.position.clamp(low,high)
		else:
			_constrain_fighter(fighter)
		for skill in fighter.skills:
			if skill.has_method("on_bounds_changed"):
				skill.on_bounds_changed()
	for pickup in pickups:
		var inner: Rect2 = bounds.grow(-float(pickup.radius)-12)
		pickup.position = pickup.position.clamp(inner.position,inner.end)

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

func get_collision_targets(fighter) -> Array:
	return get_targets(fighter).filter(func(target): return target.airborne_remaining <= 0)

func line_across_field(origin: Vector2, direction: Vector2) -> Array:
	var low: float = -INF
	var high: float = INF
	for axis in range(2):
		if absf(direction[axis]) < 0.000001:
			if origin[axis] < bounds.position[axis] or origin[axis] > bounds.end[axis]:
				return []
			continue
		var first: float = (bounds.position[axis]-origin[axis])/direction[axis]
		var second: float = (bounds.end[axis]-origin[axis])/direction[axis]
		low = maxf(low,minf(first,second))
		high = minf(high,maxf(first,second))
	return [origin+direction*low,origin+direction*high] if low <= high else []

func add_cut_wall(source,origin: Vector2,direction: Vector2,half_width: float = 7.0) -> void:
	if not running or source == null or not source.alive or is_time_stopped(source) or direction.is_zero_approx():
		return
	var normal: Vector2 = direction.normalized().orthogonal()
	# Repeated identical cuts share a wall; damage still settles on every slash.
	for existing in cut_walls:
		if absf(existing.normal.dot(normal)) > .99999 and absf((origin-existing.origin).dot(normal)) < .25:
			return
	var wall: Dictionary = {"id":_next_cut_id,"origin":origin,"direction":direction.normalized(),"normal":normal,"half_width":maxf(0,half_width),"owner_id":source.fighter_id}
	_next_cut_id += 1
	cut_walls.append(wall)
	for actor in fighters:
		if not actor.alive:
			continue
		var distance: float = (actor.position-origin).dot(normal)
		actor.cut_wall_sides[wall.id] = 1.0 if distance >= 0 else -1.0
		if actor.airborne_remaining <= 0 and not is_time_stopped(actor):
			_project_from_cut_walls(actor)
	_log({"kind":"arena_cut","source":source.side,"origin":origin,"direction":direction.normalized()})

func clip_motion_to_cut_walls(actor,from: Vector2,to: Vector2) -> Dictionary:
	var earliest: float = 1.0
	var normal := Vector2.ZERO
	for wall in cut_walls:
		var side: float = float(actor.cut_wall_sides.get(wall.id,1.0 if (from-wall.origin).dot(wall.normal) >= 0 else -1.0))
		var inward: Vector2 = wall.normal*side
		var clearance: float = actor.definition.radius+wall.half_width
		var start_distance: float = (from-wall.origin).dot(inward)
		var end_distance: float = (to-wall.origin).dot(inward)
		if end_distance >= clearance-.00001 or end_distance >= start_distance-.00001:
			continue
		var contact: float = clampf((start_distance-clearance)/maxf(.000001,start_distance-end_distance),0,1)
		if contact < earliest or normal.is_zero_approx():
			earliest = contact
			normal = inward
	return {"position":from.lerp(to,earliest),"normal":normal,"fraction":earliest}

func _project_from_cut_walls(actor) -> void:
	# Position corrections (new cut, crowd separation, landing, shrinking) must
	# keep each actor on its assigned side, rather than tunnelling through a seam.
	for _iteration in range(12):
		var changed: bool = false
		for wall in cut_walls:
			var side: float = float(actor.cut_wall_sides.get(wall.id,1.0 if (actor.position-wall.origin).dot(wall.normal) >= 0 else -1.0))
			actor.cut_wall_sides[wall.id] = side
			var inward: Vector2 = wall.normal*side
			var distance: float = (actor.position-wall.origin).dot(inward)
			var clearance: float = actor.definition.radius+wall.half_width
			if distance < clearance-.00001:
				actor.position += inward*(clearance-distance)
				changed = true
		actor.position = actor.position.clamp(bounds.position+Vector2.ONE*actor.definition.radius,bounds.end-Vector2.ONE*actor.definition.radius)
		if not changed:
			break

func _move_with_cut_reflection(actor,destination: Vector2) -> void:
	var remaining: Vector2 = destination-actor.position
	for _iteration in range(8):
		var contact: Dictionary = clip_motion_to_cut_walls(actor,actor.position,actor.position+remaining)
		actor.position = contact.position
		if contact.normal.is_zero_approx():
			return
		_notify_cut_contact(actor,contact.normal)
		if not actor.alive or actor.movement_override != null:
			return
		remaining = (remaining*(1.0-float(contact.fraction))).bounce(contact.normal)
		if remaining.length_squared() < .000001:
			return

func _notify_cut_contact(actor,normal: Vector2) -> void:
	_damage_knockback_wall(actor,normal)
	actor.last_wall_velocity = actor.velocity
	actor.movement.on_collision(normal)
	_reflect_motion(actor,normal)
	if actor.movement_override != null:
		actor.movement_override.cancel_cast()
	for skill in actor.skills:
		if actor.alive and skill.active:
			skill.on_wall_contact(normal)

func forfeit_outside(actor,direction: Vector2,texture: Texture2D,exit_velocity: Vector2 = Vector2.ZERO) -> void:
	if not running or not actor.alive:
		return
	actor.health = 0
	var travel: Vector2 = exit_velocity if not exit_velocity.is_zero_approx() else direction.normalized()*actor.movement_speed()
	_defeat_fighter(actor,{"exit_kind":"lost","exit_texture":texture,"direction":direction.normalized(),"exit_velocity":travel})

func apply_damage(source, target, amount: float, skill_id: String, allow_reaction: bool = true, impulse: Vector2 = Vector2.ZERO, airborne: Dictionary = {}, damage_type: String = "normal", wall_damage: float = 0.0) -> void:
	if not running or target == null or not target.alive or amount <= 0.0 or not is_finite(amount):
		return
	if source != null and (not source.alive or not is_enemy(source, target) or is_time_stopped(source)):
		return
	if _damage_queue.size() >= MAX_DAMAGE_EVENTS_PER_STEP:
		return
	if not impulse.is_finite():
		return
	_damage_queue.append({
		"source": source, "target": target, "amount": amount,
		"skill_id": skill_id, "allow_reaction": allow_reaction, "impulse": impulse, "airborne":airborne.duplicate(), "damage_type":damage_type,"wall_damage":wall_damage,
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
	if source != null and is_time_stopped(source):
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
	if not running or source == null or not source.alive or is_time_stopped(source) or projectiles.size() >= MAX_PROJECTILES:
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
	projectile["visual_height"] = source.airborne_height
	projectile["visual_clock"] = 0.0
	if bool(projectile.get("piercing",false)):
		projectile["hit_targets"] = {}
	projectiles.append(projectile)
	record_event({"kind":"projectile","source":source.side,"projectile_id":projectile.id,"skill_id":projectile.skill_id,"position":projectile.position,"velocity":projectile.velocity,"damage":projectile.damage,"radius":projectile.radius})

func spawn_pickup(source, options: Dictionary) -> Dictionary:
	if not running or source == null or not source.alive or is_time_stopped(source) or pickups.size() >= 32:
		return {}
	var kind: String = str(options.get("kind","toast"))
	if kind == "toast" and pickups.any(func(pickup): return pickup.kind == "toast"):
		return {}
	var radius: float = maxf(1,float(options.get("radius",18.0)))
	var inner: Rect2 = bounds.grow(-radius - 12)
	var position: Vector2 = inner.get_center()
	var best_distance: float = -1
	for attempt in range(16):
		var candidate := Vector2(rng.randf_range(inner.position.x,inner.end.x),rng.randf_range(inner.position.y,inner.end.y))
		var distance: float = INF
		for fighter in fighters:
			if fighter.alive:
				distance = minf(distance,candidate.distance_to(fighter.position) - fighter.definition.radius)
		if distance > best_distance:
			best_distance = distance
			position = candidate
		if distance > radius + 40:
			break
	if options.has("position"):
		position = options.position.clamp(inner.position,inner.end)
	var pickup := {"id":_next_pickup_id,"kind":kind,"position":position,"radius":radius,"remaining":INF if kind == "toast" else maxf(0.1,float(options.get("lifetime",20.0))),"source":source}
	_next_pickup_id += 1
	pickups.append(pickup)
	record_event({"kind":"pickup_spawn","source":source.side,"pickup_id":pickup.id,"item":kind,"position":position})
	if kind == "toast":
		toast_initialized = true
		toast_refresh.clear()
	return pickup

func ensure_initial_toast(source,radius: float) -> void:
	if not toast_initialized:
		spawn_pickup(source,{"kind":"toast","radius":radius})

func schedule_toast_refresh(delay: float,radius: float) -> void:
	if not running or pickups.any(func(pickup): return pickup.kind == "toast"):
		return
	# Multiple Feiying share one pending refresh; never stack copies or timers.
	if toast_refresh.is_empty() or float(toast_refresh.remaining) > delay:
		toast_refresh = {"remaining":maxf(0,delay),"radius":radius}

func _toast_provider():
	for fighter in fighters:
		if fighter.alive:
			for skill in fighter.skills:
				if skill.active and skill.skill_id == "feiying_toast":
					return fighter
	return null

func nearest_pickup(fighter, kind: String = "toast") -> Dictionary:
	var nearest: Dictionary = {}
	var distance: float = INF
	for pickup in pickups:
		if pickup.kind != kind:
			continue
		var current: float = fighter.position.distance_squared_to(pickup.position)
		if current < distance:
			distance = current
			nearest = pickup
	return nearest

func consume_pickup(id: int,consumer = null) -> bool:
	for i in range(pickups.size()):
		if int(pickups[i].id) == id:
			record_event({"kind":"pickup_taken","source":consumer.side if consumer != null else -1,"pickup_id":id,"item":pickups[i].kind})
			pickups.remove_at(i)
			return true
	return false

func _update_pickups(delta: float) -> void:
	var provider = _toast_provider()
	for pickup in pickups:
		pickup.remaining -= delta
		if pickup.kind == "toast" and provider != null:
			pickup.source = provider
	pickups = pickups.filter(func(pickup): return pickup.remaining > 0 and (provider != null if pickup.kind == "toast" else pickup.source.alive))
	if provider == null:
		toast_refresh.clear()
	elif not toast_refresh.is_empty():
		toast_refresh.remaining -= delta
		if float(toast_refresh.remaining) <= 0.000001:
			var radius: float = float(toast_refresh.radius)
			toast_refresh.clear()
			spawn_pickup(provider,{"kind":"toast","radius":radius})

func _launch_airborne(source,target,impulse: Vector2,options: Dictionary) -> void:
	if is_time_stopped(target):
		return
	if target.movement_override != null:
		if target.movement_override.resists_displacement():
			return
		target.movement_override.cancel_cast()
	target.airborne_duration = clampf(float(options.get("duration",1.5)),0.1,10)
	target.collision_rebound_remaining = 0
	target.airborne_remaining = target.airborne_duration
	target.airborne_origin = target.position
	# Choose an in-bounds landing point once; no wall or actor collisions occur
	# during the airborne arc. This also avoids landing outside small maps.
	var travel: Vector2 = impulse * (1.0 - exp(-8.0 * target.airborne_duration)) / 8.0
	target.airborne_destination = (target.position + travel).clamp(bounds.position + Vector2.ONE*target.definition.radius,bounds.end - Vector2.ONE*target.definition.radius)
	target.airborne_peak = clampf(float(options.get("height",100.0)),0,300)
	target.airborne_height = 0
	target.airborne_source = source
	target.landing_damage = maxf(0,float(options.get("landing_damage",75.0)))
	record_event({"kind":"airborne_start","source":source.side if source != null else -1,"target":target.side,"duration":target.airborne_duration,"height":target.airborne_peak,"landing_damage":target.landing_damage})
	target.dash_remaining = 0
	target.knockback = Vector2.ZERO
	target.wall_impact_source_id = -1
	target.wall_impact_damage = 0
	target.impact_remaining = target.airborne_duration
	target.impact_recovery = 0
	emit_effect("burst",target.position,Color("ffe1c5"),{"radius":52.0})

func _advance_airborne(fighter,delta: float) -> void:
	var previous: Vector2 = fighter.position
	fighter.airborne_remaining = maxf(0,fighter.airborne_remaining - delta)
	var time: float = fighter.airborne_duration - fighter.airborne_remaining
	var progress: float = clampf(time / fighter.airborne_duration,0,1)
	var travel: float = (1.0-exp(-8.0*time)) / (1.0-exp(-8.0*fighter.airborne_duration))
	fighter.position = fighter.airborne_origin.lerp(fighter.airborne_destination,travel)
	fighter.velocity = (fighter.position - previous) / maxf(delta,0.000001)
	fighter.airborne_height = sin(progress*PI) * fighter.airborne_peak
	fighter.impact_angle -= deg_to_rad(720.0) * delta
	fighter.impact_remaining = fighter.airborne_remaining
	if fighter.airborne_remaining > 0.000001:
		return
	fighter.airborne_remaining = 0
	fighter.airborne_height = 0
	if not cut_walls.is_empty():
		_project_from_cut_walls(fighter)
	fighter.velocity = Vector2.ZERO
	fighter.knockback = Vector2.ZERO
	fighter.impact_remaining = 0
	fighter.impact_recovery = 0.12
	fighter.impact_recovery_start = fighter.impact_angle
	fighter.impact_recovery_target = floorf(fighter.impact_angle / TAU) * TAU
	var source = fighter.airborne_source
	var damage: float = fighter.landing_damage
	record_event({"kind":"airborne_end","target":fighter.side})
	fighter.airborne_source = null
	fighter.landing_damage = 0
	apply_damage(source if source != null and source.alive else null,fighter,damage,"feiying_landing",false)
	emit_effect("smash",fighter.position,Color("eed0ac"),{"radius":65.0,"angle":0.0})

func emit_effect(kind: String, at: Vector2, color: Color, extra: Dictionary = {}) -> void:
	if kind in ["dry_fire","revolver_shot","revolver_reload","guard_start","acheron_slash"]:
		var action: Dictionary = extra.duplicate(true)
		action.merge({"kind":"skill_action","action":kind,"source":int(extra.get("side",-1)),"position":at},true)
		record_event(action)
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
	for pickup in pickups:
		visuals.append({"kind":"toast","position":pickup.position,"radius":pickup.radius,"clock":world_elapsed})
	for fighter in fighters:
		if fighter.alive:
			for skill in fighter.skills:
				if is_instance_valid(skill) and skill.has_method("get_visuals"):
					var items: Array = skill.get_visuals()
					for item in items:
						item["clock"] = fighter.local_time
						item["frozen"] = is_time_stopped(fighter)
					if fighter.airborne_height > 0:
						for item in items:
							if item.get("kind","") in ["revolver","sword","ring","charge_meter","yunli_guard","dayun"]:
								item.position -= Vector2(0,fighter.airborne_height)
					visuals.append_array(items)
	return visuals

func clear_battle() -> void:
	running = false
	_end_time_stop()
	pending_time_stop.clear()
	world_elapsed = 0
	shrink_scale = 1
	shrink_accumulator = 0
	_damage_queue.clear()
	projectiles.clear()
	pickups.clear()
	_next_pickup_id = 1
	toast_initialized = false
	toast_refresh.clear()
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
	cut_walls.clear()
	_next_cut_id = 1

func _exit_tree() -> void:
	time_stop_owner = null
	pending_time_stop.clear()
	# Children are freed by Godot; explicitly break RefCounted owner/source cycles.
	for fighter in fighters:
		fighter.clear_runtime()
	_damage_queue.clear()
	projectiles.clear()
	pickups.clear()
	toast_refresh.clear()

func _update_timers(fighter, delta: float) -> void:
	fighter.collision_rebound_remaining = maxf(0,fighter.collision_rebound_remaining - delta)
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
			record_event({"kind":"shield_end","target":fighter.side,"amount":fighter.shield})
			fighter.shield = 0.0
	for id in fighter.statuses.keys():
		var status: Dictionary = fighter.statuses[id]
		if status.get("source") != null and is_time_stopped(status.source):
			continue
		var status_delta: float = minf(delta, float(status["remaining"]))
		status["remaining"] = maxf(0.0, float(status["remaining"]) - delta)
		if id == "burn":
			status["tick_accumulator"] = float(status["tick_accumulator"]) + status_delta
			while float(status["tick_accumulator"]) >= 0.5 - 0.00001:
				status["tick_accumulator"] = maxf(0.0, float(status["tick_accumulator"]) - 0.5)
				apply_damage(status["source"], fighter, float(status["power"]) * 0.5, "burn", false)
		if float(status["remaining"]) <= 0.00001:
			record_event({"kind":"status_end","source":status.source.side if status.get("source") != null else -1,"target":fighter.side,"id":id})
			fighter.statuses.erase(id)

func _move_fighter(fighter, delta: float) -> void:
	if fighter.airborne_remaining > 0:
		_advance_airborne(fighter,delta)
		return
	if fighter.movement_override != null:
		fighter.movement_override.advance_movement(delta)
		_constrain_fighter(fighter)
		return
	var desired: Vector2 = fighter.movement.desired_velocity(delta)
	for skill in fighter.skills:
		if skill.active and skill.has_method("desired_velocity_override"):
			var replacement = skill.desired_velocity_override()
			if replacement is Vector2:
				desired = replacement
	if fighter.collision_rebound_remaining > 0:
		desired = fighter.collision_rebound_direction * fighter.movement_speed()
	if fighter.casting_skill != null and fighter.casting_skill.phase == "charge" and not fighter.casting_skill.charge_can_move:
		desired = Vector2.ZERO
	var slow: float = 0
	if fighter.statuses.has("slow") and not is_time_stopped(fighter.statuses.slow.source):
		slow = float(fighter.statuses.slow.power)
	for effect in fighter.aura_slows.values():
		if effect.source.alive and not is_time_stopped(effect.source):
			slow = maxf(slow,float(effect.power))
	desired *= clampf(1.0-slow,0.05,1.0)
	if fighter.dash_remaining > 0.0:
		desired = fighter.dash_velocity
		fighter.dash_remaining = maxf(0.0, fighter.dash_remaining - delta)
	if fighter.impact_remaining > 0.0:
		desired = Vector2.ZERO
	fighter.velocity = desired + fighter.knockback
	if cut_walls.is_empty():
		fighter.position += fighter.velocity * delta
	else:
		_move_with_cut_reflection(fighter,fighter.position+fighter.velocity*delta)
	if not fighter.alive:
		return
	fighter.knockback *= exp(-8.0 * delta)
	_constrain_fighter(fighter)
	_update_impact(fighter, delta)

func _apply_impact(fighter, impulse: Vector2) -> bool:
	if fighter.airborne_remaining > 0 or is_time_stopped(fighter):
		return false
	if fighter.movement_override != null:
		if fighter.movement_override.resists_displacement():
			return false
		fighter.movement_override.cancel_cast()
	fighter.knockback = impulse
	fighter.wall_impact_source_id = -1
	fighter.wall_impact_damage = 0
	fighter.collision_rebound_remaining = 0
	fighter.last_hit_direction = impulse.normalized()
	fighter.impact_remaining = maxf(0.000001,log(maxf(60.0,impulse.length()) / 60.0) / 8.0)
	fighter.impact_recovery = 0.0
	fighter.lift_time = 0.28
	emit_effect("impact", fighter.position, Color("ffe4a0"), {"side":fighter.side, "angle":impulse.angle()})
	return true

func _damage_knockback_wall(fighter, normal: Vector2) -> void:
	if fighter.impact_remaining <= 0 or fighter.wall_impact_damage <= 0 or fighter.knockback.dot(normal) >= 0:
		return
	var source_id: int = fighter.wall_impact_source_id
	var amount: float = fighter.wall_impact_damage
	# One bonus per successful heavy knockback, including corner contacts.
	fighter.wall_impact_damage = 0
	fighter.wall_impact_source_id = -1
	if source_id >= 0 and source_id < fighters.size():
		apply_damage(fighters[source_id],fighter,amount,"collision_smash_wall",false)

func _update_impact(fighter, delta: float) -> void:
	if fighter.impact_remaining > 0.0:
		fighter.impact_angle -= deg_to_rad(720.0) * delta
		var speed: float = fighter.knockback.length()
		fighter.impact_remaining = maxf(0.000001,log(maxf(60.0,speed) / 60.0) / 8.0)
		if speed < 60.0:
			fighter.knockback = Vector2.ZERO
			fighter.wall_impact_damage = 0
			fighter.wall_impact_source_id = -1
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
		_damage_knockback_wall(fighter,normal)
		fighter.last_wall_velocity = fighter.velocity
		# Reflect each axis at corners instead of reflecting around a diagonal normal.
		if normal.x != 0.0:
			fighter.movement.on_collision(Vector2(normal.x, 0.0))
			_reflect_motion(fighter,Vector2(normal.x,0.0))
		if normal.y != 0.0:
			fighter.movement.on_collision(Vector2(0.0, normal.y))
			_reflect_motion(fighter,Vector2(0.0,normal.y))
		if fighter.movement_override == null:
			for skill in fighter.skills:
				if fighter.alive and skill.active and skill.has_method("on_wall_contact"):
					skill.on_wall_contact(normal)
	if fighter.alive and not cut_walls.is_empty():
		_project_from_cut_walls(fighter)

func _reflect_motion(fighter,normal: Vector2) -> void:
	if fighter.velocity.dot(normal) < -0.000001:
		fighter.velocity = fighter.velocity.bounce(normal)
		# Let even chase/kite and bread pursuit visibly depart before steering
		# back. Normal bounce retains its reflected heading after this window.
		fighter.collision_rebound_direction = fighter.velocity.normalized()
		fighter.collision_rebound_remaining = 0.2
	if fighter.knockback.dot(normal) < 0:
		fighter.knockback = fighter.knockback.bounce(normal)
	if fighter.dash_velocity.dot(normal) < 0:
		fighter.dash_velocity = fighter.dash_velocity.bounce(normal)

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
	if first.airborne_remaining > 0 or second.airborne_remaining > 0 or is_time_stopped(first) or is_time_stopped(second):
		return
	var minimum_distance: float = first.definition.radius + second.definition.radius + 0.05
	for iteration in range(2):
		var offset: Vector2 = first.position - second.position
		var distance: float = offset.length()
		if is_enemy(first, second):
			if distance <= minimum_distance + 0.05 + _contact_bonus(first) and not first.contact_enemies.has(second):
				first.contact_enemies.append(second)
			if distance <= minimum_distance + 0.05 + _contact_bonus(second) and not second.contact_enemies.has(first):
				second.contact_enemies.append(first)
		if first.movement_override != null or second.movement_override != null:
			break
		var normal: Vector2 = offset / distance if distance > 0.001 else Vector2.LEFT
		if iteration == 0 and distance <= minimum_distance + 0.01:
			if first.velocity.dot(normal) < -0.000001:
				first.movement.on_collision(normal)
			if second.velocity.dot(-normal) < -0.000001:
				second.movement.on_collision(-normal)
			_reflect_motion(first,normal)
			_reflect_motion(second,-normal)
		if distance >= minimum_distance:
			break
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
			record_event({"kind":"projectile_end","source":source.side,"projectile_id":projectile.id,"reason":"source_dead"})
			continue
		var travel_delta: float = minf(delta, float(projectile["lifetime"]))
		if travel_delta <= 0.0:
			record_event({"kind":"projectile_end","source":source.side,"projectile_id":projectile.id,"reason":"expired"})
			continue
		projectile["lifetime"] = maxf(0.0, float(projectile["lifetime"]) - delta)
		projectile["visual_height"] = float(projectile.get("visual_height",0)) * exp(-10.0 * delta)
		projectile["visual_clock"] = float(projectile.get("visual_clock",0)) + travel_delta
		var start: Vector2 = projectile["position"]
		var destination: Vector2 = start + projectile["velocity"] * travel_delta
		projectile["previous_position"] = start
		projectile["position"] = destination
		if bool(projectile.get("piercing",false)):
			var hits: Array = []
			for target in get_collision_targets(source):
				if projectile.hit_targets.has(target.fighter_id):
					continue
				var contact: float = _segment_circle_contact(start,destination,target.position,float(projectile.radius) + target.definition.radius)
				if contact >= 0:
					hits.append({"target":target,"contact":contact})
			hits.sort_custom(func(a,b): return a.target.fighter_id < b.target.fighter_id if a.contact == b.contact else a.contact < b.contact)
			for hit in hits:
				projectile.hit_targets[hit.target.fighter_id] = true
				projectile.position = start.lerp(destination,hit.contact)
				_projectile_impact(projectile,hit.target)
			projectile.position = destination
			if float(projectile.lifetime) > 0 and bounds.grow(float(projectile.get("exit_margin",40.0))).has_point(destination):
				remaining.append(projectile)
			else:
				record_event({"kind":"projectile_end","source":source.side,"projectile_id":projectile.id,"reason":"expired" if float(projectile.lifetime) <= 0 else "outside"})
			continue
		var impacted = null
		var closest_t: float = 2.0
		for target in get_collision_targets(source):
			var radius: float = float(projectile["radius"]) + target.definition.radius
			var contact: float = _segment_circle_contact(start, destination, target.position, radius)
			if contact >= 0.0 and contact < closest_t:
				impacted = target
				closest_t = contact
		if impacted != null:
			projectile["position"] = start.lerp(destination, closest_t)
			_projectile_impact(projectile, impacted)
			record_event({"kind":"projectile_end","source":source.side,"projectile_id":projectile.id,"reason":"hit"})
		elif float(projectile["lifetime"]) > 0.0 and bounds.grow(40.0).has_point(destination):
			remaining.append(projectile)
		else:
			record_event({"kind":"projectile_end","source":source.side,"projectile_id":projectile.id,"reason":"expired" if float(projectile.lifetime) <= 0 else "outside"})
	projectiles = remaining

func _projectile_impact(projectile: Dictionary, direct_target) -> void:
	var source = projectile["source"]
	var hit_position: Vector2 = projectile["position"]
	record_event({"kind":"projectile_hit","source":source.side,"target":direct_target.side,"projectile_id":projectile.id,"skill_id":projectile.skill_id,"position":hit_position})
	var blast_radius: float = float(projectile.get("blast_radius", 0.0))
	var targets: Array = [direct_target]
	if blast_radius > 0.0:
		for target in get_collision_targets(source):
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
		event["raw_amount"] = incoming
		for skill in target.skills:
			if is_instance_valid(skill) and skill.active and skill.has_method("incoming_damage_multiplier"):
				var multiplier: float = skill.incoming_damage_multiplier(event)
				if is_finite(multiplier):
					incoming *= clampf(multiplier,0.0,10.0)
		event["mitigated_amount"] = incoming
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
				if _apply_impact(target, impulse) and source != null:
					target.wall_impact_source_id = source.fighter_id
					target.wall_impact_damage = maxf(0,float(event.get("wall_damage",0)))
			elif source != null:
				target.last_hit_direction = source.position.direction_to(target.position)
			var airborne: Dictionary = event.get("airborne",{})
			if not airborne.is_empty() and target.health > 0:
				_launch_airborne(source,target,impulse,airborne)
		if source != null:
			source.damage_dealt += actual + absorbed
		event["amount"] = actual
		event["absorbed"] = absorbed
		var hit_color: Color = Color("ffe18c") if absorbed == 0.0 else Color("9fddff")
		emit_effect("hit", target.position, hit_color, {
			"amount": actual + absorbed, "absorbed": absorbed,
			"side": target.side, "skill_id": event["skill_id"], "damage_type":event.get("damage_type","normal"),
		})
		_log({"kind": "damage", "source": source.side if source != null else -1,
			"target": target.side, "amount": actual, "absorbed": absorbed, "skill_id": event["skill_id"],"raw_amount":event.raw_amount,"mitigated_amount":incoming,"damage_type":event.get("damage_type","normal"),"health_after":target.health,"shield_after":target.shield,"impulse":event.get("impulse",Vector2.ZERO),"airborne":event.get("airborne",{})})
		# State observers see every settled hit; allow_reaction still gates immediate counters.
		if not is_time_stopped(target):
			for skill in target.skills:
				if is_instance_valid(skill) and skill.active and skill.has_method("on_damage_settled"):
					skill.on_damage_settled(event)
		if event["allow_reaction"] and not is_time_stopped(target):
			for skill in target.skills:
				if is_instance_valid(skill) and skill.active and skill.has_method("on_damage_received"):
					skill.on_damage_received(event)
		if actual + absorbed > 0:
			for observer in fighters:
				if observer.alive and not is_time_stopped(observer):
					for skill in observer.skills:
						if skill.active:
							skill.on_battle_damage(event)
	if not _damage_queue.is_empty():
		_log({"kind": "diagnostic", "message": "Damage reaction budget exceeded; remaining events discarded."})
		_damage_queue.clear()

func _resolve_deaths_and_result() -> void:
	var alive_teams: Dictionary = {}
	for fighter in fighters:
		if fighter.alive and fighter.health <= 0:
			_defeat_fighter(fighter)
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

func _defeat_fighter(fighter,extra: Dictionary = {}) -> void:
	fighter.alive = false
	fighter.velocity = Vector2.ZERO
	fighter.dash_remaining = 0
	fighter.airborne_remaining = 0
	fighter.airborne_height = 0
	fighter.airborne_source = null
	for skill in fighter.skills:
		skill.cancel_cast()
		skill.active = false
	var data: Dictionary = {"side":fighter.side,"direction":fighter.last_hit_direction,"angle":fighter.impact_angle}
	data.merge(extra,true)
	emit_effect("death",fighter.position,fighter.definition.theme_color,data)
	_log({"kind":"death","side":fighter.side,"reason":extra.get("exit_kind","damage")})

func _finish_team(team: int, reason: String) -> void:
	running = false
	_end_time_stop()
	pending_time_stop.clear()
	winner_team = team
	winner = -1
	if team >= 0:
		for fighter in fighters:
			if fighter.team_id == team:
				winner = fighter.fighter_id
				break
	result = {"winning_team":team, "draw":team < 0, "reason":reason}
	projectiles.clear()
	pickups.clear()
	toast_refresh.clear()
	for fighter in fighters:
		var heading: Vector2 = fighter.velocity.normalized()
		if heading.is_zero_approx():
			heading = fighter.movement.direction if fighter.movement_id in ["bounce","wander"] else Vector2(fighter.facing,0)
		fighter.post_result_heading = heading.normalized()
		fighter.velocity = Vector2.ZERO
		fighter.dash_remaining = 0
		fighter.lift_time = 0
		fighter.knockback = Vector2.ZERO
		fighter.impact_remaining = 0.0
		fighter.impact_recovery = 0.0
		fighter.impact_angle = 0.0
		fighter.airborne_remaining = 0
		fighter.airborne_height = 0
		fighter.airborne_source = null
		fighter.collision_rebound_remaining = 0
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
	record_event(entry)
	event_log.append(entry)
	if event_log.size() > MAX_LOG_ENTRIES:
		event_log.pop_front()

func record_event(entry: Dictionary) -> void:
	# Separate from the bounded debug/effect buffers. No runtime object references
	# are required by listeners, and presentation after the result is excluded.
	if not running and entry.get("kind","") not in ["end","time_stop_end"]:
		return
	if combat_event.get_connections().is_empty():
		return
	var data: Dictionary = entry.duplicate(true)
	data["tick"] = tick_count
	data["time"] = elapsed
	combat_event.emit(data)
