extends SceneTree
## Real UI integration checks. Does not alter player preferences or content files.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("UI FAIL: " + message)

func _run() -> void:
	var ui = load("res://main.tscn").instantiate()
	ui.qa_mode = true
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui.board.set_process(false)
	verify(ui.roster.size() == 4, "Four selectable characters")
	verify(ui.role_options[0].item_count == 4, "Roster displayed in selection")
	verify(ui.move_options[0].item_count == 4, "Four selectable movements")
	verify(not ui.has_started and ui.pause_button.disabled, "Initial state")
	ui._on_role_selected(1, 0)
	verify(ui.match_panel.slot_data[0].character_id == "mage", "Selecting character updates participant")
	verify(ui.move_options[0].selected == 2, "Selecting mage applies keep-distance default")
	ui._on_role_selected(0, 0)
	# Exercise a real transparent PNG decode without supplying pretend final artwork.
	var img := Image.create(96, 160, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	img.fill_rect(Rect2i(18, 16, 60, 128), Color("86e3c7"))
	var decoded := Image.new()
	verify(decoded.load_png_from_buffer(img.save_png_to_buffer()) == OK, "PNG alpha decoding")
	var visual_definition = ui.roster[0].duplicate()
	visual_definition.portrait = ImageTexture.create_from_image(decoded)
	visual_definition.portrait_size = 90.0
	visual_definition.portrait_offset = Vector2(4, -3)
	ui.library.characters[0] = visual_definition
	ui._update_configuration()
	verify(visual_definition.portrait.get_size() == Vector2(96, 160), "PNG aspect ratio retained")
	ui.seed_input.value = 2718
	ui._start_battle()
	verify(ui.arena.running and ui.has_started, "Start transitions to running battle")
	verify(ui.role_options[0].disabled and ui.move_options[1].disabled, "Selection locks during battle")
	verify(ui.random_button.disabled and not ui.seed_input.editable, "Seed cannot change during battle")
	verify(ui.arena.seed_value == 2718, "Selected seed reaches simulation")
	for _i in range(60):
		ui._process(1.0 / 60.0)
	verify(absf(ui.arena.elapsed - 1.0) < 0.00001, "One second at normal speed")
	ui._toggle_pause()
	var elapsed: float = ui.arena.elapsed
	var visual_time: float = ui.board.visual_time
	ui._process(0.25)
	ui.board._process(0.25)
	verify(ui.arena.elapsed == elapsed and ui.board.visual_time == visual_time, "Pause freezes simulation and effects")
	ui._set_speed(2.0)
	ui._toggle_pause()
	ui._process(0.1)
	verify(absf(ui.arena.elapsed - elapsed - 0.2) < 0.017, "Double-speed advances two tenths")
	ui._set_speed(0.5)
	elapsed = ui.arena.elapsed
	ui._process(0.2)
	verify(absf(ui.arena.elapsed - elapsed - 0.1) < 0.017, "Half-speed advances one tenth")
	ui._set_volume(0)
	verify(AudioServer.is_bus_mute(0), "Zero volume mutes audio")
	ui._set_volume(35)
	verify(not AudioServer.is_bus_mute(0), "Positive volume restores audio")
	ui.board.ingest([{"kind": "hit", "position": Vector2(300, 300), "side": 0, "amount": 40}])
	ui.board._process(0.03)
	ui.board.queue_redraw()
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := ProjectSettings.globalize_path("res://test-results/ui-png-branch.png")
		DirAccess.make_dir_recursive_absolute(screenshot.get_base_dir())
		verify(root.get_texture().get_image().save_png(screenshot) == OK, "PNG portrait branch renders to viewport")
	ui.arena.fighters[1].health = 0.0
	ui._process(0.1)
	verify(ui.result_shown and ui.result_panel.visible and not ui.arena.running, "Death opens result panel")
	verify(ui.result_detail.text.contains("2718"), "Result displays actual match seed")
	ui.board._process(1.0)
	verify(ui.board.hit_flashes.get(0, 0.0) == 0.0, "Hit flash fades after simulation ends")
	ui._start_battle()
	verify(not ui.result_panel.visible and ui.arena.elapsed == 0.0, "Rematch resets result and clock")
	ui._return_to_selection()
	verify(ui.arena.fighters.is_empty() and ui.arena.get_child_count() == 0, "Return clears runtime skills")
	verify(not ui.role_options[0].disabled and not ui.random_button.disabled, "Return unlocks character and seed")
	verify(ui.board.preview_definitions.size() == 2, "Preview restores both portraits")
	# Editor and content persistence, using the isolated qa_mode library.
	var editor = ui.workshop
	editor.open_editor()
	verify(editor.art_items.size() == 416, "Supplied sticker pack is indexed")
	editor._open_art_browser("normal")
	editor.art_search.text = "姬子"
	editor._filter_art()
	verify(editor.filtered_art.size() >= 3, "Sticker browser searches character names")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test-results/sticker-browser.png"))
	editor._use_browser_image()
	editor.art_browser.hide()
	verify(editor.draft.normal_image_path.begins_with("res://assets/stickers/"), "Sticker selection assigns packaged PNG")
	editor._select_skill(0)
	editor._open_art_browser("charge")
	editor.art_search.text = "蓄势待发"
	editor._filter_art()
	editor._use_browser_image()
	editor.art_browser.hide()
	verify(editor.draft.skill_slots[0].charge_image.contains("蓄势待发"), "Sticker selection assigns per-skill charge art")
	editor._new_character()
	var custom_id: String = editor.draft.id
	editor.fields.name.text = "界面测试角色"
	editor.fields.health.value = 2468
	editor.fields.attack.value = 55
	editor._changed()
	verify(editor.dirty and editor.draft.max_health == 2468, "Editor fields update unsaved draft")
	ui._on_close_requested()
	verify(editor.leave_dialog.visible, "Closing window with unsaved edit requests a choice")
	editor.leave_dialog.hide()
	verify(editor.save_draft(), "Editor saves custom character")
	verify(ui.library.get_character(custom_id) != null, "Saved character is available for match selection")
	var image := Image.create(72,96,false,Image.FORMAT_RGBA8)
	image.fill(Color(0.6,0.85,1,0.6))
	var png_source := "user://qa-ui-source.png"
	image.save_png(png_source)
	editor.pending_image = "normal"
	editor.import_image(png_source)
	verify(editor.draft.portrait != null, "Editor imports normal PNG")
	editor._select_skill(0)
	editor.pending_image = "charge"
	editor.import_image(png_source)
	editor.pending_image = "release"
	editor.import_image(png_source)
	editor.charge_input.value = 0.5
	editor.release_input.value = 0.4
	editor.movement_check.button_pressed = false
	editor._skill_changed()
	verify(editor.save_draft(), "Editor saves independent skill images and timings")
	DirAccess.remove_absolute(png_source)
	editor._select_character(ui.library.index_of(custom_id))
	verify(editor.draft.portrait != null and editor.draft.skill_slots[0].charge_time == 0.5, "Reloading editor restores owned PNG and timing")
	editor.preview_mode.select(1)
	editor._refresh_preview()
	verify(editor.preview_board.preview_definitions[0].portrait != null, "Charge-image preview loads")
	editor.play_preview()
	verify(editor.preview_arena.fighters[0].visual_phase == "charge", "Skill preview starts real charge")
	for _i in range(32):
		editor._process(1.0/60.0)
	verify(editor.preview_arena.fighters[0].visual_phase == "release", "Skill preview transitions into release")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test-results/editor-preview.png"))
	editor._refresh_preview()
	editor.hide()
	ui.match_panel.count_input.value = 8
	ui.match_panel.mode_option.select(1)
	ui.match_panel.width_input.value = 1200
	ui.match_panel.height_input.value = 700
	for i in range(8):
		ui.match_panel.slot_data[i].team = i % 4
	ui.match_panel.rebuild_rows()
	ui._update_configuration()
	verify(ui.role_options.size() == 8 and ui.board.preview_definitions.size() == 8, "Eight participant rows and previews")
	ui._start_battle()
	verify(ui.arena.running and ui.arena.fighters.size() == 8, "Eight-person team match starts from UI")
	verify(ui.arena.bounds.size == Vector2(1200,700), "Rectangular map reaches simulation")
	if DisplayServer.get_name() != "headless":
		ui._process(1.0/60.0)
		ui.board.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test-results/eight-person-layout.png"))
		verify(ui.board.world_size == Vector2(1296,796), "Renderer uses rectangular world size")
	for fighter in ui.arena.fighters:
		if fighter.team_id != 2:
			fighter.health = 0
	ui._process(0.1)
	verify(ui.result_title.text == "C 队获胜", "Team winner is displayed by team, not actor index")
	ui._return_to_selection()
	var restored = load("res://scripts/core/character_library.gd").new(ui.library.storage_root)
	restored.reload()
	verify(restored.get_character(custom_id).max_health == 2468, "Separate library instance restores UI save")
	ui.library.remove_or_restore(custom_id)
	ui._library_changed()
	print("UI CHECKS: ", checks, " failures: ", failures)
	if failures == 0:
		print("UI TESTS PASSED")
	ui.free()
	# Let the audio mixer release queued playback references before engine shutdown.
	await create_timer(0.15).timeout
	quit(0 if failures == 0 else 1)
