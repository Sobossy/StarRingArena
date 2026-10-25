extends PanelContainer
signal closed
signal library_changed
const Catalog = preload("res://scripts/core/skill_catalog.gd")
const Board = preload("res://scripts/ui/arena_board.gd")
const Arena = preload("res://scripts/core/battle_arena.gd")
var ui
var library
var draft
var dirty: bool = false
var loading: bool = false
var list: ItemList
var status_label: Label
var fields: Dictionary = {}
var normal_path_label: Label
var skills_list: ItemList
var template_option: OptionButton
var skill_title: Label
var charge_input: SpinBox
var release_input: SpinBox
var movement_check: CheckBox
var charge_path_label: Label
var release_path_label: Label
var file_dialog: FileDialog
var pending_image: String = "normal"
var selected_skill: int = -1
var preview_board
var preview_arena
var preview_caption: Label
var preview_mode: OptionButton
var preview_playing: bool = false
var preview_clock: float = 0.0
var preview_accumulator: float = 0.0
var pending_action: Callable
var leave_dialog: ConfirmationDialog
var delete_dialog: ConfirmationDialog
var art_browser: ConfirmationDialog
var art_search: LineEdit
var art_list: ItemList
var art_items: Array = []
var filtered_art: Array = []

func build(host, content_library) -> void:
	ui = host
	library = content_library
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", ui._style(Color("0b1523"), ui.LINE, 12, 24, 20))
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 14)
	add_child(root_v)
	var heading := HBoxContainer.new()
	root_v.add_child(heading)
	var title = ui._label("角色编辑", 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(ui._button("保存角色", save_draft, true))
	heading.add_child(ui._button("返回对战", func(): _guard(_close_editor)))
	status_label = ui._label("为你的角色配置属性、技能与形象。", 13, ui.MUTED)
	root_v.add_child(status_label)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_child(columns)
	_build_library_column(columns)
	_build_form(columns)
	_build_preview(columns)
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png ; PNG 透明图片"])
	file_dialog.use_native_dialog = true
	file_dialog.title = "导入角色 PNG"
	file_dialog.file_selected.connect(import_image)
	add_child(file_dialog)
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = "有尚未保存的修改"
	leave_dialog.dialog_text = "是否保存当前角色后继续？"
	leave_dialog.ok_button_text = "保存并继续"
	leave_dialog.cancel_button_text = "留在编辑页"
	leave_dialog.add_button("放弃修改", false, "discard")
	leave_dialog.confirmed.connect(func(): if save_draft(): pending_action.call())
	leave_dialog.custom_action.connect(func(action): if action == "discard": dirty = false; pending_action.call(); leave_dialog.hide())
	leave_dialog.canceled.connect(func():
		var index: int = library.index_of(draft.id)
		if index >= 0:
			list.select(index)
		else:
			list.deselect_all()
	)
	add_child(leave_dialog)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "确认角色操作"
	delete_dialog.confirmed.connect(_delete_confirmed)
	add_child(delete_dialog)
	_build_art_browser()
	_refresh_list()
	_select_character(0)
	hide()

func _build_library_column(parent: HBoxContainer) -> void:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 180
	v.add_theme_constant_override("separation", 9)
	parent.add_child(v)
	v.add_child(ui._label("角色库", 17))
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(index): _guard(_select_character.bind(index)))
	v.add_child(list)
	v.add_child(ui._button("＋ 新建角色", func(): _guard(_new_character)))
	v.add_child(ui._button("复制当前角色", func(): _guard(_copy_character)))
	v.add_child(ui._button("恢复默认 / 删除", _request_delete))

func _build_form(parent: HBoxContainer) -> void:
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(tabs)
	var basic := _tab(tabs, "基础属性")
	fields.name = _line(basic, "角色名称")
	fields.description = _line(basic, "角色说明")
	fields.health = _number(basic, "基础血量", 1, 100000, 1)
	fields.attack = _number(basic, "基础攻击力", 0, 10000, 1)
	fields.speed = _number(basic, "移动速度", 0, 1000, 1)
	basic.add_child(ui._label("默认移动方式", 13, ui.MUTED))
	var move := OptionButton.new()
	for text in ui.MOVE_NAMES:
		move.add_item(text)
	basic.add_child(move)
	fields.movement = move
	move.item_selected.connect(func(_i): _changed())
	var note = ui._label("修改基础攻击力会影响技能伤害倍率。\n当前战斗使用开局快照，修改从下一局生效。", 12, ui.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	basic.add_child(note)
	var art := _tab(tabs, "常规形象")
	art.add_child(ui._label("常规 PNG", 15))
	normal_path_label = ui._label("未导入 · 使用占位图", 12, ui.MUTED)
	normal_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	art.add_child(normal_path_label)
	var row := HBoxContainer.new()
	art.add_child(row)
	row.add_child(ui._button("导入 PNG", _open_image.bind("normal")))
	row.add_child(ui._button("素材库", _open_art_browser.bind("normal")))
	row.add_child(ui._button("移除图片", _remove_image.bind("normal")))
	fields.image_size = _number(art, "显示大小", 24, 180, 1)
	fields.offset_x = _number(art, "水平偏移", -150, 150, 1)
	fields.offset_y = _number(art, "垂直偏移", -150, 150, 1)
	fields.radius = _number(art, "碰撞半径（独立于图片）", 8, 80, 1)
	art.add_child(ui._label("主题颜色", 13, ui.MUTED))
	var color := ColorPickerButton.new()
	color.custom_minimum_size.y = 36
	color.color_changed.connect(func(_value): _changed())
	art.add_child(color)
	fields.color = color
	var skills := _tab(tabs, "技能与状态")
	var add_row := HBoxContainer.new()
	skills.add_child(add_row)
	template_option = OptionButton.new()
	template_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for template in Catalog.ITEMS:
		template_option.add_item(template.name + " · " + template.type)
	add_row.add_child(template_option)
	add_row.add_child(ui._button("添加", _add_skill))
	skills_list = ItemList.new()
	skills_list.custom_minimum_size.y = 130
	skills_list.item_selected.connect(_select_skill)
	skills.add_child(skills_list)
	var order := HBoxContainer.new()
	skills.add_child(order)
	order.add_child(ui._button("上移", _move_skill.bind(-1)))
	order.add_child(ui._button("下移", _move_skill.bind(1)))
	order.add_child(ui._button("移除", _remove_skill))
	skill_title = ui._label("选择一个技能", 15, ui.CYAN)
	skills.add_child(skill_title)
	charge_input = _number(skills, "蓄力时长（秒）", 0, 10, 0.05, false)
	release_input = _number(skills, "释放形象持续时间（秒）", 0, 10, 0.05, false)
	movement_check = CheckBox.new()
	movement_check.text = "蓄力时允许移动"
	movement_check.toggled.connect(func(_value): _skill_changed())
	skills.add_child(movement_check)
	charge_input.value_changed.connect(func(_value): _skill_changed())
	release_input.value_changed.connect(func(_value): _skill_changed())
	charge_path_label = _image_row(skills, "蓄力形象", "charge")
	release_path_label = _image_row(skills, "释放形象", "release")
	var info = ui._label("主动技能：蓄力结束才出手。\n被动技能无蓄力，触发时可显示释放形象。\n飞剑持续运行，不强加施法停顿。", 12, ui.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skills.add_child(info)

func _tab(parent: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(v)
	return v

func _line(parent: Node, text: String) -> LineEdit:
	parent.add_child(ui._label(text, 13, ui.MUTED))
	var field := LineEdit.new()
	field.max_length = 120
	field.text_changed.connect(func(_value): _changed())
	parent.add_child(field)
	return field

func _number(parent: Node, text: String, minimum: float, maximum: float, step_value: float, bind_changes: bool = true) -> SpinBox:
	parent.add_child(ui._label(text, 13, ui.MUTED))
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = step_value
	field.custom_minimum_size.y = 35
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bind_changes:
		field.value_changed.connect(func(_value): _changed())
	parent.add_child(field)
	return field

func _image_row(parent: Node, title: String, kind: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(ui._button("导入" + title, _open_image.bind(kind)))
	row.add_child(ui._button("素材库", _open_art_browser.bind(kind)))
	row.add_child(ui._button("清除", _remove_image.bind(kind)))
	var label = ui._label("未设置，回退常规图", 11, ui.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _build_preview(parent: HBoxContainer) -> void:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 365
	v.add_theme_constant_override("separation", 12)
	parent.add_child(v)
	v.add_child(ui._label("实时预览", 18))
	preview_caption = ui._label("常规形象", 13, ui.MUTED)
	v.add_child(preview_caption)
	preview_board = Board.new()
	preview_board.custom_minimum_size = Vector2(365,365)
	preview_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(preview_board)
	preview_mode = OptionButton.new()
	for text in ["常规形象", "所选技能 · 蓄力形象", "所选技能 · 释放形象"]:
		preview_mode.add_item(text)
	preview_mode.item_selected.connect(func(_index): _refresh_preview())
	v.add_child(preview_mode)
	v.add_child(ui._button("试放所选技能", play_preview, true))
	v.add_child(ui._button("停止预览", _refresh_preview))
	var note = ui._label("测试目标仅用于预览。\n图片缺失时使用常规形象或占位图。\n预览不修改正式对战与角色存档。", 12, ui.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	preview_arena = Arena.new()
	add_child(preview_arena)

func _refresh_list() -> void:
	list.clear()
	for definition in library.characters:
		list.add_item(definition.display_name + (" · 内置" if library.is_builtin(definition.id) else ""))

func open_editor() -> void:
	_refresh_list()
	var index: int = library.index_of(draft.id) if draft != null else 0
	_select_character(maxi(0,index))
	show()

func _select_character(index: int) -> void:
	if index < 0 or index >= library.characters.size():
		return
	draft = library.characters[index].duplicate(true)
	list.select(index)
	_load_draft()

func _new_character() -> void:
	draft = library.make_new()
	list.deselect_all()
	_load_draft()
	dirty = true
	status_label.text = "新角色尚未保存。"

func _copy_character() -> void:
	draft = library.make_copy(draft)
	list.deselect_all()
	_load_draft()
	dirty = true
	status_label.text = "角色副本尚未保存。"

func _load_draft() -> void:
	loading = true
	fields.name.text = draft.display_name
	fields.description.text = draft.description
	fields.health.value = draft.max_health
	fields.attack.value = draft.attack
	fields.speed.value = draft.speed
	fields.image_size.value = draft.portrait_size
	fields.offset_x.value = draft.portrait_offset.x
	fields.offset_y.value = draft.portrait_offset.y
	fields.radius.value = draft.radius
	fields.color.color = draft.theme_color
	fields.movement.select(maxi(0, ui.MOVE_IDS.find(draft.default_movement)))
	normal_path_label.text = _image_description(draft.normal_image_path)
	loading = false
	dirty = false
	status_label.text = "正在编辑：" + draft.display_name
	_refresh_skills()
	_refresh_preview()

func _changed() -> void:
	if loading or draft == null:
		return
	draft.display_name = fields.name.text
	draft.description = fields.description.text
	draft.max_health = fields.health.value
	draft.attack = fields.attack.value
	draft.speed = fields.speed.value
	draft.portrait_size = fields.image_size.value
	draft.portrait_offset = Vector2(fields.offset_x.value, fields.offset_y.value)
	draft.radius = fields.radius.value
	draft.theme_color = fields.color.color
	draft.default_movement = ui.MOVE_IDS[fields.movement.selected]
	_mark_dirty()
	_refresh_preview()

func _mark_dirty() -> void:
	dirty = true
	status_label.text = "有未保存的修改 · " + draft.display_name

func save_draft() -> bool:
	if draft == null:
		return false
	if not library.save_character(draft):
		status_label.text = library.last_error
		return false
	dirty = false
	_refresh_list()
	list.select(library.index_of(draft.id))
	status_label.text = "已保存：" + draft.display_name
	library_changed.emit()
	return true

func _guard(action: Callable) -> void:
	if not dirty:
		action.call()
		return
	pending_action = action
	leave_dialog.popup_centered()

func _close_editor() -> void:
	_refresh_preview()
	hide()
	closed.emit()

func _request_delete() -> void:
	if draft == null:
		return
	delete_dialog.dialog_text = ("恢复内置角色默认配置？用户副本会保留。" if library.is_builtin(draft.id) else "删除此自建角色？已经开始的对战不受影响。")
	delete_dialog.popup_centered()

func _delete_confirmed() -> void:
	if library.remove_or_restore(draft.id):
		_refresh_list()
		_select_character(0)
		library_changed.emit()
	else:
		status_label.text = library.last_error

func _refresh_skills() -> void:
	skills_list.clear()
	for slot in draft.skill_slots:
		var item := Catalog.find(slot.template_id)
		skills_list.add_item(item.get("name", "未知技能") + " · " + item.get("type", ""))
	selected_skill = clampi(selected_skill, 0, draft.skill_slots.size() - 1)
	if not draft.skill_slots.is_empty():
		skills_list.select(selected_skill)
	_select_skill(selected_skill)

func _select_skill(index: int) -> void:
	selected_skill = index
	loading = true
	var slot: Dictionary = draft.skill_slots[index] if index >= 0 and index < draft.skill_slots.size() else {}
	var item := Catalog.find(str(slot.get("template_id", "")))
	skill_title.text = item.get("name", "尚未添加技能") + " · " + item.get("type", "")
	charge_input.editable = item.get("type", "") == "主动"
	release_input.editable = not item.is_empty() and item.get("type", "") != "持续"
	movement_check.disabled = not charge_input.editable
	charge_input.value = float(slot.get("charge_time", 0))
	release_input.value = float(slot.get("release_time", 0.3))
	movement_check.button_pressed = bool(slot.get("charge_can_move", true))
	charge_path_label.text = _image_description(str(slot.get("charge_image", "")))
	release_path_label.text = _image_description(str(slot.get("release_image", "")))
	loading = false
	_refresh_preview()

func _skill_changed() -> void:
	if loading or selected_skill < 0 or selected_skill >= draft.skill_slots.size():
		return
	var slot: Dictionary = draft.skill_slots[selected_skill]
	slot.charge_time = charge_input.value
	slot.release_time = release_input.value
	slot.charge_can_move = movement_check.button_pressed
	_mark_dirty()
	_refresh_preview()

func _add_skill() -> void:
	if draft.skill_slots.size() >= 8:
		status_label.text = "每个角色最多配置 8 个技能。"
		return
	draft.skill_slots.append(Catalog.new_slot(Catalog.ITEMS[template_option.selected].id))
	selected_skill = draft.skill_slots.size() - 1
	_mark_dirty()
	_refresh_skills()

func _remove_skill() -> void:
	if selected_skill >= 0 and selected_skill < draft.skill_slots.size():
		draft.skill_slots.remove_at(selected_skill)
		_mark_dirty()
		_refresh_skills()

func _move_skill(direction: int) -> void:
	var destination: int = selected_skill + direction
	if selected_skill >= 0 and destination >= 0 and destination < draft.skill_slots.size():
		var slot: Dictionary = draft.skill_slots[selected_skill]
		draft.skill_slots.remove_at(selected_skill)
		draft.skill_slots.insert(destination,slot)
		selected_skill = destination
		_mark_dirty()
		_refresh_skills()

func _open_image(kind: String) -> void:
	if kind != "normal" and (selected_skill < 0 or selected_skill >= draft.skill_slots.size()):
		status_label.text = "请先选择一个技能。"
		return
	pending_image = kind
	file_dialog.popup_centered_ratio(0.7)

func import_image(path: String) -> void:
	var owned_path: String = library.import_png(path)
	if owned_path.is_empty():
		status_label.text = library.last_error
		return
	if pending_image == "normal":
		draft.normal_image_path = owned_path
		draft.portrait = library.texture_from_path(owned_path)
		normal_path_label.text = _image_description(owned_path)
	else:
		draft.skill_slots[selected_skill][pending_image + "_image"] = owned_path
		_select_skill(selected_skill)
	_mark_dirty()
	_refresh_preview()

func _build_art_browser() -> void:
	art_browser = ConfirmationDialog.new()
	art_browser.title = "选择角色素材"
	art_browser.ok_button_text = "使用所选图片"
	art_browser.cancel_button_text = "取消"
	art_browser.confirmed.connect(_use_browser_image)
	add_child(art_browser)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(850,540)
	v.add_theme_constant_override("separation",10)
	art_browser.add_child(v)
	art_search = LineEdit.new()
	art_search.placeholder_text = "搜索角色或表情，例如：姬子、蓄势待发、看剑"
	art_search.text_changed.connect(func(_text): _filter_art())
	v.add_child(art_search)
	art_list = ItemList.new()
	art_list.max_columns = 5
	art_list.fixed_column_width = 154
	art_list.fixed_icon_size = Vector2i(96,96)
	art_list.icon_mode = ItemList.ICON_MODE_TOP
	art_list.max_text_lines = 2
	art_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_list.item_activated.connect(func(_index): _use_browser_image(); art_browser.hide())
	v.add_child(art_list)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/stickers/manifest.json"))
	if parsed is Array:
		art_items = parsed

func _open_art_browser(kind: String) -> void:
	if kind != "normal" and (selected_skill < 0 or selected_skill >= draft.skill_slots.size()):
		status_label.text = "请先选择一个技能。"
		return
	pending_image = kind
	art_search.text = ""
	_filter_art()
	art_browser.popup_centered()
	art_search.grab_focus()

func _filter_art() -> void:
	art_list.clear()
	filtered_art.clear()
	var query := art_search.text.strip_edges().to_lower()
	for item in art_items:
		if query.is_empty() or str(item.name).to_lower().contains(query):
			filtered_art.append(item)
			art_list.add_item(item.name,load(item.path))
	if not filtered_art.is_empty():
		art_list.select(0)

func _use_browser_image() -> void:
	var selected_items := art_list.get_selected_items()
	if selected_items.is_empty():
		return
	var path: String = filtered_art[selected_items[0]].path
	if pending_image == "normal":
		draft.normal_image_path = path
		draft.portrait = library.texture_from_path(path)
		normal_path_label.text = _image_description(path)
	else:
		draft.skill_slots[selected_skill][pending_image + "_image"] = path
		_select_skill(selected_skill)
	_mark_dirty()
	_refresh_preview()

func _remove_image(kind: String) -> void:
	if kind == "normal":
		draft.normal_image_path = ""
		draft.portrait = null
		normal_path_label.text = _image_description("")
	elif selected_skill >= 0 and selected_skill < draft.skill_slots.size():
		draft.skill_slots[selected_skill][kind + "_image"] = ""
		_select_skill(selected_skill)
	_mark_dirty()
	_refresh_preview()

func _image_description(path: String) -> String:
	if path.is_empty():
		return "未设置 · 回退常规图或占位图"
	return ("已导入 · " if library.texture_from_path(path) != null else "图片缺失 · 已回退 · ") + path.get_file().left(20)

func _refresh_preview() -> void:
	if preview_board == null or draft == null:
		return
	preview_playing = false
	preview_arena.clear_battle()
	preview_board.arena = null
	preview_board.reset_visuals()
	var sample = draft.duplicate(true)
	if preview_mode.selected > 0 and selected_skill >= 0 and selected_skill < draft.skill_slots.size():
		var key: String = "charge_image" if preview_mode.selected == 1 else "release_image"
		var texture: Texture2D = library.texture_from_path(str(draft.skill_slots[selected_skill].get(key,"")))
		if texture != null:
			sample.portrait = texture
	preview_board.preview_definitions = [sample]
	preview_caption.text = preview_mode.get_item_text(preview_mode.selected)

func play_preview() -> void:
	_refresh_preview()
	if selected_skill < 0 or selected_skill >= draft.skill_slots.size():
		status_label.text = "请先添加并选择技能。"
		return
	var sample = draft.duplicate(true)
	sample.skill_slots.clear()
	sample.skill_slots.append(draft.skill_slots[selected_skill].duplicate(true))
	sample.speed = 0
	var dummy = load("res://scripts/core/character_definition.gd").new()
	dummy.display_name = "测试目标"
	dummy.max_health = 100000
	dummy.speed = 0
	preview_arena.start_battle([sample,dummy],["chase","chase"],42)
	preview_arena.fighters[0].position = Vector2(310,380)
	preview_arena.fighters[1].position = Vector2(405,380)
	var skill = preview_arena.fighters[0].skills[0]
	skill.cooldown_remaining = 0
	if skill.phase_type == "主动":
		skill.request_cast(preview_arena.fighters[1])
	elif skill.skill_id == "counter":
		preview_arena.apply_damage(preview_arena.fighters[1],preview_arena.fighters[0],1,"preview")
	preview_board.arena = preview_arena
	preview_playing = true
	preview_clock = 0
	preview_accumulator = 0

func _process(delta: float) -> void:
	if not visible or not preview_playing:
		return
	preview_clock += delta
	preview_accumulator += minf(delta,0.1)
	while preview_accumulator >= 1.0/60.0 and preview_arena.running:
		preview_arena.step(1.0/60.0)
		preview_board.ingest(preview_arena.drain_events())
		preview_accumulator -= 1.0/60.0
	if not preview_arena.fighters.is_empty():
		preview_caption.text = {"charge":"蓄力中", "release":"释放中", "normal":"常规形象"}.get(preview_arena.fighters[0].visual_phase,"常规形象")
	if preview_clock > float(draft.skill_slots[selected_skill].get("charge_time",0)) + float(draft.skill_slots[selected_skill].get("release_time",0.3)) + 1.0:
		_refresh_preview()
