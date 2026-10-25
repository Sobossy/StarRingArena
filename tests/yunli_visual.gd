extends SceneTree
var ui
const DT := 1.0/60.0

func _initialize() -> void:
	_run.call_deferred()

func advance(count: int) -> void:
	for i in range(count):
		ui._process(DT)
		ui.board._process(DT)

func capture(name: String) -> void:
	ui.board.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/yunli-"+name+".png"))

func _run() -> void:
	ui = load("res://main.tscn").instantiate()
	ui.qa_mode = true
	ui.mobile_mode = true
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui.board.set_process(false)
	ui.library.get_character("yunli").speed = 0
	var dummy = ui.library.get_character("sparkle")
	dummy.speed = 0
	dummy.max_health = 10000
	dummy.skill_slots.clear()
	dummy.skill_scenes.clear()
	ui.match_panel.slot_data[0].character_id = "yunli"
	ui.match_panel.slot_data[1].character_id = "sparkle"
	ui.match_panel.rebuild_rows()
	ui._update_configuration()
	ui._start_battle()
	var owner = ui.arena.fighters[0]
	var enemy = ui.arena.fighters[1]
	owner.position = Vector2(420,300)
	enemy.position = Vector2(130,300)
	owner.health = 900
	advance(60)
	assert(owner.health == 930)
	await capture("eating")
	ui.arena.apply_damage(enemy,owner,100,"preview")
	advance(1)
	advance(60)
	ui.arena.apply_damage(enemy,owner,200,"preview")
	advance(1)
	assert(owner.visual_phase == "guard" and owner.health == 670)
	await capture("guard")
	while owner.skills[0].guarding:
		advance(1)
	assert(ui.arena.projectiles.size() == 1)
	await capture("throw")
	ui._return_to_selection()
	ui.workshop.open_editor()
	ui.workshop._select_character(ui.library.index_of("yunli"))
	ui.workshop._select_skill(0)
	assert(ui.workshop.parameter_fields.has("guard_duration") and ui.workshop.parameter_fields.has("counter_damage_ratio"))
	ui.workshop.play_preview()
	for i in range(255):
		ui.workshop._process(DT)
	assert(ui.workshop.preview_playing and ui.workshop.preview_arena.fighters[0].skills[0].throws_count == 1)
	print("YUNLI VISUAL OK: eating heal, guard image, counter throw, editable parameters and full preview")
	ui.free()
	await create_timer(.15).timeout
	quit()
