extends Control

const ArenaScript = preload("res://scripts/core/battle_arena.gd")
const BoardScript = preload("res://scripts/ui/arena_board.gd")
const Roster = preload("res://data/roster.gd")
const LibraryScript = preload("res://scripts/core/character_library.gd")
const MatchPanelScript = preload("res://scripts/ui/match_panel.gd")
const WorkshopScript = preload("res://scripts/ui/character_editor.gd")
const HistoryStore = preload("res://scripts/core/match_history.gd")
const HistoryPanel = preload("res://scripts/ui/history_panel.gd")
const BG := Color("080f1b")
const PANEL := Color("111e2e")
const LINE := Color("263a50")
const TEXT := Color("e4edf1")
const MUTED := Color("8397aa")
const CYAN := Color("78e5dc")
const GOLD := Color("dec58d")
const MOVE_IDS := ["bounce", "chase", "kite", "wander"]
const MOVE_NAMES := ["碰壁反弹", "主动追击", "保持距离", "自由游走"]
const STEP := 1.0 / 60.0

var arena
var board
var roster: Array = []
var library
var match_panel
var workshop
var editor_button: Button
var match_error_label: Label
var live_roster_label: Label
var role_options: Array[OptionButton] = []
var move_options: Array[OptionButton] = []
var matchup_labels: Array[Label] = []
var seed_label: Label
var last_seed: int = 0
var seed_rng := RandomNumberGenerator.new()
var history_store
var history_panel
var history_button: Button
var current_record_button: Button
var history_notice: Label
var current_record_id: String = ""
var phase_label: Label
var timer_label: Label
var hint_label: Label
var start_button: Button
var pause_button: Button
var return_button: Button
var speed_buttons: Array[Button] = []
var result_panel: PanelContainer
var result_title: Label
var result_detail: Label
var volume_slider: HSlider
var volume_label: Label
var music_toggle: CheckButton
var music_slider: HSlider
var music_label: Label
var game_audio
var map_default_migrated: bool = true
var settings_path: String = "user://settings.cfg"
var fullscreen_button: Button
var audio_players: Array[AudioStreamPlayer] = []
var hit_sound: AudioStream
var audio_index: int = 0

var paused: bool = false
var speed: float = 1.0
var accumulator: float = 0.0
var has_started: bool = false
var result_shown: bool = false
var result_wait_remaining: float = 4.0
var post_motion_accumulator: float = 0.0
var boot_time: float = 0.0
var smoke_mode: bool = false
var capture_done: bool = false
var font: Font
var qa_mode: bool = false
var mobile_mode: bool = false
var mobile_page: String = "config"
var main_margin: MarginContainer
var arena_column: VBoxContainer
var config_panel: PanelContainer
var mobile_toolbar: HBoxContainer
var mobile_page_button: Button
var mobile_exit_dialog: ConfirmationDialog
var mobile_metrics_clock: float = 0.0
var screen_effects

func _ready() -> void:
	qa_mode = qa_mode or "--qa" in OS.get_cmdline_user_args()
	mobile_mode = mobile_mode or OS.has_feature("android") or "--mobile" in OS.get_cmdline_user_args()
	if mobile_mode:
		get_tree().quit_on_go_back = false
		if OS.has_feature("android"):
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
			Engine.max_fps = 60
		get_window().content_scale_size = Vector2i(720,1280)
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		get_window().min_size = Vector2i(540,960)
		get_tree().auto_accept_quit = false
	var font_variation := FontVariation.new()
	font_variation.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	font_variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
	font = font_variation
	library = LibraryScript.new("user://qa_ui_library" if qa_mode else "user://characters")
	roster = library.reload()
	arena = ArenaScript.new()
	add_child(arena)
	seed_rng.randomize()
	history_store = HistoryStore.new("user://qa_match_history/ui" if qa_mode else "user://match_history")
	arena.combat_event.connect(history_store.append_event)
	arena.battle_ended.connect(_on_match_completed)
	_build_theme()
	_build_ui()
	screen_effects = load("res://scripts/ui/screen_effects.gd").new()
	screen_effects.ui = self
	add_child(screen_effects)
	_build_audio()
	game_audio = load("res://scripts/ui/game_audio.gd").new()
	add_child(game_audio)
	game_audio.setup()
	board.death_ejected.connect(game_audio.play_cheer)
	if not qa_mode:
		_load_settings()
	_update_music()
	game_audio.start_music()
	_update_configuration()
	_set_speed(1.0)
	var args := OS.get_cmdline_user_args()
	smoke_mode = "--smoke" in args
	if "--demo-eight" in args:
		match_panel.count_input.set_value_no_signal(8)
		match_panel.mode_option.select(1)
		match_panel.width_input.set_value_no_signal(1200)
		match_panel.height_input.set_value_no_signal(700)
		for i in range(8):
			match_panel.slot_data[i].team = i % 4
		match_panel.rebuild_rows()
		_update_configuration()
	if "--demo-bat" in args:
		match_panel.count_input.set_value_no_signal(2)
		match_panel.mode_option.select(0)
		match_panel.slot_data[0].character_id = "destruction_trailblazer"
		match_panel.slot_data[0].movement = "bounce"
		match_panel.slot_data[1].character_id = "sparkle"
		match_panel.slot_data[1].movement = "bounce"
		match_panel.rebuild_rows()
		_update_configuration()
	if "--demo" in args or smoke_mode:
		_start_battle()
	if "--editor-demo" in args:
		workshop.open_editor()
	if not mobile_mode:
		get_window().min_size = Vector2i(1020,675)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_on_close_requested)
	if mobile_mode:
		get_viewport().size_changed.connect(_update_safe_area)
		get_window().go_back_requested.connect(_handle_mobile_back)
		_update_safe_area()

func _build_theme() -> void:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("52677b"))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_disabled_color", "OptionButton", MUTED)
	for control_type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", control_type, _style(Color("16273a"), LINE, 8, 12, 8))
		t.set_stylebox("hover", control_type, _style(Color("21394e"), Color("4c7a8d"), 8, 12, 8))
		t.set_stylebox("pressed", control_type, _style(Color("294755"), CYAN, 8, 12, 8))
		t.set_stylebox("disabled", control_type, _style(Color("101d2c"), Color("1c3044"), 8, 12, 8))
		t.set_stylebox("focus", control_type, _style(Color.TRANSPARENT, CYAN, 8, 12, 8))
	t.set_stylebox("panel", "PopupMenu", _style(Color("14263a"), Color("426278"), 8, 8, 8))
	t.set_stylebox("hover", "PopupMenu", _style(Color("294555"), Color.TRANSPARENT, 4, 4, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", CYAN)
	t.set_constant("v_separation", "PopupMenu", 12)
	t.set_font_size("font_size", "PopupMenu", 16)
	t.set_stylebox("normal", "LineEdit", _style(Color("0d1928"), LINE, 7, 10, 7))
	t.set_stylebox("focus", "LineEdit", _style(Color("112133"), CYAN, 7, 10, 7))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", CYAN)
	t.set_stylebox("slider", "HSlider", _style(Color("293d50"), Color.TRANSPARENT, 3, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", _style(Color("68cfc7"), Color.TRANSPARENT, 3, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", _style(CYAN, Color.TRANSPARENT, 3, 0, 3))
	t.set_stylebox("panel", "ItemList", _style(Color("0e1b2b"), LINE, 8, 8, 8))
	t.set_stylebox("selected", "ItemList", _style(Color("29484d"), Color("59958c"), 5, 4, 3))
	t.set_stylebox("selected_focus", "ItemList", _style(Color("29484d"), CYAN, 5, 4, 3))
	t.set_stylebox("panel", "TabContainer", _style(Color("111e2e"), LINE, 8, 0, 0))
	t.set_stylebox("tab_selected", "TabContainer", _style(Color("233b4c"), Color("4e7a85"), 5, 12, 9))
	t.set_stylebox("tab_unselected", "TabContainer", _style(Color("102030"), LINE, 5, 12, 9))
	t.set_color("font_selected_color", "TabContainer", CYAN)
	theme = t

func _style(bg: Color, border: Color, radius: int = 10, horizontal: int = 16, vertical: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = horizontal
	s.content_margin_right = horizontal
	s.content_margin_top = vertical
	s.content_margin_bottom = vertical
	return s

func _label(text: String, font_size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 42
	if mobile_mode:
		b.custom_minimum_size.y = 48
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(callback)
	if primary:
		b.add_theme_stylebox_override("normal", _style(CYAN, CYAN, 9, 14, 12))
		b.add_theme_stylebox_override("hover", _style(Color("a2f3e8"), Color("c4fff4"), 9, 14, 12))
		b.add_theme_stylebox_override("pressed", _style(Color("4cbab4"), CYAN, 9, 14, 12))
		b.add_theme_color_override("font_color", Color("0e2935"))
		b.add_theme_color_override("font_hover_color", Color("0e2935"))
		b.add_theme_color_override("font_pressed_color", Color("0e2935"))
	return b

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin := MarginContainer.new()
	main_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 23)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10 if mobile_mode else 20)
	margin.add_child(stack)
	_build_header(stack)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 28)
	stack.add_child(content)
	_build_arena_column(content)
	_build_sidebar(content)
	if mobile_mode:
		mobile_toolbar = HBoxContainer.new()
		mobile_toolbar.add_theme_constant_override("separation",12)
		stack.add_child(mobile_toolbar)
		var playback: Node = pause_button.get_parent()
		playback.reparent(mobile_toolbar)
		playback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var speed_row: Node = speed_buttons[0].get_parent()
		speed_row.reparent(mobile_toolbar)
		speed_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mobile_toolbar.add_child(_button("重开",_start_battle))
		_show_mobile_page("config")
	var footer := HBoxContainer.new()
	stack.add_child(footer)
	var left_note := _label("星环竞技场  /  本地自动对战", 11, Color("546c81"))
	left_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(left_note)
	footer.add_child(_label("SPACE  暂停     R  重开     F11  全屏", 11, Color("6a8296")))
	footer.visible = not mobile_mode
	workshop = WorkshopScript.new()
	add_child(workshop)
	workshop.build(self,library)
	workshop.library_changed.connect(_library_changed)
	history_panel = HistoryPanel.new()
	add_child(history_panel)
	history_panel.build(self,history_store)
	if mobile_mode:
		mobile_exit_dialog = ConfirmationDialog.new()
		mobile_exit_dialog.title = "退出游戏"
		mobile_exit_dialog.dialog_text = "确定退出星环竞技场吗？角色与设置会保留。"
		mobile_exit_dialog.ok_button_text = "退出"
		mobile_exit_dialog.cancel_button_text = "取消"
		mobile_exit_dialog.confirmed.connect(_on_close_requested)
		add_child(mobile_exit_dialog)


func _build_header(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 15)
	parent.add_child(row)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/icon.svg")
	logo.custom_minimum_size = Vector2(46, 46)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(logo)
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	title.add_child(_label("星环竞技场", 25))
	title.add_child(_label("S T A R   R I N G   /   A U T O   B A T T L E", 10, MUTED))
	editor_button = _button("角色编辑", func(): workshop.open_editor())
	editor_button.custom_minimum_size.y = 37
	if mobile_mode:
		editor_button.custom_minimum_size.y = 48
	editor_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(editor_button)
	if not mobile_mode:
		history_button = _button("对局记录",_open_history)
		history_button.custom_minimum_size.y = 37
		row.add_child(history_button)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _style(Color("142630"), Color("284850"), 16, 13, 6))
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	phase_label = _label("●  准备就绪", 12, CYAN)
	badge.add_child(phase_label)
	fullscreen_button = _button("全屏  F11", _toggle_fullscreen)
	fullscreen_button.custom_minimum_size = Vector2(105, 37)
	fullscreen_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(fullscreen_button)
	fullscreen_button.visible = not mobile_mode
	if mobile_mode:
		mobile_page_button = _button("看对战",func(): _show_mobile_page("battle" if mobile_page == "config" else "config"))
		row.add_child(mobile_page_button)

func _build_arena_column(parent: HBoxContainer) -> void:
	var column := VBoxContainer.new()
	arena_column = column
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	parent.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	column.add_child(top)
	for i in range(2):
		if i == 1:
			var center := VBoxContainer.new()
			center.custom_minimum_size.x = 110
			center.add_theme_constant_override("separation", 0)
			top.add_child(center)
			timer_label = _label("01:30", 23, GOLD)
			timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			center.add_child(timer_label)
			var timer_caption := _label("对战时限", 10, MUTED)
			timer_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			center.add_child(timer_caption)
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _style(Color("101d2c"), LINE, 9, 16, 8))
		top.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		card.add_child(v)
		var tag := _label("模式 / MODE" if i == 0 else "地图 / ARENA", 10, CYAN if i == 0 else GOLD)
		var name_label := _label("", 18)
		if i == 1:
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_child(tag)
		v.add_child(name_label)
		matchup_labels.append(name_label)
	var board_holder := Control.new()
	board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(board_holder)
	board = BoardScript.new()
	board.arena = arena
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_holder.add_child(board)
	var overlay_center := CenterContainer.new()
	overlay_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_holder.add_child(overlay_center)
	result_panel = PanelContainer.new()
	result_panel.custom_minimum_size.x = 344
	result_panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.075, 0.12, 0.97), GOLD, 16, 28, 26))
	result_panel.hide()
	overlay_center.add_child(result_panel)
	var results := VBoxContainer.new()
	results.add_theme_constant_override("separation", 13)
	result_panel.add_child(results)
	var finished := _label("M A T C H   C O M P L E T E", 10, GOLD)
	finished.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results.add_child(finished)
	result_title = _label("", 28)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results.add_child(result_title)
	result_detail = _label("", 13, MUTED)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results.add_child(result_detail)
	results.add_child(_button("再战一局", _start_battle, true))
	current_record_button = _button("查看本局记录",func(): _open_history(current_record_id))
	results.add_child(current_record_button)
	history_notice = _label("",12,MUTED)
	history_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results.add_child(history_notice)
	results.add_child(_button("返回选角", _return_to_selection))
	hint_label = _label("双角色自动对战  ·  角色图片待替换", 12, MUTED)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint_label)

func _build_sidebar(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	config_panel = panel
	panel.custom_minimum_size.x = 360
	if mobile_mode:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(PANEL, LINE, 14, 16, 15))
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	if mobile_mode:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		panel.add_child(scroll)
		scroll.add_child(v)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		panel.add_child(v)
	v.add_child(_label("对战配置", 20))
	if mobile_mode:
		history_button = _button("对局记录",_open_history)
		v.add_child(history_button)
	match_panel = MatchPanelScript.new()
	match_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(match_panel)
	match_panel.build(self,library)
	if mobile_mode:
		match_panel.custom_minimum_size.y = 340
	match_panel.configuration_changed.connect(_update_configuration)
	match_error_label = _label("", 11, Color("ffb7a4"))
	match_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(match_error_label)
	seed_label = _label("随机种子 · 每局开始时自动生成",12,MUTED)
	v.add_child(seed_label)
	start_button = _button("开始对战  →", _start_battle, true)
	start_button.custom_minimum_size.y = 47
	v.add_child(start_button)
	var playback := HBoxContainer.new()
	playback.add_theme_constant_override("separation",8)
	v.add_child(playback)
	pause_button = _button("暂停",_toggle_pause)
	pause_button.disabled = true
	pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playback.add_child(pause_button)
	return_button = _button("返回配置",_return_to_selection)
	return_button.disabled = true
	return_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playback.add_child(return_button)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation",7)
	v.add_child(speed_row)
	for value in [0.5,1.0,2.0]:
		var button := _button(("%.1f" % value).trim_suffix(".0") + "×",_set_speed.bind(value))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 32
		speed_row.add_child(button)
		speed_buttons.append(button)
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation",8)
	v.add_child(volume_row)
	volume_label = _label("总音量 35%",11,MUTED)
	volume_label.custom_minimum_size.x = 75
	volume_row.add_child(volume_label)
	volume_slider = HSlider.new()
	volume_slider.max_value = 100
	volume_slider.value = 35
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.custom_minimum_size.y = 25
	volume_slider.value_changed.connect(_set_volume)
	volume_row.add_child(volume_slider)
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation",8)
	v.add_child(music_row)
	music_toggle = CheckButton.new()
	music_toggle.text = "背景音乐"
	music_toggle.button_pressed = true
	music_toggle.add_theme_font_size_override("font_size",12)
	music_toggle.toggled.connect(func(_on): _update_music())
	music_row.add_child(music_toggle)
	music_slider = HSlider.new()
	music_slider.max_value = 100
	music_slider.value = 50
	music_slider.custom_minimum_size = Vector2(55,25)
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.value_changed.connect(func(_value): _update_music())
	music_row.add_child(music_slider)
	music_label = _label("50%",11,MUTED)
	music_label.custom_minimum_size.x = 33
	music_row.add_child(music_label)
	live_roster_label = _label("最多 8 人 · 角色形象可在编辑页导入",11,MUTED)
	live_roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(live_roster_label)

func _update_configuration() -> void:
	if match_panel == null or start_button == null:
		return
	roster = library.characters
	role_options = match_panel.role_options
	move_options = match_panel.move_options
	var config = match_panel.get_config(last_seed if last_seed > 0 else 42)
	board.preview_config = config
	board.preview_positions = arena._spawn_layout(config)
	board.queue_redraw()
	board.preview_definitions = []
	for slot in config.participants:
		board.preview_definitions.append(slot.definition)
	matchup_labels[0].text = ("个人竞技" if config.mode == "ffa" else "组队对战") + " · %d 人" % config.participants.size()
	matchup_labels[1].text = "%d × %d" % [config.width,config.height]
	if not has_started:
		match_error_label.text = arena.validate_config(config)
		start_button.disabled = not match_error_label.text.is_empty()
		hint_label.text = "配置阵容与地图，或在角色编辑页导入你的形象。"

func _library_changed() -> void:
	roster = library.characters
	match_panel.rebuild_rows()
	_update_configuration()

func _on_role_selected(index: int, side: int) -> void:
	match_panel._select_role(index,side)

func _start_battle() -> void:
	var candidate_seed: int = seed_rng.randi_range(1,999999)
	if candidate_seed == last_seed:
		candidate_seed = candidate_seed%999999+1
	var config = match_panel.get_config(candidate_seed)
	var validation: String = arena.validate_config(config)
	if not validation.is_empty():
		match_error_label.text = validation
		return
	history_store.discard()
	arena.clear_battle()
	history_store.begin(config)
	game_audio.stop_cheers()
	board.reset_visuals()
	result_panel.hide()
	result_shown = false
	result_wait_remaining = 4.0
	post_motion_accumulator = 0
	paused = false
	accumulator = 0.0
	has_started = true
	var error: String = arena.start_match(config)
	if not error.is_empty():
		has_started = false
		match_error_label.text = error
		history_store.discard()
		return
	last_seed = candidate_seed
	seed_label.text = "本局种子 · %d（每局自动更换）" % last_seed
	current_record_id = ""
	_save_settings()
	match_panel.set_locked(true)
	editor_button.disabled = true
	board.ingest(arena.drain_events())
	board.frozen = false
	for option in role_options:
		option.disabled = true
	for option in move_options:
		option.disabled = true
	_refresh_history_state()
	start_button.text = "重新开局  ↻"
	if mobile_mode:
		_show_mobile_page("battle")
	pause_button.text = "暂停"
	pause_button.disabled = false
	return_button.disabled = false
	phase_label.text = "●  正在对战"
	hint_label.text = "全自动交锋中  ·  可随时暂停、变速或重新开局"

func _return_to_selection() -> void:
	history_store.discard()
	arena.clear_battle()
	game_audio.stop_cheers()
	board.reset_visuals()
	board.frozen = false
	result_panel.hide()
	has_started = false
	result_shown = false
	result_wait_remaining = 4.0
	post_motion_accumulator = 0
	paused = false
	accumulator = 0.0
	for option in role_options:
		option.disabled = false
	for option in move_options:
		option.disabled = false
	match_panel.set_locked(false)
	editor_button.disabled = false
	seed_label.text = "随机种子 · 每局开始时自动生成"
	current_record_id = ""
	_refresh_history_state()
	start_button.text = "开始对战  →"
	pause_button.disabled = true
	pause_button.text = "暂停"
	return_button.disabled = true
	phase_label.text = "●  准备就绪"
	timer_label.text = "01:30"
	_update_configuration()
	if mobile_mode:
		_show_mobile_page("config")

func _waiting_for_result() -> bool:
	return has_started and not arena.running and not result_shown

func _toggle_pause() -> void:
	if not has_started or (not arena.running and not _waiting_for_result() and not board.has_departures()):
		return
	paused = not paused
	board.frozen = paused
	pause_button.text = "继续" if paused else "暂停"
	phase_label.text = "Ⅱ  已暂停" if paused else "●  正在对战"
	accumulator = 0.0
	game_audio.sync_character_audio(arena,paused,speed)

func _set_speed(value: float) -> void:
	speed = value
	board.display_speed = speed
	if game_audio != null:
		game_audio.sync_character_audio(arena,paused,speed)
	var values := [0.5, 1.0, 2.0]
	for i in range(speed_buttons.size()):
		var active: bool = is_equal_approx(values[i], speed)
		speed_buttons[i].add_theme_stylebox_override("normal", _style(Color("254648") if active else Color("142437"), Color("59958c") if active else LINE, 7, 8, 5))
		speed_buttons[i].add_theme_color_override("font_color", CYAN if active else MUTED)

func _toggle_fullscreen() -> void:
	var full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	fullscreen_button.text = "全屏  F11" if full else "窗口  F11"

func _show_mobile_page(page: String) -> void:
	if not mobile_mode:
		return
	if page == "config" and has_started and not paused and (arena.running or _waiting_for_result() or board.has_departures()):
		_toggle_pause()
	mobile_page = page
	arena_column.visible = page == "battle"
	config_panel.visible = page == "config"
	if mobile_toolbar != null:
		mobile_toolbar.visible = page == "battle"
	if mobile_page_button != null:
		mobile_page_button.text = "看对战" if page == "config" else "配置 / 声音"

func _update_safe_area() -> void:
	if not mobile_mode or main_margin == null:
		return
	var padding := Vector4(12,12,12,12)
	if OS.has_feature("android") and DisplayServer.has_method("get_display_safe_area"):
		var safe: Rect2i = DisplayServer.call("get_display_safe_area")
		var window_size := Vector2(DisplayServer.window_get_size())
		if window_size.x > 0 and window_size.y > 0 and safe.has_area():
			var ratio: Vector2 = get_viewport_rect().size / window_size
			padding.x += maxf(0,safe.position.x) * ratio.x
			padding.y += maxf(0,safe.position.y) * ratio.y
			padding.z += maxf(0,window_size.x-safe.end.x) * ratio.x
			padding.w += maxf(0,window_size.y-safe.end.y) * ratio.y
	main_margin.add_theme_constant_override("margin_left",ceili(padding.x))
	main_margin.add_theme_constant_override("margin_top",ceili(padding.y))
	main_margin.add_theme_constant_override("margin_right",ceili(padding.z))
	main_margin.add_theme_constant_override("margin_bottom",ceili(padding.w))
	if workshop != null:
		workshop.offset_left = padding.x - 12
		workshop.offset_top = padding.y - 12
		workshop.offset_right = -(padding.z - 12)
		workshop.offset_bottom = -(padding.w - 12)
	if history_panel != null:
		history_panel.offset_left = padding.x-12
		history_panel.offset_top = padding.y-12
		history_panel.offset_right = -(padding.z-12)
		history_panel.offset_bottom = -(padding.w-12)

func _handle_mobile_back() -> void:
	if history_panel.visible:
		history_panel.go_back()
	elif workshop.visible:
		if workshop.art_browser.visible:
			workshop.art_browser.hide()
		elif workshop.delete_dialog.visible:
			workshop.delete_dialog.hide()
		elif workshop.file_dialog.visible:
			workshop.file_dialog.hide()
		elif workshop.leave_dialog.visible:
			workshop.leave_dialog.hide()
		else:
			workshop._guard(workshop._close_editor)
	elif mobile_exit_dialog.visible:
		mobile_exit_dialog.hide()
	elif mobile_page == "battle":
		_show_mobile_page("config")
	else:
		mobile_exit_dialog.popup_centered()

func _set_backgrounded(backgrounded: bool) -> void:
	if not mobile_mode or game_audio == null:
		return
	game_audio.set_character_backgrounded(backgrounded)
	if backgrounded:
		_save_settings()
		if has_started and not paused and (arena.running or _waiting_for_result() or board.has_departures()):
			_toggle_pause()
	game_audio.music_player.stream_paused = backgrounded
	game_audio.cheer_player.stream_paused = backgrounded
	for player in game_audio.weapon_players:
		player.stream_paused = backgrounded
	for player in audio_players:
		player.stream_paused = backgrounded

func _notification(what: int) -> void:
	if not mobile_mode:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_set_backgrounded(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_set_backgrounded(false)

func _process(delta: float) -> void:
	boot_time += delta
	if mobile_mode and OS.has_feature("android") and OS.is_debug_build():
		mobile_metrics_clock += delta
		if mobile_metrics_clock >= 5.0:
			mobile_metrics_clock = 0.0
			print("PHONE_PERF fps=",Engine.get_frames_per_second()," actors=",arena.fighters.size()," page=",mobile_page," paused=",paused)
	if workshop.visible or history_panel.visible:
		_tick_smoke()
		return

	if has_started and arena.running and not paused:
		accumulator += minf(delta, 0.25) * speed
		while accumulator >= STEP and arena.running:
			arena.step(STEP)
			accumulator -= STEP
			var events: Array = arena.drain_events()
			board.ingest(events)
			for e in events:
				game_audio.play_weapon_event(str(e.get("kind","")))
				game_audio.play_character_event(e,arena,speed)
				if e.get("kind", "") == "hit" and float(e.get("amount",0)) > 0:
					_play_hit()
		var seconds: int = maxi(0, int(ceil(arena.duration - arena.elapsed)))
		timer_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	game_audio.sync_character_audio(arena,paused,speed)
	if has_started:
		var alive: int = 0
		var names: Array[String] = []
		var team_counts: Dictionary = {}
		for fighter in arena.fighters:
			if fighter.alive:
				alive += 1
			names.append("%02d %s %d" % [fighter.fighter_id + 1,fighter.definition.display_name,fighter.health])
			if fighter.fighter_id < match_panel.health_labels.size():
				match_panel.health_labels[fighter.fighter_id].text = str(int(ceil(fighter.health))) if fighter.alive else "淘汰"
			if not team_counts.has(fighter.team_id):
				team_counts[fighter.team_id] = Vector2i.ZERO
			team_counts[fighter.team_id] += Vector2i(1 if fighter.alive else 0,1)
		live_roster_label.text = "存活 %d / %d" % [alive,arena.fighters.size()]
		if arena.mode == "teams":
			var team_text: Array[String] = []
			for team in team_counts:
				team_text.append("%s队 %d/%d" % [["A","B","C","D"][team],team_counts[team].x,team_counts[team].y])
			live_roster_label.text += "\n" + "  ".join(team_text)
		live_roster_label.tooltip_text = "\n".join(names)
	if has_started and not arena.running and not result_shown:
		if not paused:
			var active_delta: float = minf(maxf(0,delta),result_wait_remaining)
			result_wait_remaining = maxf(0,result_wait_remaining-active_delta)
			post_motion_accumulator += active_delta*speed
			while post_motion_accumulator >= STEP-.000001:
				arena.step_post_result_motion(STEP)
				post_motion_accumulator = maxf(0,post_motion_accumulator-STEP)
		if result_wait_remaining <= .000001:
			for fighter in arena.fighters:
				fighter.velocity = Vector2.ZERO
			_show_result()
		else:
			phase_label.text = "Ⅱ  已暂停" if paused else "◆  胜负已定 · %.1f秒后结算" % result_wait_remaining
	_tick_smoke()

func _tick_smoke() -> void:
	if smoke_mode and boot_time > 4.0 and not capture_done:
		capture_done = true
		_capture_smoke.call_deferred()
	if smoke_mode and boot_time > 7.0:
		print("UI_SMOKE_OK fps=", Engine.get_frames_per_second(), " elapsed=", arena.elapsed)
		get_tree().quit()

func _on_close_requested() -> void:
	if workshop.visible and workshop.dirty:
		workshop._guard(func(): _save_settings(); get_tree().quit())
	else:
		_save_settings()
		get_tree().quit()

func _show_result() -> void:
	result_shown = true
	paused = false
	board.frozen = false
	if arena.winner_team < 0:
		result_title.text = "势均力敌 · 平局"
	elif arena.mode == "teams":
		result_title.text = ["A","B","C","D"][arena.winner_team] + " 队获胜"
	else:
		result_title.text = "%02d · %s 获胜" % [arena.winner + 1, arena.fighters[arena.winner].definition.display_name]
	result_detail.text = "战斗用时 %.1f 秒  ·  种子 %d" % [arena.elapsed, arena.seed_value]
	result_panel.show()
	pause_button.disabled = true
	phase_label.text = "◆  对战结束"
	hint_label.text = "每一种搭配，都有新的可能。"
	_refresh_history_state()

func _on_match_completed(_winner: int) -> void:
	var saved_id: String = history_store.complete(arena)
	if not saved_id.is_empty():
		current_record_id = saved_id
	if not history_store.pending.is_empty():
		hint_label.text = "记录保存未完成，可在对局记录中重试。"
	_refresh_history_state()

func _refresh_history_state() -> void:
	if history_button != null:
		history_button.disabled = has_started and not result_shown
		history_button.text = "对局记录" if history_store.pending.is_empty() else "对局记录 · 待保存"
	if current_record_button != null:
		current_record_button.disabled = current_record_id.is_empty() or not history_store.has_record(current_record_id)
	if history_notice != null:
		history_notice.text = "本局记录已保存" if not current_record_id.is_empty() and history_store.has_record(current_record_id) else ""
		if history_store.pending.has(current_record_id):
			history_notice.text = "记录保存未完成，请在对局记录中重试。"

func _open_history(id: String = "") -> void:
	if has_started and not result_shown:
		return
	history_panel.open_history()
	if not id.is_empty():
		history_panel.open_record(id)

func _input(event: InputEvent) -> void:
	if workshop.visible or history_panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11:
				_toggle_fullscreen()
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				if has_started:
					_toggle_pause()
					get_viewport().set_input_as_handled()
			KEY_R:
				_start_battle()
				get_viewport().set_input_as_handled()

func _build_audio() -> void:
	# Headless verification has no output device or audio mix loop.
	if DisplayServer.get_name() == "headless":
		_set_volume(volume_slider.value)
		return
	hit_sound = load("res://assets/audio/hit.mp3")
	for i in range(4):
		var player := AudioStreamPlayer.new()
		player.stream = hit_sound
		player.max_polyphony = 4
		add_child(player)
		audio_players.append(player)
	_set_volume(volume_slider.value)

func _play_hit() -> void:
	if volume_slider.value <= 0 or audio_players.is_empty():
		return
	audio_players[audio_index].volume_db = -8.0 if game_audio != null and game_audio.memory_voice_active else 0.0
	audio_players[audio_index].play()
	audio_index = (audio_index + 1) % audio_players.size()


func _exit_tree() -> void:
	for player in audio_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	audio_players.clear()
	hit_sound = null

func _set_volume(value: float) -> void:
	volume_label.text = "总音量 %d%%" % value
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value / 100.0, 0.0001)))
	AudioServer.set_bus_mute(0, value <= 0)

func _update_music() -> void:
	if music_label != null:
		music_label.text = "%d%%" % music_slider.value
	if game_audio != null:
		game_audio.apply_music_settings(music_toggle.button_pressed,music_slider.value)

func _save_settings() -> void:
	if qa_mode:
		return
	var config := ConfigFile.new()
	config.set_value("audio","volume",volume_slider.value)
	config.set_value("audio","music_enabled",music_toggle.button_pressed)
	config.set_value("audio","music_volume",music_slider.value)
	config.set_value("migration","map_default_500",map_default_migrated)
	config.set_value("match","last_seed",last_seed)
	config.set_value("match","configuration_v2",match_panel.serialize())
	config.save(settings_path)

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	volume_slider.value = float(config.get_value("audio","volume",35))
	music_toggle.set_pressed_no_signal(bool(config.get_value("audio","music_enabled",true)))
	music_slider.set_value_no_signal(clampf(float(config.get_value("audio","music_volume",50)),0,100))
	_update_music()
	last_seed = clampi(int(config.get_value("match","last_seed",config.get_value("match","seed",0))),0,999999)
	var match_data = config.get_value("match","configuration_v2",{})
	if match_data is Dictionary and not match_data.is_empty():
		match_data = load("res://scripts/core/settings_migration.gd").map_configuration(match_data,bool(config.get_value("migration","map_default_500",false)))
		match_panel.restore(match_data)
	else:
		# Old selections were roster indices. Resolve them once into stable IDs.
		var old_roles = config.get_value("match","roles",[0,3])
		var old_moves = config.get_value("match","moves",[0,3])
		for i in range(2):
			if old_roles is Array and old_roles.size() > i:
				match_panel.slot_data[i].character_id = roster[clampi(int(old_roles[i]),0,roster.size()-1)].id
			if old_moves is Array and old_moves.size() > i:
				match_panel.slot_data[i].movement = MOVE_IDS[clampi(int(old_moves[i]),0,3)]
		match_panel.rebuild_rows()
	map_default_migrated = true
	if not config.has_section_key("migration","map_default_500"):
		_save_settings()

func _capture_smoke() -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("user://ui-smoke.png" if OS.has_feature("android") else "res://build/ui-smoke.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	get_viewport().get_texture().get_image().save_png(path)
	print("UI_CAPTURE ", path)
