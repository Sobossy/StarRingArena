extends RefCounted
## Runtime-safe content library; built-ins remain immutable and user files are atomic.
const Definition = preload("res://scripts/core/character_definition.gd")
const Roster = preload("res://data/roster.gd")
const Catalog = preload("res://scripts/core/skill_catalog.gd")
var storage_root: String = "user://characters"
var characters: Array = []
var last_error: String = ""

func _init(directory: String = "user://characters") -> void:
	storage_root = directory

func reload() -> Array:
	characters.clear()
	for original in Roster.get_all():
		var definition = original.duplicate(true)
		var ids: Array = {"sword":["orbit"], "mage":["fireball"], "guard":["melee", "shield", "counter"], "assassin":["dash"]}.get(definition.id, [])
		if definition.skill_slots.is_empty():
			for i in range(ids.size()):
				definition.skill_slots.append(Catalog.new_slot(ids[i], definition.id + "_" + str(i)))
			var image_presets := {
				"mage": ["389_姬子 计算.png", "017_姬子 引领.png"],
				"guard": ["327_杰帕德 浇花.png", "390_杰帕德 开门.png"],
				"assassin": ["044_千冶•刃 蓄势待发.png", "043_千冶•刃 看剑.png"],
			}
			if image_presets.has(definition.id):
				for slot in definition.skill_slots:
					slot.charge_image = "res://assets/stickers/" + image_presets[definition.id][0]
					slot.release_image = "res://assets/stickers/" + image_presets[definition.id][1]
			if not ids.is_empty():
				definition.skill_scenes.clear()
		characters.append(definition)
	var dir := DirAccess.open(storage_root)
	if dir != null:
		var files := dir.get_files()
		files.sort()
		for file in files:
			if not file.ends_with(".json"):
				continue
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(storage_root.path_join(file)))
			if not parsed is Dictionary or int(parsed.get("version", 0)) != 1:
				continue
			var loaded = from_data(parsed)
			if loaded == null or not validate(loaded).is_empty():
				continue
			var index: int = index_of(loaded.id)
			if index >= 0:
				characters[index] = loaded
			else:
				characters.append(loaded)
	return characters

func index_of(id: String) -> int:
	for i in range(characters.size()):
		if characters[i].id == id:
			return i
	return -1

func get_character(id: String):
	var index := index_of(id)
	return characters[index] if index >= 0 else null

func make_new():
	var definition = Definition.new()
	definition.id = "custom_" + str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(randi())
	definition.display_name = "新角色"
	definition.skill_slots.append(Catalog.new_slot("fireball"))
	return definition

func make_copy(original):
	var definition = original.duplicate(true)
	definition.id = make_new().id
	definition.display_name = original.display_name + " 副本"
	for i in range(definition.skill_slots.size()):
		definition.skill_slots[i]["slot_id"] = definition.id + "_" + str(i)
	return definition

func validate(definition) -> String:
	if definition.id.is_empty() or not definition.id.is_valid_identifier():
		return "角色标识无效。"
	if definition.display_name.strip_edges().is_empty():
		return "请填写角色名称。"
	if not is_finite(definition.max_health) or definition.max_health < 1 or definition.max_health > 100000:
		return "基础血量应为 1～100000。"
	if not is_finite(definition.attack) or definition.attack < 0 or definition.attack > 10000:
		return "攻击力应为 0～10000。"
	if not is_finite(definition.speed) or definition.speed < 0 or definition.speed > 1000:
		return "速度应为 0～1000。"
	if definition.skill_slots.size() > 8:
		return "每个角色最多配置 8 个技能。"
	for slot in definition.skill_slots:
		var template := Catalog.find(str(slot.get("template_id", "")))
		if template.is_empty():
			return "角色包含未注册的技能模板。"
		for key in ["charge_time", "release_time"]:
			var duration_value: float = float(slot.get(key, 0))
			var maximum: float = float(template.get("charge_max",10)) if key == "charge_time" else 10.0
			if not is_finite(duration_value) or duration_value < 0 or duration_value > maximum:
				return "该技能阶段时长应为 0～%d 秒。" % maximum
	return ""

func save_character(definition) -> bool:
	last_error = validate(definition)
	if not last_error.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(storage_root)
	var destination := storage_root.path_join(definition.id + ".json")
	var temp := destination + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入角色数据，请检查目录是否可写。"
		return false
	file.store_string(JSON.stringify(to_data(definition), "\t"))
	file.close()
	if DirAccess.rename_absolute(temp, destination) != OK:
		last_error = "保存角色失败，原有数据保持不变。"
		return false
	reload()
	return true

func is_builtin(id: String) -> bool:
	for definition in Roster.get_all():
		if definition.id == id:
			return true
	return false

func remove_or_restore(id: String) -> bool:
	last_error = ""
	if not id.is_valid_identifier():
		return false
	var path := storage_root.path_join(id + ".json")
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		last_error = "无法删除角色配置。"
		return false
	reload()
	return true

func import_png(path: String) -> String:
	last_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 32 * 1024 * 1024:
		last_error = "无法读取图片，或图片超过 32 MB。"
		return ""
	var bytes := file.get_buffer(file.get_length())
	var image := Image.new()
	if bytes.size() < 8 or bytes.slice(0, 8) != PackedByteArray([137,80,78,71,13,10,26,10]) or image.load_png_from_buffer(bytes) != OK:
		last_error = "请选择有效的 PNG 图片。"
		return ""
	if image.get_width() > 8192 or image.get_height() > 8192:
		last_error = "图片宽高不能超过 8192 像素。"
		return ""
	var destination := storage_root.path_join("images").path_join(FileAccess.get_sha256(path) + ".png")
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if not FileAccess.file_exists(destination) and image.save_png(destination) != OK:
		last_error = "图片复制失败。"
		return ""
	return destination

static func texture_from_path(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		if not path.begins_with("res://assets/") or not path.ends_with(".png") or ".." in path:
			return null
		return load(path) if ResourceLoader.exists(path) else null
	# Saved content can refer only to game-owned PNG copies, never arbitrary scripts.
	if not path.begins_with("user://") or not path.ends_with(".png") or ".." in path:
		return null
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)

static func to_data(definition) -> Dictionary:
	return {"version":1, "id":definition.id, "name":definition.display_name, "description":definition.description, "max_health":definition.max_health, "attack":definition.attack, "speed":definition.speed, "radius":definition.radius, "portrait_size":definition.portrait_size, "offset_x":definition.portrait_offset.x, "offset_y":definition.portrait_offset.y, "color":definition.theme_color.to_html(), "movement":definition.default_movement, "normal_image":definition.normal_image_path, "skills":definition.skill_slots.duplicate(true)}

static func from_data(data: Dictionary):
	var definition = Definition.new()
	definition.id = str(data.get("id", ""))
	definition.display_name = str(data.get("name", "新角色"))
	definition.description = str(data.get("description", ""))
	definition.max_health = float(data.get("max_health", 1000))
	definition.attack = float(data.get("attack", 38))
	definition.speed = float(data.get("speed", 150))
	definition.radius = clampf(float(data.get("radius", 28)), 8, 80)
	definition.portrait_size = clampf(float(data.get("portrait_size", 82)), 24, 180)
	definition.portrait_offset = Vector2(clampf(float(data.get("offset_x", 0)), -150, 150), clampf(float(data.get("offset_y", 0)), -150, 150))
	definition.theme_color = Color.from_string(str(data.get("color", "69d9ff")), Color("69d9ff"))
	definition.default_movement = str(data.get("movement", "bounce"))
	if definition.default_movement not in ["bounce", "chase", "kite", "wander"]:
		definition.default_movement = "bounce"
	definition.normal_image_path = str(data.get("normal_image", ""))
	definition.portrait = texture_from_path(definition.normal_image_path)
	var slots = data.get("skills", [])
	if not slots is Array:
		return null
	for slot in slots:
		if not slot is Dictionary:
			return null
		definition.skill_slots.append(slot.duplicate(true))
	return definition
