extends SceneTree
## Native render benchmark. The match uses high HP so all 8 remain active.
var ui
var time_passed: float = 0
var measured_time: float = 0
var frames: int = 0
var started: bool = false
var kit: String = "sword"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Native rendering required for performance test.")
		quit(1)
		return
	if "--fireball" in OS.get_cmdline_user_args():
		kit = "mage"
	if "--bat" in OS.get_cmdline_user_args():
		kit = "destruction_trailblazer"
	ui = load("res://main.tscn").instantiate()
	ui.qa_mode = true
	root.add_child(ui)
	await process_frame
	ui.match_panel.count_input.set_value_no_signal(8)
	var compact: bool = "--compact" in OS.get_cmdline_user_args()
	ui.match_panel.width_input.set_value_no_signal(500 if compact else 1000)
	ui.match_panel.height_input.set_value_no_signal(500 if compact else 700)
	if "--teams" in OS.get_cmdline_user_args():
		ui.match_panel.mode_option.select(1)
	var definition = ui.library.get_character(kit)
	definition.max_health = 100000
	definition.attack = 0.1
	for slot in ui.match_panel.slot_data:
		slot.character_id = kit
		slot.movement = "kite" if kit == "mage" else "bounce"
	ui.match_panel.rebuild_rows()
	ui._update_configuration()
	ui._set_speed(2)
	ui._start_battle()
	started = true

func _process(delta: float) -> bool:
	if not started:
		return false
	time_passed += delta
	if time_passed >= 1.0:
		measured_time += delta
		frames += 1
	if time_passed > 4.0:
		started = false
		var fps: float = frames / maxf(0.001,measured_time)
		var alive: int = 0
		for fighter in ui.arena.fighters:
			if fighter.alive:
				alive += 1
		print("PERFORMANCE kit=",kit," actors=",alive," mode=",ui.arena.mode," map=",ui.arena.bounds.size," speed=2x fps=",snappedf(fps,0.1)," projectiles=",ui.arena.projectiles.size())
		_capture_and_quit.call_deferred(fps,alive)
	return false

func _capture_and_quit(fps: float,alive: int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test-results/performance-" + kit + ".png"))
	ui.free()
	await create_timer(0.15).timeout
	quit(0 if fps >= 60 and alive == 8 else 1)
