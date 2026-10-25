extends SceneTree
## Native-window verification: screenshots plus actual music/cheer playback checks.
const DT := 1.0/60.0
var ui
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("VISUAL FAIL: " + message)

func advance(ticks: int) -> void:
	for i in range(ticks):
		ui._process(DT)
		ui.board._process(DT)

func capture(name: String) -> void:
	ui.board.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/feedback-"+name+".png")) == OK,"Capture "+name)

func _run() -> void:
	ui = load("res://main.tscn").instantiate()
	ui.qa_mode = true
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui.board.set_process(false)
	await create_timer(0.2).timeout
	check(ui.game_audio.music_player.playing and ui.game_audio.music_player.get_playback_position() > 0,"Native music really plays")
	await capture("selection")
	var position: float = ui.game_audio.music_player.get_playback_position()
	ui.music_toggle.button_pressed = false
	await create_timer(0.15).timeout
	check(ui.game_audio.music_player.playing and ui.game_audio.music_player.get_playback_position() > position,"Disabled music continues silently without restarting")
	ui.music_toggle.button_pressed = true
	ui.game_audio.music_player.seek(ui.game_audio.music_player.stream.get_length()-0.15)
	await create_timer(0.4).timeout
	check(ui.game_audio.music_player.playing and ui.game_audio.music_player.get_playback_position() < 2,"Music loops across its actual endpoint")
	var hero = ui.library.get_character("destruction_trailblazer")
	hero.speed = 0
	var dummy = ui.library.get_character("mage")
	dummy.speed = 0
	dummy.max_health = 10000
	dummy.skill_slots.clear()
	dummy.skill_scenes.clear()
	ui.match_panel.slot_data[0].character_id = hero.id
	ui.match_panel.slot_data[1].character_id = dummy.id
	ui.match_panel.rebuild_rows()
	ui._update_configuration()
	ui._start_battle()
	ui.arena.fighters[0].position = Vector2(180,300)
	ui.arena.fighters[1].position = Vector2(355,300)
	var source = ui.arena.fighters[0]
	var target = ui.arena.fighters[1]
	ui.arena.apply_damage(source,target,100,"visual_heavy",true,Vector2.RIGHT * 900)
	advance(6)
	check(target.impact_angle < 0 and target.position.x > 355,"Native image rotates and moves away")
	await capture("impact")
	advance(40)
	check(target.impact_angle == 0,"Native fighter recovers upright")
	await capture("recovered")
	ui.arena.apply_damage(source,target,100000,"visual_lethal",true,Vector2.UP * 1100)
	advance(1)
	var origin: Vector2 = target.position
	advance(17)
	check(ui.board.departure_pose(1).position == origin and not ui.result_shown,"Native dead actor holds before ejection")
	await capture("death-hold")
	advance(25)
	check(ui.game_audio.cheer_player.playing and ui.board.departure_pose(1).position.y < origin.y,"Native cheer and ejection play together")
	await capture("death-flight")
	advance(20)
	check(ui.result_shown,"Native overlay appears after exit")
	await capture("result")
	ui._return_to_selection()
	ui.match_panel.count_input.value = 8
	ui.match_panel.mode_option.select(1)
	for i in range(8):
		ui.match_panel.slot_data[i].team = i%2
	ui.match_panel.rebuild_rows()
	ui._update_configuration()
	ui._start_battle()
	advance(60)
	check(ui.arena.fighters.size() == 8 and ui.arena.bounds.size == Vector2(500,500),"Native eight-player 500-square match")
	await capture("eight-player")
	print("FEEDBACK VISUAL CHECKS: ",checks," failures: ",failures)
	ui.free()
	await create_timer(0.15).timeout
	quit(0 if failures == 0 else 1)
