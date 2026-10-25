extends RefCounted
## Register another CharacterDefinition here to expose it in character selection.

const CHARACTERS = [
	preload("res://data/characters/sword.tres"),
	preload("res://data/characters/mage.tres"),
	preload("res://data/characters/guard.tres"),
	preload("res://data/characters/assassin.tres"),
	preload("res://data/characters/destruction_trailblazer.tres"),
]


static func get_all() -> Array:
	# Definitions are templates. Runtime health and timers live on Fighter/Skill.
	return CHARACTERS.duplicate()
