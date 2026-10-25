extends "res://scripts/skills/skill_base.gd"
## Eating -> first settled hit -> four-second guard -> snapshotted sword throw.
@export_range(0,1000,1) var healing_per_second: float = 30.0
@export_range(0.1,60,0.05) var guard_duration: float = 4.0
@export_range(0,1,0.05) var damage_reduction: float = 0.2
@export_range(0,100000,1) var counter_base_damage: float = 150.0
@export_range(0,10,0.05) var counter_damage_ratio: float = 0.4
@export_range(100,5000,10) var sword_speed: float = 850.0
@export_range(1,200,1) var sword_radius: float = 24.0
@export_range(0.1,10,0.1) var sword_lifetime: float = 4.0
@export_range(0,3000,10) var sword_knockback: float = 1000.0
@export_range(-50,50,0.1) var sword_spin_speed: float = 10.0
var guarding: bool = false
var guard_remaining: float = 0.0
var stored_damage: float = 0.0
var heal_accumulator: float = 0.0
var throws_count: int = 0
var last_counter_damage: float = 0.0

func tick(delta: float) -> void:
	if not can_act() or not arena.running:
		return
	if guarding:
		guard_remaining = maxf(0,guard_remaining-delta)
		if guard_remaining <= 0.000001:
			_throw_sword()
		else:
			_set_visual("guard",charge_texture,guard_remaining)
		return
	heal_accumulator += delta
	while heal_accumulator >= 1.0 - 0.000001:
		heal_accumulator = maxf(0,heal_accumulator-1.0)
		arena.heal(fighter,healing_per_second)

func incoming_damage_multiplier(_event: Dictionary) -> float:
	return 1.0 - damage_reduction if guarding else 1.0

func on_damage_settled(event: Dictionary) -> void:
	if not can_act() or fighter.health <= 0 or float(event.get("amount",0)) + float(event.get("absorbed",0)) <= 0:
		return
	if guarding:
		# Count HP actually lost after mitigation and shields; healing never subtracts it.
		stored_damage += float(event.get("amount",0))
		return
	guarding = true
	guard_remaining = guard_duration
	stored_damage = 0
	heal_accumulator = 0
	phase = "guard"
	fighter.casting_skill = self
	_set_visual("guard",charge_texture,guard_remaining)
	arena.emit_effect("guard_start",fighter.position,Color("f3cb73"),{"side":fighter.side})

func _throw_sword() -> void:
	var target = arena.nearest_enemy(fighter)
	last_counter_damage = counter_base_damage + counter_damage_ratio * stored_damage
	var damage: float = last_counter_damage
	# Return to eating immediately; the launched projectile owns its damage snapshot.
	cancel_cast()
	if target == null:
		return
	var direction: Vector2 = fighter.position.direction_to(target.position)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	arena.spawn_projectile(fighter,{"position":fighter.position + direction * 30,"velocity":direction*sword_speed,"damage":damage,"radius":sword_radius,"lifetime":sword_lifetime,"color":Color("eabf68"),"skill_id":skill_id,"visual_type":"laotie","knockback":sword_knockback,"spin_speed":sword_spin_speed})
	throws_count += 1
	arena.emit_effect("slash",fighter.position,Color("ecc777"),{"angle":direction.angle(),"radius":85.0})

func cancel_cast() -> void:
	super.cancel_cast()
	guarding = false
	guard_remaining = 0
	stored_damage = 0
	heal_accumulator = 0

func get_visuals() -> Array:
	if not can_act() or not guarding:
		return []
	return [{"kind":"yunli_guard","position":fighter.position,"remaining":guard_remaining,"duration":guard_duration,"damage":counter_base_damage + counter_damage_ratio * stored_damage,"reduction":damage_reduction}]
