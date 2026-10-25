extends SceneTree
const Arena = preload("res://scripts/core/battle_arena.gd")
const Library = preload("res://scripts/core/character_library.gd")
const Catalog = preload("res://scripts/core/skill_catalog.gd")
const Config = preload("res://scripts/core/match_config.gd")
const Definition = preload("res://scripts/core/character_definition.gd")
var checks: int = 0
var failures: int = 0
var arena
var library
var qa_root: String

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("EXT FAIL: " + message)

func _run() -> void:
	qa_root = "user://qa_extension_" + str(OS.get_process_id())
	library = Library.new(qa_root)
	library.reload()
	arena = Arena.new()
	root.add_child(arena)
	_test_library()
	_test_phases()
	_test_teams_and_hits()
	_test_maps_and_results()
	_test_multiplayer_stability()
	arena.clear_battle()
	arena.free()
	_remove_qa(qa_root)
	print("EXTENSION CHECKS: ",checks," failures: ",failures)
	if failures == 0:
		print("EXTENSION TESTS PASSED")
	quit(0 if failures == 0 else 1)

func _remove_qa(path: String) -> void:
	if not path.begins_with(qa_root) or not qa_root.begins_with("user://qa_extension_"):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for folder in dir.get_directories():
		_remove_qa(path.path_join(folder))
	DirAccess.remove_absolute(path)

func config_for(count: int, mode: String = "ffa", teams: Array = [], width: float = 664, height: float = 664):
	var config = Config.new()
	config.mode = mode
	config.width = width
	config.height = height
	config.seed_value = 101
	for i in range(count):
		config.participants.append({"definition":library.characters[i % 4],"movement":["bounce","chase","kite","wander"][i % 4],"team":teams[i] if i < teams.size() else i % 2})
	return config

func advance(steps: int) -> void:
	for _i in range(steps):
		arena.step(1.0/60.0)
		arena.drain_events()

func passive(config) -> void:
	for slot in config.participants:
		var definition = Definition.new()
		definition.speed = 0
		slot.definition = definition
	arena.start_match(config)

func _test_library() -> void:
	check(library.characters.size() == 5,"Built-in defaults load")
	for definition in library.characters:
		check(definition.portrait != null and not definition.normal_image_path.is_empty(),"Supplied PNG is connected for " + definition.id)
	check(library.get_character("guard").skill_slots.size() == 3,"Guardian has independent melee shield counter slots")
	var character = library.make_copy(library.get_character("mage"))
	character.display_name = "保存测试"
	character.max_health = 1234
	character.attack = 67
	character.speed = 190
	character.skill_slots[0].charge_time = 0.5
	character.skill_slots[0].release_time = 0.4
	character.skill_slots[0].charge_can_move = false
	DirAccess.make_dir_recursive_absolute(qa_root)
	var image := Image.create(48,80,false,Image.FORMAT_RGBA8)
	image.fill(Color(0.4,0.8,1,0.5))
	var source := qa_root.path_join("source.png")
	image.save_png(source)
	var owned: String = library.import_png(source)
	check(not owned.is_empty() and owned != source,"PNG copied to owned image store")
	character.normal_image_path = owned
	character.portrait = Library.texture_from_path(owned)
	character.skill_slots[0].charge_image = owned
	character.skill_slots[0].release_image = owned
	check(library.save_character(character),"New character saves")
	character.attack = 70
	check(library.save_character(character),"Atomic replacement of existing save works on Windows")
	DirAccess.remove_absolute(source)
	var reloaded = Library.new(qa_root)
	reloaded.reload()
	var saved = reloaded.get_character(character.id)
	check(saved != null and saved.max_health == 1234 and saved.attack == 70 and saved.speed == 190,"Reopening library restores attributes")
	check(saved.portrait != null and saved.portrait.get_size() == Vector2(48,80),"PNG survives deleting original and retains aspect ratio")
	check(saved.skill_slots[0].charge_image == owned and saved.skill_slots[0].release_time == 0.4,"Per-slot images and phase settings survive reload")
	var copy = reloaded.make_copy(saved)
	copy.skill_slots[0].charge_time = 2
	check(saved.skill_slots[0].charge_time == 0.5,"Copying does not share mutable skill dictionaries")
	check(copy.id != saved.id,"Copies have stable distinct IDs")
	var invalid := FileAccess.open(qa_root.path_join("broken.png"),FileAccess.WRITE)
	invalid.store_string("not an image")
	invalid.close()
	check(library.import_png(qa_root.path_join("broken.png")).is_empty(),"Damaged PNG rejected")
	check(Library.texture_from_path("user://missing-qa-state.png") == null,"Missing PNG safely returns null")
	var original = library.get_character("sword")
	original.max_health = 777
	check(library.save_character(original),"Built-in override saves")
	check(library.remove_or_restore("sword") and library.get_character("sword").max_health == 1000,"Built-in restoration preserves template")
	check(library.get_character(character.id) != null,"Restoring built-in keeps user characters")
	check(library.remove_or_restore(character.id) and library.get_character(character.id) == null,"Custom character deletion")
	print("PASS GROUP: character persistence, PNG ownership, copies and restore")

func _test_phases() -> void:
	var caster = library.get_character("mage").duplicate(true)
	caster.skill_slots[0].charge_time = 0.5
	caster.skill_slots[0].release_time = 0.4
	caster.skill_slots[0].charge_can_move = false
	caster.skill_slots[0].charge_image = "user://does-not-exist.png"
	var config = config_for(3)
	config.participants[0].definition = caster
	config.participants[0].movement = "chase"
	for i in range(1,3):
		config.participants[i].definition = Definition.new()
		config.participants[i].definition.speed = 0
	check(arena.start_match(config).is_empty(),"Phase test battle starts")
	var fighter = arena.fighters[0]
	var skill = fighter.skills[0]
	skill.cooldown_remaining = 0
	skill.request_cast(arena.fighters[1])
	check(fighter.visual_phase == "charge" and fighter.visual_texture == null,"Charge state with missing PNG falls back")
	var position: Vector2 = fighter.position
	advance(20)
	check(arena.projectiles.is_empty(),"No projectile before actual charge completes")
	check(fighter.position.distance_to(position) < 0.001,"Movement disabled during charge")
	arena.fighters[1].health = 0
	advance(12)
	check(fighter.visual_phase == "release" and not arena.projectiles.is_empty(),"Charge completes and retargets dead enemy")
	advance(26)
	check(fighter.visual_phase == "normal" and fighter.casting_skill == null,"Release returns to normal")
	skill.cooldown_remaining = 0
	skill.charge_can_move = true
	position = fighter.position
	skill.request_cast(arena.fighters[2])
	advance(8)
	check(fighter.position.distance_to(position) > 0.1,"Movement allowed when skill enables it")
	fighter.health = 0
	advance(1)
	check(not fighter.alive and fighter.casting_skill == null and skill.phase == "normal","Death cancels charge")
	var guard = library.get_character("guard")
	check(guard.skill_slots.size() == 3,"Passive mechanics remain separate")
	arena.start_match(config_for(2))
	var snapshot_attack: float = arena.fighters[0].definition.attack
	library.get_character("sword").attack += 1
	check(arena.fighters[0].definition.attack == snapshot_attack,"Editing templates cannot mutate active battle snapshot")
	library.reload()
	print("PASS GROUP: true charge, movement lock, retargeting, cancellation and snapshots")

func _test_teams_and_hits() -> void:
	var config = config_for(4,"teams",[0,0,1,1])
	passive(config)
	var first = arena.fighters[0]
	var ally = arena.fighters[1]
	var enemy = arena.fighters[2]
	arena.apply_damage(first,ally,100,"friendly")
	arena.apply_status(first,ally,"burn",2,50)
	arena.apply_status(first,ally,"slow",2,0.5)
	advance(1)
	check(ally.health == 1000 and ally.statuses.is_empty(),"Central damage and hostile states reject friendly fire")
	check(arena.get_targets(first).size() == 2 and not arena.get_targets(first).has(ally),"Targets filter team members")
	first.position = Vector2(200,300)
	ally.position = Vector2(300,300)
	enemy.position = Vector2(400,300)
	arena.fighters[3].position = Vector2(420,360)
	arena.spawn_projectile(first,{"position":Vector2(240,300),"velocity":Vector2(12000,0),"damage":50,"blast_radius":100})
	advance(1)
	check(ally.health == 1000 and enemy.health == 950,"Friendly body does not block projectile")
	check(arena.fighters[3].health == 950,"Blast hits multiple enemies once each")
	var sword = library.get_character("sword").duplicate(true)
	sword.speed = 0
	config = config_for(3)
	for slot in config.participants:
		slot.definition = Definition.new()
		slot.definition.speed = 0
	config.participants[0].definition = sword
	arena.start_match(config)
	first = arena.fighters[0]
	first.position = Vector2(300,380)
	arena.fighters[1].position = Vector2(373,365)
	arena.fighters[2].position = Vector2(373,395)
	# Different sides of a broad test blade so body separation doesn't mask contact.
	var orbit = first.skills[0]
	orbit.angular_speed = 0
	orbit.blade_radius = 70
	advance(1)
	check(arena.fighters[1].health < 1000 and arena.fighters[2].health < 1000,"Orbit blades inspect every enemy")
	var assassin = library.get_character("assassin").duplicate(true)
	assassin.speed = 0
	config.participants[0].definition = assassin
	arena.start_match(config)
	first = arena.fighters[0]
	first.position = Vector2(240,380)
	arena.fighters[1].position = Vector2(330,370)
	arena.fighters[2].position = Vector2(430,390)
	var dash = first.skills[0]
	dash.cooldown_remaining = 99
	dash.activate(arena.fighters[2])
	advance(30)
	check(arena.fighters[1].health == 900 and arena.fighters[2].health == 900,"Dash damages every crossed enemy exactly once")
	print("PASS GROUP: no friendly fire, allied projectile pass-through and multi-target attacks")

func _test_maps_and_results() -> void:
	for mode_value in ["ffa","teams"]:
		for dimensions in [Vector2(480,480),Vector2(2400,480),Vector2(480,2400),Vector2(2400,2400)]:
			var config = config_for(8,mode_value,[0,0,1,1,2,2,3,3],dimensions.x,dimensions.y)
			check(arena.start_match(config).is_empty(),"Eight actors fit valid rectangular layout")
			for i in range(8):
				var fighter = arena.fighters[i]
				check(arena.bounds.grow(-fighter.definition.radius).has_point(fighter.position),"Spawn inside rectangle")
				for j in range(i):
					check(fighter.position.distance_to(arena.fighters[j].position) >= fighter.definition.radius + arena.fighters[j].definition.radius,"Spawns do not overlap")
	var invalid = config_for(4,"teams",[0,0,0,0])
	check(not arena.validate_config(invalid).is_empty(),"One occupied team cannot start")
	invalid.width = 400
	check(not arena.validate_config(invalid).is_empty(),"Map range validation")
	var config = config_for(8,"teams",[0,1,1,1,1,1,1,1])
	passive(config)
	for i in range(1,8):
		arena.fighters[i].health = 500
	arena.duration = 0.02
	advance(2)
	check(arena.winner_team == 0,"Unequal teams compare fractions, not raw HP or members")
	passive(config)
	for fighter in arena.fighters:
		fighter.health = 0
	advance(1)
	check(arena.winner_team == -1,"Simultaneous eight-way elimination draws")
	config = config_for(8,"teams",[0,0,1,1,2,2,3,3])
	passive(config)
	for fighter in arena.fighters:
		if fighter.team_id != 2:
			fighter.health = 0
	advance(1)
	check(arena.winner_team == 2,"Last surviving team wins")
	passive(config)
	arena.duration = 0.02
	advance(2)
	check(arena.winner_team == -1 and arena.result.reason == "timeout","Equal team health fractions draw on timeout")
	print("PASS GROUP: rectangular maps, spawn validation, unequal teams and results")

func _complete(config) -> Dictionary:
	check(arena.start_match(config).is_empty(),"Multiplayer config starts")
	for _tick in range(5402):
		if not arena.running:
			break
		arena.step(1.0/60.0)
		arena.drain_events()
	return {"winner":arena.winner_team,"tick":arena.tick_count,"events":JSON.stringify(arena.event_log)}

func _test_multiplayer_stability() -> void:
	for kit_id in ["sword", "mage"]:
		var stress = config_for(8)
		for slot in stress.participants:
			slot.definition = library.get_character(kit_id)
			var movement: String = "bounce" if kit_id == "sword" else "kite"
			slot.movement = movement
		_complete(stress)
		check(not arena.running,"Eight simultaneous " + kit_id + " kits complete")
	for count in range(2,9):
		var config = config_for(count)
		var result := _complete(config)
		check(not arena.running,"FFA %d actors completes" % count)
		check(result == _complete(config),"FFA %d fixed seed reproduces entire log" % count)
	for teams in [[0,1,1,1,1,1,1,1],[0,0,1,1,1,2,2,2],[0,0,1,1,2,2,3,3]]:
		var config = config_for(8,"teams",teams)
		var result := _complete(config)
		check(result == _complete(config),"Unequal/multiple team seed reproducibility")
	for i in range(100):
		var config = config_for(8,"ffa" if i%2 == 0 else "teams",[0,0,1,1,2,2,3,3])
		config.seed_value = 5000 + i
		_complete(config)
		check(not arena.running,"Eight-person restart completes")
		var fighter_ref := weakref(arena.fighters[0])
		var skill_ref := weakref(arena.fighters[0].skills[0])
		arena.clear_battle()
		check(arena.get_child_count() == 0 and arena.projectiles.is_empty(),"Restart clears every skill and projectile")
		check(fighter_ref.get_ref() == null and skill_ref.get_ref() == null,"Restart frees old participants and skills")
	print("PASS GROUP: 2–8 actor matches, seeded results and 100 full eight-person restarts")
