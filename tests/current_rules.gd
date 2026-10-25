extends SceneTree
const Arena = preload("res://scripts/core/battle_arena.gd")
const Config = preload("res://scripts/core/match_config.gd")
const Definition = preload("res://scripts/core/character_definition.gd")
const Catalog = preload("res://scripts/core/skill_catalog.gd")
const Library = preload("res://scripts/core/character_library.gd")
const DT := 1.0/60.0
var checks: int = 0
var failures: int = 0
var arena
var library

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CURRENT RULE FAIL: " + message)

func begin(first,second) -> void:
	var config = Config.new()
	config.participants = [{"definition":first,"movement":"bounce","team":0},{"definition":second,"movement":"bounce","team":1}]
	check(arena.start_match(config).is_empty(),"Match starts")
	arena.fighters[0].position = Vector2(130,300)
	arena.fighters[1].position = Vector2(420,300)
	arena.drain_events()

func advance(ticks: int) -> void:
	for i in range(ticks):
		arena.step(DT)
		arena.drain_events()

func dummy():
	var definition = Definition.new()
	definition.max_health = 10000
	definition.speed = 0
	return definition

func _run() -> void:
	library = Library.new("user://qa_current_rules")
	var roles: Array = library.reload()
	check(roles.size() == 3 and roles[0].id == "destruction_trailblazer" and roles[1].id == "sparkle" and roles[2].id == "yunli","Three current built-ins are listed")
	for role in roles:
		check(role.max_health == 1000 and role.speed == 160 and role.default_movement == "bounce","Built-in defaults are 1000 HP, 160 speed, bounce")
	var fresh = library.make_new()
	check(fresh.max_health == 1000 and fresh.speed == 160 and fresh.skill_slots.is_empty(),"New role has default stats and no contact attack")
	for id in ["sword","mage","guard","assassin"]:
		check(library.get_character(id) == null,"Retired role is absent")
	for item in Catalog.ITEMS:
		for entry in Catalog.parameter_definitions(item.id):
			check(entry.key not in ["process_mode","process_priority"],"Parameter editor exposes exported skill fields only")
	var slot: Dictionary = Catalog.new_slot("sparkle_revolver")
	slot.parameters = {"bullet_damage":345.0,"bullet_speed":1800.0,"reload_time":2.0}
	var skill = Catalog.instantiate(slot)
	check(skill.bullet_damage == 345 and skill.bullet_speed == 1800 and skill.reload_time == 2,"Saved numeric overrides reach the runtime skill")
	skill.free()
	slot.parameters.bullet_speed = -1
	check(not Catalog.validate_parameters(slot).is_empty(),"Invalid numeric ranges are rejected")
	arena = Arena.new()
	root.add_child(arena)
	var blank = Definition.new()
	blank.speed = 0
	begin(blank,blank)
	arena.fighters[1].position = arena.fighters[0].position + Vector2(50,0)
	advance(30)
	check(arena.fighters[0].health == 1000 and arena.fighters[1].health == 1000,"Body separation does not add collision damage")
	_test_bat()
	_test_revolver()
	var signatures: Array = []
	for repeat in range(2):
		begin(roles[0],roles[1])
		var budget: int = 5401
		while arena.running and budget > 0:
			arena.step(DT)
			arena.drain_events()
			budget -= 1
		check(not arena.running,"Current character pair completes")
		signatures.append([arena.winner_team,arena.tick_count,arena.fighters[0].health,arena.fighters[1].health])
	check(signatures[0] == signatures[1],"Seed reproduces current pair outcome")
	if "--extended" in OS.get_cmdline_user_args():
		for i in range(20):
			var config = Config.new()
			config.mode = "teams" if i%2 == 0 else "ffa"
			for j in range(8):
				config.participants.append({"definition":roles[j%2],"movement":"bounce","team":j%2})
			check(arena.start_match(config).is_empty(),"Extended eight-player match starts")
			advance(5401)
			check(not arena.running,"Extended eight-player match ends")
	arena.clear_battle()
	arena.free()
	print("CURRENT RULE CHECKS: ",checks," failures: ",failures)
	if failures == 0:
		print("CURRENT RULE TESTS PASSED")
	quit(0 if failures == 0 else 1)

func _test_bat() -> void:
	var hero = library.get_character("destruction_trailblazer").duplicate(true)
	hero.speed = 0
	hero.attack = 999
	hero.skill_slots[0].parameters = {"throw_distance":360.0,"outbound_damage":17.0,"return_damage":23.0,"knockback_strength":0.0}
	begin(hero,dummy())
	var owner = arena.fighters[0]
	var enemy = arena.fighters[1]
	var bat = owner.skills[0]
	bat.activate(enemy)
	var start: Vector2 = bat.bat_position
	check(absf(start.distance_to(bat.launch_point)-360) < 0.001,"Bat flies a fixed distance instead of stopping at enemy")
	check(start.direction_to(bat.launch_point).dot(start.direction_to(enemy.position)) > .999,"Bat aims at completion-time enemy position")
	var saw_return: bool = false
	var budget: int = 600
	while bat.is_in_flight() and budget > 0:
		arena.step(DT)
		arena.drain_events()
		saw_return = saw_return or bat.bat_state == "returning"
		budget -= 1
	check(saw_return and not bat.is_in_flight(),"Bat reaches fixed point and returns to hand")
	check(enemy.health == 9960,"One outgoing and one returning hit use separately configured damage")
	check(owner.visual_texture == null,"Catch restores the normal image")
	begin(hero,dummy())
	owner = arena.fighters[0]
	enemy = arena.fighters[1]
	enemy.position = owner.position + Vector2(70,0)
	owner.skills[0].charge_elapsed = 5.9
	arena.step(DT)
	check(enemy.health == 9880 and enemy.impact_remaining > 0,"Expanded contact range deals independent 120 damage")
	check(owner.skills[0].charge_elapsed == 0,"Expanded contact also resets bat charge")

func _test_revolver() -> void:
	var hero = library.get_character("sparkle").duplicate(true)
	hero.speed = 0
	hero.skill_slots[0].parameters = {"reload_time":1.2,"shot_interval":0.1,"bullet_speed":1400.0,"bullet_damage":200.0,"bullet_knockback":0.0}
	begin(hero,dummy())
	var owner = arena.fighters[0]
	var enemy = arena.fighters[1]
	var gun = owner.skills[0]
	advance(30)
	check(gun.state == "reload" and gun.shots_count == 0,"Reload waits for its configured time")
	gun.state = "firing"
	gun.loaded_chamber = 5
	gun.chamber = 0
	gun.shot_remaining = 0
	arena.step(DT)
	var events: Array = arena.drain_events()
	check(gun.dry_count == 1 and gun.flag_remaining > 0 and arena.projectiles.is_empty(),"Empty chamber makes a flag but no projectile")
	check(events.any(func(event): return event.kind == "dry_fire"),"Empty shot emits its sound/effect event")
	advance(31)
	check(gun.shots_count == 6 and gun.dry_count == 5 and gun.rounds_fired == 1,"One live round is reached after five empties")
	check(gun.state == "reload" and gun.loaded_chamber == -1,"Live round immediately starts another reload")
	advance(25)
	check(enemy.health == 9800,"A live round deals exactly 200 independently of base attack")
	enemy.position = owner.position - Vector2(80,0)
	advance(1)
	check(owner.facing == -1 and absf(gun.aim_angle) > PI/2,"Enemy behind the gun turns Sparkle and changes aim")
	begin(hero,dummy())
	gun = arena.fighters[0].skills[0]
	advance(72)
	check(gun.loads_count == 1 and gun.shots_count >= 1,"Completed reload draws one random chamber and fires")
