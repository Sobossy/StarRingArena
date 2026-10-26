extends "res://scripts/skills/skill_base.gd"
@export_range(30,800,1) var aura_radius: float = 180.0
@export_range(0,100000,1) var aura_damage: float = 25.0
@export_range(0.05,10,0.05) var aura_tick_interval: float = 1.0
@export_range(1,30,1) var maximum_marks: int = 9
@export_range(0,90,1) var slow_base_percent: float = 6.0
@export_range(0,10,0.1) var slow_per_mark_percent: float = 1.0
@export_range(0,1000000,1) var execution_damage: float = 100000.0
@export_range(0,100,1) var retreat_distance: float = 18.0
@export_range(0.05,10,0.05) var shrink_interval: float = 0.5
@export_range(0.001,0.1,0.001) var shrink_fraction: float = 0.01
@export_range(0.25,1,0.01) var minimum_arena_scale: float = 0.5
var marks: Dictionary = {}

func _refresh_members() -> void:
	var members: Dictionary = {}
	for target in arena.get_collision_targets(fighter):
		if fighter.position.distance_to(target.position) <= aura_radius + target.definition.radius:
			members[target.fighter_id] = target
			if not marks.has(target.fighter_id):
				marks[target.fighter_id] = {"target":target,"stacks":0,"timer":0.0,"executed":false}
	for id in marks.keys():
		var entry: Dictionary = marks[id]
		if not members.has(id):
			_record_marks(entry.target,0)
			entry.target.aura_slows.erase(fighter.fighter_id)
			marks.erase(id)
		elif int(entry.stacks) > 0:
			entry.target.aura_slows[fighter.fighter_id] = {"source":fighter,"power":minf(.95,(slow_base_percent+entry.stacks*slow_per_mark_percent)/100),"stacks":entry.stacks}

func before_step(_delta: float) -> void:
	if can_act():
		_refresh_members()

func cleanup_spatial_effects() -> void:
	for id in marks.keys():
		var target = marks[id].target
		if not target.alive or target.airborne_remaining > 0 or fighter.position.distance_to(target.position) > aura_radius + target.definition.radius:
			_record_marks(target,0)
			target.aura_slows.erase(fighter.fighter_id)
			marks.erase(id)

func tick(delta: float) -> void:
	if not can_act() or not arena.running:
		return
	_refresh_members()
	for entry in marks.values():
		entry.timer += delta
		while entry.timer >= aura_tick_interval - 0.000001:
			entry.timer = maxf(0,entry.timer-aura_tick_interval)
			entry.stacks = mini(maximum_marks,int(entry.stacks)+1)
			_record_marks(entry.target,int(entry.stacks))
			arena.apply_damage(fighter,entry.target,aura_damage,skill_id)
			entry.target.aura_slows[fighter.fighter_id] = {"source":fighter,"power":minf(.95,(slow_base_percent+entry.stacks*slow_per_mark_percent)/100),"stacks":entry.stacks}
		_try_execute(entry.target)

func _try_execute(target) -> void:
	if not marks.has(target.fighter_id):
		return
	var entry: Dictionary = marks[target.fighter_id]
	if entry.stacks >= maximum_marks and not entry.executed and fighter.position.distance_to(target.position) <= fighter.definition.radius+target.definition.radius+0.15:
		entry.executed = true
		arena.apply_damage(fighter,target,execution_damage,"titan_execution")
		arena.emit_effect("smash",target.position,Color("ec4d72"),{"radius":95.0,"angle":fighter.position.direction_to(target.position).angle(),"execution":true})

func on_enemy_contact(enemy) -> void:
	_try_execute(enemy)

func desired_velocity_override():
	var target = null
	var distance: float = INF
	for entry in marks.values():
		var current: float = fighter.position.distance_squared_to(entry.target.position)
		if entry.target.alive and current < distance:
			distance = current
			target = entry.target
	return fighter.position.direction_to(target.position)*fighter.movement_speed() if target != null else null

func on_damage_settled(event: Dictionary) -> void:
	if not can_act() or fighter.health <= 0 or float(event.amount)+float(event.get("absorbed",0)) <= 0 or retreat_distance <= 0:
		return
	var source = event.get("source")
	var direction: Vector2 = source.position.direction_to(fighter.position) if source != null else fighter.last_hit_direction
	if direction.is_zero_approx():
		direction = Vector2.RIGHT if fighter.fighter_id%2 == 0 else Vector2.LEFT
	arena._apply_impact(fighter,fighter.knockback+direction*(retreat_distance*8.0+60.0))

func cancel_cast() -> void:
	for entry in marks.values():
		_record_marks(entry.target,0)
		entry.target.aura_slows.erase(fighter.fighter_id)
	marks.clear()
	super.cancel_cast()

func _record_marks(target,count: int) -> void:
	arena.record_event({"kind":"mark","source":fighter.side,"target":target.side,"id":"titan","stacks":count,"slow":minf(.95,(slow_base_percent+count*slow_per_mark_percent)/100) if count > 0 else 0.0})

func seed_preview() -> void:
	arena.fighters[1].position = fighter.position + Vector2(130,0)

func get_visuals() -> Array:
	if not can_act():
		return []
	var highest: int = 0
	for entry in marks.values():
		highest = maxi(highest,int(entry.stacks))
	return [{"kind":"castorice_aura","position":fighter.position,"radius":aura_radius,"stacks":highest,"maximum":maximum_marks,"warning":not marks.is_empty()}]
