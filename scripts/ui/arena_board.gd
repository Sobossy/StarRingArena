extends Control
## Presentation only: all combat state belongs to BattleArena.
signal death_ejected(fighter_id: int)

var arena
var preview_definitions: Array = []
var preview_config = null
var preview_positions: Array = []
var world_size := Vector2(596,596)
var render_scale: float = 1.0
const TEAM_COLORS := [Color("78e5dc"),Color("dec58d"),Color("bb96ff"),Color("ff92ae"),Color("91dda2"),Color("8abfff"),Color("ffa16a"),Color("d8e3ef")]
var effects: Array = []
var trails: Dictionary = {}
var hit_flashes: Dictionary = {}
var hit_reactions: Dictionary = {}
var dash_ghosts: Dictionary = {}
var punch_popup_index: int = 0
const HIT_REACTION_DURATION := 0.18
const DASH_SAMPLE_INTERVAL := 0.025
const DASH_GHOST_LIFETIME := 0.085
var departures: Dictionary = {}
var world_transform := Transform2D.IDENTITY
var visual_time: float = 0.0
var frozen: bool = false
var display_speed: float = 1.0
var font: Font
var background_texture: Texture2D
var mimi_punch_texture: Texture2D = preload("res://assets/effects/mimi_punch.png")
var ashen_hand_texture: Texture2D = preload("res://assets/effects/ashen_hand.png")
var _trail_timer: float = 0.0
const ChargedPortrait = preload("res://scripts/ui/charged_portrait.gd")
const Plates = preload("res://scripts/ui/board_plates.gd")
const Backdrop = preload("res://scripts/ui/board_backdrop.gd")
var plates = Plates.new()
var backdrop
var base_world_transform := Transform2D.IDENTITY
var plate_clock: float = 0.0
var charged_portraits: Dictionary = {}
var charged_textures: Dictionary = {}
var slash_waves: Array = []
const FIELD := 760.0
const INK := Color("0b1524")
const GOLD := Color("dec58d")
const CYAN := Color("78e5dc")

func _ready() -> void:
	backdrop = Backdrop.new()
	add_child(backdrop)
	var font_variation := FontVariation.new()
	font_variation.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	font_variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	font = font_variation
	if ResourceLoader.exists("res://assets/arena/background.png"):
		background_texture = load("res://assets/arena/background.png")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func reset_visuals() -> void:
	for surface in charged_portraits.values():
		surface.queue_free()
	charged_portraits.clear()
	charged_textures.clear()
	slash_waves.clear()
	plate_clock = 0
	effects.clear()
	trails.clear()
	hit_flashes.clear()
	hit_reactions.clear()
	dash_ghosts.clear()
	punch_popup_index = 0
	departures.clear()
	visual_time = 0.0
	_trail_timer = 0.0
	queue_redraw()

func ingest(items: Array) -> void:
	for event in items:
		if event.get("kind","") == "end":
			trails.clear()
			dash_ghosts.clear()
		if event.get("kind", "") in ["end","revolver_reload"]:
			continue
		if event.get("kind", "") == "death":
			dash_ghosts.erase(int(event.get("side",0)))
			var origin: Vector2 = event.get("position",Vector2.ZERO)
			var direction: Vector2 = event.get("direction",Vector2.ZERO)
			if direction.is_zero_approx():
				var center: Vector2 = arena.bounds.get_center() if arena != null else world_size * 0.5
				direction = center.direction_to(origin)
			if direction.is_zero_approx():
				direction = Vector2.UP
			var side: int = int(event.get("side",0))
			var exit_velocity: Vector2 = event.get("exit_velocity",direction*160)
			departures[side] = {"age":0.0,"origin":origin,"direction":direction.normalized(),"velocity":exit_velocity,"display_shift":plate_offset(origin),"angle":float(event.get("angle",0)),"cheered":false,"done":false,"lost":event.get("exit_kind","") == "lost","texture":event.get("exit_texture")}
			continue
		if event.get("kind", "") == "hit":
			var side: int = int(event.get("side",0))
			hit_flashes[side] = 0.14
			if float(event.get("amount",0)) > 0 or float(event.get("absorbed",0)) > 0:
				hit_reactions[side] = {"age":0.0,"start":hit_scale(side)}
		var e: Dictionary = event.duplicate()
		e["age"] = 0.0
		e["life"] = 0.85 if e.get("kind", "") == "hit" else 0.5
		if e.get("kind","") == "hit" and e.get("skill_id","") == "mimi_punch":
			e["life"] = .36
			e["punch_lane"] = (punch_popup_index%3-1)*11
			punch_popup_index += 1
		if e.get("kind", "") == "impact":
			e["life"] = 0.18
		if e.get("kind", "") == "mimi_punch":
			e["life"] = 0.10
		if e.get("kind", "") == "time_stop_start":
			e["life"] = 0.35
		if e.get("kind", "") == "acheron_slash":
			e["life"] = 0.24
			_start_slash_wave(e)
		if e.get("kind", "") == "death":
			e["life"] = 1.2
		effects.append(e)
	if effects.size() > 180:
		effects = effects.slice(effects.size() - 180)

func _start_slash_wave(event: Dictionary) -> void:
	_prepare_geometry()
	var origin: Vector2 = event.position
	var signs: Dictionary = {}
	var side: int = int(event.get("side",0))
	if arena != null:
		for actor in arena.fighters:
			if actor.side == side:
				# Resolve the actually visible portrait centre after new-wall
				# correction, including its plate offset, bob, lift and art offset.
				var pose: Dictionary = _portrait_pose(actor.position,side,actor.velocity,actor.hit_flash,actor.alive,actor.impact_angle,false,actor.lift_time,actor.airborne_height,actor.facing)
				var body := Transform2D(float(pose.angle),Vector2(float(pose.facing),1)*float(pose.pulse),0,pose.position)
				origin = body*actor.definition.portrait_offset
				signs = actor.cut_wall_sides
				break
	var wave: Dictionary = {"origin":origin,"age":0.0,"expand":float(event.get("expand_time",.5)),"duration":float(event.get("recovery_time",2)),"side":side}
	var viewport_size: Vector2 = get_viewport_rect().size
	if render_scale > 0 and viewport_size.x > 0 and viewport_size.y > 0:
		wave["screen_uv"] = screen_position(origin,signs)/viewport_size
	slash_waves.append(wave)

func _process(delta: float) -> void:
	var step: float = 0.0 if frozen else delta * display_speed
	visual_time += step
	for side in hit_flashes.keys():
		hit_flashes[side] = maxf(0.0, hit_flashes[side] - step)
	for side in hit_reactions.keys():
		hit_reactions[side].age += step
		if float(hit_reactions[side].age) >= HIT_REACTION_DURATION - 0.000001:
			hit_reactions.erase(side)
	_update_dash_ghosts(step)
	for wave in slash_waves:
		if not _actor_stopped(int(wave.side)):
			wave.age += step
	slash_waves = slash_waves.filter(func(wave): return wave.age < wave.duration-.000001)
	_update_acheron_visuals()
	for e in effects:
		e["age"] += step
	for side in departures:
		var departure: Dictionary = departures[side]
		if departure.done:
			continue
		departure.age += step
		if departure.age >= (0.0 if departure.get("lost",false) else 0.5) and not departure.cheered:
			departure.cheered = true
			death_ejected.emit(int(side))
		if departure.get("lost",false):
			var screen_position: Vector2 = get_global_transform_with_canvas()*base_world_transform*(departure_pose(int(side)).position+departure.display_shift)
			var visible_area: Rect2 = get_viewport_rect().grow(200*render_scale)
			if departure.age > 0 and not visible_area.has_point(screen_position):
				departure.done = true
		elif departure.age >= 0.95:
			departure.done = true
	effects = effects.filter(func(e): return e["age"] < e["life"])
	_trail_timer += step
	if arena == null or arena.time_stop_remaining <= 0:
		plate_clock += step
	_prepare_geometry()
	if arena != null and arena.running and _trail_timer >= 0.04:
		_trail_timer = 0.0
		for f in arena.fighters:
			if arena.is_time_stopped(f):
				continue
			if not trails.has(f.side):
				trails[f.side] = []
			trails[f.side].append(f.position)
			if trails[f.side].size() > 15:
				trails[f.side].pop_front()
	queue_redraw()

func hit_scale(side: int) -> float:
	if not hit_reactions.has(side):
		return 1.0
	var reaction: Dictionary = hit_reactions[side]
	var age: float = float(reaction.age)
	if age < 0.04:
		return lerpf(float(reaction.start),0.84,smoothstep(0.0,0.04,age))
	if age < 0.12:
		return lerpf(0.84,1.02,smoothstep(0.04,0.12,age))
	return lerpf(1.02,1.0,smoothstep(0.12,HIT_REACTION_DURATION,age))

func _portrait_pose(position: Vector2,side: int,velocity: Vector2,flash: float,alive: bool,angle: float,departing: bool,lift: float,air_height: float,facing: float) -> Dictionary:
	var clock: float = _actor_clock(side)
	var bob: float = sin(clock * 4.0 + float(side) * PI) * 2.5 if alive else 0.0
	var center := position + Vector2(0,bob - air_height)
	if lift > 0:
		center.y -= sin(clampf(lift/0.28,0,1) * PI) * 15
	var tilt: float = clampf(velocity.x / 1800.0,-0.12,0.12) if alive else 0.0
	if not is_zero_approx(angle) or departing:
		tilt = angle
	return {"position":center,"angle":tilt,"facing":facing,"pulse":1.0 + sin(clock*4.0 + side)*0.015,"flash":flash,"squash":hit_scale(side),"velocity":velocity,"stopped":_actor_stopped(side)}

func _actor_clock(side: int) -> float:
	if arena != null:
		for fighter in arena.fighters:
			if fighter.side == side:
				return fighter.local_time
	return visual_time

func _actor_stopped(side: int) -> bool:
	if arena != null:
		for fighter in arena.fighters:
			if fighter.side == side:
				return arena.is_time_stopped(fighter)
	return false

func _display_statuses(fighter) -> Dictionary:
	var result: Dictionary = fighter.statuses.duplicate()
	var highest: int = 0
	for effect in fighter.aura_slows.values():
		if effect.source.alive:
			highest = maxi(highest,int(effect.stacks))
	if highest > 0:
		result["titan_mark"] = highest
	return result

func _update_dash_ghosts(step: float) -> void:
	var active: Dictionary = {}
	if arena != null:
		for fighter in arena.fighters:
			if not fighter.alive or fighter.visual_phase != "thread_dash":
				continue
			active[fighter.side] = true
			var pose: Dictionary = _portrait_pose(fighter.position,fighter.side,fighter.velocity,hit_flashes.get(fighter.side,0),true,fighter.impact_angle,false,fighter.lift_time,fighter.airborne_height,fighter.facing)
			pose["definition"] = fighter.definition
			pose["texture"] = fighter.visual_texture if fighter.visual_texture != null else fighter.definition.portrait
			var history: Dictionary = dash_ghosts.get(fighter.side,{"clock":0.0,"samples":[],"previous":pose})
			if step > 0 and not arena.is_time_stopped(fighter):
				for sample in history.samples:
					sample.age += step
				history.samples = history.samples.filter(func(sample): return sample.age <= DASH_GHOST_LIFETIME)
				history.clock += step
				if float(history.clock) >= DASH_SAMPLE_INTERVAL:
					history.clock = fmod(float(history.clock),DASH_SAMPLE_INTERVAL)
					if step <= DASH_GHOST_LIFETIME:
						var sample: Dictionary = history.previous.duplicate()
						sample["age"] = step
						history.samples.append(sample)
						if history.samples.size() > 2:
							history.samples.pop_front()
				history.previous = pose
			dash_ghosts[fighter.side] = history
	for side in dash_ghosts.keys():
		if not active.has(side):
			dash_ghosts.erase(side)

func _draw_dash_ghosts() -> void:
	if arena == null:
		return
	for fighter in arena.fighters:
		if not fighter.alive or fighter.visual_phase != "thread_dash" or not dash_ghosts.has(fighter.side):
			continue
		var samples: Array = dash_ghosts[fighter.side].samples
		for i in range(samples.size()):
			var sample: Dictionary = samples[i]
			_object_transform(sample.position)
			_draw_portrait(sample.definition,sample.texture,sample,0.10 if i == samples.size()-1 else 0.05,false)
	draw_set_transform_matrix(world_transform)

func has_departures() -> bool:
	for departure in departures.values():
		if not departure.done:
			return true
	return false

func departure_pose(side: int) -> Dictionary:
	var departure: Dictionary = departures[side]
	if departure.get("lost",false):
		return {"position":departure.origin+departure.velocity*float(departure.age),"angle":0.0}
	var t: float = clampf((departure.age - 0.5) / 0.45,0.0,1.0)
	var travel: float = (world_size.length() + 220.0) * t * t
	return {"position":departure.origin + departure.direction * travel,"angle":departure.angle - TAU * 2.0 * t}

func _update_acheron_visuals() -> void:
	var active: Dictionary = {}
	charged_textures.clear()
	if arena != null:
		for fighter in arena.fighters:
			if not fighter.alive:
				continue
			for skill in fighter.skills:
				if skill.skill_id != "acheron_slash":
					continue
				var ending_wave: bool = not arena.running and slash_waves.any(func(wave): return int(wave.side) == fighter.side)
				if not skill.active and not ending_wave:
					continue
				var portrait: Texture2D = fighter.visual_texture if fighter.visual_texture != null else fighter.definition.portrait
				if portrait != null:
					if not charged_portraits.has(fighter.side):
						var surface = ChargedPortrait.new()
						add_child(surface)
						charged_portraits[fighter.side] = surface
					active[fighter.side] = true
					charged_textures[fighter.side] = charged_portraits[fighter.side].update_portrait(portrait,1.0 if ending_wave else skill.portrait_progress())
	for side in charged_portraits.keys():
		if not active.has(side):
			charged_portraits[side].queue_free()
			charged_portraits.erase(side)

func _prepare_geometry() -> void:
	world_size = Vector2(596,596)
	if arena != null and not arena.fighters.is_empty():
		world_size = arena.initial_bounds.end+Vector2(48,48)
	elif preview_config != null:
		world_size = Vector2(preview_config.width+96,preview_config.height+96)
	render_scale = minf(size.x/world_size.x,size.y/world_size.y)
	base_world_transform = Transform2D(0,Vector2.ONE*render_scale,0,(size-world_size*render_scale)*.5)
	plates.rebuild(world_size,arena)
	if backdrop != null:
		backdrop.configure(world_size,background_texture,font)

func plate_offset(point: Vector2,signs: Dictionary = {}) -> Vector2:
	return plates.point_offset(point,plate_clock,signs)

func _object_transform(point: Vector2,signs: Dictionary = {}) -> void:
	world_transform = base_world_transform*Transform2D(0,plate_offset(point,signs))
	draw_set_transform_matrix(world_transform)

func _base_transform() -> void:
	world_transform = base_world_transform
	draw_set_transform_matrix(world_transform)

func screen_position(point: Vector2,signs: Dictionary = {}) -> Vector2:
	return get_global_transform_with_canvas()*base_world_transform*(point+plate_offset(point,signs))

func _board_line(first: Vector2,last: Vector2,color: Color,width: float = 1,antialias: bool = true) -> void:
	for part in plates.line_parts(first,last,plate_clock):
		draw_set_transform_matrix(base_world_transform*Transform2D(0,part.shift))
		draw_line(part.from,part.to,color,width,antialias)
	draw_set_transform_matrix(world_transform)

func _box(rect: Rect2, color: Color, radius: int, border: Color = Color.TRANSPARENT, width: int = 1) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(width)
	draw_style_box(s, rect)

func _text(text: String, at: Vector2, size_px: int, color: Color, centered: bool = false) -> void:
	if font == null:
		return
	var p := at
	if centered:
		p.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x * 0.5
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func _draw() -> void:
	_prepare_geometry()
	_base_transform()
	_draw_board_fragments()
	_draw_shrinking_arena()
	_draw_cut_walls()
	if arena != null and not arena.fighters.is_empty():
		for f in arena.fighters:
			_draw_trail(f)
		_draw_projectiles()
		for visual in arena.get_visuals():
			if visual.get("kind","") != "revolver":
				_object_transform(visual.get("position",Vector2.ZERO))
				_draw_skill_visual(visual)
		_draw_dash_ghosts()
		for f in arena.fighters:
			if f.alive:
				_object_transform(f.position,f.cut_wall_sides)
				_draw_fighter(f.definition, f.position, f.side, f.health_ratio(), f.shield, hit_flashes.get(f.side, 0.0), true, f.velocity, _display_statuses(f), f.visual_texture, TEAM_COLORS[f.team_id % TEAM_COLORS.size()], f.visual_phase, f.lift_time, f.impact_angle, false, f.facing, f.airborne_height)
				if f.airborne_remaining > 0:
					_text("腾空 %.1fs" % f.airborne_remaining,f.position+Vector2(0,85),11,Color("f5c6df"),true)
			elif departures.has(f.side) and not departures[f.side].done:
				var pose: Dictionary = departure_pose(f.side)
				if departures[f.side].get("lost",false):
					world_transform = base_world_transform*Transform2D(0,departures[f.side].display_shift)
					draw_set_transform_matrix(world_transform)
				else:
					_object_transform(pose.position)
				_draw_fighter(f.definition, pose.position, f.side, 0.0, 0.0, 0.0, false, Vector2.ZERO, {}, departures[f.side].get("texture"), TEAM_COLORS[f.team_id % TEAM_COLORS.size()], "normal", 0.0, pose.angle, true)
		for visual in arena.get_visuals():
			if visual.get("kind","") == "revolver":
				_object_transform(visual.position)
				_draw_skill_visual(visual)
		for f in arena.fighters:
			if f.alive:
				_object_transform(f.position,f.cut_wall_sides)
				_draw_titan_marks(f)
		for visual in arena.get_visuals():
			if visual.get("kind","") == "memory_mimi":
				_object_transform(visual.summon)
				_draw_mimi_sprite(visual)
	else:
		var positions: Array = []
		if preview_config != null:
			positions = preview_positions
		for i in range(preview_definitions.size()):
			_base_transform()
			var p: Vector2 = world_size * 0.5
			if i < positions.size():
				p = positions[i]
			elif preview_definitions.size() > 1:
				p += Vector2.from_angle(TAU * i / preview_definitions.size()) * 150
			var team_id: int = int(preview_config.participants[i].team) if preview_config != null and preview_config.mode == "teams" else i
			_draw_fighter(preview_definitions[i],p,i,1.0,0.0,0.0,true,Vector2.ZERO,{},null,TEAM_COLORS[team_id % 8])
			for slot in preview_definitions[i].skill_slots:
				if slot.get("template_id","") == "sparkle_revolver":
					_draw_revolver({"position":p,"angle":0.0,"facing":1.0,"loaded":-1,"chamber":0,"reload":true,"progress":0.0})
		if preview_definitions.size() > 1:
			_text("配置完成后，开始自动对战",Vector2(world_size.x * 0.5,world_size.y - 100),16,Color("677f96"),true)
	for e in effects:
		_object_transform(e.get("position",Vector2.ZERO))
		_draw_effect(e)
	draw_set_transform(Vector2.ZERO)

func _draw_board_fragments() -> void:
	if backdrop == null:
		return
	var texture: Texture2D = backdrop.get_texture()
	for cell in plates.cells:
		var polygon := PackedVector2Array()
		var uvs := PackedVector2Array()
		var shift: Vector2 = plates.offset(cell,plate_clock)
		for point in cell.polygon:
			polygon.append(point+shift)
			uvs.append(((point-world_size*.5)/plates.scale+world_size*.5)/world_size)
		draw_polygon(polygon,PackedColorArray([Color.WHITE]),uvs,texture)

func _draw_shrinking_arena() -> void:
	if arena == null or arena.fighters.is_empty():
		return
	var has_hands: bool = arena.fighters.any(func(f): return f.alive and f.skills.any(func(skill): return skill.skill_id == "castorice_aura"))
	if has_hands or arena.shrink_scale < 1:
		var current: Rect2 = plates.outer.grow(-18*plates.scale)
		if has_hands:
			var points: Array = [current.position,Vector2(current.end.x,current.position.y),current.end,Vector2(current.position.x,current.end.y)]
			for i in range(4):
				_object_transform(points[i])
				draw_set_transform_matrix(world_transform * Transform2D((-PI/2)+i*PI/2,points[i]))
				draw_texture_rect(ashen_hand_texture,Rect2(-Vector2.ONE*42*plates.scale,Vector2.ONE*84*plates.scale),false)
		_base_transform()
		_text("灰黯之手 · 场地 %d%%" % roundi(arena.shrink_scale*100),Vector2(current.get_center().x,current.position.y-12),12,Color("cfb3ed"),true)
	if arena.time_stop_remaining > 0:
		_base_transform()
		draw_rect(Rect2(Vector2.ZERO,world_size),Color(0.07,0.07,0.11,0.33))
		_text("时停 %.1fs" % arena.time_stop_remaining,Vector2(world_size.x*.5,120),21,Color("fff2d3"),true)

func _draw_cut_walls() -> void:
	if arena == null:
		return
	for cell in plates.cells:
		var polygon: PackedVector2Array = cell.polygon
		var shift: Vector2 = plates.offset(cell,plate_clock)
		for i in range(polygon.size()):
			var first: Vector2 = polygon[i]
			var last: Vector2 = polygon[(i+1)%polygon.size()]
			for wall in arena.cut_walls:
				if absf(absf((first-wall.origin).dot(wall.normal))-wall.half_width) < .02 and absf(absf((last-wall.origin).dot(wall.normal))-wall.half_width) < .02:
					draw_line(first+shift,last+shift,Color("6d1837"),5*plates.scale,true)
					draw_line(first+shift,last+shift,Color("ff4977"),2*plates.scale,true)
					draw_line(first+shift,last+shift,Color("ffe4e9"),.7*plates.scale,true)
					break

func titan_mark_poses(fighter) -> Array:
	var result: Array = []
	var sources: Array = fighter.aura_slows.keys()
	sources.sort()
	var row: int = 0
	for source_id in sources:
		var effect: Dictionary = fighter.aura_slows[source_id]
		if not effect.source.alive or int(effect.get("stacks",0)) <= 0:
			continue
		var count: int = int(effect.stacks)
		var radius: float = fighter.definition.portrait_size*.48 + 13 + row*20
		var center: Vector2 = fighter.position + fighter.definition.portrait_offset + Vector2(0,-fighter.airborne_height)
		for i in range(count):
			var angle: float = -PI*.5 if count == 1 else lerpf(-PI*.90,-PI*.10,float(i)/maxf(1,count-1))
			result.append({"position":center+Vector2.from_angle(angle)*radius,"angle":angle+PI*.25,"size":34.0,"frozen":arena.is_time_stopped(effect.source) if arena != null else false})
		row += 1
	return result

func _draw_titan_marks(fighter) -> void:
	for pose in titan_mark_poses(fighter):
		draw_set_transform_matrix(world_transform*Transform2D(float(pose.angle),pose.position))
		var extent := Vector2.ONE*float(pose.get("size",34))
		draw_texture_rect(ashen_hand_texture,Rect2(-extent*.5,extent),false,Color(1,1,1,.65 if pose.frozen else 1.0))
	draw_set_transform_matrix(world_transform)

func _draw_mimi_sprite(v: Dictionary) -> void:
	var texture: Texture2D = v.texture
	var extent: Vector2 = texture.get_size()/float(maxi(texture.get_width(),texture.get_height()))*float(v.get("size",64))
	var summon: Vector2 = v.summon + Vector2(0,sin(float(v.clock)*4)*2)
	draw_set_transform_matrix(world_transform*Transform2D(0,Vector2(float(v.facing),1),0,summon))
	draw_texture_rect(texture,Rect2(-extent*.5,extent),false,Color(.63,.65,.73) if v.get("frozen",false) else Color.WHITE)
	draw_set_transform_matrix(world_transform)

func _draw_trail(f) -> void:
	if not f.alive or not trails.has(f.side):
		return
	var positions: Array = trails[f.side]
	for i in range(1, positions.size()):
		var alpha: float = float(i) / float(positions.size()) * 0.18
		var color: Color = f.definition.theme_color
		color.a = alpha
		_board_line(positions[i - 1], positions[i], color, 3.0, true)

func _draw_fighter(definition, position: Vector2, side: int, hp: float, shield: float, flash: float, alive: bool, velocity: Vector2, statuses: Dictionary, state_texture: Texture2D = null, team_color: Color = CYAN, phase: String = "normal", lift: float = 0.0, impact_angle: float = 0.0, departing: bool = false, facing: float = 1.0, air_height: float = 0.0) -> void:
	var alpha: float = 1.0 if alive or departing else 0.35
	var pose: Dictionary = _portrait_pose(position,side,velocity,flash,alive,impact_angle,departing,lift,air_height,facing)
	var pos: Vector2 = pose.position
	draw_circle(position + Vector2(0, 28), 34, Color(0.0, 0.025, 0.05, 0.3 * alpha))
	if shield > 0:
		draw_circle(pos, 51, Color(0.35, 0.75, 1, 0.1))
		draw_arc(pos, 51, 0, TAU, 64, Color(0.55, 0.85, 1, 0.65), 2.0, true)
	var portrait: Texture2D = state_texture if state_texture != null else definition.portrait
	if alive and charged_textures.has(side):
		portrait = charged_textures[side]
	_draw_portrait(definition,portrait,pose,alpha,alive and phase == "thread_dash")
	draw_set_transform_matrix(world_transform)
	var bar := Rect2(position + Vector2(-46, 51), Vector2(92, 7))
	_box(Rect2(bar.position - Vector2(2, 2), bar.size + Vector2(4, 4)), Color("060c17"), 3)
	_box(bar, Color("223046"), 2)
	if hp > 0:
		_box(Rect2(bar.position, Vector2(92 * clampf(hp, 0, 1), 7)), Color(team_color,alpha), 2)
	if shield > 0:
		_box(Rect2(bar.position + Vector2(0, 10), Vector2(92 * minf(shield / definition.max_health, 1), 3)), Color("88bdff"), 1)
	_text(str(int(ceil(hp * definition.max_health))), position + Vector2(46, 47), 12, Color("d6e8ee"))
	var tags := "蓄力 " if phase == "charge" else ""
	if phase == "guard":
		tags = "防反 "
	if phase == "thread_dash":
		tags = "不可阻挡 "
	if phase == "dayun_charge":
		tags = "大运蓄力 "
	if phase == "dayun_rush":
		tags = "大运冲撞 "
	if phase == "time_stop":
		tags = "时停 "
	if phase == "acheron_charge":
		tags = "蓄力 "
	if phase == "acheron_locked":
		tags = "斩击预警 "
	if statuses.has("titan_mark"):
		tags += "泰坦%d层 " % int(statuses.titan_mark)
	if phase == "charge" and definition.skill_slots.any(func(slot): return slot.get("template_id","") == "sparkle_revolver"):
		tags = "上膛 "
	if statuses.has("burn"):
		tags += "灼烧 "
	if statuses.has("slow"):
		tags += "减速 "
	if not tags.is_empty():
		_text(tags.strip_edges(), position + Vector2(0, 84), 11, Color("eebd7c"), true)

func _draw_portrait(definition,portrait: Texture2D,pose: Dictionary,alpha: float,soften: bool) -> void:
	var body := world_transform * Transform2D(float(pose.angle),Vector2(float(pose.facing),1)*float(pose.pulse),0,pose.position)
	if portrait == null:
		draw_set_transform_matrix(body * Transform2D(0,Vector2(1,float(pose.squash)),0,Vector2.ZERO))
		_draw_placeholder(Vector2.ZERO,definition.theme_color,definition,alpha,float(pose.flash),pose.velocity)
		return
	# Keep the authored image offset stable; squash around the image's own center.
	var image_transform: Transform2D = body * Transform2D(0,Vector2(1,float(pose.squash)),0,definition.portrait_offset)
	var image_size: Vector2 = portrait.get_size()
	var extent: Vector2 = image_size / maxf(image_size.x,image_size.y) * definition.portrait_size
	var rect := Rect2(-extent*0.5,extent)
	var white: float = 1 + minf(float(pose.flash)*5,1)
	var tint := Color(white,white,white,alpha)
	if bool(pose.get("stopped",false)):
		tint = Color(.63*white,.65*white,.73*white,alpha)
	if soften:
		# Offsets are in canvas pixels, independent of character size and tilt.
		for offset in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var sample_transform: Transform2D = image_transform
			sample_transform.origin += offset * 1.2
			draw_set_transform_matrix(sample_transform)
			draw_texture_rect(portrait,rect,false,Color(tint,tint.a*0.08))
	draw_set_transform_matrix(image_transform)
	draw_texture_rect(portrait,rect,false,Color(tint,tint.a*(0.86 if soften else 1.0)))

func _draw_placeholder(pos: Vector2, tint: Color, definition, alpha: float, flash: float, velocity: Vector2) -> void:
	var face_color: Color = tint.lightened(0.22)
	if flash > 0:
		face_color = face_color.lerp(Color.WHITE, minf(flash * 5, 0.9))
	draw_circle(pos, 33, Color("081725"))
	draw_circle(pos, 29, Color(face_color, alpha))
	draw_circle(pos + Vector2(-9, -2), 3, Color("15273b"))
	draw_circle(pos + Vector2(9, -2), 3, Color("15273b"))
	draw_arc(pos + Vector2(0, 2), 9, 0.3, PI - 0.3, 16, Color("29415a"), 2, true)
	var top := PackedVector2Array([pos + Vector2(-27, -13), pos + Vector2(-19, -32), pos + Vector2(-8, -24), pos + Vector2(1, -38), pos + Vector2(12, -26), pos + Vector2(24, -32), pos + Vector2(29, -12)])
	draw_colored_polygon(top, Color(tint.darkened(0.4), alpha))
	_box(Rect2(pos + Vector2(-20, 16), Vector2(40, 17)), Color("14283d"), 5, Color(tint, 0.75), 1)
	_text("占位", pos + Vector2(0, 29), 10, Color(tint, alpha), true)
	if velocity.length() > 300:
		draw_line(pos - velocity.normalized() * 35, pos - velocity.normalized() * 80, Color(tint, 0.55), 5, true)

func _draw_projectiles() -> void:
	for p in arena.projectiles:
		var position: Vector2 = p.get("position", Vector2.ZERO)
		_object_transform(position)
		position.y -= float(p.get("visual_height",0))
		var velocity: Vector2 = p.get("velocity", Vector2.RIGHT)
		var radius: float = p.get("radius", 8.0)
		var color: Color = p.get("color", Color("ffac6d"))
		if p.get("visual_type","") == "laotie":
			var direction: Vector2 = velocity.normalized()
			_board_line(position-direction*75,position,Color(0.52,0.68,0.51,0.25),16,true)
			var clock: float = float(p.get("visual_clock",visual_time))
			draw_arc(position,55,clock*8,clock*8+PI,24,Color(0.86,0.76,0.43,0.3),5,true)
			_draw_laotie(position,velocity.angle() + clock*float(p.get("spin_speed",10)))
			continue
		if p.get("visual_type","") == "red_bullet":
			var direction: Vector2 = velocity.normalized()
			_board_line(position-direction*22,position+direction*8,Color("9e193b"),9,true)
			_board_line(position-direction*14,position+direction*7,Color("ff4260"),6,true)
			_board_line(position-direction*6,position+direction*5,Color("ffd0be"),2,true)
			continue
		_board_line(position - velocity.normalized() * 28, position, Color(color, 0.3), radius, true)
		draw_circle(position, radius * 1.9, Color(color, 0.08))
		draw_circle(position, radius, color)
		draw_circle(position, radius * 0.45, Color("fff3d2"))

func _draw_skill_visual(v: Dictionary) -> void:
	var p: Vector2 = v.get("position", Vector2.ZERO)
	var color: Color = v.get("color", CYAN)
	if v.get("kind", "") == "acheron":
		var line: Array = v.line
		if line.size() == 2:
			line = plates.full_line(line[0],line[0].direction_to(line[1]))
		if line.size() == 2 and v.state in ["charge","locked"]:
			var locked: bool = v.state == "locked"
			var pulse: float = .75+.25*sin(float(v.clock)*18) if locked else 1.0
			_board_line(line[0],line[1],Color(1,.12,.32,(.25 if locked else .06)*pulse),8 if locked else 4,true)
			_board_line(line[0],line[1],Color(1,.32,.48,(.95 if locked else .45)*pulse),2 if locked else 1.2,true)
			if locked:
				_text("斩击 %.1fs" % float(v.remaining),p+Vector2(0,103),12,Color("ff92ae"),true)
	elif v.get("kind", "") == "memory_mimi":
		for i in range(18):
			var angle: float = TAU*i/18.0
			draw_arc(p,float(v.range),angle,angle+TAU/30,5,Color("f2b9d0"),1.5,true)
		_box(Rect2(p+Vector2(-46,65),Vector2(92,4)),Color("293b4c"),2)
		var amount: float = float(v.remaining)/maxf(.05,float(v.duration)) if v.stopped else float(v.charge)/100.0
		_box(Rect2(p+Vector2(-46,65),Vector2(92*clampf(amount,0,1),4)),Color("f8c5d9"),2)
		_text("%.1fs" % float(v.remaining) if v.stopped else "%d%%" % roundi(v.charge),p+Vector2(53,70),12,Color("ffe4ee"))
	elif v.get("kind", "") == "castorice_aura":
		var aura_color: Color = Color("8c57d6").lerp(Color("ed4265"),clampf(float(v.stacks)/maxf(1,float(v.maximum)),0,1))
		if v.get("frozen",false):
			aura_color = Color("8b899b")
		draw_circle(p,float(v.radius),Color(aura_color,.035))
		for i in range(28):
			var angle: float = TAU*i/28.0+float(v.clock)*.08
			draw_arc(p,float(v.radius),angle,angle+TAU/45,6,Color(aura_color,.8),2.4,true)
		if v.warning:
			_text("!",p+Vector2(34,-58),35,aura_color.lightened(.3),true)
	elif v.get("kind", "") == "toast":
		var bob: float = sin(float(v.get("clock",visual_time))*3 + p.x) * 2
		var rect := Rect2(p+Vector2(-18,-15+bob),Vector2(36,32))
		_box(rect.grow(2),Color("bc7e3e"),7)
		_box(rect,Color("f0b868"),6)
		_box(Rect2(p+Vector2(-14,-11+bob),Vector2(28,24)),Color("ffedc4"),5)
		draw_circle(p+Vector2(-9,-12+bob),9,Color("f3bf76"))
		draw_circle(p+Vector2(8,-12+bob),9,Color("f3bf76"))
		draw_circle(p+Vector2(-8,-11+bob),6,Color("ffedc4"))
		draw_circle(p+Vector2(7,-11+bob),6,Color("ffedc4"))
		for offset in [Vector2(-6,0),Vector2(7,5),Vector2(-4,9)]:
			draw_circle(p+offset+Vector2(0,bob),1.5,Color("dfac67"))
	elif v.get("kind", "") == "dayun":
		if v.state == "charge":
			var direction: Vector2 = v.direction
			draw_line(p+direction*55,p+direction*100,Color(1,0.69,0.83,0.65),3,true)
			draw_line(p+direction*100,p+direction*86+direction.orthogonal()*7,Color("ffd0e3"),3,true)
			draw_line(p+direction*100,p+direction*86-direction.orthogonal()*7,Color("ffd0e3"),3,true)
			_text("大运 %.1f / %.1fs" % [maxf(0,v.duration-v.remaining),v.duration],p+Vector2(0,105),11,Color("ffd0e3"),true)
		elif v.seeking:
			_text("寻找吐司",p+Vector2(0,86),11,Color("ffe1b4"),true)
	elif v.get("kind", "") == "golden_threads":
		var points: Array = v.points
		for i in range(1,points.size()):
			_board_line(points[i-1],points[i],Color(1,0.77,0.2,0.14),9,true)
			_board_line(points[i-1],points[i],Color("ffdb57"),2.3,true)
		for point in points:
			_object_transform(point)
			draw_circle(point,3,Color("fff1af"))
		_object_transform(p)
		var trail: Array = v.trail
		for i in range(1,trail.size()):
			_board_line(trail[i-1],trail[i],Color(1,0.88,0.48,float(i)/trail.size()*0.6),12,true)
		_text("金线 %d/%d · 移速 %.0f" % [v.count,v.required,v.speed],p+Vector2(0,104),11,Color("f9db8a"),true)
	elif v.get("kind", "") == "yunli_guard":
		draw_arc(p,52,-PI*.85,-PI*.15,36,Color(0.94,0.78,0.38,0.7),3,true)
		var progress: float = clampf(float(v.remaining)/maxf(float(v.duration),0.001),0,1)
		draw_line(p+Vector2(-41,93),p+Vector2(41,93),Color("493f2f"),3,true)
		draw_line(p+Vector2(-41,93),p+Vector2(-41+82*progress,93),Color("ecc777"),3,true)
		_text("%.1fs · 老铁 %.0f" % [v.remaining,v.damage],p+Vector2(0,110),11,Color("f3db9a"),true)
	elif v.get("kind", "") == "revolver":
		_draw_revolver(v)
	elif v.get("kind", "") == "sword":
		var direction := Vector2.from_angle(float(v.get("angle", 0.0)))
		var normal := direction.orthogonal()
		draw_line(p - direction * 34, p - direction * 13, Color(color, 0.25), 5, true)
		draw_colored_polygon(PackedVector2Array([p + direction * 25, p + direction * 3 + normal * 5, p - direction * 10, p + direction * 3 - normal * 5]), color)
		draw_line(p - direction * 6 + normal * 9, p - direction * 6 - normal * 9, color.lightened(0.4), 3, true)
		draw_line(p - direction * 7, p - direction * 17, color.darkened(0.3), 3, true)
	elif v.get("kind", "") == "ring":
		draw_arc(p, v.get("radius", 50.0), 0, TAU, 64, color, 2, true)
	elif v.get("kind", "") == "charge_meter":
		var progress: float = v.get("progress",0.0)
		draw_arc(p,49,-PI*0.5,TAU-PI*0.5,64,Color(color,0.13),3,true)
		if progress > 0:
			draw_arc(p,49,-PI*0.5,-PI*0.5 + TAU*progress,64,color,3,true)
		_text("%.1f / %.1f" % [v.get("elapsed",0),v.get("duration",6)],p+Vector2(0,104),12,Color("efd18a"),true)
	elif v.get("kind", "") == "bat":
		var points: Array = v.get("trail",[])
		for i in range(1,points.size()):
			var alpha: float = float(i) / maxf(points.size(),1) * 0.48
			_board_line(points[i-1],points[i],Color(0.38,0.43,0.48,alpha),4,true)
		draw_set_transform_matrix(world_transform * Transform2D(float(v.get("angle",0)),p))
		var silhouette := PackedVector2Array([Vector2(-49,-6),Vector2(-44,-10),Vector2(-15,-9),Vector2(27,-3),Vector2(39,-3),Vector2(42,-1),Vector2(42,2),Vector2(39,4),Vector2(27,3),Vector2(-15,9),Vector2(-44,10),Vector2(-49,6)])
		draw_colored_polygon(silhouette,Color("313842"))
		var outline := silhouette.duplicate()
		outline.append(silhouette[0])
		draw_polyline(outline,Color("9a9f9d"),1.3,true)
		draw_line(Vector2(-43,-6),Vector2(-14,-6),Color("656e76"),2,true)
		for band in [16.0,21.0,26.0,32.0]:
			draw_line(Vector2(band,-3),Vector2(band,3),Color("d7b875"),2,true)
		draw_circle(Vector2(40,0),3,Color("d9bd7d"))
		draw_set_transform_matrix(world_transform)

func _draw_laotie(position: Vector2, angle: float) -> void:
	draw_set_transform_matrix(world_transform * Transform2D(angle,position))
	# A broad jade-grey blade, gold guard and a red/gold pommel, following the reference.
	draw_colored_polygon(PackedVector2Array([Vector2(-73,-8),Vector2(-61,-15),Vector2(-50,-10),Vector2(-47,8),Vector2(-60,15),Vector2(-74,9)]),Color("e49b25"))
	draw_colored_polygon(PackedVector2Array([Vector2(-69,-5),Vector2(-61,-10),Vector2(-54,-6),Vector2(-52,6),Vector2(-61,10),Vector2(-70,5)]),Color("a92d24"))
	draw_line(Vector2(-52,0),Vector2(-17,0),Color("af783d"),12,true)
	draw_line(Vector2(-50,-2),Vector2(-20,-2),Color("f4c95b"),3,true)
	draw_line(Vector2(-21,-26),Vector2(-21,26),Color("dcad48"),7,true)
	var blade := PackedVector2Array([Vector2(-17,-14),Vector2(12,-15),Vector2(52,-27),Vector2(43,-9),Vector2(67,0),Vector2(43,9),Vector2(52,27),Vector2(12,15),Vector2(-17,14)])
	draw_colored_polygon(blade,Color("51695d"))
	var outline := blade.duplicate()
	outline.append(blade[0])
	draw_polyline(outline,Color("ddbd77"),2.5,true)
	draw_colored_polygon(PackedVector2Array([Vector2(-15,-7),Vector2(40,-13),Vector2(26,0),Vector2(40,13),Vector2(-15,7)]),Color("8da18e"))
	draw_line(Vector2(-12,0),Vector2(59,0),Color("293d36"),3,true)
	for x in [0,15,30]:
		draw_line(Vector2(x,-9),Vector2(x+8,0),Color("c7c49b"),2,true)
		draw_line(Vector2(x,9),Vector2(x+8,0),Color("c7c49b"),2,true)
	draw_set_transform_matrix(world_transform)

func _draw_revolver(v: Dictionary) -> void:
	var p: Vector2 = v.position
	var facing: float = v.get("facing",1.0)
	var angle: float = v.get("angle",0.0)
	var cylinder: Vector2 = p + Vector2(-40*facing,16)
	draw_circle(cylinder,26,Color("ead4d3"))
	draw_circle(cylinder,24,Color("97142e"))
	var loaded: int = v.get("loaded",-1)
	var current: int = v.get("chamber",0)
	for i in range(6):
		var point: Vector2 = cylinder + Vector2.from_angle(-PI/2 + TAU*i/6.0 + float(v.get("cylinder_angle",0.0))) * 15
		draw_circle(point,6,Color("390b18"))
		if i == loaded:
			draw_circle(point,4.8,Color("f2d16b"))
			draw_circle(point,2.5,Color("fff2a6"))
		if not v.get("reload",true) and i == current:
			draw_arc(point,7.4,0,TAU,20,Color("fff3df"),1.2,true)
	draw_circle(cylinder,4,Color("671326"))
	if v.get("reload",false):
		draw_arc(cylinder,28,-PI/2,-PI/2 + TAU*maxf(.01,float(v.get("progress",0))),40,Color("efb98a"),2,true)
	var hand: Vector2 = p + Vector2(29*facing,8)
	draw_set_transform_matrix(world_transform * Transform2D(angle,Vector2(1,facing),0,hand))
	var grip := PackedVector2Array([Vector2(-9,3),Vector2(-5,25),Vector2(7,25),Vector2(10,5)])
	draw_colored_polygon(grip,Color("761b30"))
	draw_polyline(PackedVector2Array([Vector2(-9,3),Vector2(-5,25),Vector2(7,25),Vector2(10,5)]),Color("fff0e8"),2,true)
	var frame := PackedVector2Array([Vector2(-15,-8),Vector2(12,-9),Vector2(17,-5),Vector2(38,-5),Vector2(40,4),Vector2(15,5),Vector2(10,11),Vector2(-12,10)])
	draw_colored_polygon(frame,Color("fff0e7"))
	draw_colored_polygon(PackedVector2Array([Vector2(-12,-6),Vector2(10,-7),Vector2(12,7),Vector2(-11,8)]),Color("b91c3d"))
	draw_line(Vector2(17,-2),Vector2(36,-2),Color("a61231"),4,true)
	draw_line(Vector2(26,-6),Vector2(29,3),Color("ae1834"),3,true)
	draw_line(Vector2(34,-6),Vector2(37,3),Color("ae1834"),3,true)
	draw_circle(Vector2(-2,0),5,Color("561027"))
	draw_arc(Vector2(6,11),7,0,PI,16,Color("fff1df"),2,true)
	if float(v.get("flag",0)) > 0:
		draw_line(Vector2(40,0),Vector2(49,-24),Color("f5e9df"),2,true)
		var wave: float = sin(float(v.get("clock",visual_time))*25)*2
		draw_colored_polygon(PackedVector2Array([Vector2(49,-24),Vector2(70,-22+wave),Vector2(67,-11+wave),Vector2(53,-14)]),Color("fffaf1"))
	if float(v.get("flash",0)) > 0:
		draw_colored_polygon(PackedVector2Array([Vector2(39,0),Vector2(49,-9),Vector2(47,-3),Vector2(61,0),Vector2(47,4),Vector2(50,10)]),Color("ffce6e"))
	draw_set_transform_matrix(world_transform)

func _draw_effect(e: Dictionary) -> void:
	var age: float = e.get("age", 0.0)
	var t: float = age / e.get("life", 0.5)
	var position: Vector2 = e.get("position", Vector2(380, 380))
	var color: Color = e.get("color", CYAN)
	color.a *= 1.0 - t
	var kind: String = e.get("kind", "")
	if kind == "acheron_slash":
		var first: Vector2 = e.get("from",position)
		var last: Vector2 = e.get("to",position)
		var line: Array = plates.full_line(first,first.direction_to(last))
		if line.size() == 2:
			_board_line(line[0],line[1],Color(1,.07,.27,(1-t)*.30),48*(1-t)+12,true)
			_board_line(line[0],line[1],Color("ff315f"),10*(1-t)+2,true)
			_board_line(line[0],line[1],Color(1,.94,.96,1-t),4*(1-t)+1,true)
	elif kind == "mimi_punch":
		var angle: float = float(e.get("angle",0))
		var center: Vector2 = position + Vector2.from_angle(angle)*t*12
		draw_set_transform_matrix(world_transform*Transform2D(angle,center))
		draw_texture_rect(mimi_punch_texture,Rect2(Vector2(-29,-29),Vector2(58,58)),false,Color(1,1,1,1-t*.7))
		draw_set_transform_matrix(world_transform)
	elif kind == "time_stop_start":
		draw_circle(position,80+t*maxf(world_size.x,world_size.y),Color(1,.96,.82,(1-t)*.18))
	elif kind == "heal":
		_text("+%d" % int(round(float(e.get("amount",0)))),position+Vector2(0,-42-age*48),19,Color(0.64,0.94,0.48,1-t),true)
		draw_arc(position,35+t*20,0,TAU,32,Color(0.64,0.94,0.48,(1-t)*.4),2,true)
	elif kind == "guard_start":
		draw_arc(position,36+t*32,0,TAU,48,Color(0.98,0.81,0.45,1-t),3*(1-t)+1,true)
	elif kind == "dry_fire":
		var angle: float = e.get("angle",0.0)
		var colors := [Color("ff6eac"),Color("f2d579"),Color("91e5f0"),Color("f7ebf2")]
		for i in range(8):
			var direction := Vector2.from_angle(angle + (i-3.5)*0.22)
			var at: Vector2 = position + direction*(8+age*110) + Vector2(0,age*age*80)
			draw_line(at,at+direction.rotated(1.0)*6,Color(colors[i%4],1-t),2.5,true)
	elif kind == "revolver_shot":
		if age < 0.12:
			var direction := Vector2.from_angle(float(e.get("angle",0)))
			draw_line(position,position+direction*24,Color("ffe3a0"),4,true)
	elif kind == "hit":
		var label := str(int(round(float(e.get("amount", 0)))))
		if e.get("damage_type","") == "true":
			label = "真伤" + label
		var p := position + Vector2(sin(float(e.get("amount", 0))) * 21, -37 - 50 * t)
		p.x += float(e.get("punch_lane",0))
		var text_size: int = 19 if e.has("punch_lane") else 23
		_text(label, p + Vector2(1, 2), text_size, Color(0.02, 0.06, 0.1, 1.0 - t), true)
		_text(label, p, text_size, Color(GOLD.lightened(0.2), 1.0 - t), true)
	elif kind == "slash" or kind == "dash" or kind == "smash" or kind == "impact":
		if e.get("execution",false):
			_text("终结",position+Vector2(0,-58-age*30),26,Color("ff88a2"),true)
		var angle: float = e.get("angle", -PI * 0.25)
		draw_arc(position, 28 + t * 45, angle, angle + PI * 1.4, 32, color, (1.0 - t) * 6 + 1, true)
		if kind == "smash" or kind == "impact":
			var normal := Vector2.from_angle(angle)
			for i in range(5):
				var d := normal.rotated((i-2)*0.25)
				draw_line(position+d*(12+t*50),position+d*(38+t*70),color,3*(1-t)+1,true)
	elif kind == "shield" or kind == "heal":
		draw_arc(position, 36 + t * 30, 0, TAU, 40, color, 2, true)
	else:
		var reach: float = float(e.get("radius", 54)) if kind != "death" else 100
		draw_arc(position, 6 + t * reach, 0, TAU, 40, color, 2.0, true)
		for i in range(8):
			var d := Vector2.from_angle(float(i) * TAU / 8.0 + float(e.get("side", 0)))
			draw_line(position + d * t * reach, position + d * (t * reach + 7 * (1.0 - t)), color, 2.0, true)
