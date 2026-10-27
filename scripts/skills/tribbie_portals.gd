extends "res://scripts/skills/skill_base.gd"
@export_range(0.1,60,0.1) var portal_interval: float = 8.0
@export_range(0,100000,1) var rocket_damage: float = 60.0
@export_range(100,5000,10) var rocket_speed: float = 600.0
@export_range(0,180,0.5) var rocket_turn_rate: float = 40.0
@export_range(1,1000,1) var explosion_radius: float = 90.0
@export_range(1,100,1) var rocket_radius: float = 12.0
@export_range(16,180,1) var rocket_size: float = 48.0
@export_range(0,1000,1) var rainbow_length: float = 180.0
@export_range(0.1,60,0.1) var rocket_lifetime: float = 10.0

func seed_preview() -> void:
	arena.portals.walls.assign([0,3])
	fighter.position = Vector2(arena.bounds.position.x+fighter.definition.radius+2,arena.bounds.get_center().y)
	fighter.movement.direction = Vector2.LEFT
	fighter.definition.speed = 160
	arena.fighters[1].position = arena.bounds.get_center()
