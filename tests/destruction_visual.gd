extends SceneTree
const DT := 1.0/60.0
var ui
var bat

func _initialize() -> void:
	_run.call_deferred()

func advance(ticks: int) -> void:
	for _tick in range(ticks):
		ui._process(DT)
		ui.board._process(DT)

func capture(name: String) -> void:
	ui.board.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/destruction-"+name+".png"))

func _run() -> void:
	ui = load("res://main.tscn").instantiate()
	ui.qa_mode = true
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui.board.set_process(false)
	var hero = ui.library.get_character("destruction_trailblazer")
	hero.speed = 0
	var dummy = ui.library.get_character("mage")
	dummy.speed = 0
	dummy.max_health = 10000
	dummy.skill_slots.clear()
	dummy.skill_scenes.clear()
	ui.match_panel.slot_data[0].character_id = "destruction_trailblazer"
	ui.match_panel.slot_data[1].character_id = "mage"
	ui.match_panel.rebuild_rows()
	ui._update_configuration()
	ui._start_battle()
	ui.arena.fighters[0].position = Vector2(210,420)
	ui.arena.fighters[1].position = Vector2(560,420)
	bat = ui.arena.fighters[0].skills[0]
	advance(180)
	await capture("charging")
	advance(190)
	assert(bat.is_in_flight())
	await capture("outbound")
	while bat.bat_state == "outbound":
		advance(1)
	advance(8)
	assert(bat.bat_state == "returning")
	await capture("returning")
	while bat.is_in_flight():
		advance(1)
	await capture("caught")
	advance(359)
	ui.arena.fighters[1].position = ui.arena.fighters[0].position + Vector2(55,0)
	advance(5)
	assert(bat.charge_elapsed < 0.1)
	await capture("collision")
	print("DESTRUCTION VISUAL OK: charge, outbound, returning, catch, collision")
	bat = null
	ui.free()
	await create_timer(0.15).timeout
	quit()
