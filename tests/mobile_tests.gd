extends SceneTree
var checks: int = 0
var failures: int = 0
var ui

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("MOBILE FAIL: " + message)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test-results/mobile-"+name+".png")) == OK,"Capture mobile "+name)

func _run() -> void:
	ui = load("res://main.tscn").instantiate()
	ui.qa_mode = true
	ui.mobile_mode = true
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui.board.set_process(false)
	check(ui.mobile_page == "config" and ui.config_panel.visible and not ui.arena_column.visible,"Phone starts on config page")
	check(not ui.fullscreen_button.visible and ui.mobile_page_button.visible,"Mobile navigation replaces desktop fullscreen")
	check(not quit_on_go_back,"System back is handled by game navigation instead of auto-exit")
	check(ui.pause_button.custom_minimum_size.y >= 48,"Phone buttons have a touch target")
	check(root.content_scale_size == Vector2i(720,1280),"Mobile logical viewport is portrait")
	await capture("config")
	ui.match_panel.count_input.value = 8
	ui.match_panel.mode_option.select(1)
	ui.match_panel.rebuild_rows()
	ui._update_configuration()
	check(ui.match_panel.role_options.size() == 8,"Phone exposes eight role slots")
	ui._start_battle()
	check(ui.mobile_page == "battle" and ui.arena_column.visible and not ui.config_panel.visible,"Starting opens full battle page")
	check(ui.mobile_toolbar.visible and ui.arena.fighters.size() == 8,"Battle has touch controls and all actors")
	ui._process(0.1)
	await capture("battle")
	ui._show_mobile_page("config")
	check(ui.paused and ui.board.frozen,"Opening config during combat pauses")
	ui._show_mobile_page("battle")
	check(ui.paused,"Going back does not silently resume")
	ui._toggle_pause()
	ui._set_backgrounded(true)
	var elapsed: float = ui.arena.elapsed
	ui._process(0.5)
	check(ui.arena.elapsed == elapsed and ui.paused,"Backgrounding freezes combat")
	check(ui.game_audio.silent_runtime or ui.game_audio.music_player.stream_paused,"Backgrounding pauses real audio when a mixer exists")
	ui._set_backgrounded(false)
	check(ui.paused and not ui.game_audio.music_player.stream_paused,"Foreground resumes sound but waits to resume combat")
	ui._handle_mobile_back()
	check(ui.mobile_page == "config","System back from battle opens config")
	ui._return_to_selection()
	check(ui.mobile_page == "config" and ui.arena.fighters.is_empty(),"Return clears match and opens config")
	ui.workshop.open_editor()
	check(ui.workshop.mobile_pages.get_tab_count() == 3,"Editor splits library, attributes and preview into three mobile pages")
	ui.workshop.mobile_pages.current_tab = 1
	check(ui.workshop.file_dialog.use_native_dialog and ui.workshop.file_dialog.access == FileDialog.ACCESS_FILESYSTEM,"Android PNG uses system file picker")
	check(ui.workshop.file_dialog.filters[0].contains("image/png"),"File picker includes Android PNG MIME filter")
	await capture("editor")
	ui.workshop._open_art_browser("normal")
	check(ui.workshop.art_browser.visible and ui.workshop.art_items.size() == 416,"Phone retains searchable sticker library")
	ui._handle_mobile_back()
	check(not ui.workshop.art_browser.visible and ui.workshop.visible,"Back closes popup before editor")
	ui.workshop._mark_dirty()
	ui._handle_mobile_back()
	check(ui.workshop.leave_dialog.visible and ui.workshop.visible,"Back protects unsaved editor changes")
	ui.workshop.leave_dialog.hide()
	ui.workshop.dirty = false
	ui._handle_mobile_back()
	check(not ui.workshop.visible,"Clean editor returns normally")
	ui._handle_mobile_back()
	check(ui.mobile_exit_dialog.visible,"Config back asks before exiting")
	ui.mobile_exit_dialog.hide()
	ui.free()
	await create_timer(0.15).timeout
	print("MOBILE CHECKS: ",checks," failures: ",failures)
	if failures == 0:
		print("MOBILE TESTS PASSED")
	quit(0 if failures == 0 else 1)
