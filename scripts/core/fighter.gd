class_name Fighter
extends RefCounted
## Per-match mutable state, deliberately separate from shared character resources.

var definition
var side: int = 0
var fighter_id: int = 0
var team_id: int = 0
var casting_skill = null
var visual_skill = null
var visual_phase: String = "normal"
var visual_remaining: float = 0.0
var visual_texture: Texture2D = null
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var health: float = 1000.0
var shield: float = 0.0
var shield_remaining: float = 0.0
var alive: bool = true
var skills: Array = []
var statuses: Dictionary = {}
var movement_id: String = "bounce"
var movement
var hit_flash: float = 0.0
var dash_velocity: Vector2 = Vector2.ZERO
var dash_remaining: float = 0.0
var knockback: Vector2 = Vector2.ZERO
var movement_speed_bonus: float = 0.0
var movement_override = null
var local_time: float = 0.0
var aura_slows: Dictionary = {}
var collision_rebound_direction: Vector2 = Vector2.ZERO
var collision_rebound_remaining: float = 0.0
var airborne_remaining: float = 0.0
var airborne_duration: float = 0.0
var airborne_origin: Vector2 = Vector2.ZERO
var airborne_destination: Vector2 = Vector2.ZERO
var airborne_height: float = 0.0
var airborne_peak: float = 0.0
var landing_damage: float = 0.0
var airborne_source = null
var contact_enemies: Array = []
var cut_wall_sides: Dictionary = {}
var last_wall_velocity: Vector2 = Vector2.ZERO
var post_result_heading: Vector2 = Vector2.RIGHT
var lift_time: float = 0.0
var impact_remaining: float = 0.0
var impact_angle: float = 0.0
var impact_recovery: float = 0.0
var impact_recovery_start: float = 0.0
var impact_recovery_target: float = 0.0
var last_hit_direction: Vector2 = Vector2.ZERO
var facing: float = 1.0
var damage_dealt: float = 0.0
var damage_taken: float = 0.0
var healing_done: float = 0.0

func initialize(character_definition, index: int) -> void:
	definition = character_definition
	side = index
	fighter_id = index
	team_id = index
	health = maxf(1.0, definition.max_health)
	movement_id = definition.default_movement

func health_ratio() -> float:
	return clampf(health / maxf(1.0, definition.max_health), 0.0, 1.0)

func movement_speed() -> float:
	return maxf(0.0,definition.speed + movement_speed_bonus)

func clear_runtime() -> void:
	# Status sources and movement owners can otherwise create RefCounted cycles.
	statuses.clear()
	aura_slows.clear()
	contact_enemies.clear()
	cut_wall_sides.clear()
	casting_skill = null
	visual_skill = null
	visual_texture = null
	movement_override = null
	collision_rebound_remaining = 0
	airborne_source = null
	airborne_remaining = 0
	airborne_height = 0
	skills.clear()
	if movement != null:
		movement.fighter = null
		movement.arena = null
	movement = null
