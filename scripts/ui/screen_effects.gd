extends CanvasLayer
## One screen-reading layer above gameplay and UI, shared with editor preview.
var ui
var overlay: ColorRect
var palette: ShaderMaterial

func _ready() -> void:
	layer = 100
	overlay = ColorRect.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette = ShaderMaterial.new()
	palette.shader = preload("res://assets/shaders/acheron_world.gdshader")
	overlay.material = palette
	add_child(overlay)
	overlay.hide()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	if ui == null or overlay == null:
		return
	var board = ui.workshop.preview_board if ui.workshop.visible and ui.workshop.preview_playing else ui.board
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	overlay.size = viewport_size
	palette.set_shader_parameter("canvas_size",viewport_size)
	var waves := PackedVector4Array()
	for wave in board.slash_waves:
		if not wave.has("screen_uv"):
			wave.screen_uv = board.screen_position(wave.origin)/viewport_size
		var center: Vector2 = wave.screen_uv*viewport_size
		var reach: float = 0
		for corner in [Vector2.ZERO,Vector2(viewport_size.x,0),viewport_size,Vector2(0,viewport_size.y)]:
			reach = maxf(reach,center.distance_to(corner))
		var radius: float = (reach+6)*clampf(float(wave.age)/maxf(.000001,float(wave.expand)),0,1)
		waves.append(Vector4(center.x,center.y,radius,1))
	palette.set_shader_parameter("wave_count",mini(8,waves.size()))
	waves.resize(8)
	palette.set_shader_parameter("waves",waves)
	var start: Vector2 = board.get_global_transform_with_canvas()*board.base_world_transform*board.plates.outer.position
	var end: Vector2 = board.get_global_transform_with_canvas()*board.base_world_transform*board.plates.outer.end
	palette.set_shader_parameter("board_rect",Vector4(start.x,start.y,end.x,end.y))
	overlay.visible = not board.slash_waves.is_empty()
