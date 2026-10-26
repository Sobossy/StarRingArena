extends "res://scripts/skills/skill_base.gd"
## Six chambers, one random live round per reload; aim follows the nearest enemy.
@export_range(0,60,0.05) var reload_time: float = 1.2
@export_range(0.05,10,0.05) var shot_interval: float = 0.35
@export_range(100,5000,10) var bullet_speed: float = 1400.0
@export_range(0,100000,1) var bullet_damage: float = 200.0
@export_range(1,50,1) var bullet_radius: float = 6.0
@export_range(0,3000,10) var bullet_knockback: float = 450.0
@export_range(0.1,10,0.1) var bullet_lifetime: float = 4.0
var state: String = "reload"
var reload_elapsed: float = 0.0
var loaded_chamber: int = -1
var chamber: int = 0
var shot_remaining: float = 0.0
var aim_angle: float = 0.0
var flag_remaining: float = 0.0
var flash_remaining: float = 0.0
var shots_count: int = 0
var dry_count: int = 0
var rounds_fired: int = 0
var loads_count: int = 0
var cylinder_rotation: float = 0.0

func tick(delta: float) -> void:
	if not can_act() or not arena.running:
		return
	flag_remaining = maxf(0,flag_remaining-delta)
	flash_remaining = maxf(0,flash_remaining-delta)
	cylinder_rotation = lerp_angle(cylinder_rotation,-float(chamber)*TAU/6.0,1.0-exp(-18.0*delta))
	var target = arena.nearest_enemy(fighter)
	if target == null:
		return
	var dx: float = target.position.x - fighter.position.x
	if absf(dx) > 0.1:
		fighter.facing = 1.0 if dx > 0 else -1.0
	aim_angle = _gun_position().direction_to(target.position).angle()
	if state == "reload":
		if fighter.casting_skill != null and fighter.casting_skill != self:
			return
		fighter.casting_skill = self
		phase = "charge"
		reload_elapsed += delta
		phase_remaining = maxf(0,reload_time-reload_elapsed)
		_set_visual("charge",charge_texture,phase_remaining)
		if reload_elapsed < reload_time - 0.000001:
			return
		loaded_chamber = arena.rng.randi_range(0,5)
		chamber = 0
		loads_count += 1
		state = "firing"
		shot_remaining = 0.0
		super.cancel_cast()
	shot_remaining -= delta
	if shot_remaining <= 0.000001:
		_fire()

func _gun_position() -> Vector2:
	return fighter.position + Vector2(29 * fighter.facing,8)

func _fire() -> void:
	shots_count += 1
	var muzzle: Vector2 = _gun_position() + Vector2.from_angle(aim_angle) * 39
	if chamber == loaded_chamber:
		rounds_fired += 1
		flash_remaining = 0.15
		flag_remaining = 0
		arena.spawn_projectile(fighter,{"position":muzzle,"velocity":Vector2.from_angle(aim_angle)*bullet_speed,"damage":bullet_damage,"radius":bullet_radius,"lifetime":bullet_lifetime,"color":Color("ff3256"),"skill_id":skill_id,"visual_type":"red_bullet","knockback":bullet_knockback})
		arena.emit_effect("revolver_shot",muzzle,Color("ffdb8c"),{"angle":aim_angle,"side":fighter.side})
		state = "reload"
		reload_elapsed = 0
		loaded_chamber = -1
		arena.emit_effect("revolver_reload",fighter.position,Color("e986a5"),{"side":fighter.side})
	else:
		dry_count += 1
		flag_remaining = 0.30
		arena.emit_effect("dry_fire",muzzle-Vector2(0,fighter.airborne_height),Color.WHITE,{"angle":aim_angle,"side":fighter.side})
		chamber = (chamber + 1) % 6
		shot_remaining = shot_interval

func cancel_cast() -> void:
	super.cancel_cast()
	state = "reload"
	reload_elapsed = 0
	loaded_chamber = -1
	flag_remaining = 0
	flash_remaining = 0

func get_visuals() -> Array:
	if not can_act():
		return []
	return [{"kind":"revolver","position":fighter.position,"angle":aim_angle,"facing":fighter.facing,"loaded":loaded_chamber,"chamber":chamber,"cylinder_angle":cylinder_rotation,"reload":state == "reload","progress":clampf(reload_elapsed/maxf(reload_time,0.0001),0,1),"flag":flag_remaining,"flash":flash_remaining}]
