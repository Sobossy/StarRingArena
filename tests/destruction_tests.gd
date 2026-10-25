extends SceneTree
const Arena = preload("res://scripts/core/battle_arena.gd")
const Config = preload("res://scripts/core/match_config.gd")
const Definition = preload("res://scripts/core/character_definition.gd")
const Library = preload("res://scripts/core/character_library.gd")
const Catalog = preload("res://scripts/core/skill_catalog.gd")
var arena
var library
var checks: int = 0
var failures: int = 0
const DT := 1.0/60.0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("BAT FAIL: " + message)

func _run() -> void:
	library = Library.new("user://qa_bat_empty")
	library.reload()
	arena = Arena.new()
	root.add_child(arena)
	_test_throw_and_return()
	_test_contact_interrupt()
	_test_friendly_and_cleanup()
	_test_settings_and_mirrors()
	arena.clear_battle()
	arena.free()
	print("DESTRUCTION CHECKS: ",checks," failures: ",failures)
	if failures == 0:
		print("DESTRUCTION TESTS PASSED")
	quit(0 if failures == 0 else 1)

func start(charge: float = 6.0, ally: bool = false) -> void:
	var definition = library.get_character("destruction_trailblazer").duplicate(true)
	definition.speed = 0
	definition.skill_slots[0].charge_time = charge
	var dummy = Definition.new()
	dummy.max_health = 10000
	dummy.speed = 0
	var config = Config.new()
	config.width = 664
	config.height = 664
	config.mode = "teams" if ally else "ffa"
	config.participants = [{"definition":definition,"movement":"bounce","team":0},{"definition":dummy,"movement":"bounce","team":0 if ally else 1}]
	if ally:
		config.participants.append({"definition":dummy,"movement":"bounce","team":1})
	check(arena.start_match(config).is_empty(),"Test match starts")
	arena.fighters[0].position = Vector2(200,380)
	arena.fighters[1].position = Vector2(600,380)
	if ally:
		arena.fighters[2].position = Vector2(620,600)

func advance(ticks: int) -> void:
	for _i in range(ticks):
		arena.step(DT)
		arena.drain_events()

func _test_throw_and_return() -> void:
	start()
	var fighter = arena.fighters[0]
	var enemy = arena.fighters[1]
	var bat = fighter.skills[0]
	check(bat.charge_time == 6,"Default charge is six seconds")
	check(fighter.definition.portrait.resource_path.ends_with("063_开拓者 球棒.png"),"Normal art is image 1")
	advance(359)
	check(bat.bat_state == "held" and bat.throws_count == 0,"No early throw")
	enemy.position = Vector2(600,430)
	advance(1)
	check(bat.bat_state == "outbound" and bat.throws_count == 1,"Throw occurs on completion tick")
	check(bat.launch_point == Vector2(600,430),"Target snapshot taken at launch")
	check(fighter.visual_texture != null and fighter.visual_texture.resource_path.ends_with("064_开拓者 棒球.png"),"Away art is image 2")
	var locked: Vector2 = bat.launch_point
	enemy.position = Vector2(600,650)
	advance(5)
	check(bat.launch_point == locked,"Outbound point does not home after launch")
	var saw_return: bool = false
	for _tick in range(180):
		arena.step(DT)
		arena.drain_events()
		if bat.bat_state == "returning":
			saw_return = true
			fighter.position = fighter.position.move_toward(Vector2(100,180),1.2)
		if bat.bat_state == "held":
			break
		check(fighter.visual_texture == bat.release_texture,"Away art lasts through both travel legs")
	check(saw_return and bat.bat_state == "held","Bat turns around and catches moving owner")
	check(fighter.visual_texture == null and bat.charge_elapsed == 0,"Catch restores image 1 and resets charge")
	advance(30)
	check(bat.throws_count == 1 and absf(bat.charge_elapsed-0.5)<0.001,"No simultaneous second bat; next charge starts after catch")
	# One damage event per enemy across the complete outward and return trip.
	start(0.2)
	fighter = arena.fighters[0]
	enemy = arena.fighters[1]
	bat = fighter.skills[0]
	advance(12)
	while bat.is_in_flight():
		arena.step(DT)
		arena.drain_events()
	check(is_equal_approx(enemy.health,10000-fighter.definition.attack*bat.damage_multiplier),"Round trip cannot repeatedly damage one stationary enemy")
	print("PASS GROUP: six-second charge, snapshot aim, spinning return and image lifetime")

func _test_contact_interrupt() -> void:
	start()
	var fighter = arena.fighters[0]
	var enemy = arena.fighters[1]
	var bat = fighter.skills[0]
	var smash = fighter.skills[1]
	advance(359)
	enemy.position = fighter.position + Vector2(55,0)
	advance(1)
	check(bat.throws_count == 0 and bat.charge_elapsed == 0,"Contact on completion tick prevents throw and resets all charge")
	check(is_equal_approx(enemy.health,10000-fighter.definition.attack*smash.damage_multiplier),"Collision deals configured heavy damage")
	check(smash.damage_multiplier > bat.damage_multiplier and enemy.knockback.x > 1000,"Collision is stronger than throw and knocks outward")
	check(enemy.lift_time > 0,"Collision requests lift/tilt visual")
	var hit_health: float = enemy.health
	for _i in range(50):
		enemy.position = fighter.position + Vector2(55,0)
		enemy.knockback = Vector2.ZERO
		advance(1)
	check(enemy.health == hit_health and bat.charge_elapsed == 0,"Sustained contact does not repeatedly damage or accumulate charge")
	enemy.position = Vector2(600,380)
	enemy.knockback = Vector2.ZERO
	advance(359)
	check(bat.throws_count == 0,"Full new charge required after separation")
	advance(1)
	check(bat.is_in_flight(),"Charge can complete after a full collision-free interval")
	enemy.position = fighter.position + Vector2(55,0)
	advance(1)
	check(bat.is_in_flight() and fighter.visual_texture == bat.release_texture,"Collision during flight does not recall bat or restore image early")
	print("PASS GROUP: contact-only heavy damage, interruption and continuous-contact debounce")

func _test_friendly_and_cleanup() -> void:
	start(0.2,true)
	var fighter = arena.fighters[0]
	var ally = arena.fighters[1]
	var enemy = arena.fighters[2]
	var bat = fighter.skills[0]
	ally.position = fighter.position + Vector2(55,0)
	advance(12)
	check(bat.is_in_flight() and ally.health == 10000,"Ally contact neither interrupts charge nor deals smash damage")
	check(bat.launch_point == enemy.position,"Throw targets enemy rather than nearby ally")
	arena.step(0)
	var position: Vector2 = bat.bat_position
	var angle: float = bat.bat_angle
	arena.step(0)
	check(bat.bat_position == position and bat.bat_angle == angle,"Paused step freezes bat trajectory and spin")
	fighter.health = 0
	advance(1)
	check(not fighter.alive and not bat.is_in_flight() and bat.get_visuals().is_empty(),"Owner death clears bat and image lock")
	var old := weakref(fighter)
	fighter = null
	ally = null
	enemy = null
	bat = null
	arena.clear_battle()
	check(old.get_ref() == null,"Contact references do not leak fighters after cleanup")
	print("PASS GROUP: team filtering, pause, death cancellation and cleanup")

func _test_settings_and_mirrors() -> void:
	var definition = library.get_character("destruction_trailblazer").duplicate(true)
	definition.skill_slots[0].charge_time = 20.0
	check(library.validate(definition).is_empty(),"Charge can be configured beyond the generic ten-second range")
	var slot := Catalog.new_slot("bat_throw")
	check(slot.charge_time == 6,"Adding bat template uses six-second default")
	var serialized: Dictionary = Library.to_data(definition)
	var restored = Library.from_data(serialized)
	check(restored.skill_slots[0].charge_time == 20 and restored.skill_slots[0].release_image.ends_with("064_开拓者 棒球.png"),"Charge and art survive character serialization")
	var config = Config.new()
	for i in range(8):
		config.participants.append({"definition":definition,"movement":"bounce","team":i})
	definition.max_health = 100000
	definition.skill_slots[0].charge_time = 0.2
	check(arena.start_match(config).is_empty(),"Eight destruction Trailblazers start")
	advance(20)
	check(arena.fighters[0].skills[0] != arena.fighters[1].skills[0],"Mirror players have independent bat states")
	for i in range(50):
		arena.start_match(config)
		advance(30)
		arena.clear_battle()
		check(arena.get_child_count() == 0 and arena.get_visuals().is_empty(),"Restart removes all bats and trails")
	print("PASS GROUP: editable charge, template defaults, mirrors and 50 eight-person restarts")
