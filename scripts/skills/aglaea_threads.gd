extends "res://scripts/skills/skill_base.gd"
## Wall anchors form a polyline. A full weave is retraced without collision stops.
@export_range(1,100,1) var initial_thread_count: int = 1
@export_range(0,1,0.01) var threads_per_speed: float = 0.05
@export_range(0,1000,1) var speed_gain_per_dash: float = 20.0
@export_range(100,10000,10) var thread_dash_speed: float = 1600.0
@export_range(1,500,1) var minimum_thread_length: float = 60.0
@export_range(0,75,1) var minimum_departure_angle: float = 30.0
@export_range(0,90,1) var departure_jitter: float = 20.0
@export_range(0,100000,1) var thread_damage: float = 50.0
@export_range(0,100000,1) var collision_damage: float = 50.0
@export_range(0.05,10,0.05) var thread_hit_interval: float = 0.5
@export_range(0.05,10,0.05) var collision_hit_interval: float = 0.5
@export_range(0,100000,1) var thread_dash_damage: float = 140.0
@export_range(0,10,0.05) var speed_damage_ratio: float = 1.0
@export_range(0,100,1) var thread_hit_radius: float = 3.0
@export_range(1,100,1) var thread_dash_radius: float = 28.0
@export_range(0,10000,10) var thread_dash_knockback: float = 0.0
var initial_speed: float = 0.0
var anchors: Array[Vector2] = []
var dashing: bool = false
var dash_path: Array[Vector2] = []
var dash_segment: int = 0
var segment_hits: Dictionary = {}
var thread_contacts: Dictionary = {}
var thread_cooldowns: Dictionary = {}
var collision_cooldowns: Dictionary = {}
var previous_targets: Dictionary = {}
var dash_trail: Array[Vector2] = []
var last_wall_tick: int = -1
var latched_walls: Dictionary = {}
var completed_dashes: int = 0
var current_dash_damage: float = 0.0

func setup(owner_fighter,battle_arena) -> void:
	super.setup(owner_fighter,battle_arena)
	initial_speed = fighter.definition.speed

func required_threads() -> int:
	return maxi(1,ceili(initial_thread_count + maxf(0,fighter.movement_speed() - initial_speed) * threads_per_speed - 0.000001))

func resists_displacement() -> bool:
	return true

func on_bounds_changed() -> void:
	var low: Vector2 = arena.bounds.position + Vector2.ONE*fighter.definition.radius
	var high: Vector2 = arena.bounds.end - Vector2.ONE*fighter.definition.radius
	for i in range(anchors.size()):
		anchors[i] = anchors[i].clamp(low,high)
	for i in range(dash_path.size()):
		dash_path[i] = dash_path[i].clamp(low,high)
	_refresh_wall_latches(_wall_surfaces())

func before_step(_delta: float) -> void:
	if can_act() and arena.running:
		_refresh_wall_latches(_wall_surfaces())

# Surface origins describe the legal centre position, including actor radius.
func _wall_surfaces() -> Array:
	var low: Vector2 = arena.bounds.position + Vector2.ONE*fighter.definition.radius
	var high: Vector2 = arena.bounds.end - Vector2.ONE*fighter.definition.radius
	var walls: Array = [
		{"id":"left","origin":low,"normal":Vector2.RIGHT},
		{"id":"right","origin":high,"normal":Vector2.LEFT},
		{"id":"top","origin":low,"normal":Vector2.DOWN},
		{"id":"bottom","origin":high,"normal":Vector2.UP},
	]
	for wall in arena.cut_walls:
		var side: float = float(fighter.cut_wall_sides.get(wall.id,1.0 if (fighter.position-wall.origin).dot(wall.normal) >= 0 else -1.0))
		var inward: Vector2 = wall.normal*side
		walls.append({"id":"cut_%d" % wall.id,"normal":inward,"origin":wall.origin+inward*(fighter.definition.radius+wall.half_width)})
	return walls

func _wall_contacts(walls: Array) -> Array:
	return walls.filter(func(wall): return (fighter.position-wall.origin).dot(wall.normal) <= 0.75)

func _refresh_wall_latches(walls: Array) -> void:
	var remaining: Dictionary = {}
	for wall in walls:
		if latched_walls.has(wall.id) and (fighter.position-wall.origin).dot(wall.normal) < fighter.definition.radius - 0.00001:
			remaining[wall.id] = true
	latched_walls = remaining

func _latch_contacts(contacts: Array) -> void:
	for wall in contacts:
		latched_walls[wall.id] = true

func _inward_score(direction: Vector2, contacts: Array) -> float:
	var score: float = 1.0
	for wall in contacts:
		score = minf(score,direction.dot(wall.normal))
	return score

func _departure_direction(incoming: Vector2, contacts: Array, jitter: bool) -> Vector2:
	var desired: Vector2 = incoming.normalized()
	if desired.is_zero_approx():
		desired = fighter.position.direction_to(arena.bounds.get_center())
	if desired.is_zero_approx():
		desired = Vector2.RIGHT
	for wall in contacts:
		if desired.dot(wall.normal) < 0:
			desired = desired.bounce(wall.normal)
	if jitter and departure_jitter > 0:
		desired = desired.rotated(deg_to_rad(arena.rng.randf_range(-departure_jitter,departure_jitter)))
	if contacts.is_empty():
		return desired
	# Acute cut-wall corners may not have room for the requested angle.
	# Find their feasible inward margin before constraining the heading.
	var candidates: Array[Vector2] = [desired]
	for first in contacts:
		candidates.append(first.normal)
		candidates.append(first.normal.orthogonal())
		candidates.append(-first.normal.orthogonal())
		for second in contacts:
			var bisector: Vector2 = first.normal+second.normal
			if not bisector.is_zero_approx():
				candidates.append(bisector.normalized())
	var best: Vector2 = desired
	var maximum_margin: float = -INF
	for candidate in candidates:
		var margin: float = _inward_score(candidate,contacts)
		if margin > maximum_margin:
			maximum_margin = margin
			best = candidate
	var required: float = minf(sin(deg_to_rad(minimum_departure_angle)),maxf(0,maximum_margin))
	var half_angle: float = acos(clampf(required,0,1))
	for wall in contacts:
		candidates.append(wall.normal.rotated(half_angle))
		candidates.append(wall.normal.rotated(-half_angle))
	var alignment: float = -INF
	for candidate in candidates:
		if _inward_score(candidate,contacts) >= required - 0.00001 and candidate.dot(desired) > alignment:
			alignment = candidate.dot(desired)
			best = candidate
	return best.normalized()

func _set_departure(direction: Vector2) -> void:
	if fighter.movement_id in ["bounce","wander"]:
		fighter.movement.direction = direction
	fighter.velocity = direction*fighter.movement_speed()
	fighter.collision_rebound_direction = direction
	fighter.collision_rebound_remaining = 0.2

func on_wall_contact(normal: Vector2) -> void:
	if not can_act() or dashing or fighter.movement_override != null or not arena.running or last_wall_tick == arena.tick_count:
		return
	last_wall_tick = arena.tick_count
	var walls: Array = _wall_surfaces()
	_refresh_wall_latches(walls)
	var contacts: Array = _wall_contacts(walls)
	# Preserve impulse-led movement; only correct ordinary reflected movement.
	if fighter.impact_remaining <= 0 and fighter.airborne_remaining <= 0 and fighter.dash_remaining <= 0:
		var departure_contacts: Array = contacts if not contacts.is_empty() else [{"normal":normal.normalized()}]
		_set_departure(_departure_direction(fighter.velocity,departure_contacts,false))
	for wall in contacts:
		if latched_walls.has(wall.id):
			return
	if not anchors.is_empty() and anchors.back().distance_to(fighter.position) < maxf(0.001,minimum_thread_length):
		return
	anchors.append(fighter.position)
	_latch_contacts(contacts)
	arena.emit_effect("burst",fighter.position,Color("ffe280"),{"radius":18.0})
	if anchors.size() - 1 >= required_threads():
		_begin_dash()

func on_enemy_contact(enemy) -> void:
	if not can_act() or dashing or not arena.is_enemy(fighter,enemy) or not enemy.alive:
		return
	if float(collision_cooldowns.get(enemy.fighter_id,-1.0)) > arena.elapsed:
		return
	collision_cooldowns[enemy.fighter_id] = arena.elapsed + collision_hit_interval
	arena.apply_damage(fighter,enemy,collision_damage,skill_id + "_contact")

func tick(_delta: float) -> void:
	if not can_act() or not arena.running:
		return
	var points: Array[Vector2] = anchors.duplicate()
	if not dashing and not points.is_empty() and points.back().distance_to(fighter.position) > 0.001:
		points.append(fighter.position)
	var contacts: Dictionary = {}
	for i in range(points.size() - 1):
		for target in arena.get_collision_targets(fighter):
			var key: String = "%d:%d" % [i,target.fighter_id]
			var previous: Vector2 = previous_targets.get(target.fighter_id,target.position)
			var radius: float = target.definition.radius + thread_hit_radius
			var touching: bool = arena._segment_circle_contact(points[i],points[i+1],target.position,radius) >= 0
			var crossed: bool = Geometry2D.segment_intersects_segment(previous,target.position,points[i],points[i+1]) != null
			if touching:
				contacts[key] = true
			if (touching or crossed) and not thread_contacts.has(key) and float(thread_cooldowns.get(key,-1.0)) <= arena.elapsed:
				thread_cooldowns[key] = arena.elapsed + thread_hit_interval
				arena.apply_damage(fighter,target,thread_damage,skill_id + "_thread")
	thread_contacts = contacts
	for target in arena.get_collision_targets(fighter):
		previous_targets[target.fighter_id] = target.position

func _begin_dash() -> void:
	if anchors.size() < 2 or dashing:
		return
	dash_path = anchors.duplicate()
	dash_path.reverse()
	dash_segment = 0
	segment_hits.clear()
	dash_trail.clear()
	current_dash_damage = thread_dash_damage + maxf(0,fighter.movement_speed() - initial_speed) * speed_damage_ratio
	dashing = true
	phase = "thread_dash"
	fighter.casting_skill = self
	fighter.movement_override = self
	fighter.knockback = Vector2.ZERO
	fighter.impact_remaining = 0
	fighter.impact_recovery = 0
	fighter.impact_angle = 0
	fighter.dash_remaining = 0
	_set_visual("thread_dash",release_texture,0)

func advance_movement(delta: float) -> void:
	if not dashing or not can_act():
		return
	var remaining: float = delta
	while remaining > 0 and dash_segment < dash_path.size() - 1:
		var start: Vector2 = fighter.position
		var destination: Vector2 = dash_path[dash_segment + 1]
		var direction: Vector2 = start.direction_to(destination)
		var seconds: float = minf(remaining,start.distance_to(destination) / maxf(1,thread_dash_speed))
		var wall_contact: Dictionary = arena.clip_motion_to_cut_walls(fighter,start,start.move_toward(destination,thread_dash_speed*seconds))
		fighter.position = wall_contact.position
		fighter.velocity = direction * thread_dash_speed
		if not is_zero_approx(direction.x):
			fighter.facing = signf(direction.x)
		for target in arena.get_collision_targets(fighter):
			if not segment_hits.has(target.fighter_id) and arena._segment_circle_contact(start,fighter.position,target.position,target.definition.radius + thread_dash_radius) >= 0:
				segment_hits[target.fighter_id] = true
				arena.apply_damage(fighter,target,current_dash_damage,skill_id + "_dash",true,direction * thread_dash_knockback)
		if not wall_contact.normal.is_zero_approx():
			arena._notify_cut_contact(fighter,wall_contact.normal)
			return
		remaining -= seconds
		if fighter.position.distance_to(destination) <= 0.001:
			dash_segment += 1
			segment_hits.clear()
		else:
			break
	dash_trail.append(fighter.position)
	if dash_trail.size() > 12:
		dash_trail.pop_front()
	if dash_segment >= dash_path.size() - 1:
		_finish_dash()

func _finish_dash() -> void:
	completed_dashes += 1
	fighter.movement_speed_bonus += speed_gain_per_dash
	# The endpoint starts the next weave, but its outgoing heading must leave the wall.
	var endpoint: Vector2 = fighter.position
	var contacts: Array = _wall_contacts(_wall_surfaces())
	var outgoing: Vector2 = _departure_direction(fighter.velocity,contacts,true)
	var slash_angle: float = fighter.velocity.angle()
	cancel_cast()
	anchors.append(endpoint)
	_latch_contacts(contacts)
	last_wall_tick = arena.tick_count
	_set_departure(outgoing)
	arena.emit_effect("slash",endpoint,Color("ffe280"),{"radius":55.0,"angle":slash_angle})

func cancel_cast() -> void:
	if fighter != null and fighter.movement_override == self:
		fighter.movement_override = null
	dashing = false
	anchors.clear()
	dash_path.clear()
	dash_trail.clear()
	segment_hits.clear()
	thread_contacts.clear()
	thread_cooldowns.clear()
	previous_targets.clear()
	latched_walls.clear()
	last_wall_tick = -1
	super.cancel_cast()

func is_in_flight() -> bool:
	return dashing

func seed_preview() -> void:
	fighter.position = Vector2(arena.bounds.end.x - fighter.definition.radius - 35,380)
	anchors.assign([Vector2(arena.bounds.position.x + fighter.definition.radius,380)])
	fighter.movement.direction = Vector2.RIGHT

func get_visuals() -> Array:
	if not can_act():
		return []
	var points: Array[Vector2] = anchors.duplicate()
	if not dashing and not points.is_empty() and points.back().distance_to(fighter.position) > 0.001:
		points.append(fighter.position)
	return [{"kind":"golden_threads","position":fighter.position,"points":points,"trail":dash_trail.duplicate(),"dashing":dashing,"count":maxi(0,anchors.size()-1),"required":required_threads(),"speed":fighter.movement_speed()}]
