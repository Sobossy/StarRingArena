extends "res://scripts/skills/skill_base.gd"
## A shared toast pickup powers one charged ram, followed by a separate air arc.
@export_range(0,60,0.1) var toast_respawn_delay: float = 1.0
@export_range(1,60,1) var toast_radius: float = 18.0
@export_range(0,100000,1) var toast_healing: float = 125.0
@export_range(0,60,0.1) var toast_seek_delay: float = 5.0
@export_range(100,5000,10) var ram_speed: float = 1200.0
@export_range(1,100,1) var ram_hit_radius: float = 28.0
@export_range(0,100000,1) var ram_damage: float = 150.0
@export_range(0,10000,10) var launch_strength: float = 1800.0
@export_range(0.1,10,0.1) var flight_duration: float = 1.5
@export_range(0,300,1) var flight_height: float = 100.0
@export_range(0,100000,1) var fall_damage: float = 75.0
var state: String = "normal"
var normal_elapsed: float = 0.0
var ram_direction: Vector2 = Vector2.RIGHT
var ram_wall_point: Vector2 = Vector2.ZERO
var ram_hit_targets: Dictionary = {}
var pickups_count: int = 0
var hits_count: int = 0

func setup(owner_fighter,battle_arena) -> void:
	super.setup(owner_fighter,battle_arena)
	arena.ensure_initial_toast(fighter,toast_radius)

func tick(delta: float) -> void:
	if not can_act() or not arena.running:
		return
	if state == "charge":
		phase_remaining = maxf(0,phase_remaining - delta)
		_set_visual("dayun_charge",charge_texture,phase_remaining)
		if phase_remaining <= 0.000001 and fighter.airborne_remaining <= 0:
			_begin_ram()
		return
	if state == "rush":
		return
	normal_elapsed += delta
	if fighter.airborne_remaining > 0 or fighter.casting_skill != null or fighter.movement_override != null:
		return
	var pickup: Dictionary = arena.nearest_pickup(fighter)
	if not pickup.is_empty() and fighter.position.distance_to(pickup.position) <= fighter.definition.radius + float(pickup.radius):
		if arena.consume_pickup(int(pickup.id),fighter):
			_pickup_toast()

func _pickup_toast() -> void:
	pickups_count += 1
	arena.heal(fighter,toast_healing)
	normal_elapsed = 0
	state = "charge"
	phase = "charge"
	phase_remaining = charge_time
	fighter.casting_skill = self
	_set_visual("dayun_charge",charge_texture,phase_remaining)
	arena.emit_effect("burst",fighter.position,Color("ffd6ad"),{"radius":48.0})

func desired_velocity_override():
	if state != "normal" or normal_elapsed < toast_seek_delay or fighter.airborne_remaining > 0:
		return null
	var pickup: Dictionary = arena.nearest_pickup(fighter)
	if pickup.is_empty():
		return null
	return fighter.position.direction_to(pickup.position) * fighter.movement_speed()

func request_cast(_target) -> bool:
	# Actual bread, not a generic cast button, is required to power the ram.
	return false

func _begin_ram() -> void:
	var target = arena.nearest_enemy(fighter)
	if target == null:
		cancel_cast()
		return
	ram_direction = fighter.position.direction_to(target.position)
	if ram_direction.is_zero_approx():
		ram_direction = Vector2.RIGHT
	var minimum: Vector2 = arena.bounds.position + Vector2.ONE*fighter.definition.radius
	var maximum: Vector2 = arena.bounds.end - Vector2.ONE*fighter.definition.radius
	var wall_distance: float = INF
	if ram_direction.x > 0.000001:
		wall_distance = minf(wall_distance,(maximum.x - fighter.position.x) / ram_direction.x)
	elif ram_direction.x < -0.000001:
		wall_distance = minf(wall_distance,(minimum.x - fighter.position.x) / ram_direction.x)
	if ram_direction.y > 0.000001:
		wall_distance = minf(wall_distance,(maximum.y - fighter.position.y) / ram_direction.y)
	elif ram_direction.y < -0.000001:
		wall_distance = minf(wall_distance,(minimum.y - fighter.position.y) / ram_direction.y)
	ram_wall_point = (fighter.position + ram_direction * maxf(0,wall_distance)).clamp(minimum,maximum)
	ram_hit_targets.clear()
	state = "rush"
	phase = "dayun_rush"
	fighter.movement_override = self
	fighter.knockback = Vector2.ZERO
	fighter.impact_remaining = 0
	fighter.impact_recovery = 0
	fighter.impact_angle = 0
	_set_visual("dayun_rush",release_texture,0)
	arena.emit_effect("dash",fighter.position,Color("ffc9de"),{"angle":ram_direction.angle(),"radius":55.0})

func advance_movement(delta: float) -> void:
	if state != "rush" or not can_act():
		return
	var start: Vector2 = fighter.position
	var wall_contact: Dictionary = arena.clip_motion_to_cut_walls(fighter,start,start.move_toward(ram_wall_point,ram_speed*delta))
	var destination: Vector2 = wall_contact.position
	var hits: Array = []
	for target in arena.get_collision_targets(fighter):
		if ram_hit_targets.has(target.fighter_id):
			continue
		var contact: float = arena._segment_circle_contact(start,destination,target.position,ram_hit_radius + target.definition.radius)
		if contact >= 0:
			hits.append({"target":target,"contact":contact})
	hits.sort_custom(func(a,b): return a.target.fighter_id < b.target.fighter_id if a.contact == b.contact else a.contact < b.contact)
	fighter.velocity = ram_direction * ram_speed
	if absf(ram_direction.x) > 0.01:
		fighter.facing = signf(ram_direction.x)
	for hit in hits:
		ram_hit_targets[hit.target.fighter_id] = true
		arena.apply_damage(fighter,hit.target,ram_damage,skill_id,true,ram_direction*launch_strength,{"duration":flight_duration,"height":flight_height,"landing_damage":fall_damage})
		hits_count += 1
	fighter.position = destination
	if not wall_contact.normal.is_zero_approx():
		arena._notify_cut_contact(fighter,wall_contact.normal)
		return
	if fighter.position.distance_to(ram_wall_point) <= 0.001:
		if fighter.movement_id in ["bounce","wander"]:
			fighter.movement.direction = ram_direction
		var minimum: Vector2 = arena.bounds.position + Vector2.ONE*fighter.definition.radius
		var maximum: Vector2 = arena.bounds.end - Vector2.ONE*fighter.definition.radius
		if absf(destination.x - minimum.x) < 0.001:
			fighter.movement.on_collision(Vector2.RIGHT)
		elif absf(destination.x - maximum.x) < 0.001:
			fighter.movement.on_collision(Vector2.LEFT)
		if absf(destination.y - minimum.y) < 0.001:
			fighter.movement.on_collision(Vector2.DOWN)
		elif absf(destination.y - maximum.y) < 0.001:
			fighter.movement.on_collision(Vector2.UP)
		cancel_cast()

func resists_displacement() -> bool:
	return state == "rush"

func on_bounds_changed() -> void:
	if state != "rush":
		return
	var low: Vector2 = arena.bounds.position + Vector2.ONE*fighter.definition.radius
	var high: Vector2 = arena.bounds.end - Vector2.ONE*fighter.definition.radius
	var distance: float = INF
	if absf(ram_direction.x) > 0.000001:
		distance = minf(distance,((high.x if ram_direction.x > 0 else low.x)-fighter.position.x)/ram_direction.x)
	if absf(ram_direction.y) > 0.000001:
		distance = minf(distance,((high.y if ram_direction.y > 0 else low.y)-fighter.position.y)/ram_direction.y)
	ram_wall_point = (fighter.position+ram_direction*maxf(0,distance)).clamp(low,high)

func cancel_cast() -> void:
	var was_dayun: bool = state != "normal"
	if fighter != null and fighter.movement_override == self:
		fighter.movement_override = null
		fighter.velocity = Vector2.ZERO
	state = "normal"
	normal_elapsed = 0
	ram_hit_targets.clear()
	super.cancel_cast()
	if was_dayun and arena != null and arena.running:
		arena.schedule_toast_refresh(toast_respawn_delay,toast_radius)

func is_in_flight() -> bool:
	return state != "normal"

func seed_preview() -> void:
	arena.pickups.clear()
	arena.toast_refresh.clear()
	arena.spawn_pickup(fighter,{"position":fighter.position,"radius":toast_radius})

func get_visuals() -> Array:
	if not can_act():
		return []
	var target = arena.nearest_enemy(fighter)
	return [{"kind":"dayun","position":fighter.position,"state":state,"remaining":phase_remaining,"duration":charge_time,"direction":fighter.position.direction_to(target.position) if target != null else ram_direction,"seeking":state == "normal" and normal_elapsed >= toast_seek_delay and not arena.nearest_pickup(fighter).is_empty()}]
