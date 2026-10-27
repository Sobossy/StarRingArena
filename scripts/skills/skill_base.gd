class_name SkillBase
extends Node
## A fresh skill node is instantiated for every fighter, every battle.
## Override tick/activate or the damage hook to add arbitrary mechanics.

@export var skill_id: String = "skill"
@export var cooldown: float = 1.0

var fighter
var arena
var cooldown_remaining: float = 0.0
var active: bool = true
var slot_id: String = ""
var phase_type: String = "主动"
var charge_time: float = 0.0
var release_time: float = 0.0
var charge_can_move: bool = true
var charge_image_path: String = ""
var release_image_path: String = ""
var charge_texture: Texture2D
var release_texture: Texture2D
var phase: String = "normal"
var phase_remaining: float = 0.0
var _phase_target = null
var _reported_phase: String = "normal"


func setup(owner_fighter, battle_arena) -> void:
	fighter = owner_fighter
	arena = battle_arena
	cooldown_remaining = 0.0
	active = true
	var library = load("res://scripts/core/character_library.gd")
	charge_texture = library.texture_from_path(charge_image_path)
	release_texture = library.texture_from_path(release_image_path)


func tick(delta: float) -> void:
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if not active or fighter == null:
		return
	if phase != "normal":
		phase_remaining = maxf(0.0, phase_remaining - delta)
		if fighter.visual_skill == self:
			fighter.visual_remaining = phase_remaining
		if phase_remaining <= 0.000001:
			if phase == "charge":
				_perform_cast()
			else:
				cancel_cast()

func request_cast(target) -> bool:
	if not can_act() or cooldown_remaining > 0 or phase != "normal" or fighter.casting_skill != null or fighter.dash_remaining > 0:
		return false
	_phase_target = target
	fighter.casting_skill = self
	if charge_time > 0:
		phase = "charge"
		phase_remaining = charge_time
		_set_visual("charge", charge_texture, charge_time)
	else:
		_perform_cast()
	return true

func _perform_cast() -> void:
	if not can_act() or not arena.running:
		cancel_cast()
		return
	if _phase_target == null or not arena.is_enemy(fighter, _phase_target) or not _phase_target.alive:
		_phase_target = arena.opponent(fighter)
	if _phase_target == null:
		cancel_cast()
		return
	phase = "release"
	phase_remaining = release_time
	_set_visual("release", release_texture, release_time)
	activate(_phase_target)
	_phase_target = null
	if release_time <= 0:
		cancel_cast()

func _set_visual(kind: String, texture: Texture2D, seconds: float) -> void:
	if arena != null and (kind != _reported_phase or fighter.visual_skill != self or fighter.visual_phase != kind):
		arena.record_event({"kind":"skill_phase","source":fighter.side,"skill_id":skill_id,"slot_id":slot_id,"phase":kind,"duration":seconds})
	_reported_phase = kind
	fighter.visual_skill = self
	fighter.visual_phase = kind
	fighter.visual_remaining = seconds
	fighter.visual_texture = texture

func flash_release() -> void:
	if fighter.casting_skill != null or release_time <= 0:
		return
	_set_visual("release", release_texture, release_time)

func cancel_cast() -> void:
	if _reported_phase != "normal" and arena != null and fighter != null:
		arena.record_event({"kind":"skill_phase","source":fighter.side,"skill_id":skill_id,"slot_id":slot_id,"phase":"normal"})
	_reported_phase = "normal"
	phase = "normal"
	phase_remaining = 0.0
	_phase_target = null
	if fighter != null:
		if fighter.casting_skill == self:
			fighter.casting_skill = null
		if fighter.visual_skill == self:
			fighter.visual_skill = null
			fighter.visual_phase = "normal"
			fighter.visual_texture = null
			fighter.visual_remaining = 0.0


func activate(_target) -> void:
	pass


func on_damage_received(_event: Dictionary) -> void:
	pass

func incoming_damage_multiplier(_event: Dictionary) -> float:
	return 1.0

func on_damage_settled(_event: Dictionary) -> void:
	pass

func on_battle_damage(_event: Dictionary) -> void:
	pass

func before_step(_delta: float) -> void:
	pass

func cleanup_spatial_effects() -> void:
	pass

func on_time_stop_started() -> void:
	pass

func on_time_stop_ended() -> void:
	pass

func on_enemy_contact(_enemy) -> void:
	pass

func on_wall_contact(_normal: Vector2) -> void:
	pass

func on_fighter_teleported(_actor, _from: Vector2, _to: Vector2) -> void:
	pass

func on_fighter_portal_rotated(_actor, _angle: float) -> void:
	pass

func desired_velocity_override():
	return null

func resists_displacement() -> bool:
	return false


func get_visuals() -> Array:
	return []


func can_act() -> bool:
	return active and fighter != null and fighter.alive and arena != null


func restart_cooldown() -> void:
	cooldown_remaining = maxf(0.05, cooldown)
