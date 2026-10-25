extends "res://scripts/skills/skill_base.gd"
## A single bat: hold/charge -> fixed launch point -> return to moving owner.
@export var outbound_speed: float = 700.0
@export var return_speed: float = 900.0
@export var damage_multiplier: float = 1.5
@export var hit_radius: float = 18.0
@export var spin_speed: float = 12.0
var bat_state: String = "held"
var charge_elapsed: float = 0.0
var bat_position: Vector2 = Vector2.ZERO
var launch_point: Vector2 = Vector2.ZERO
var bat_angle: float = 0.0
var hit_targets: Dictionary = {}
var trail: Array = []
var throws_count: int = 0

func setup(owner_fighter, battle_arena) -> void:
	super.setup(owner_fighter,battle_arena)
	bat_position = fighter.position

func tick(delta: float) -> void:
	if not can_act() or not arena.running:
		return
	if is_in_flight():
		_advance_bat(delta)
		return
	if not fighter.contact_enemies.is_empty():
		interrupt_charge()
		return
	var target = arena.opponent(fighter)
	if target == null or (fighter.casting_skill != null and fighter.casting_skill != self):
		interrupt_charge()
		return
	phase = "charge"
	fighter.casting_skill = self
	charge_elapsed += delta
	phase_remaining = maxf(0,charge_time - charge_elapsed)
	_set_visual("charge",charge_texture,phase_remaining)
	if charge_elapsed >= charge_time - 0.000001:
		# Acquire at launch, not at the start of the six-second charge.
		activate(arena.opponent(fighter))

func request_cast(target) -> bool:
	if not can_act() or is_in_flight() or target == null or not fighter.contact_enemies.is_empty() or (fighter.casting_skill != null and fighter.casting_skill != self):
		return false
	phase = "charge"
	fighter.casting_skill = self
	phase_remaining = maxf(0,charge_time - charge_elapsed)
	_set_visual("charge",charge_texture,phase_remaining)
	return true

func activate(target) -> void:
	if target == null or not target.alive or not can_act() or is_in_flight():
		return
	launch_point = target.position
	bat_position = _hand_position()
	bat_angle = bat_position.direction_to(launch_point).angle()
	bat_state = "outbound"
	charge_elapsed = 0
	phase = "release"
	phase_remaining = 0
	fighter.casting_skill = self
	_set_visual("release",release_texture,0)
	hit_targets.clear()
	trail.clear()
	throws_count += 1
	arena.emit_effect("slash",bat_position,fighter.definition.theme_color,{"angle":bat_angle,"radius":50.0})

func is_in_flight() -> bool:
	return bat_state != "held"

func interrupt_charge() -> void:
	charge_elapsed = 0
	if not is_in_flight():
		super.cancel_cast()

func cancel_cast() -> void:
	bat_state = "held"
	charge_elapsed = 0
	trail.clear()
	hit_targets.clear()
	super.cancel_cast()

func _hand_position() -> Vector2:
	return fighter.position + Vector2(14,-4)

func _advance_bat(delta: float) -> void:
	bat_angle += spin_speed * delta
	var remaining: float = delta
	# Consume the remainder after reaching the fixed turnaround point.
	for _leg in range(2):
		if remaining <= 0 or not is_in_flight():
			break
		var destination: Vector2 = launch_point if bat_state == "outbound" else _hand_position()
		var speed: float = maxf(1,outbound_speed) if bat_state == "outbound" else maxf(return_speed,fighter.definition.speed * 1.8 + 200)
		var distance: float = bat_position.distance_to(destination)
		var travel_time: float = minf(remaining,distance / speed)
		var previous: Vector2 = bat_position
		bat_position = bat_position.move_toward(destination,speed * travel_time)
		_damage_on_segment(previous,bat_position)
		remaining -= travel_time
		if bat_position.distance_to(destination) <= 0.001:
			if bat_state == "outbound":
				bat_state = "returning"
			else:
				cancel_cast()
				return
	if is_in_flight():
		_set_visual("release",release_texture,0)
		trail.append(bat_position + Vector2.from_angle(bat_angle) * -45)
		if trail.size() > 18:
			trail.pop_front()

func _damage_on_segment(start: Vector2, finish: Vector2) -> void:
	for target in arena.get_targets(fighter):
		if hit_targets.has(target.fighter_id):
			continue
		var radius: float = target.definition.radius + hit_radius
		if arena._segment_circle_contact(start,finish,target.position,radius) >= 0:
			hit_targets[target.fighter_id] = true
			arena.apply_damage(fighter,target,fighter.definition.attack * damage_multiplier,skill_id)
			arena.emit_effect("burst",target.position,Color("efd18a"),{"radius":45.0})

func get_visuals() -> Array:
	if not can_act():
		return []
	if is_in_flight():
		return [{"kind":"bat","position":bat_position,"angle":bat_angle,"color":fighter.definition.theme_color,"trail":trail}]
	if phase == "charge":
		return [{"kind":"charge_meter","position":fighter.position,"progress":clampf(charge_elapsed / maxf(charge_time,0.00001),0,1),"elapsed":charge_elapsed,"duration":charge_time,"color":fighter.definition.theme_color}]
	return []
