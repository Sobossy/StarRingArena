extends SubViewport
var canvas: Node2D
var source_size := Vector2.ZERO
var source_texture: Texture2D

func _init() -> void:
	transparent_bg = true
	disable_3d = true
	gui_disable_input = true
	render_target_update_mode = SubViewport.UPDATE_ONCE
	canvas = Backdrop.new()
	add_child(canvas)

func configure(world_size: Vector2,texture: Texture2D,font: Font) -> void:
	if source_size == world_size and source_texture == texture and canvas.font == font:
		return
	source_size = world_size
	source_texture = texture
	var factor: float = minf(1.0,1024.0/maxf(world_size.x,world_size.y))
	size = Vector2i(ceili(world_size.x*factor),ceili(world_size.y*factor))
	canvas.scale = Vector2.ONE*factor
	canvas.world_size = world_size
	canvas.background_texture = texture
	canvas.font = font
	canvas.queue_redraw()
	render_target_update_mode = SubViewport.UPDATE_ONCE

class Backdrop extends Node2D:
	var world_size := Vector2(596,596)
	var background_texture: Texture2D
	var font: Font
	const CYAN := Color("78e5dc")
	const GOLD := Color("dec58d")

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
