extends "res://scripts/skills/skill_base.gd"
## Wall anchors form a polyline. A full weave is retraced without collision stops.
@export_range(1,100,1) var initial_thread_count: int = 1
@export_range(0,1,0.01) var threads_per_speed: float = 0.05
@export_range(0,1000,1) var speed_gain_per_dash: float = 20.0
@export_range(100,10000,10) var thread_dash_speed: float = 1600.0
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

func on_wall_contact(_normal: Vector2) -> void:
	if not can_act() or dashing or fighter.movement_override != null or not arena.running or last_wall_tick == arena.tick_count:
		return
	last_wall_tick = arena.tick_count
	if not anchors.is_empty() and anchors.back().distance_to(fighter.position) < 1.0:
		return
	anchors.append(fighter.position)
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
	# End on the original anchor and depart along the final flight direction.
	if fighter.movement_id == "bounce" and not fighter.velocity.is_zero_approx():
		fighter.movement.direction = fighter.velocity.normalized()
	var endpoint: Vector2 = fighter.position
	cancel_cast()
	anchors.append(endpoint)
	arena.emit_effect("slash",endpoint,Color("ffe280"),{"radius":55.0,"angle":fighter.velocity.angle()})

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
