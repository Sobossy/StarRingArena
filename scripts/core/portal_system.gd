extends RefCounted
## Shared gates and opt-in curved rockets. Correction-only motion never enters here.
const NORMALS = [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]
const PAIRS = [[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]]
var arena
var walls: Array[int] = []
var remaining: float = 0.0
var owner_id: int = -1
var providers: Array = []
var pending: Array = []

func _init(battle) -> void:
	arena = battle

func clear() -> void:
	walls.clear()
	remaining = 0
	owner_id = -1
	providers.clear()
	pending.clear()

func enabled() -> bool:
	return walls.size() == 2 and not providers.is_empty()

func update(delta: float) -> void:
	providers.clear()
	for actor in arena.fighters:
		if actor.alive:
			for skill in actor.skills:
				if skill.skill_id == "tribbie_portals" and (skill.active or not arena.running):
					providers.append(skill)
					break
	if providers.is_empty():
		if not walls.is_empty():
			arena.record_event({"kind":"portal_closed","source":owner_id})
		clear()
		return
	owner_id = providers[0].fighter.fighter_id
	if not arena.running:
		return
	if walls.is_empty():
		_choose_walls()
	if arena.time_stop_remaining > 0:
		return
	remaining -= delta
	while remaining <= 0.000001:
		var overshoot: float = -remaining
		_choose_walls()
		remaining -= overshoot

func _choose_walls() -> void:
	walls.assign(PAIRS[arena.rng.randi_range(0,5)])
	remaining = maxf(.1,providers[0].portal_interval)
	arena.record_event({"kind":"portal_walls","source":owner_id,"walls":walls.duplicate(),"duration":remaining})

func boundary(from: Vector2, displacement: Vector2, radius: float) -> Dictionary:
	var inner: Rect2 = arena.bounds.grow(-radius)
	var times: Array = []
	if displacement.x < -.000001:
		times.append([(inner.position.x-from.x)/displacement.x,0])
	elif displacement.x > .000001:
		times.append([(inner.end.x-from.x)/displacement.x,1])
	if displacement.y < -.000001:
		times.append([(inner.position.y-from.y)/displacement.y,2])
	elif displacement.y > .000001:
		times.append([(inner.end.y-from.y)/displacement.y,3])
	var fraction: float = 2.0
	var touched: Array[int] = []
	for pair in times:
		var t: float = float(pair[0])
		if t < -.000001 or t > 1.000001:
			continue
		if t < fraction-.000001:
			fraction = maxf(0,t)
			touched.assign([int(pair[1])])
		elif absf(t-fraction) <= .000001:
			touched.append(int(pair[1]))
	return {"fraction":minf(1,fraction),"walls":touched}

func gate_mapping(point: Vector2, sides: Array, velocity: Vector2, radius: float) -> Dictionary:
	# Pick one entrance at a shared corner; ordered wall IDs resolve exact ties.
	var entry: int = -1
	var approach: float = -INF
	for side in range(4):
		if sides.has(side) and walls.has(side):
			var speed: float = -velocity.dot(NORMALS[side])
			if speed > approach+.000001:
				entry = side
				approach = speed
	var exit_wall: int = walls[1] if walls[0] == entry else walls[0]
	var angle: float = (-NORMALS[entry]).angle_to(NORMALS[exit_wall])
	var inner: Rect2 = arena.bounds.grow(-radius)
	var entry_tangent: Vector2 = Vector2.DOWN if entry < 2 else Vector2.RIGHT
	var exit_tangent: Vector2 = Vector2.DOWN if exit_wall < 2 else Vector2.RIGHT
	var entry_length: float = inner.size.y if entry < 2 else inner.size.x
	var exit_length: float = inner.size.y if exit_wall < 2 else inner.size.x
	var u: float = clampf((point-inner.position).dot(entry_tangent)/maxf(.000001,entry_length),0,1)
	if entry_tangent.rotated(angle).dot(exit_tangent) < 0:
		u = 1-u
	var along: float = u*exit_length
	if sides.size() > 1:
		var margin: float = minf(radius,exit_length*.25)
		along = clampf(along,margin,exit_length-margin)
	var destination: Vector2
	if exit_wall < 2:
		destination = Vector2(inner.position.x if exit_wall == 0 else inner.end.x,inner.position.y+along)
	else:
		destination = Vector2(inner.position.x+along,inner.position.y if exit_wall == 2 else inner.end.y)
	return {"position":destination,"angle":angle,"entry_wall":entry,"exit_wall":exit_wall}

func _trigger(kind: String, id: int, source: int = -1) -> void:
	if arena.running and arena.time_stop_remaining <= 0:
		pending.append({"type":kind,"id":id,"source":source})

func _teleport_actor(actor, sides: Array, post: bool) -> float:
	var from: Vector2 = actor.position
	var mapping: Dictionary = gate_mapping(from,sides,actor.velocity,actor.definition.radius)
	var angle: float = float(mapping.angle)
	actor.position = mapping.position
	for key in ["velocity","knockback","dash_velocity","collision_rebound_direction","post_result_heading","last_hit_direction"]:
		actor.set(key,actor.get(key).rotated(angle))
	if actor.movement_id in ["bounce","wander"]:
		actor.movement.direction = actor.movement.direction.rotated(angle)
	if absf(actor.velocity.x) > .01:
		actor.facing = signf(actor.velocity.x)
	actor.teleport_serial += 1
	actor.cut_wall_sides.clear()
	for wall in arena.cut_walls:
		actor.cut_wall_sides[wall.id] = 1.0 if (actor.position-wall.origin).dot(wall.normal) >= 0 else -1.0
	if not arena.cut_walls.is_empty():
		arena._project_from_cut_walls(actor)
	for observer in arena.fighters:
		for skill in observer.skills:
			skill.on_fighter_portal_rotated(actor,angle)
			skill.on_fighter_teleported(actor,from,actor.position)
	if not post:
		arena.emit_effect("portal_teleport",from,Color("ffe789"),{"side":actor.side,"exit":actor.position})
		arena.record_event({"kind":"portal_fighter","source":owner_id,"target":actor.side,"entry":from,"exit":actor.position,"walls":sides.duplicate(),"entry_wall":mapping.entry_wall,"exit_wall":mapping.exit_wall,"rotation_deg":rad_to_deg(angle),"fire_suppressed":arena.time_stop_remaining > 0})
		_trigger("fighter",actor.fighter_id,actor.side)
	return angle

func move_actor(actor, displacement: Vector2, stop_on_wall: bool = false, post: bool = false) -> Dictionary:
	var segments: Array = []
	var rest: Vector2 = displacement
	for iteration in range(64):
		if rest.length_squared() < .00000001:
			break
		var start: Vector2 = actor.position
		var outer: Dictionary = boundary(start,rest,actor.definition.radius)
		var cut: Dictionary = arena.clip_motion_to_cut_walls(actor,start,start+rest)
		var is_cut: bool = not cut.normal.is_zero_approx() and (outer.walls.is_empty() or float(cut.fraction) <= float(outer.fraction)+.000001)
		var fraction: float = float(cut.fraction) if is_cut else float(outer.fraction)
		actor.position = start+rest*fraction
		segments.append({"from":start,"to":actor.position})
		var solid: Vector2 = cut.normal if is_cut else Vector2.ZERO
		var open_sides: Array[int] = []
		if not is_cut:
			for side in outer.walls:
				if enabled() and walls.has(side):
					open_sides.append(side)
				else:
					solid += NORMALS[side]
		if stop_on_wall and not solid.is_zero_approx():
			return {"segments":segments,"normal":solid,"cut":is_cut}
		rest *= 1.0-fraction
		if not solid.is_zero_approx():
			if is_cut:
				arena._notify_cut_contact(actor,solid)
				rest = rest.bounce(solid)
			else:
				arena._notify_outer_contact(actor,solid)
				if solid.x != 0:
					rest.x *= -1
				if solid.y != 0:
					rest.y *= -1
			if not actor.alive or actor.movement_override != null:
				break
		if not open_sides.is_empty():
			rest = rest.rotated(_teleport_actor(actor,open_sides,post))
		if not is_cut and outer.walls.is_empty():
			break
	return {"segments":segments,"normal":Vector2.ZERO,"cut":false}

func flush_launches() -> void:
	var triggers: Array = pending
	pending = []
	if not arena.running or arena.time_stop_remaining > 0:
		return
	var dropped: int = 0
	for trigger in triggers:
		for skill in providers:
			if not skill.active or not skill.fighter.alive:
				continue
			var target = arena.nearest_enemy(skill.fighter)
			if target == null:
				continue
			if arena.projectiles.size() >= arena.MAX_PROJECTILES:
				dropped += 1
				continue
			var direction: Vector2 = skill.fighter.position.direction_to(target.position)
			if direction.is_zero_approx():
				direction = Vector2.RIGHT
			var turn: float = deg_to_rad(skill.rocket_turn_rate)*(1 if arena.rng.randi_range(0,1) else -1)
			arena.spawn_projectile(skill.fighter,{"position":skill.fighter.position,"velocity":direction*skill.rocket_speed,"damage":skill.rocket_damage,"radius":skill.rocket_radius,"blast_radius":skill.explosion_radius,"lifetime":skill.rocket_lifetime,"color":Color("ffcd7b"),"skill_id":"tribbie_portals","visual_type":"tribbie_rocket","portal_eligible":true,"angular_velocity":turn,"explode_on_wall":true,"explode_on_expiry":true,"rainbow_length":skill.rainbow_length,"sprite_size":skill.rocket_size,"trail":[]})
			arena.record_event({"kind":"portal_launch","source":skill.fighter.side,"target":target.side,"trigger_type":trigger.type,"trigger_id":trigger.id,"trigger_source":trigger.source})
	if dropped > 0:
		arena.record_event({"kind":"portal_limit","count":dropped})

func _trail(projectile: Dictionary, point: Vector2) -> void:
	var trail: Array = projectile.get("trail",[])
	if trail.is_empty() or trail.back().distance_to(point) >= 2:
		trail.append(point)
	var limit: float = float(projectile.get("rainbow_length",180))
	var length: float = 0
	for i in range(trail.size()-2,-1,-1):
		var segment: float = trail[i].distance_to(trail[i+1])
		if length+segment > limit:
			trail[i] = trail[i+1].move_toward(trail[i],maxf(0,limit-length))
			trail = trail.slice(i)
			break
		length += segment
	if trail.size() > 96:
		# Keep the configured distance even for slow rockets with dense samples.
		var reduced: Array = [trail[0]]
		for i in range(2,trail.size()-1,2):
			reduced.append(trail[i])
		reduced.append(trail.back())
		trail = reduced
	projectile.trail = trail

func advance_rocket(p: Dictionary, delta: float) -> bool:
	var inner: Rect2 = arena.bounds.grow(-float(p.radius))
	p.position = p.position.clamp(inner.position,inner.end)
	var turn: float = float(p.get("angular_velocity",0))
	var steps: int = maxi(1,ceili(absf(turn*delta)/deg_to_rad(.5)))
	for substep in range(steps):
		var rest: float = delta/steps
		for crossing in range(64):
			if rest <= .00000001:
				break
			var start: Vector2 = p.position
			_trail(p,start)
			var half_angle: float = turn*rest*.5
			var offset: Vector2 = p.velocity.rotated(half_angle)*rest*(sin(half_angle)/half_angle if absf(half_angle) > .000001 else 1.0)
			var edge: Dictionary = boundary(start,offset,float(p.radius))
			var hit = null
			var hit_t: float = 2
			for enemy in arena.get_collision_targets(p.source):
				var t: float = arena._segment_circle_contact(start,start+offset,enemy.position,float(p.radius)+enemy.definition.radius)
				if t >= 0 and t < hit_t:
					hit_t = t
					hit = enemy
			var fraction: float = minf(float(edge.fraction),hit_t)
			p.position = start+offset*fraction
			p.velocity = p.velocity.rotated(turn*rest*fraction)
			_trail(p,p.position)
			if hit != null and hit_t <= float(edge.fraction)+.000001:
				_explode(p,"hit",hit)
				return false
			if edge.walls.is_empty():
				break
			var solid: bool = not bool(p.get("portal_eligible",false)) or not enabled() or edge.walls.any(func(side): return not walls.has(side))
			if solid:
				if bool(p.get("explode_on_wall",true)):
					_explode(p,"wall")
				return false
			var entry: Vector2 = p.position
			arena.emit_effect("rainbow_afterimage",entry,Color.WHITE,{"points":p.trail.duplicate()})
			var mapping: Dictionary = gate_mapping(entry,edge.walls,p.velocity,float(p.radius))
			p.position = mapping.position
			p.velocity = p.velocity.rotated(float(mapping.angle))
			p.previous_position = p.position
			p.trail = [p.position]
			arena.record_event({"kind":"portal_projectile","source":p.source.side,"projectile_id":p.id,"entry":entry,"exit":p.position,"walls":edge.walls.duplicate(),"entry_wall":mapping.entry_wall,"exit_wall":mapping.exit_wall,"rotation_deg":rad_to_deg(float(mapping.angle))})
			_trigger("rocket",int(p.id),p.source.side)
			rest *= 1.0-fraction
	if float(p.lifetime) <= .000001:
		if bool(p.get("explode_on_expiry",true)):
			_explode(p,"expired")
		return false
	return true

func _explode(p: Dictionary, reason: String, direct = null) -> void:
	var targets: Array = []
	for enemy in arena.get_collision_targets(p.source):
		if enemy == direct or enemy.position.distance_to(p.position) <= float(p.get("blast_radius",0))+enemy.definition.radius:
			targets.append(enemy.fighter_id)
			arena.apply_damage(p.source,enemy,float(p.damage),p.skill_id)
	arena.record_event({"kind":"rocket_explosion","source":p.source.side,"projectile_id":p.id,"position":p.position,"reason":reason,"damage":p.damage,"radius":p.get("blast_radius",0),"targets":targets})
	arena.record_event({"kind":"projectile_end","source":p.source.side,"projectile_id":p.id,"reason":reason})
	arena.emit_effect("burst",p.position,p.color,{"radius":p.get("blast_radius",24)})
