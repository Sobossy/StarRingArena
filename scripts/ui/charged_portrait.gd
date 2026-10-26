extends SubViewport
## A small offscreen sprite keeps recolouring isolated from bars, text, squash
## and the original PNG. There is one reusable surface per charging fighter.
const PALETTE = preload("res://assets/shaders/acheron_portrait.gdshader")
var sprite: Sprite2D
var palette: ShaderMaterial
var input_texture: Texture2D

func _init() -> void:
	transparent_bg = true
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	gui_disable_input = true
	palette = ShaderMaterial.new()
	palette.shader = PALETTE
	sprite = Sprite2D.new()
	sprite.material = palette
	add_child(sprite)

func update_portrait(texture: Texture2D,progress: float) -> Texture2D:
	if texture != input_texture:
		input_texture = texture
		var ratio: float = 192.0/maxf(texture.get_width(),texture.get_height())
		size = Vector2i(maxi(1,roundi(texture.get_width()*ratio)),maxi(1,roundi(texture.get_height()*ratio)))
		sprite.texture = texture
		sprite.position = Vector2(size)*.5
		sprite.scale = Vector2.ONE*ratio
	palette.set_shader_parameter("charge_progress",progress)
	return get_texture()
