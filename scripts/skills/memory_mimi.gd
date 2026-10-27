extends "res://scripts/skills/skill_base.gd"
@export_range(0,200,1) var punch_range: float = 21.0
@export_range(0.1,60,0.1) var punches_per_second: float = 13.0
@export_range(0,100000,1) var punch_damage: float = 10.0
@export_range(0,100,0.1) var ally_hit_charge: float = 5.0
@export_range(0,100,0.1) var mimi_hit_charge: float = 3.5
@export_range(0.1,30,0.1) var time_stop_duration: float = 7.0
@export_range(0,200,1) var stopped_range_bonus: float = 10.0
@export_range(16,120,1) var mimi_size: float = 64.0
@export_range(100,3000,10) var mimi_move_speed: float = 800.0
@export_range(100,3000,10) var mimi_return_speed: float = 650.0
var mimi_position: Vector2 = Vector2.ZERO
var charge: float = 0.0
var punch_accumulator: float = 0.0
var attack_remaining: float = 0.0
var punch_count: int = 0
var time_stops_count: int = 0
const REST = preload("res://assets/stickers/106_迷迷 睡觉.png")
const ATTACK = preload("res://assets/stickers/105_迷迷 攻击.png")

func setup(owner_fighter,battle_arena) -> void:
	super.setup(owner_fighter,battle_arena)
	mimi_position = rest_position()

func rest_position() -> Vector2:
	return fighter.position + Vector2(26*fighter.facing,-54-fighter.airborne_height)

func summon_position() -> Vector2:
	return mimi_position

func on_fighter_teleported(actor, from: Vector2, to: Vector2) -> void:
	if actor == fighter and attack_remaining <= 0:
		mimi_position += to-from

func attack_position(target) -> Vector2:
	var toward_owner: Vector2 = target.position.direction_to(fighter.position)
	if toward_owner.is_zero_approx():
		toward_owner = Vector2.LEFT if fighter.facing > 0 else Vector2.RIGHT
	var desired: Vector2 = target.position + toward_owner*(target.definition.radius + mimi_size*.22) + Vector2(0,-8)
	var inner: Rect2 = arena.bounds.grow(-mimi_size*.2)
	return desired.clamp(inner.position,inner.end)

func attack_reach(target) -> float:
	return fighter.definition.radius + target.definition.radius + punch_range + (stopped_range_bonus if arena.time_stop_owner == fighter else 0.0)

func tick(delta: float) -> void:
	if not can_act() or not arena.running:
		return
	attack_remaining = maxf(0,attack_remaining-delta)
	if charge >= 100 and arena.time_stop_remaining <= 0:
		arena.request_time_stop(fighter,time_stop_duration)
	if arena.time_stop_owner == fighter:
		_set_visual("time_stop",release_texture,arena.time_stop_remaining)
	if fighter.airborne_remaining > 0:
		# Airborne interrupts punching without banking attacks for landing.
		punch_accumulator = 0
		attack_remaining = 0
		mimi_position = mimi_position.move_toward(rest_position(),mimi_return_speed*delta)
		return
	var target = null
	var distance: float = INF
	for enemy in arena.get_collision_targets(fighter):
		var current: float = fighter.position.distance_to(enemy.position)
		if current <= attack_reach(enemy) and current < distance:
			distance = current
			target = enemy
	if target == null:
		punch_accumulator = 0
		attack_remaining = 0
		mimi_position = mimi_position.move_toward(rest_position(),mimi_return_speed*delta)
		return
	if absf(target.position.x-fighter.position.x) > 0.01:
		fighter.facing = signf(target.position.x-fighter.position.x)
	mimi_position = mimi_position.move_toward(attack_position(target),mimi_move_speed*delta)
	punch_accumulator += delta
	var interval: float = 1.0/maxf(.1,punches_per_second)
	while punch_accumulator >= interval - 0.000001:
		punch_accumulator = maxf(0,punch_accumulator-interval)
		var stopped: bool = arena.time_stop_owner == fighter
		arena.apply_damage(fighter,target,punch_damage,"mimi_punch",true,Vector2.ZERO,{},"true" if stopped else "normal")
		punch_count += 1
		attack_remaining = 0.12
		var direction: Vector2 = summon_position().direction_to(target.position)
		var effect_position: Vector2 = target.position-direction*target.definition.radius+direction.orthogonal()*(7 if punch_count%2 else -7)
		arena.emit_effect("mimi_punch",effect_position,Color("ffc9df"),{"angle":direction.angle(),"side":fighter.side,"true_damage":stopped})

func on_battle_damage(event: Dictionary) -> void:
	if not can_act() or arena.time_stop_remaining > 0:
		return
	var source = event.get("source")
	if source == null or source.team_id != fighter.team_id:
		return
	var own_punch: bool = source == fighter and str(event.skill_id) == "mimi_punch"
	charge = minf(100,charge + (mimi_hit_charge if own_punch else ally_hit_charge))
	if charge >= 100:
		arena.request_time_stop(fighter,time_stop_duration)

func on_time_stop_started() -> void:
	charge = 0
	time_stops_count += 1
	phase = "time_stop"
	fighter.casting_skill = self
	_set_visual("time_stop",release_texture,arena.time_stop_remaining)

func on_time_stop_ended() -> void:
	charge = 0
	super.cancel_cast()

func cancel_cast() -> void:
	charge = 0
	attack_remaining = 0
	punch_accumulator = 0
	if fighter != null:
		mimi_position = rest_position()
	super.cancel_cast()

func seed_preview() -> void:
	charge = 100
	arena.fighters[1].position = fighter.position + Vector2(65,0)
	arena.request_time_stop(fighter,time_stop_duration)

func is_in_flight() -> bool:
	return arena.time_stop_owner == fighter

func get_visuals() -> Array:
	if not can_act():
		return []
	return [{"kind":"memory_mimi","position":fighter.position,"summon":summon_position(),"texture":ATTACK if attack_remaining > 0 else REST,"size":mimi_size,"charge":charge,"range":fighter.definition.radius+punch_range+(stopped_range_bonus if arena.time_stop_owner == fighter else 0),"stopped":arena.time_stop_owner == fighter,"remaining":arena.time_stop_remaining,"duration":time_stop_duration,"facing":fighter.facing}]
