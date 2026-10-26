extends "res://scripts/skills/skill_base.gd"
## Charge -> decelerating tracking line -> locked warning -> slash/colour hold.
@export_range(0.1,10,0.1) var warning_lock_time: float = 1.5
@export_range(0,100000,1) var slash_damage: float = 10000.0
@export_range(1,100,1) var slash_half_width: float = 12.0
@export_range(1,40,1) var cut_wall_half_width: float = 7.0
@export_range(0.1,5,0.1) var colour_expand_time: float = 0.5
@export_range(0,10,0.1) var colour_hold_time: float = 1.5
@export_range(0,100,0.1) var lost_chance_percent: float = 1.5
@export_range(0,90,1) var aim_wobble_degrees: float = 20.0
@export_range(0.05,2,0.05) var aim_jitter_interval: float = 0.25
@export_range(0,3000,10) var aim_tracking_speed: float = 480.0
@export_range(0,720,1) var aim_rotation_speed: float = 60.0
var state: String = "charge"
var charge_elapsed: float = 0.0
var state_elapsed: float = 0.0
var aim_origin := Vector2.ZERO
var aim_direction := Vector2.RIGHT
var wave_origin := Vector2.ZERO
var last_wall_tick: int = -1
var slashes_count: int = 0
var aim_target = null
var base_angle: float = 0.0
var wobble: float = 0.0
var wobble_target: float = 0.0
var wobble_remaining: float = 0.0
const LOST = preload("res://assets/stickers/261_黄泉 迷茫.png")

func setup(owner_fighter,battle_arena) -> void:
	super.setup(owner_fighter,battle_arena)
	_begin_charge()

func _begin_charge() -> void:
	state = "charge"
	phase = "charge"
	charge_elapsed = 0
	state_elapsed = 0
	aim_target = arena.nearest_enemy(fighter)
	if aim_target != null:
		aim_origin = aim_target.position
	base_angle = arena.rng.randf_range(-PI,PI)
	wobble = arena.rng.randf_range(-1,1)
	wobble_target = wobble
	wobble_remaining = 0
	aim_direction = Vector2.from_angle(base_angle+wobble*deg_to_rad(aim_wobble_degrees))
	fighter.casting_skill = self
	_set_visual("acheron_charge",charge_texture,charge_time)

func _update_aim(delta: float) -> void:
	if aim_target == null or not aim_target.alive or not arena.is_enemy(fighter,aim_target):
		aim_target = arena.nearest_enemy(fighter)
	if aim_target == null:
		return
	var ease: float = pow(1.0-clampf(charge_elapsed/maxf(.000001,charge_time),0,1),2)
	aim_origin = aim_origin.move_toward(aim_target.position,aim_tracking_speed*ease*delta)
	wobble_remaining -= delta
	if wobble_remaining <= 0:
		wobble_target = arena.rng.randf_range(-1,1)
		wobble_remaining += aim_jitter_interval
	wobble = move_toward(wobble,wobble_target,delta/maxf(.05,aim_jitter_interval)*1.5)
	var desired_angle: float = base_angle+wobble*deg_to_rad(aim_wobble_degrees)*ease
	var change: float = wrapf(desired_angle-aim_direction.angle(),-PI,PI)
	var limit: float = deg_to_rad(aim_rotation_speed)*ease*delta
	aim_direction = Vector2.from_angle(aim_direction.angle()+clampf(change,-limit,limit))

func tick(delta: float) -> void:
	if not can_act() or not arena.running:
		return
	if fighter.casting_skill != null and fighter.casting_skill != self:
		return
	if state == "charge":
		charge_elapsed += delta
		_update_aim(delta)
		_set_visual("acheron_charge",charge_texture,maxf(0,charge_time-charge_elapsed))
		if charge_elapsed >= charge_time-.000001:
			state = "locked"
			phase = "locked"
			state_elapsed = 0
			_set_visual("acheron_locked",charge_texture,warning_lock_time)
		return
	state_elapsed += delta
	if state == "locked":
		_set_visual("acheron_locked",charge_texture,maxf(0,warning_lock_time-state_elapsed))
		if state_elapsed >= warning_lock_time-.000001:
			_release_slash()
	elif state == "aftermath":
		if state_elapsed >= colour_expand_time+colour_hold_time-.000001:
			_begin_charge()

func _release_slash() -> void:
	wave_origin = fighter.position
	var line: Array = arena.line_across_field(aim_origin,aim_direction)
	if line.size() == 2:
		for enemy in arena.get_collision_targets(fighter):
			if Geometry2D.get_closest_point_to_segment(enemy.position,line[0],line[1]).distance_to(enemy.position) <= enemy.definition.radius+slash_half_width:
				arena.apply_damage(fighter,enemy,slash_damage,skill_id)
		arena.add_cut_wall(fighter,aim_origin,aim_direction,cut_wall_half_width)
		arena.emit_effect("acheron_slash",wave_origin,Color("ff315f"),{"from":line[0],"to":line[1],"side":fighter.side,"expand_time":colour_expand_time,"hold_time":colour_hold_time,"recovery_time":colour_expand_time+colour_hold_time})
	slashes_count += 1
	state = "aftermath"
	phase = "release"
	state_elapsed = 0
	_set_visual("acheron_release",release_texture,colour_expand_time+colour_hold_time)

func portrait_progress() -> float:
	return clampf(charge_elapsed/maxf(.000001,charge_time),0,1) if state == "charge" else 1.0

func on_wall_contact(normal: Vector2) -> void:
	if not can_act() or not arena.running or last_wall_tick == arena.tick_count:
		return
	last_wall_tick = arena.tick_count
	if lost_chance_percent <= 0 or arena.rng.randf()*100.0 >= lost_chance_percent:
		return
	var direction: Vector2 = fighter.last_wall_velocity.normalized()
	if direction.is_zero_approx():
		direction = -normal.normalized()
	arena.forfeit_outside(fighter,direction,LOST,fighter.last_wall_velocity)

func cancel_cast() -> void:
	state = "idle"
	state_elapsed = 0
	charge_elapsed = 0
	aim_target = null
	super.cancel_cast()

func request_cast(_target) -> bool:
	return false

func is_in_flight() -> bool:
	return state in ["locked","aftermath"]

func get_visuals() -> Array:
	if not can_act():
		return []
	var line: Array = arena.line_across_field(aim_origin,aim_direction)
	return [{"kind":"acheron","position":fighter.position,"side":fighter.side,"state":state,"progress":portrait_progress(),"line":line,"remaining":maxf(0,warning_lock_time-state_elapsed),"wave_origin":wave_origin,"wave_progress":clampf(state_elapsed/maxf(.000001,colour_expand_time),0,1),"aftermath":state == "aftermath"}]
