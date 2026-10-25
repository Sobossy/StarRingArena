extends RefCounted
## Code-registered templates. Saved characters contain IDs, never executable paths.
const ITEMS := [
	{"id":"orbit", "name":"环绕飞剑", "type":"持续", "scene":"res://scenes/skills/orbit_blades.tscn"},
	{"id":"fireball", "name":"火球", "type":"主动", "scene":"res://scenes/skills/fireball.tscn"},
	{"id":"melee", "name":"近战重击", "type":"主动", "scene":"res://scenes/skills/melee.tscn"},
	{"id":"shield", "name":"周期护盾", "type":"被动", "scene":"res://scenes/skills/shield.tscn"},
	{"id":"counter", "name":"受击反击", "type":"被动", "scene":"res://scenes/skills/counter.tscn"},
	{"id":"dash", "name":"冲刺斩击", "type":"主动", "scene":"res://scenes/skills/dash_slash.tscn"},
]

static func find(id: String) -> Dictionary:
	for item in ITEMS:
		if item.id == id:
			return item
	return {}

static func new_slot(template_id: String, slot_id: String = "") -> Dictionary:
	return {"template_id":template_id, "slot_id": slot_id if not slot_id.is_empty() else str(Time.get_ticks_usec()) + "_" + str(randi()), "charge_time":0.0, "release_time":0.3, "charge_can_move":true, "charge_image":"", "release_image":""}

static func instantiate(slot: Dictionary):
	var item := find(str(slot.get("template_id", "")))
	if item.is_empty():
		return null
	var skill = load(item.scene).instantiate()
	skill.slot_id = str(slot.get("slot_id", item.id))
	skill.phase_type = item.type
	skill.charge_time = clampf(float(slot.get("charge_time", 0)), 0, 10)
	skill.release_time = clampf(float(slot.get("release_time", 0.3)), 0, 10)
	skill.charge_can_move = bool(slot.get("charge_can_move", true))
	skill.charge_image_path = str(slot.get("charge_image", ""))
	skill.release_image_path = str(slot.get("release_image", ""))
	return skill
