extends RefCounted
## Register another CharacterDefinition here to expose it in character selection.

const CHARACTERS = [
	preload("res://data/characters/destruction_trailblazer.tres"),
	preload("res://data/characters/sparkle.tres"),
	preload("res://data/characters/yunli.tres"),
	preload("res://data/characters/aglaea.tres"),
	preload("res://data/characters/feiying.tres"),
	preload("res://data/characters/memory_trailblazer.tres"),
	preload("res://data/characters/castorice.tres"),
	preload("res://data/characters/acheron.tres"),
	preload("res://data/characters/tribbie.tres"),
]


static func get_all() -> Array:
	# Definitions are templates. Runtime health and timers live on Fighter/Skill.
	return CHARACTERS.duplicate()
