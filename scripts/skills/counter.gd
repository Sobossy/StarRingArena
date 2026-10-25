extends "res://scripts/skills/skill_base.gd"
@export var damage_multiplier: float = 0.65

func on_damage_received(event: Dictionary) -> void:
	if not can_act() or cooldown_remaining > 0 or not event.get("allow_reaction", true):
		return
	var source = event.get("source")
	if source == null or not source.alive or not arena.is_enemy(fighter, source):
		return
	arena.apply_damage(fighter, source, fighter.definition.attack * damage_multiplier, skill_id, false)
	arena.emit_effect("burst", source.position, fighter.definition.theme_color, {"radius":42.0})
	restart_cooldown()
	flash_release()
