extends SceneTree
var ui
var checks: int = 0
var failures: int = 0
var visual: bool = false

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CURRENT UI FAIL: " + message)

func capture(name: String) -> void:
	if not visual:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/sparkle-"+name+".png"))

func _run() -> void:
	visual = DisplayServer.get_name() != "headless"
	ui = load("res://main.tscn").instantiate()
	ui.qa_mode = true
	ui.mobile_mode = "--mobile" in OS.get_cmdline_user_args()
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui.board.set_process(false)
	check(ui.roster.size() == 3 and ui.role_options[0].item_count == 3,"Current three characters appear in selection")
	check(ui.match_panel.slot_data[1].character_id == "sparkle","Default matchup includes Sparkle")
	var editor = ui.workshop
	editor.open_editor()
	editor._select_character(ui.library.index_of("sparkle"))
	editor._select_skill(0)
	check(editor.parameter_fields.has("reload_time") and editor.parameter_fields.has("bullet_damage") and editor.parameter_fields.has("bullet_speed"),"Revolver numeric fields appear automatically")
	editor._copy_character()
	var custom_id: String = editor.draft.id
	editor.parameter_fields.bullet_damage.value = 345
	editor.parameter_fields.reload_time.value = 2.5
	check(editor.draft.skill_slots[0].parameters.bullet_damage == 345,"Editing a field changes only draft parameters")
	check(editor.save_draft(),"Parameterized role saves")
	var saved = ui.library.get_character(custom_id)
	check(saved.skill_slots[0].parameters.reload_time == 2.5 and saved.skill_slots[0].parameters.bullet_damage == 345,"Saved numeric overrides reload")
	ui.library.remove_or_restore(custom_id)
	ui._library_changed()
	editor._select_character(ui.library.index_of("destruction_trailblazer"))
	editor._select_skill(0)
	check(editor.parameter_fields.has("throw_distance") and editor.parameter_fields.has("return_damage"),"Bat distance and each leg damage are editable")
	if ui.mobile_mode:
		editor.mobile_pages.current_tab = 1
		var tabs: TabContainer = editor.mobile_pages.get_child(1)
		tabs.current_tab = 2
	await capture("parameters")
	editor.dirty = false
	editor.hide()
	var sparkle = ui.library.get_character("sparkle")
	sparkle.speed = 0
	for i in range(2):
		ui.match_panel.slot_data[i].character_id = "sparkle"
	ui.match_panel.rebuild_rows()
	ui._update_configuration()
	ui._start_battle()
	ui.arena.fighters[0].position = Vector2(155,300)
	ui.arena.fighters[1].position = Vector2(440,300)
	for fighter in ui.arena.fighters:
		var gun = fighter.skills[0]
		gun.state = "firing"
		gun.loaded_chamber = 5
		gun.chamber = 0
		gun.shot_remaining = 0
	ui._process(1.0/60)
	ui.board._process(1.0/60)
	check(ui.game_audio.weapon_event_count >= 2,"Dry-fire sound reaches audio system")
	check(ui.arena.fighters[0].facing == 1 and ui.arena.fighters[1].facing == -1,"Two revolvers face each other")
	await capture("empty")
	for fighter in ui.arena.fighters:
		fighter.skills[0].chamber = 5
		fighter.skills[0].shot_remaining = 0
	ui._process(1.0/60)
	ui.board._process(1.0/60)
	check(ui.arena.projectiles.size() == 2 and ui.arena.projectiles[0].visual_type == "red_bullet","Live shots spawn red projectiles")
	await capture("live")
	ui._toggle_pause()
	var count: int = ui.arena.fighters[0].skills[0].shots_count
	ui._process(1)
	check(ui.arena.fighters[0].skills[0].shots_count == count,"Pause freezes revolver mechanism")
	ui._toggle_pause()
	ui.arena.fighters[1].health = 0
	ui._process(.1)
	ui.board._process(1.0)
	ui._process(.01)
	check(ui.result_shown,"Current match still reaches result overlay after departure")
	ui._return_to_selection()
	check(ui.arena.fighters.is_empty(),"Return cleans the current weapons and projectiles")
	ui.free()
	await create_timer(.15).timeout
	print("CURRENT UI CHECKS: ",checks," failures: ",failures)
	if failures == 0:
		print("CURRENT UI TESTS PASSED")
	quit(0 if failures == 0 else 1)
