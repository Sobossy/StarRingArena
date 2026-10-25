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
var departures: Dictionary = {}
var world_transform := Transform2D.IDENTITY
var visual_time: float = 0.0
var frozen: bool = false
var display_speed: float = 1.0
var font: Font
var background_texture: Texture2D
var _trail_timer: float = 0.0
const FIELD := 760.0
const INK := Color("0b1524")
const GOLD := Color("dec58d")
const CYAN := Color("78e5dc")

func _ready() -> void:
	var font_variation := FontVariation.new()
	font_variation.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	font_variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	font = font_variation
	if ResourceLoader.exists("res://assets/arena/background.png"):
		background_texture = load("res://assets/arena/background.png")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func reset_visuals() -> void:
	effects.clear()
	trails.clear()
	hit_flashes.clear()
	departures.clear()
	visual_time = 0.0
	_trail_timer = 0.0
	queue_redraw()

func ingest(items: Array) -> void:
	for event in items:
		if event.get("kind", "") in ["end","revolver_reload"]:
			continue
		if event.get("kind", "") == "death":
			var origin: Vector2 = event.get("position",Vector2.ZERO)
			var direction: Vector2 = event.get("direction",Vector2.ZERO)
			if direction.is_zero_approx():
				var center: Vector2 = arena.bounds.get_center() if arena != null else world_size * 0.5
				direction = center.direction_to(origin)
			if direction.is_zero_approx():
				direction = Vector2.UP
			departures[int(event.get("side",0))] = {"age":0.0,"origin":origin,"direction":direction.normalized(),"angle":float(event.get("angle",0)),"cheered":false,"done":false}
			continue
		if event.get("kind", "") == "hit":
			hit_flashes[int(event.get("side", 0))] = 0.14
		var e: Dictionary = event.duplicate()
		e["age"] = 0.0
		e["life"] = 0.85 if e.get("kind", "") == "hit" else 0.5
		if e.get("kind", "") == "impact":
			e["life"] = 0.18
		if e.get("kind", "") == "death":
			e["life"] = 1.2
		effects.append(e)
	if effects.size() > 180:
		effects = effects.slice(effects.size() - 180)

func _process(delta: float) -> void:
	var step: float = 0.0 if frozen else delta * display_speed
	visual_time += step
	for side in hit_flashes.keys():
		hit_flashes[side] = maxf(0.0, hit_flashes[side] - step)
	for e in effects:
		e["age"] += step
	for side in departures:
		var departure: Dictionary = departures[side]
		if departure.done:
			continue
		departure.age += step
		if departure.age >= 0.5 and not departure.cheered:
			departure.cheered = true
			death_ejected.emit(int(side))
		if departure.age >= 0.95:
			departure.done = true
	effects = effects.filter(func(e): return e["age"] < e["life"])
	_trail_timer += step
	if arena != null and arena.running and _trail_timer >= 0.04:
		_trail_timer = 0.0
		for f in arena.fighters:
			if not trails.has(f.side):
				trails[f.side] = []
			trails[f.side].append(f.position)
			if trails[f.side].size() > 15:
				trails[f.side].pop_front()
	queue_redraw()

func has_departures() -> bool:
	for departure in departures.values():
		if not departure.done:
			return true
	return false

func departure_pose(side: int) -> Dictionary:
	var departure: Dictionary = departures[side]
	var t: float = clampf((departure.age - 0.5) / 0.45,0.0,1.0)
	var travel: float = (world_size.length() + 220.0) * t * t
	return {"position":departure.origin + departure.direction * travel,"angle":departure.angle - TAU * 2.0 * t}

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
	world_size = Vector2(596,596)
	if arena != null and not arena.fighters.is_empty():
		world_size = arena.bounds.end + Vector2(48,48)
	elif preview_config != null:
		world_size = Vector2(preview_config.width + 96,preview_config.height + 96)
	var scale_factor: float = minf(size.x / world_size.x,size.y / world_size.y)
	render_scale = scale_factor
	var offset: Vector2 = (size - world_size * scale_factor) * 0.5
	world_transform = Transform2D(0.0, Vector2.ONE * scale_factor, 0.0, offset)
	draw_set_transform_matrix(world_transform)
	_draw_field()
	if arena != null and not arena.fighters.is_empty():
		for f in arena.fighters:
			_draw_trail(f)
		_draw_projectiles()
		for visual in arena.get_visuals():
			if visual.get("kind","") != "revolver":
				_draw_skill_visual(visual)
		for f in arena.fighters:
			if f.alive:
				_draw_fighter(f.definition, f.position, f.side, f.health_ratio(), f.shield, hit_flashes.get(f.side, 0.0), true, f.velocity, f.statuses, f.visual_texture, TEAM_COLORS[f.team_id % TEAM_COLORS.size()], f.visual_phase, f.lift_time, f.impact_angle, false, f.facing)
			elif departures.has(f.side) and not departures[f.side].done:
				var pose: Dictionary = departure_pose(f.side)
				_draw_fighter(f.definition, pose.position, f.side, 0.0, 0.0, 0.0, false, Vector2.ZERO, {}, null, TEAM_COLORS[f.team_id % TEAM_COLORS.size()], "normal", 0.0, pose.angle, true)
		for visual in arena.get_visuals():
			if visual.get("kind","") == "revolver":
				_draw_skill_visual(visual)
	else:
		var positions: Array = []
		if preview_config != null:
			positions = preview_positions
		for i in range(preview_definitions.size()):
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
		_draw_effect(e)
	draw_set_transform(Vector2.ZERO)

func _draw_field() -> void:
	var w: float = world_size.x
	var h: float = world_size.y
	_box(Rect2(5,12,w-10,h-16),Color("040a13"),64)
	_box(Rect2(7,7,w-14,h-14),Color("162a42"),60,Color("34546e"),2)
	_box(Rect2(20,20,w-40,h-40),Color("263f5a"),50,Color("436783"),1)
	_box(Rect2(32,32,w-64,h-64),Color("102337"),40,Color("081321"),3)
	_box(Rect2(47,47,w-94,h-94),Color("122b40"),30,Color("416579"),1)
	if background_texture != null:
		draw_texture_rect(background_texture,Rect2(55,55,w-110,h-110),false)
	else:
		var grid_step: int = maxi(42,int(maxf(w,h) / 26.0))
		for x in range(90,int(w)-70,grid_step):
			for y in range(90,int(h)-70,grid_step):
				draw_circle(Vector2(x,y),1,Color(0.38,0.63,0.70,0.13))
		var center: Vector2 = world_size * 0.5
		draw_line(Vector2(center.x,48),Vector2(center.x,h-48),Color(0.45,0.75,0.82,0.14),1,true)
		var radius: float = minf(w,h) * 0.145
		draw_circle(center,radius,Color(0.3,0.6,0.7,0.05))
		draw_arc(center,radius,0,TAU,96,Color(0.4,0.7,0.8,0.16),1,true)
		draw_arc(center,radius+15,0,TAU,96,Color(0.4,0.7,0.8,0.05),1,true)
		var star := PackedVector2Array()
		for i in range(8):
			star.append(center + Vector2.from_angle(-PI*0.5+float(i)*PI*0.25) * (26 if i%2==0 else 12))
		draw_colored_polygon(star,Color("29485f"))
	for x in [19.0,w-26]:
		_box(Rect2(x,h*0.5-86,7,172),Color("0b1827"),3)
		_box(Rect2(x+1,h*0.5-59,5,118),Color(CYAN,0.65),2)
	for y in [19.0,h-26]:
		_box(Rect2(w*0.5-86,y,172,7),Color("0b1827"),3)
		_box(Rect2(w*0.5-45,y+1,90,5),Color(GOLD,0.75),2)
	_text("STAR RING",Vector2(w*0.5,90),11,Color("4d748c"),true)

func _draw_trail(f) -> void:
	if not f.alive or not trails.has(f.side):
		return
	var positions: Array = trails[f.side]
	for i in range(1, positions.size()):
		var alpha: float = float(i) / float(positions.size()) * 0.18
		var color: Color = f.definition.theme_color
		color.a = alpha
		draw_line(positions[i - 1], positions[i], color, 3.0, true)

func _draw_fighter(definition, position: Vector2, side: int, hp: float, shield: float, flash: float, alive: bool, velocity: Vector2, statuses: Dictionary, state_texture: Texture2D = null, team_color: Color = CYAN, phase: String = "normal", lift: float = 0.0, impact_angle: float = 0.0, departing: bool = false, facing: float = 1.0) -> void:
	var tint: Color = definition.theme_color
	var alpha: float = 1.0 if alive or departing else 0.35
	var bob: float = sin(visual_time * 4.0 + float(side) * PI) * 2.5 if alive else 0.0
	var pos := position + Vector2(0, bob)
	if lift > 0:
		pos.y -= sin(clampf(lift/0.28,0,1) * PI) * 15
	draw_circle(position + Vector2(0, 28), 34, Color(0.0, 0.025, 0.05, 0.3 * alpha))
	if shield > 0:
		draw_circle(pos, 51, Color(0.35, 0.75, 1, 0.1))
		draw_arc(pos, 51, 0, TAU, 64, Color(0.55, 0.85, 1, 0.65), 2.0, true)
	var tilt: float = clampf(velocity.x / 1800.0, -0.12, 0.12) if alive else 0.0
	if not is_zero_approx(impact_angle) or departing:
		tilt = impact_angle
	var pulse: float = 1.0 + sin(visual_time * 4.0 + side) * 0.015 + flash * 0.35
	draw_set_transform_matrix(world_transform * Transform2D(tilt, Vector2(facing,1.0) * pulse, 0.0, pos))
	var portrait: Texture2D = state_texture if state_texture != null else definition.portrait
	if portrait != null:
		var image_size: Vector2 = portrait.get_size()
		var extent: Vector2 = image_size / maxf(image_size.x, image_size.y) * definition.portrait_size
		var color := Color(1 + minf(flash * 5, 1), 1 + minf(flash * 5, 1), 1 + minf(flash * 5, 1), alpha)
		draw_texture_rect(portrait, Rect2(-extent * 0.5 + definition.portrait_offset, extent), false, color)
	else:
		_draw_placeholder(Vector2.ZERO, tint, definition, alpha, flash, velocity)
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
	if phase == "charge" and definition.skill_slots.any(func(slot): return slot.get("template_id","") == "sparkle_revolver"):
		tags = "上膛 "
	if statuses.has("burn"):
		tags += "灼烧 "
	if statuses.has("slow"):
		tags += "减速 "
	if not tags.is_empty():
		_text(tags.strip_edges(), position + Vector2(0, 84), 11, Color("eebd7c"), true)

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
		var velocity: Vector2 = p.get("velocity", Vector2.RIGHT)
		var radius: float = p.get("radius", 8.0)
		var color: Color = p.get("color", Color("ffac6d"))
		if p.get("visual_type","") == "red_bullet":
			var direction: Vector2 = velocity.normalized()
			draw_line(position-direction*22,position+direction*8,Color("9e193b"),9,true)
			draw_line(position-direction*14,position+direction*7,Color("ff4260"),6,true)
			draw_line(position-direction*6,position+direction*5,Color("ffd0be"),2,true)
			continue
		draw_line(position - velocity.normalized() * 28, position, Color(color, 0.3), radius, true)
		draw_circle(position, radius * 1.9, Color(color, 0.08))
		draw_circle(position, radius, color)
		draw_circle(position, radius * 0.45, Color("fff3d2"))

func _draw_skill_visual(v: Dictionary) -> void:
	var p: Vector2 = v.get("position", Vector2.ZERO)
	var color: Color = v.get("color", CYAN)
	if v.get("kind", "") == "revolver":
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
			draw_line(points[i-1],points[i],Color(0.38,0.43,0.48,alpha),4,true)
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
		var wave: float = sin(visual_time*25)*2
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
	if kind == "dry_fire":
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
		var p := position + Vector2(sin(float(e.get("amount", 0))) * 21, -37 - 50 * t)
		_text(label, p + Vector2(1, 2), 23, Color(0.02, 0.06, 0.1, 1.0 - t), true)
		_text(label, p, 23, Color(GOLD.lightened(0.2), 1.0 - t), true)
	elif kind == "slash" or kind == "dash" or kind == "smash" or kind == "impact":
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
