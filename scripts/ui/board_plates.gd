extends RefCounted
## Convex board fragments. All offsets are bounded visual transforms only.
var cells: Array = []
var walls: Array = []
var outer: Rect2
var scale: float = 1.0
var _key: String = ""

func rebuild(world_size: Vector2,arena) -> void:
	scale = arena.shrink_scale if arena != null else 1.0
	var center: Vector2 = world_size*.5
	outer = Rect2(center-world_size*scale*.5,world_size*scale)
	walls = arena.cut_walls if arena != null else []
	var key: String = str(world_size)+str(scale)+str(walls)
	if key == _key:
		return
	_key = key
	cells = [{"polygon":PackedVector2Array([outer.position,Vector2(outer.end.x,outer.position.y),outer.end,Vector2(outer.position.x,outer.end.y)]),"signs":{},"shift":Vector2.ZERO,"key":"","motion":Vector4.ZERO}]
	for wall in walls:
		var next: Array = []
		for cell in cells:
			for side in [-1.0,1.0]:
				var polygon: PackedVector2Array = clip(cell.polygon,wall.origin,wall.normal*side,wall.half_width)
				if polygon.size() < 3:
					continue
				var signs: Dictionary = cell.signs.duplicate()
				signs[wall.id] = side
				var shift: Vector2 = (cell.shift+wall.normal*side*4*scale).limit_length(12*scale)
				var cell_key: String = cell.key+str(wall.id)+("+" if side > 0 else "-")
				next.append({"polygon":polygon,"signs":signs,"shift":shift,"key":cell_key,"motion":_motion_parameters(cell_key)})
		cells = next

static func clip(polygon: PackedVector2Array,origin: Vector2,normal: Vector2,clearance: float) -> PackedVector2Array:
	var output := PackedVector2Array()
	if polygon.is_empty():
		return output
	var previous: Vector2 = polygon[-1]
	var previous_distance: float = (previous-origin).dot(normal)-clearance
	for current in polygon:
		var distance: float = (current-origin).dot(normal)-clearance
		if (distance >= 0) != (previous_distance >= 0):
			output.append(previous.lerp(current,previous_distance/(previous_distance-distance)))
		if distance >= 0:
			output.append(current)
		previous = current
		previous_distance = distance
	return output

func offset(cell: Dictionary,clock: float) -> Vector2:
	if walls.is_empty():
		return Vector2.ZERO
	var motion: Vector4 = cell.motion
	var drift := Vector2(sin(clock*TAU*motion.z+motion.x),sin(clock*TAU*motion.w+motion.y))
	return cell.shift+drift*(1.5/sqrt(2.0))*scale

static func _motion_parameters(key: String) -> Vector4:
	# Adjacent keys such as 1- / 1+ have almost identical String.hash values.
	# Mix their bits once so every fragment has independent slow motion, without
	# consuming the battle RNG or accumulating displacement over time.
	var bytes: PackedByteArray = key.sha256_buffer()
	var a: float = float(int(bytes[0])*256+int(bytes[1]))/65535.0
	var b: float = float(int(bytes[2])*256+int(bytes[3]))/65535.0
	return Vector4(a*TAU,b*TAU,.08+float(bytes[4])/255.0*.04,.06+float(bytes[5])/255.0*.04)

func cell_at(point: Vector2,signs: Dictionary = {}) -> Dictionary:
	var nearest: Dictionary = {}
	var best: float = INF
	for cell in cells:
		var matches: bool = true
		for wall in walls:
			var side: float = float(signs.get(wall.id,1.0 if (point-wall.origin).dot(wall.normal) >= 0 else -1.0))
			if cell.signs.get(wall.id,side) != side:
				matches = false
				break
		if matches:
			return cell
		for vertex in cell.polygon:
			var distance: float = point.distance_squared_to(vertex)
			if distance < best:
				best = distance
				nearest = cell
	return nearest

func point_offset(point: Vector2,clock: float,signs: Dictionary = {}) -> Vector2:
	var cell: Dictionary = cell_at(point,signs)
	return offset(cell,clock) if not cell.is_empty() else Vector2.ZERO

func line_parts(first: Vector2,last: Vector2,clock: float) -> Array:
	if walls.is_empty():
		return [{"from":first,"to":last,"shift":Vector2.ZERO}]
	var parts: Array = []
	for cell in cells:
		var low: float = 0
		var high: float = 1
		for wall in walls:
			var inward: Vector2 = wall.normal*float(cell.signs[wall.id])
			var start: float = (first-wall.origin).dot(inward)-wall.half_width
			var finish: float = (last-wall.origin).dot(inward)-wall.half_width
			if start < 0 and finish < 0:
				high = -1
				break
			if (start < 0) != (finish < 0):
				var t: float = start/(start-finish)
				if start < 0:
					low = maxf(low,t)
				else:
					high = minf(high,t)
		if low <= high:
			parts.append({"from":first.lerp(last,low),"to":first.lerp(last,high),"shift":offset(cell,clock)})
	return parts

func full_line(origin: Vector2,direction: Vector2) -> Array:
	var low: float = -INF
	var high: float = INF
	for axis in range(2):
		if absf(direction[axis]) < .000001:
			if origin[axis] < outer.position[axis] or origin[axis] > outer.end[axis]:
				return []
			continue
		var first: float = (outer.position[axis]-origin[axis])/direction[axis]
		var last: float = (outer.end[axis]-origin[axis])/direction[axis]
		low = maxf(low,minf(first,last))
		high = minf(high,maxf(first,last))
	return [origin+direction*low,origin+direction*high] if low <= high else []
