extends Control
## Presentation only: all combat state belongs to BattleArena.

var arena
var preview_definitions: Array = []
var effects: Array = []
var trails: Dictionary = {}
var hit_flashes: Dictionary = {}
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
	visual_time = 0.0
	_trail_timer = 0.0

func ingest(items: Array) -> void:
	for event in items:
		if event.get("kind", "") == "end":
			continue
		if event.get("kind", "") == "hit":
			hit_flashes[int(event.get("side", 0))] = 0.14
		var e: Dictionary = event.duplicate()
		e["age"] = 0.0
		e["life"] = 0.85 if e.get("kind", "") == "hit" else 0.5
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
	var scale_factor: float = minf(size.x, size.y) / FIELD
	var offset: Vector2 = (size - Vector2.ONE * FIELD * scale_factor) * 0.5
	world_transform = Transform2D(0.0, Vector2.ONE * scale_factor, 0.0, offset)
	draw_set_transform_matrix(world_transform)
	_draw_field()
	if arena != null and not arena.fighters.is_empty():
		for f in arena.fighters:
			_draw_trail(f)
		_draw_projectiles()
		for visual in arena.get_visuals():
			_draw_skill_visual(visual)
		for f in arena.fighters:
			_draw_fighter(f.definition, f.position, f.side, f.health_ratio(), f.shield, hit_flashes.get(f.side, 0.0), f.alive, f.velocity, f.statuses)
	else:
		for i in range(mini(2, preview_definitions.size())):
			var p := Vector2(252 + i * 256, 380)
			_draw_fighter(preview_definitions[i], p, i, 1.0, 0.0, 0.0, true, Vector2.ZERO, {})
		_text("选择对手，开启一场新的交锋", Vector2(380, 552), 18, Color("677f96"), true)
		_text("自动战斗  /  自由搭配  /  无限可能", Vector2(380, 582), 12, Color("4a657f"), true)
	for e in effects:
		_draw_effect(e)
	draw_set_transform(Vector2.ZERO)

func _draw_field() -> void:
	_box(Rect2(5, 12, 750, 744), Color("040a13"), 74)
	_box(Rect2(7, 7, 746, 746), Color("162a42"), 68, Color("34546e"), 2)
	_box(Rect2(20, 20, 720, 720), Color("263f5a"), 58, Color("436783"), 1)
	_box(Rect2(32, 32, 696, 696), Color("102337"), 48, Color("081321"), 3)
	_box(Rect2(47, 47, 666, 666), Color("122b40"), 36, Color("416579"), 1)
	if background_texture != null:
		draw_texture_rect(background_texture, Rect2(55, 55, 650, 650), false)
	else:
		for x in range(92, 680, 42):
			for y in range(92, 680, 42):
				draw_circle(Vector2(x, y), 1.0, Color(0.38, 0.63, 0.70, 0.13))
		draw_line(Vector2(380, 48), Vector2(380, 712), Color(0.45, 0.75, 0.82, 0.14), 1.0, true)
		draw_circle(Vector2(380, 380), 110, Color(0.3, 0.6, 0.7, 0.05))
		draw_arc(Vector2(380, 380), 110, 0, TAU, 96, Color(0.4, 0.7, 0.8, 0.16), 1.0, true)
		draw_arc(Vector2(380, 380), 125, 0, TAU, 96, Color(0.4, 0.7, 0.8, 0.05), 1.0, true)
		for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
			var direction := Vector2.from_angle(angle)
			draw_line(Vector2(380, 380) + direction * 98, Vector2(380, 380) + direction * 121, Color("31536b"), 2.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(380, 354), Vector2(389, 371), Vector2(406, 380), Vector2(389, 389), Vector2(380, 406), Vector2(371, 389), Vector2(354, 380), Vector2(371, 371)]), Color("29485f"))
	for x in [19.0, 734.0]:
		_box(Rect2(x, 294, 7, 172), Color("0b1827"), 3)
		_box(Rect2(x + 1, 321, 5, 118), CYAN * Color(1, 1, 1, 0.65), 2)
	for y in [19.0, 734.0]:
		_box(Rect2(294, y, 172, 7), Color("0b1827"), 3)
		_box(Rect2(335, y + 1, 90, 5), GOLD * Color(1, 1, 1, 0.75), 2)
	_text("STAR RING", Vector2(380, 90), 11, Color("4d748c"), true)
	_text("01  /  训练竞技场", Vector2(380, 683), 11, Color("4d748c"), true)

func _draw_trail(f) -> void:
	if not trails.has(f.side):
		return
	var positions: Array = trails[f.side]
	for i in range(1, positions.size()):
		var alpha: float = float(i) / float(positions.size()) * 0.18
		var color: Color = f.definition.theme_color
		color.a = alpha
		draw_line(positions[i - 1], positions[i], color, 3.0, true)

func _draw_fighter(definition, position: Vector2, side: int, hp: float, shield: float, flash: float, alive: bool, velocity: Vector2, statuses: Dictionary) -> void:
	var tint: Color = definition.theme_color
	var alpha: float = 1.0 if alive else 0.35
	var bob: float = sin(visual_time * 4.0 + float(side) * PI) * 2.5 if alive else 0.0
	var pos := position + Vector2(0, bob)
	draw_circle(position + Vector2(0, 28), 34, Color(0.0, 0.025, 0.05, 0.3 * alpha))
	draw_arc(position, 40, 0, TAU, 48, Color(tint, 0.22 * alpha), 1.5, true)
	draw_arc(position, 45, visual_time * 0.5 + side * PI, visual_time * 0.5 + side * PI + PI * 0.65, 24, Color(tint, 0.6 * alpha), 2.0, true)
	if shield > 0:
		draw_circle(pos, 51, Color(0.35, 0.75, 1, 0.1))
		draw_arc(pos, 51, 0, TAU, 64, Color(0.55, 0.85, 1, 0.65), 2.0, true)
	var tilt: float = clampf(velocity.x / 1800.0, -0.12, 0.12) if alive else 0.0
	var pulse: float = 1.0 + sin(visual_time * 4.0 + side) * 0.015 + flash * 0.35
	draw_set_transform_matrix(world_transform * Transform2D(tilt, Vector2.ONE * pulse, 0.0, pos))
	if definition.portrait != null:
		var image_size: Vector2 = definition.portrait.get_size()
		var extent: Vector2 = image_size / maxf(image_size.x, image_size.y) * definition.portrait_size
		var color := Color(1 + minf(flash * 5, 1), 1 + minf(flash * 5, 1), 1 + minf(flash * 5, 1), alpha)
		draw_texture_rect(definition.portrait, Rect2(-extent * 0.5 + definition.portrait_offset, extent), false, color)
	else:
		_draw_placeholder(Vector2.ZERO, tint, definition, alpha, flash, velocity)
	draw_set_transform_matrix(world_transform)
	var bar := Rect2(position + Vector2(-46, 51), Vector2(92, 7))
	_box(Rect2(bar.position - Vector2(2, 2), bar.size + Vector2(4, 4)), Color("060c17"), 3)
	_box(bar, Color("223046"), 2)
	if hp > 0:
		_box(Rect2(bar.position, Vector2(92 * clampf(hp, 0, 1), 7)), Color(CYAN if side == 0 else GOLD, alpha), 2)
	if shield > 0:
		_box(Rect2(bar.position + Vector2(0, 10), Vector2(92 * minf(shield / definition.max_health, 1), 3)), Color("88bdff"), 1)
	_text(str(int(ceil(hp * definition.max_health))), position + Vector2(46, 47), 12, Color("d6e8ee"))
	_text(definition.display_name, position + Vector2(0, -54), 14, Color("e2edf2"), true)
	var tags := ""
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
		draw_line(position - velocity.normalized() * 28, position, Color(color, 0.3), radius, true)
		draw_circle(position, radius * 1.9, Color(color, 0.08))
		draw_circle(position, radius, color)
		draw_circle(position, radius * 0.45, Color("fff3d2"))

func _draw_skill_visual(v: Dictionary) -> void:
	var p: Vector2 = v.get("position", Vector2.ZERO)
	var color: Color = v.get("color", CYAN)
	if v.get("kind", "") == "sword":
		var direction := Vector2.from_angle(float(v.get("angle", 0.0)))
		var normal := direction.orthogonal()
		draw_line(p - direction * 34, p - direction * 13, Color(color, 0.25), 5, true)
		draw_colored_polygon(PackedVector2Array([p + direction * 25, p + direction * 3 + normal * 5, p - direction * 10, p + direction * 3 - normal * 5]), color)
		draw_line(p - direction * 6 + normal * 9, p - direction * 6 - normal * 9, color.lightened(0.4), 3, true)
		draw_line(p - direction * 7, p - direction * 17, color.darkened(0.3), 3, true)
	elif v.get("kind", "") == "ring":
		draw_arc(p, v.get("radius", 50.0), 0, TAU, 64, color, 2, true)

func _draw_effect(e: Dictionary) -> void:
	var age: float = e.get("age", 0.0)
	var t: float = age / e.get("life", 0.5)
	var position: Vector2 = e.get("position", Vector2(380, 380))
	var color: Color = e.get("color", CYAN)
	color.a *= 1.0 - t
	var kind: String = e.get("kind", "")
	if kind == "hit":
		var label := str(int(round(float(e.get("amount", 0)))))
		var p := position + Vector2(sin(float(e.get("amount", 0))) * 21, -37 - 50 * t)
		_text(label, p + Vector2(1, 2), 23, Color(0.02, 0.06, 0.1, 1.0 - t), true)
		_text(label, p, 23, Color(GOLD.lightened(0.2), 1.0 - t), true)
	elif kind == "slash" or kind == "dash":
		var angle: float = e.get("angle", -PI * 0.25)
		draw_arc(position, 28 + t * 45, angle, angle + PI * 1.4, 32, color, (1.0 - t) * 6 + 1, true)
	elif kind == "shield" or kind == "heal":
		draw_arc(position, 36 + t * 30, 0, TAU, 40, color, 2, true)
	else:
		var reach: float = float(e.get("radius", 54)) if kind != "death" else 100
		draw_arc(position, 6 + t * reach, 0, TAU, 40, color, 2.0, true)
		for i in range(8):
			var d := Vector2.from_angle(float(i) * TAU / 8.0 + float(e.get("side", 0)))
			draw_line(position + d * t * reach, position + d * (t * reach + 7 * (1.0 - t)), color, 2.0, true)
