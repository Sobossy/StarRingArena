extends VBoxContainer
signal configuration_changed
const Config = preload("res://scripts/core/match_config.gd")
const MOVE_IDS := ["bounce", "chase", "kite", "wander"]
const MOVE_NAMES := ["碰壁反弹", "主动追击", "保持距离", "自由游走"]
var ui
var library
var mode_option: OptionButton
var count_input: SpinBox
var width_input: SpinBox
var height_input: SpinBox
var rows: VBoxContainer
var slot_data: Array = []
var role_options: Array[OptionButton] = []
var move_options: Array[OptionButton] = []
var team_options: Array[OptionButton] = []
var health_labels: Array[Label] = []
var locked: bool = false

func build(host, content_library) -> void:
	ui = host
	library = content_library
	add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	add_child(row)
	mode_option = OptionButton.new()
	mode_option.add_item("个人竞技")
	mode_option.add_item("组队对战")
	mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mode_option)
	row.add_child(ui._label("人数", 12, ui.MUTED))
	count_input = _number(row, 2, 8, 2)
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 6)
	add_child(map_row)
	map_row.add_child(ui._label("地图", 12, ui.MUTED))
	width_input = _number(map_row, 480, 2400, 500)
	map_row.add_child(ui._label("×", 12, ui.MUTED))
	height_input = _number(map_row, 480, 2400, 500)
	var note = ui._label("宽 × 高 · 90 秒限时 · 组队无友伤", 11, ui.MUTED)
	add_child(note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 160
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 7)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for i in range(8):
		slot_data.append({"character_id":library.characters[i % library.characters.size()].id, "movement":"", "team":i % 2})
	slot_data[1].character_id = "assassin"
	rebuild_rows()
	mode_option.item_selected.connect(func(_index): rebuild_rows(); configuration_changed.emit())
	count_input.value_changed.connect(func(_value): rebuild_rows(); configuration_changed.emit())
	width_input.value_changed.connect(func(_value): configuration_changed.emit())
	height_input.value_changed.connect(func(_value): configuration_changed.emit())

func _number(parent: Node, minimum: float, maximum: float, value: float) -> SpinBox:
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.value = value
	number.custom_minimum_size.x = 82
	if ui.mobile_mode:
		number.custom_minimum_size.y = 48
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(number)
	return number

func rebuild_rows() -> void:
	for child in rows.get_children():
		child.free()
	role_options.clear()
	move_options.clear()
	team_options.clear()
	health_labels.clear()
	for i in range(int(count_input.value)):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", ui._style(Color("0d1928"), ui.LINE, 8, 9, 7))
		rows.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 5)
		card.add_child(v)
		var top := HBoxContainer.new()
		v.add_child(top)
		top.add_child(ui._label("%02d" % (i + 1), 12, ui.CYAN))
		var role := OptionButton.new()
		role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		role.add_theme_font_size_override("font_size", 13)
		if ui.mobile_mode:
			role.custom_minimum_size.y = 48
		for definition in library.characters:
			role.add_item(definition.display_name)
		var index: int = library.index_of(slot_data[i].character_id)
		if index < 0:
			index = 0
			slot_data[i].character_id = library.characters[0].id
		role.select(index)
		top.add_child(role)
		role_options.append(role)
		var health = ui._label("", 11, ui.CYAN)
		health.visible = locked
		top.add_child(health)
		health_labels.append(health)
		var bottom := HBoxContainer.new()
		v.add_child(bottom)
		var movement := OptionButton.new()
		movement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		movement.add_theme_font_size_override("font_size", 12)
		if ui.mobile_mode:
			movement.custom_minimum_size.y = 48
		for name_text in MOVE_NAMES:
			movement.add_item(name_text)
		if slot_data[i].movement.is_empty():
			slot_data[i].movement = library.characters[index].default_movement
		movement.select(maxi(0, MOVE_IDS.find(slot_data[i].movement)))
		bottom.add_child(movement)
		move_options.append(movement)
		var team := OptionButton.new()
		team.add_theme_font_size_override("font_size", 12)
		for letter in ["A 队", "B 队", "C 队", "D 队"]:
			team.add_item(letter)
		team.select(int(slot_data[i].team))
		team.visible = mode_option.selected == 1
		bottom.add_child(team)
		team_options.append(team)
		role.item_selected.connect(_select_role.bind(i))
		movement.item_selected.connect(func(move_index, slot_index=i): slot_data[slot_index].movement = MOVE_IDS[move_index]; configuration_changed.emit())
		team.item_selected.connect(func(team_index, slot_index=i): slot_data[slot_index].team = team_index; configuration_changed.emit())
	set_locked(locked)

func _select_role(index: int, slot_index: int) -> void:
	slot_data[slot_index].character_id = library.characters[index].id
	slot_data[slot_index].movement = library.characters[index].default_movement
	move_options[slot_index].select(maxi(0, MOVE_IDS.find(slot_data[slot_index].movement)))
	configuration_changed.emit()

func get_config(seed_value: int = 42):
	var config = Config.new()
	config.width = width_input.value
	config.height = height_input.value
	config.mode = "ffa" if mode_option.selected == 0 else "teams"
	config.seed_value = seed_value
	for i in range(int(count_input.value)):
		config.participants.append({"definition":library.get_character(slot_data[i].character_id), "movement":slot_data[i].movement, "team":slot_data[i].team})
	return config

func set_locked(value: bool) -> void:
	locked = value
	mode_option.disabled = value
	for input in [count_input, width_input, height_input]:
		input.editable = not value
	for option in role_options + move_options + team_options:
		option.disabled = value
	for label in health_labels:
		label.visible = value

func serialize() -> Dictionary:
	return {"mode":mode_option.selected, "count":int(count_input.value), "width":width_input.value, "height":height_input.value, "slots":slot_data.duplicate(true)}

func restore(data: Dictionary) -> void:
	mode_option.select(clampi(int(data.get("mode", 0)), 0, 1))
	count_input.set_value_no_signal(clampi(int(data.get("count", 2)), 2, 8))
	width_input.set_value_no_signal(clampf(float(data.get("width", 500)), 480, 2400))
	height_input.set_value_no_signal(clampf(float(data.get("height", 500)), 480, 2400))
	var slots = data.get("slots", [])
	if slots is Array:
		for i in range(mini(8, slots.size())):
			if slots[i] is Dictionary:
				slot_data[i] = {"character_id":str(slots[i].get("character_id", "sword")), "movement":str(slots[i].get("movement", "bounce")), "team":clampi(int(slots[i].get("team", i % 2)), 0, 3)}
				if not slot_data[i].movement in MOVE_IDS:
					slot_data[i].movement = "bounce"
	rebuild_rows()
	configuration_changed.emit()
