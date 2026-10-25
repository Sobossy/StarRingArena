extends SceneTree
const Arena = preload("res://scripts/core/battle_arena.gd")
const Config = preload("res://scripts/core/match_config.gd")
const Definition = preload("res://scripts/core/character_definition.gd")
const Library = preload("res://scripts/core/character_library.gd")
const Catalog = preload("res://scripts/core/skill_catalog.gd")
const DT := 1.0/60.0
var arena
var library
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("YUNLI FAIL: " + message)

func start() -> void:
	var yunli = library.get_character("yunli").duplicate(true)
	yunli.speed = 0
	var dummy = Definition.new()
	dummy.max_health = 10000
	dummy.speed = 0
	var config = Config.new()
	config.participants = [{"definition":dummy,"movement":"bounce","team":0},{"definition":yunli,"movement":"bounce","team":1}]
	check(arena.start_match(config).is_empty(),"Yunli match starts")
	arena.fighters[0].position = Vector2(130,300)
	arena.fighters[1].position = Vector2(420,300)
	arena.drain_events()

func advance(count: int) -> void:
	for i in range(count):
		arena.step(DT)
		arena.drain_events()

func _run() -> void:
	library = Library.new("user://qa_yunli_empty")
	library.reload()
	arena = Arena.new()
	root.add_child(arena)
	start()
	var owner = arena.fighters[1]
	var enemy = arena.fighters[0]
	var skill = owner.skills[0]
	check(owner.definition.max_health == 1000 and owner.definition.default_movement == "bounce","Standard Yunli defaults")
	check(owner.definition.portrait.resource_path.ends_with("225_云璃 好吃.png"),"Eating uses supplied image 1")
	owner.health = 900
	advance(59)
	check(owner.health == 900,"No early healing before one second")
	advance(1)
	check(owner.health == 930,"Eating restores thirty each second")
	owner.health = 990
	advance(60)
	check(owner.health == 1000,"Healing is capped at maximum HP")
	arena.apply_damage(enemy,owner,100,"first")
	arena.step(DT)
	check(owner.health == 900 and skill.guarding,"First full hit enters guard after damage")
	check(skill.stored_damage == 0 and skill.guard_remaining == 4,"Trigger hit is excluded from four-second accumulation")
	check(owner.visual_texture.resource_path.ends_with("223_云璃 威慑.png") and owner.visual_phase == "guard","Guard uses supplied image 2")
	arena.apply_damage(enemy,owner,100,"next")
	arena.step(DT)
	check(is_equal_approx(owner.health,820) and is_equal_approx(skill.stored_damage,80),"Subsequent hit is reduced twenty percent and counts actual HP loss")
	check(skill.guard_remaining < 4,"Further damage does not refresh guard")
	advance(60)
	check(is_equal_approx(owner.health,820),"No eating heal during guard")
	arena.apply_damage(enemy,owner,50,"next",false)
	arena.step(DT)
	check(is_equal_approx(skill.stored_damage,120),"Non-chain reaction damage is still observed for actual damage")
	var budget: int = 240
	while skill.guarding and budget > 0:
		arena.step(DT)
		budget -= 1
	check(not skill.guarding and skill.throws_count == 1,"One counter releases when four seconds expire")
	check(is_equal_approx(skill.last_counter_damage,198),"Counter formula is 150 plus 0.4 times 120")
	check(owner.visual_texture == null and owner.visual_phase == "normal","Release immediately restores eating art")
	check(arena.projectiles.size() == 1 and arena.projectiles[0].visual_type == "laotie","Counter launches a separate Lao Tie projectile")
	check(is_equal_approx(arena.projectiles[0].damage,198),"Projectile owns the snapshotted counter damage")
	advance(30)
	check(is_equal_approx(enemy.health,9802),"Lao Tie applies its computed damage once")
	check(enemy.position.x < 130 and enemy.last_hit_direction.x < 0,"Lao Tie knocks the enemy away before wall recovery")
	advance(30)
	check(is_equal_approx(owner.health,810),"Eating healing resumes after guard")
	start()
	owner = arena.fighters[1]
	enemy = arena.fighters[0]
	skill = owner.skills[0]
	arena.apply_damage(enemy,owner,100,"trigger")
	arena.step(DT)
	arena.add_shield(owner,100,10)
	arena.apply_damage(enemy,owner,100,"shielded")
	arena.step(DT)
	check(owner.health == 900 and is_equal_approx(owner.shield,20),"Guard mitigation happens before shield absorption")
	check(skill.stored_damage == 0,"Absorbed shield damage does not count as lost HP")
	arena.apply_damage(enemy,owner,200,"through_shield")
	arena.step(DT)
	check(is_equal_approx(skill.stored_damage,140),"Only damage reaching HP is accumulated")
	start()
	owner = arena.fighters[1]
	enemy = arena.fighters[0]
	skill = owner.skills[0]
	arena.apply_damage(enemy,owner,2000,"lethal")
	arena.step(DT)
	check(not owner.alive and skill.throws_count == 0 and not skill.guarding,"Lethal trigger cannot heal or schedule a counter")
	var slot: Dictionary = Catalog.new_slot("yunli_guard")
	slot.parameters = {"healing_per_second":45.0,"guard_duration":2.0,"damage_reduction":0.5,"counter_base_damage":90.0,"counter_damage_ratio":0.75}
	var configured = Catalog.instantiate(slot)
	check(configured.healing_per_second == 45 and configured.guard_duration == 2 and configured.damage_reduction == .5 and configured.counter_damage_ratio == .75,"Every mechanic reads independent editable parameters")
	configured.free()
	arena.clear_battle()
	arena.free()
	print("YUNLI CHECKS: ",checks," failures: ",failures)
	if failures == 0:
		print("YUNLI TESTS PASSED")
	quit(0 if failures == 0 else 1)
