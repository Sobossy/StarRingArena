class_name CharacterDefinition
extends Resource
## Immutable authoring data. Every match creates separate Fighter/skill instances.

@export var id: String = "new_character"
@export var display_name: String = "新角色"
@export_multiline var description: String = ""
@export var portrait: Texture2D
@export var normal_image_path: String = ""
@export_range(24.0, 180.0, 1.0) var portrait_size: float = 82.0
@export var portrait_offset: Vector2 = Vector2.ZERO
@export var theme_color: Color = Color("69d9ff")
@export_range(1.0, 100000.0, 1.0) var max_health: float = 1000.0
@export_range(0.0, 10000.0, 1.0) var attack: float = 38.0
@export_range(0.0, 1000.0, 1.0) var speed: float = 150.0
@export_range(8.0, 80.0, 1.0) var radius: float = 28.0
@export_enum("bounce", "chase", "kite", "wander") var default_movement: String = "bounce"
@export var skill_scenes: Array[PackedScene] = []
@export var skill_slots: Array[Dictionary] = []
