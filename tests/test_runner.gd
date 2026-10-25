extends SceneTree
## Behavioral regression suite. Run through Test.ps1; no external test framework needed.

const ArenaScript = preload("res://scripts/core/battle_arena.gd")
const DefinitionScript = preload("res://scripts/core/character_definition.gd")
const RosterScript = preload("res://data/roster.gd")
const ExampleCharacter = preload("res://examples/wind_pulse/wind_walker.tres")
const DT: float = 1.0 / 60.0

var arena
var roster: Array = []
var failures: Array[String] = []
var checks: int = 0
var match_results: Array = []
var started_usec: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	arena = ArenaScript.new()
	root.add_child(arena)
	roster = RosterScript.get_all()
	_check(roster.size() == 5, "Default roster includes destruction Trailblazer")
	_test_pairings()
	_test_movement_swaps()
	_test_determinism()
	_test_health_and_status()
	_test_movement_and_projectiles()
	_test_skill_rules()
	_test_results()
	_test_restarts()
	_test_extension()
	arena.clear_battle()
	arena.free()
	arena = null
	var seconds: float = (Time.get_ticks_usec() - started_usec) / 1000000.0
	var report: Dictionary = {"checks": checks, "failures": failures, "pairings": match_results, "duration_seconds": seconds, "engine": Engine.get_version_info().string}
	DirAccess.make_dir_recursive_absolute("res://test-results")
	var output = FileAccess.open("res://test-results/results.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	if failures.is_empty():
		print("ALL TESTS PASSED: %d checks in %.2f seconds" % [checks, seconds])
		quit(0)
	else:
		print("FAILED: %d / %d checks" % [failures.size(), checks])
		quit(1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)

func _advance(ticks: int, validate_bounds: bool = false) -> void:
	for _tick in range(ticks):
		arena.step(DT)
		if validate_bounds:
			for fighter in arena.fighters:
				var radius: float = fighter.definition.radius
				var allowed: Rect2 = arena.bounds.grow(-radius + 0.01)
				if not allowed.has_point(fighter.position):
					_check(false, "Fighter remains inside arena: " + fighter.movement_id)
					return

func _run_match(first, second, seed: int, movements: Array = []) -> Dictionary:
	if movements.is_empty():
		movements = [first.default_movement, second.default_movement]
	arena.duration = 90.0
	arena.start_battle([first, second], movements, seed)
	for tick in range(5402):
		if not arena.running:
			break
		arena.step(DT)
		if tick % 60 == 0:
			arena.drain_events()
	var result: Dictionary = {
		"first": first.id, "second": second.id, "winner": arena.winner,
		"elapsed": arena.elapsed, "health": [arena.fighters[0].health, arena.fighters[1].health],
		"log_hash": JSON.stringify(arena.event_log).sha256_text(),
	}
	return result

func _test_pairings() -> void:
	for first in roster:
		for second in roster:
			var result: Dictionary = _run_match(first, second, 20261025)
			match_results.append(result)
			_check(not arena.running and arena.winner in [-1, 0, 1], "Pairing finishes: %s vs %s" % [first.id, second.id])
			_check(arena.elapsed <= 90.0, "Pairing obeys time limit")
			_check(arena.projectiles.is_empty(), "Result clears active projectiles")
	print("PASS GROUP: all 25 pairings including mirrors")

func _test_determinism() -> void:
	for first_index in range(roster.size()):
		var first: Dictionary = _run_match(roster[first_index], roster[(first_index + 1) % roster.size()], 42891)
		var second: Dictionary = _run_match(roster[first_index], roster[(first_index + 1) % roster.size()], 42891)
		_check(first == second, "Same seed reproduces result and event log for kit %d" % first_index)
	# Presentation grouping differs, but the same fixed simulation ticks must match.
	arena.start_battle([roster[1], roster[3]], ["kite", "wander"], 71)
	_advance(1200)
	var one_step_snapshot: String = _snapshot()
	arena.start_battle([roster[1], roster[3]], ["kite", "wander"], 71)
	for _frame in range(300):
		_advance(4)
	_check(_snapshot() == one_step_snapshot, "Fixed ticks are independent of presentation grouping")
	var before: String = _snapshot()
	arena.step(0.0)
	_check(before == _snapshot(), "Paused zero step changes no simulation state")
	print("PASS GROUP: seeded simulation and fixed-step pacing")

func _test_movement_swaps() -> void:
	for character in roster:
		for strategy in ["bounce", "chase", "kite", "wander"]:
			var result: Dictionary = _run_match(character, roster[0], 317, [strategy, "bounce"])
			_check(result.winner in [-1, 0, 1], "Alternate movement finishes: %s / %s" % [character.id, strategy])
			_check(arena.fighters[0].movement_id == strategy, "Selected strategy overrides character default: " + strategy)
	print("PASS GROUP: all four movement choices on every character")

func _snapshot() -> String:
	var fighters_data: Array = []
	for fighter in arena.fighters:
		fighters_data.append([fighter.position.x, fighter.position.y, fighter.health, fighter.shield, fighter.alive])
	return JSON.stringify([arena.elapsed, arena.winner, fighters_data, arena.event_log])

func _passive(speed: float = 0.0, first_health: float = 1000.0, second_health: float = 1000.0, movements: Array = ["bounce", "bounce"]) -> void:
	var first = DefinitionScript.new()
	first.id = "test_a"
	first.max_health = first_health
	first.speed = speed
	var second = DefinitionScript.new()
	second.id = "test_b"
	second.max_health = second_health
	second.speed = speed
	arena.duration = 90.0
	arena.start_battle([first, second], movements, 19)

func _test_health_and_status() -> void:
	_passive()
	var source = arena.fighters[0]
	var target = arena.fighters[1]
	arena.add_shield(target, 100.0, 4.0)
	arena.apply_damage(source, target, 80.0, "test_hit")
	_advance(1)
	_check(is_equal_approx(target.health, 1000.0) and is_equal_approx(target.shield, 20.0), "Shield absorbs before health")
	arena.apply_damage(source, target, 50.0, "test_hit")
	_advance(1)
	_check(is_equal_approx(target.health, 970.0) and is_zero_approx(target.shield), "Damage overflow reaches health")
	arena.add_shield(target, 50.0, 0.2)
	_advance(15)
	_check(is_zero_approx(target.shield), "New shield lifetime starts afresh after previous shield is depleted")
	arena.heal(target, 5000.0)
	_check(is_equal_approx(target.health, 1000.0), "Healing caps at maximum health")
	# Isolate burn from shield regressions so one defect cannot produce two failures.
	_passive()
	source = arena.fighters[0]
	target = arena.fighters[1]
	arena.add_shield(target, 20.0, 0.2)
	_advance(15)
	_check(is_zero_approx(target.shield), "Fresh shield expires after its configured duration")
	arena.apply_status(source, target, "burn", 1.0, 20.0)
	_advance(61)
	_check(is_equal_approx(target.health, 980.0), "Burn deals configured DPS across duration")
	_check(not target.statuses.has("burn"), "Burn expires")
	_passive(120.0, 1000.0, 1000.0, ["chase", "chase"])
	source = arena.fighters[0]
	target = arena.fighters[1]
	var start_position: Vector2 = target.position
	arena.apply_status(source, target, "slow", 0.5, 0.5)
	_advance(1)
	_check(is_equal_approx(start_position.distance_to(target.position), 1.0), "50 percent slow halves movement")
	_advance(31)
	_check(not target.statuses.has("slow"), "Slow expires")
	print("PASS GROUP: shield, healing, burn and slow")

func _test_movement_and_projectiles() -> void:
	for strategy in ["bounce", "chase", "kite", "wander"]:
		_passive(4000.0, 1000.0, 1000.0, [strategy, strategy])
		arena.fighters[0].position = Vector2(76.0, 76.0)
		arena.fighters[1].position = Vector2(76.0, 76.0)
		_advance(240, true)
		_check(arena.fighters[0].position.distance_to(arena.fighters[1].position) >= 54.0, "Overlapping fighters separate for " + strategy)
	_passive()
	var fighter = arena.fighters[0]
	fighter.position = Vector2(78.0, 78.0)
	fighter.dash_velocity = Vector2(-10000.0, -10000.0)
	fighter.dash_remaining = 0.4
	_advance(30, true)
	_check(fighter.dash_remaining <= 0.0, "Dash ends and remains in bounds")
	_passive()
	var source = arena.fighters[0]
	var target = arena.fighters[1]
	arena.spawn_projectile(source, {"position": source.position, "velocity": Vector2(60000.0, 0.0), "damage": 75.0, "radius": 4.0, "blast_radius": 80.0, "skill_id": "swept_test"})
	_advance(1)
	_check(is_equal_approx(target.health, 925.0), "Fast swept projectile hits once, including blast")
	_check(arena.projectiles.is_empty(), "Hit consumes projectile")
	_passive()
	source = arena.fighters[0]
	target = arena.fighters[1]
	arena.spawn_projectile(source, {"position": source.position, "velocity": Vector2(2500.0, 0.0), "damage": 60.0, "radius": 12.0, "blast_radius": 1.0, "skill_id": "small_blast_test"})
	_advance(10)
	_check(is_equal_approx(target.health, 940.0), "Direct projectile hit survives a blast radius smaller than projectile radius")
	_passive()
	source = arena.fighters[0]
	target = arena.fighters[1]
	arena.spawn_projectile(source, {"position": target.position - Vector2(33.0, 0.0), "velocity": Vector2(180.0, 0.0), "damage": 30.0, "radius": 4.0, "skill_id": "last_segment_test"})
	# Reproduce the final fractional tick of an arbitrary projectile lifetime.
	arena.projectiles[0]["lifetime"] = DT * 0.5
	_advance(1)
	_check(is_equal_approx(target.health, 970.0), "Projectile can hit during its final partial lifetime tick")
	_check(arena.projectiles.is_empty(), "Expired final-tick projectile is removed")
	print("PASS GROUP: movement boundaries, overlap, dash and swept projectile")

func _test_skill_rules() -> void:
	arena.start_battle([roster[2], roster[2]], ["bounce", "bounce"], 22)
	var first = arena.fighters[0]
	var second = arena.fighters[1]
	first.skills[0].cooldown_remaining = 99.0
	second.skills[0].cooldown_remaining = 99.0
	first.skills[0].shield_timer = 99.0
	second.skills[0].shield_timer = 99.0
	arena.apply_damage(first, second, 10.0, "trigger_counter")
	_advance(1)
	var damage_events: int = 0
	for event in arena.event_log:
		if event.kind == "damage":
			damage_events += 1
	_check(damage_events == 2, "Guard counter produces only one response, no recursion")
	_check(first.skills[0] != second.skills[0], "Mirror characters own separate skill nodes")
	first.skills[0].cooldown_remaining = 33.0
	_check(not is_equal_approx(second.skills[0].cooldown_remaining, 33.0), "Mirror skill cooldowns are independent")
	first.statuses["slow"] = {"remaining": 1.0, "duration": 1.0, "power": 0.3, "source": second, "tick_accumulator": 0.0}
	_check(not second.statuses.has("slow"), "Mirror status dictionaries are independent")

	var sword = roster[0].duplicate()
	sword.speed = 0.0
	var dummy = DefinitionScript.new()
	dummy.speed = 0.0
	arena.start_battle([sword, dummy], ["bounce", "bounce"], 5)
	first = arena.fighters[0]
	second = arena.fighters[1]
	first.position = Vector2(300.0, 380.0)
	second.position = Vector2(373.0, 380.0)
	var orbit = first.skills[0]
	orbit.angular_speed = 0.0
	orbit.orbit_angle = 0.0
	_advance(12)
	var damage: float = dummy.max_health - second.health
	_check(is_equal_approx(damage, sword.attack * orbit.damage_multiplier), "Continuous blade contact observes its hit interval")
	_advance(13)
	_check(is_equal_approx(dummy.max_health - second.health, damage * 2.0), "Blade can hit again after interval")
	var assassin = roster[3].duplicate()
	assassin.speed = 0.0
	arena.start_battle([assassin, dummy], ["bounce", "bounce"], 9)
	first = arena.fighters[0]
	second = arena.fighters[1]
	first.position = Vector2(300.0, 380.0)
	second.position = Vector2(400.0, 380.0)
	var dash = first.skills[0]
	dash.activate(second)
	dash.cooldown_remaining = 99.0
	_advance(30)
	_check(is_equal_approx(dummy.max_health - second.health, assassin.attack * dash.damage_multiplier), "One dash hits the same target only once")
	_check(second.statuses.has("slow"), "Dash hit applies its slow effect")
	print("PASS GROUP: independent skills, counter recursion and blade intervals")

func _test_results() -> void:
	_passive()
	var first = arena.fighters[0]
	var second = arena.fighters[1]
	arena.apply_damage(first, second, 2000.0, "lethal")
	arena.apply_damage(second, first, 2000.0, "lethal")
	_advance(1)
	_check(arena.winner == -1 and not first.alive and not second.alive, "Same-tick lethal damage draws")
	var before: String = _snapshot()
	_advance(120)
	_check(before == _snapshot(), "Ended match stops future damage and movement")
	_passive(0.0, 1000.0, 2000.0)
	arena.duration = 0.05
	arena.fighters[0].health = 600.0
	arena.fighters[1].health = 1000.0
	_advance(4)
	_check(arena.winner == 0, "Timeout compares health percentage, not raw health")
	_passive(0.0, 1000.0, 2000.0)
	arena.duration = 0.05
	arena.fighters[0].health = 500.0
	arena.fighters[1].health = 1000.0
	_advance(4)
	_check(arena.winner == -1, "Equal timeout health percentage draws")
	print("PASS GROUP: simultaneous death, timeout and stopped match")

func _test_restarts() -> void:
	for index in range(100):
		var result: Dictionary = _run_match(roster[index % 4], roster[(index / 4) as int % 4], 1000 + index)
		_check(result.winner in [-1, 0, 1], "Restart %d completes" % index)
		_check(arena.get_child_count() == 2, "Restart %d does not accumulate skill nodes" % index)
		var old_fighter: WeakRef = weakref(arena.fighters[0])
		var old_skill: WeakRef = weakref(arena.fighters[0].skills[0])
		arena.clear_battle()
		_check(arena.get_child_count() == 0 and arena.projectiles.is_empty() and arena.events.is_empty(), "Restart %d clears all transient state" % index)
		_check(old_fighter.get_ref() == null and old_skill.get_ref() == null, "Restart %d releases prior fighter and skill" % index)
	print("PASS GROUP: 100 complete matches and clean restarts")

func _test_extension() -> void:
	var result: Dictionary = _run_match(ExampleCharacter, roster[0], 8787)
	_check(result.winner in [-1, 0, 1], "Fifth character runs through unchanged battle core")
	var used_new_skill: bool = false
	for event in arena.event_log:
		if event.kind == "damage" and str(event.get("skill_id", "")).contains("wind"):
			used_new_skill = true
	_check(used_new_skill, "Fifth character's new skill actually deals damage")
	_check(RosterScript.get_all().size() == 5, "Extension example does not silently change default roster")
	print("PASS GROUP: extension example")
