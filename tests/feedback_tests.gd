extends SceneTree
const Arena = preload("res://scripts/core/battle_arena.gd")
const Config = preload("res://scripts/core/match_config.gd")
const Definition = preload("res://scripts/core/character_definition.gd")
const Migration = preload("res://scripts/core/settings_migration.gd")
const DT := 1.0/60.0
var arena
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FEEDBACK FAIL: " + message)

func start(team_mode: bool = false) -> void:
	var config = Config.new()
	config.mode = "teams" if team_mode else "ffa"
	for i in range(3):
		var definition = Definition.new()
		definition.speed = 120
		definition.max_health = 10000
		config.participants.append({"definition":definition,"movement":"chase","team":0 if team_mode and i < 2 else i})
	check(arena.start_match(config).is_empty(),"500-square test starts")
	for i in range(3):
		arena.fighters[i].position = Vector2(150 + i * 150,300)

func tick(count: int) -> void:
	for i in range(count):
		arena.step(DT)
		arena.drain_events()

func _run() -> void:
	arena = Arena.new()
	root.add_child(arena)
	_test_impacts()
	_test_weapons()
	_test_migration()
	_test_determinism_and_restarts()
	arena.clear_battle()
	arena.free()
	await _test_ui_audio_and_departures()
	print("FEEDBACK CHECKS: ",checks," failures: ",failures)
	if failures == 0:
		print("FEEDBACK TESTS PASSED")
	quit(0 if failures == 0 else 1)

func _test_impacts() -> void:
	start()
	var source = arena.fighters[0]
	var target = arena.fighters[1]
	arena.apply_damage(source,target,100,"heavy",true,Vector2.RIGHT * 1100)
	check(target.knockback == Vector2.ZERO,"Impact waits for accepted damage settlement")
	arena.step(DT)
	check(target.health == 9900 and target.knockback.x == 1100,"Damage and impulse settle atomically")
	var origin: Vector2 = target.position
	arena.step(DT)
	check(target.position.x > origin.x and target.velocity.x > 1000,"Impact overrides chasing back toward attacker")
	check(target.impact_angle < 0,"Impact rotates counterclockwise")
	var angle: float = target.impact_angle
	arena.apply_damage(source,target,20,"heavy",true,Vector2.UP * 900)
	arena.step(DT)
	check(target.knockback == Vector2.UP * 900 and target.impact_angle <= angle,"Repeated hit redirects without resetting angle")
	tick(60)
	check(target.impact_remaining == 0 and target.impact_angle == 0 and target.knockback == Vector2.ZERO,"Impact decays and returns upright")
	start()
	source = arena.fighters[0]
	target = arena.fighters[1]
	arena.add_shield(target,300,2)
	arena.apply_damage(source,target,100,"shielded",true,Vector2.RIGHT * 900)
	arena.step(DT)
	check(target.health == 10000 and target.shield == 200 and target.impact_remaining > 0,"Absorbed hit still knocks back")
	start(true)
	source = arena.fighters[0]
	target = arena.fighters[1]
	arena.apply_damage(source,target,100,"friendly",true,Vector2.RIGHT * 900)
	arena.apply_damage(source,target,0,"zero",true,Vector2.RIGHT * 900)
	arena.step(DT)
	check(target.health == 10000 and target.impact_remaining == 0,"Rejected friendly hit cannot knock back")
	start()
	source = arena.fighters[0]
	target = arena.fighters[1]
	arena.apply_damage(source,target,10,"ordinary")
	arena.step(DT)
	check(target.health == 9990 and target.impact_remaining == 0,"Ordinary damage does not create heavy feedback")
	for axis in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		start()
		source = arena.fighters[0]
		target = arena.fighters[1]
		target.position = arena.bounds.get_center() + axis * (250-target.definition.radius)
		arena.apply_damage(source,target,10,"wall",true,axis * 1100)
		tick(45)
		check(arena.bounds.grow(-target.definition.radius+0.01).has_point(target.position),"Heavy hit stays inside wall")
		check(target.impact_remaining == 0 and target.impact_angle == 0,"Wall impact recovers without permanent rotation")
	start()
	source = arena.fighters[0]
	target = arena.fighters[1]
	tar_get_dash(target)
	arena.apply_damage(source,target,10,"dash_stop",true,Vector2.RIGHT * 900)
	arena.step(DT)
	arena.step(DT)
	check(target.velocity.x > 0 and target.dash_remaining < 0.4,"Hit suppresses dash displacement while its clock continues")

func tar_get_dash(target) -> void:
	target.dash_velocity = Vector2.LEFT * 1000
	target.dash_remaining = 0.4

func _test_weapons() -> void:
	var library = load("res://scripts/core/character_library.gd").new("user://qa_feedback_empty")
	library.reload()
	var config = Config.new()
	var hero = library.get_character("destruction_trailblazer").duplicate(true)
	hero.speed = 0
	var dummy = Definition.new()
	dummy.max_health = 10000
	dummy.speed = 0
	config.participants = [{"definition":hero,"movement":"bounce","team":0},{"definition":dummy,"movement":"bounce","team":1}]
	for returning in [false,true]:
		check(arena.start_match(config).is_empty(),"Bat impulse test starts")
		var fighter = arena.fighters[0]
		var enemy = arena.fighters[1]
		fighter.position = Vector2(150,300)
		enemy.position = Vector2(320,300)
		var bat = fighter.skills[0]
		bat.activate(enemy)
		bat.bat_state = "returning" if returning else "outbound"
		var begin := Vector2(380,300) if returning else Vector2(260,300)
		var end := Vector2(260,300) if returning else Vector2(380,300)
		bat._damage_on_segment(begin,end)
		arena._resolve_damage()
		check(enemy.knockback.x == (-900 if returning else 900),"Bat uses actual outbound/return segment direction")
		var health: float = enemy.health
		bat._damage_on_segment(end,begin)
		arena._resolve_damage()
		check(enemy.health == health,"Bat retains round-trip hit debounce")
	for role in ["guard","assassin"]:
		var definition = library.get_character(role).duplicate(true)
		config.participants[0].definition = definition
		check(arena.start_match(config).is_empty(),"Existing impact skill starts")
		var fighter = arena.fighters[0]
		var enemy = arena.fighters[1]
		fighter.position = Vector2(200,300)
		enemy.position = Vector2(255,300)
		var skill = fighter.skills[0]
		if role == "guard":
			skill.activate(enemy)
		else:
			fighter.dash_velocity = Vector2.RIGHT * 800
			skill._hit_target(enemy)
		arena._resolve_damage()
		check(enemy.knockback.x > 0 and enemy.impact_remaining > 0,"Existing close-range skill uses unified feedback")

func _test_migration() -> void:
	check(Config.new().width == 500 and Config.new().height == 500,"Core default is 500 by 500")
	var old := {"width":664,"height":664,"count":8}
	var migrated: Dictionary = Migration.map_configuration(old,false)
	check(migrated.width == 500 and migrated.height == 500 and old.width == 664,"Legacy defaults migrate without mutating source")
	check(Migration.map_configuration(old,true).width == 664,"Migration marker preserves later intentional 664 map")
	check(Migration.map_configuration({"width":1200,"height":700},false).width == 1200,"Custom map survives upgrade")
	check(Migration.map_configuration({"width":664,"height":500},false).width == 664,"Mixed custom dimensions survive upgrade")

func _complete(config) -> Array:
	check(arena.start_match(config).is_empty(),"Eight-person match fits 500-square map")
	var budget: int = 5401
	while arena.running and budget > 0:
		arena.step(DT)
		arena.drain_events()
		budget -= 1
	check(not arena.running,"Eight-person match completes")
	var summary: Array = [arena.winner_team,arena.tick_count]
	for fighter in arena.fighters:
		summary.append([fighter.health,fighter.position,fighter.impact_angle])
	return summary

func _test_determinism_and_restarts() -> void:
	var roles: Array = load("res://data/roster.gd").get_all()
	var config = Config.new()
	for i in range(8):
		config.participants.append({"definition":roles[i % roles.size()],"movement":"bounce","team":i%2})
	for mode in ["ffa","teams"]:
		config.mode = mode
		check(_complete(config) == _complete(config),"Seed reproduces outcome, position and rotation")
	for i in range(100):
		config.mode = "ffa" if i % 2 == 0 else "teams"
		config.seed_value = i+10
		_complete(config)
		arena.clear_battle()
		check(arena.fighters.is_empty() and arena.projectiles.is_empty() and arena.get_child_count() == 0,"100 complete eight-player restarts release combat state")

func _test_ui_audio_and_departures() -> void:
	var ui = load("res://main.tscn").instantiate()
	ui.qa_mode = true
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui.board.set_process(false)
	check(ui.match_panel.width_input.value == 500 and ui.match_panel.height_input.value == 500,"UI map default matches core")
	check(ui.music_toggle.button_pressed and ui.music_slider.value == 50,"Music defaults on at fifty percent")
	check(ui.game_audio.music_player.stream.loop,"Background stream loops")
	check(ui.game_audio.music_player.stream.get_length() > 100 and ui.game_audio.cheer_player.stream.get_length() > 2,"Delivered music and cheer decode")
	ui.music_toggle.button_pressed = false
	check(ui.game_audio.music_player.volume_linear == 0 and not ui.game_audio.enabled,"Music off mutes only its player")
	ui.music_slider.value = 0
	ui.music_toggle.button_pressed = true
	check(ui.game_audio.enabled and ui.game_audio.music_volume == 0,"Zero music volume preserves enabled switch")
	ui.music_slider.value = 67
	ui._set_speed(2)
	check(ui.game_audio.music_player.pitch_scale == 1,"Battle speed does not pitch music")
	ui.settings_path = "user://qa_feedback_settings.cfg"
	var saved = ConfigFile.new()
	saved.set_value("match","configuration_v2",{"width":664,"height":664})
	saved.save(ui.settings_path)
	ui.qa_mode = false
	ui._load_settings()
	saved.load(ui.settings_path)
	check(ui.match_panel.width_input.value == 500 and saved.get_value("migration","map_default_500",false),"Upgrade persists migration marker")
	ui.match_panel.width_input.value = 664
	ui.match_panel.height_input.value = 664
	ui.music_toggle.button_pressed = false
	ui.music_slider.value = 67
	ui._save_settings()
	ui.music_toggle.button_pressed = true
	ui.music_slider.value = 50
	ui._load_settings()
	check(not ui.music_toggle.button_pressed and ui.music_slider.value == 67,"Music switch and volume survive disk reload")
	check(ui.match_panel.width_input.value == 664,"Marked migration never overwrites later custom map")
	DirAccess.remove_absolute(ui.settings_path)
	ui.qa_mode = true
	ui._set_speed(1)
	ui._start_battle()
	var origin: Vector2 = ui.arena.fighters[1].position
	ui.arena.apply_damage(ui.arena.fighters[0],ui.arena.fighters[1],100000,"lethal",true,Vector2.RIGHT * 1100)
	ui._process(DT)
	check(not ui.arena.fighters[1].alive and not ui.arena.running and not ui.result_shown,"Lethal hit immediately eliminates but delays overlay")
	origin = ui.board.departures[1].origin
	var cheers: int = ui.game_audio.cheer_count
	ui.board._process(0.49)
	check(ui.board.departure_pose(1).position == origin and ui.game_audio.cheer_count == cheers,"Dead actor holds its exact position for half a second")
	ui._toggle_pause()
	ui.board._process(0.5)
	check(ui.board.departures[1].age < 0.5,"Pause freezes the death hold after combat ends")
	ui._toggle_pause()
	ui.board._process(0.02)
	check(ui.game_audio.cheer_count == cheers+1 and ui.board.departure_pose(1).position.x > origin.x,"Cheer starts exactly once with ejection")
	ui._set_speed(2)
	ui.board._process(0.23)
	ui._process(DT)
	check(not ui.board.has_departures() and ui.result_shown,"Accelerated departure finishes before results")
	ui._start_battle()
	check(ui.board.departures.is_empty(),"Rematch clears all departure animations")
	ui.match_panel.count_input.value = 3
	ui._start_battle()
	ui.arena.fighters[1].health = 0
	ui._process(DT)
	check(ui.arena.running and ui.board.has_departures(),"Mid-match elimination departs while survivors continue")
	var combat_time: float = ui.arena.elapsed
	ui.board._process(0.96)
	ui._process(DT)
	check(ui.arena.elapsed > combat_time and not ui.result_shown,"Non-final departure never opens result overlay")
	ui.match_panel.count_input.value = 8
	ui._start_battle()
	for fighter in ui.arena.fighters:
		fighter.health = 0
	ui._process(DT)
	check(ui.arena.winner_team == -1 and ui.board.departures.size() == 8,"Simultaneous death keeps draw and all departures")
	ui.board._process(0.5)
	var count: int = ui.game_audio.cheer_count
	ui.board._process(0.5)
	check(ui.game_audio.cheer_count == count,"Simultaneous deaths coalesce cheering without repeat")
	ui._process(DT)
	check(ui.result_shown,"Draw overlay waits for all exits")
	ui._return_to_selection()
	check(ui.board.departures.is_empty() and not ui.game_audio.cheer_player.playing,"Return clears exits and stops cheer")
	ui.free()
	await create_timer(0.15).timeout
