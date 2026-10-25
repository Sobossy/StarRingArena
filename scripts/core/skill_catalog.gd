extends RefCounted
## Code-registered templates. Saved characters contain IDs, never executable paths.
const ITEMS := [
	{"id":"orbit", "name":"环绕飞剑", "type":"持续", "scene":"res://scenes/skills/orbit_blades.tscn"},
	{"id":"fireball", "name":"火球", "type":"主动", "scene":"res://scenes/skills/fireball.tscn"},
	{"id":"melee", "name":"近战重击", "type":"主动", "scene":"res://scenes/skills/melee.tscn"},
	{"id":"shield", "name":"周期护盾", "type":"被动", "scene":"res://scenes/skills/shield.tscn"},
	{"id":"counter", "name":"受击反击", "type":"被动", "scene":"res://scenes/skills/counter.tscn"},
	{"id":"dash", "name":"冲刺斩击", "type":"主动", "scene":"res://scenes/skills/dash_slash.tscn"},
	{"id":"bat_throw", "name":"毁灭主 · 蓄力回旋球棒", "type":"主动", "scene":"res://scenes/skills/bat_throw.tscn", "charge_max":60.0, "default_charge":6.0},
	{"id":"collision_smash", "name":"毁灭主 · 碰撞重击", "type":"被动", "scene":"res://scenes/skills/collision_smash.tscn"},
	{"id":"sparkle_revolver", "name":"花火 · 六膛惊喜左轮", "type":"持续", "scene":"res://scenes/skills/sparkle_revolver.tscn"},
	{"id":"yunli_guard", "name":"云璃 · 吃串防反与老铁", "type":"被动", "scene":"res://scenes/skills/yunli_guard.tscn"},
]
static var _parameter_cache: Dictionary = {}
const PARAMETER_NAMES := {
	"cooldown":"技能冷却（秒）", "throw_distance":"球棒固定飞行距离", "outbound_speed":"球棒去程速度", "return_speed":"球棒回程速度",
	"outbound_damage":"球棒去程伤害", "return_damage":"球棒回程伤害", "damage":"单次伤害", "damage_multiplier":"伤害倍率",
	"hit_radius":"攻击判定半径", "spin_speed":"旋转速度（弧度/秒）", "knockback_strength":"击退强度", "rehit_interval":"同目标重击间隔（秒）", "contact_extra":"碰撞触发额外距离",
	"reload_time":"上膛时间（秒）", "shot_interval":"扣动扳机间隔（秒）", "bullet_speed":"红色子弹飞行速度", "bullet_damage":"红色子弹伤害", "bullet_radius":"子弹判定半径", "bullet_knockback":"子弹击退强度", "bullet_lifetime":"子弹最长飞行时间（秒）",
	"blade_count":"飞剑数量", "orbit_radius":"飞剑环绕半径", "orbit_speed":"飞剑环绕速度", "contact_radius":"接触判定半径", "hit_interval":"命中间隔（秒）",
	"projectile_speed":"投射物速度", "projectile_radius":"投射物半径", "blast_radius":"爆炸半径", "burn_duration":"灼烧时间（秒）", "burn_dps":"灼烧每秒伤害",
	"shield_amount":"护盾量", "shield_duration":"护盾时间（秒）", "shield_interval":"护盾间隔（秒）", "melee_range":"近战距离", "melee_damage_multiplier":"近战伤害倍率", "counter_multiplier":"反击倍率", "counter_interval":"反击间隔（秒）",
	"dash_speed":"冲刺速度", "dash_duration":"冲刺时间（秒）", "strike_radius":"斩击半径", "slow_duration":"减速时间（秒）", "slow_power":"减速比例", "trigger_range":"触发距离", "enable_shield":"开启护盾", "enable_counter":"开启反击"
,	"angular_speed":"环绕角速度", "blade_radius":"飞剑判定半径", "projectile_lifetime":"投射物存活时间（秒）", "explosion_radius":"爆炸范围", "burn_damage_per_second":"灼烧每秒伤害", "dash_trigger_range":"冲刺触发距离", "slash_radius":"斩击判定半径",
	"healing_per_second":"常态每秒回复生命", "guard_duration":"防反持续时间（秒）", "damage_reduction":"减伤比例（0.2=20%）", "counter_base_damage":"老铁基础伤害", "counter_damage_ratio":"防反受伤转伤害倍率", "sword_speed":"老铁飞行速度", "sword_radius":"老铁判定半径", "sword_lifetime":"老铁最长飞行时间（秒）", "sword_knockback":"老铁击退强度", "sword_spin_speed":"老铁旋转速度（弧度/秒）"
}

static func parameter_definitions(template_id: String) -> Array:
	if _parameter_cache.has(template_id):
		return _parameter_cache[template_id]
	var item := find(template_id)
	var result: Array = []
	if item.is_empty():
		return result
	var sample = load(item.scene).instantiate()
	for property in sample.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_EDITOR) or not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) or int(property.type) not in [TYPE_INT,TYPE_FLOAT,TYPE_BOOL]:
			continue
		var key := str(property.name)
		if key == "cooldown" and template_id in ["bat_throw","collision_smash","sparkle_revolver","yunli_guard"]:
			continue
		var minimum: float = 0.0
		var maximum: float = 100000.0
		var step_value: float = 1.0 if int(property.type) == TYPE_INT else 0.05
		if property.hint == PROPERTY_HINT_RANGE:
			var parts: PackedStringArray = str(property.hint_string).split(",")
			minimum = float(parts[0])
			maximum = float(parts[1])
			if parts.size() > 2:
				step_value = float(parts[2])
		result.append({"key":key,"name":PARAMETER_NAMES.get(key,key),"type":int(property.type),"default":sample.get(key),"min":minimum,"max":maximum,"step":step_value})
	sample.free()
	_parameter_cache[template_id] = result
	return result

static func validate_parameters(slot: Dictionary) -> String:
	var parameters = slot.get("parameters",{})
	if not parameters is Dictionary:
		return "技能数值格式无效。"
	for entry in parameter_definitions(str(slot.get("template_id",""))):
		if not parameters.has(entry.key):
			continue
		var value = parameters[entry.key]
		if entry.type == TYPE_BOOL:
			if not value is bool:
				return "技能开关格式无效。"
		elif not (value is float or value is int) or not is_finite(float(value)) or float(value) < entry.min or float(value) > entry.max:
			return "%s 超出允许范围。" % entry.name
	return ""

static func find(id: String) -> Dictionary:
	for item in ITEMS:
		if item.id == id:
			return item
	return {}

static func new_slot(template_id: String, slot_id: String = "") -> Dictionary:
	var item := find(template_id)
	return {"template_id":template_id, "slot_id": slot_id if not slot_id.is_empty() else str(Time.get_ticks_usec()) + "_" + str(randi()), "charge_time":float(item.get("default_charge",0.0)), "release_time":0.3, "charge_can_move":true, "charge_image":"", "release_image":"", "parameters":{}}

static func instantiate(slot: Dictionary):
	var item := find(str(slot.get("template_id", "")))
	if item.is_empty():
		return null
	var skill = load(item.scene).instantiate()
	skill.slot_id = str(slot.get("slot_id", item.id))
	skill.phase_type = item.type
	skill.charge_time = clampf(float(slot.get("charge_time", item.get("default_charge",0))), 0, float(item.get("charge_max",10)))
	skill.release_time = clampf(float(slot.get("release_time", 0.3)), 0, 10)
	skill.charge_can_move = bool(slot.get("charge_can_move", true))
	skill.charge_image_path = str(slot.get("charge_image", ""))
	skill.release_image_path = str(slot.get("release_image", ""))
	var parameters = slot.get("parameters",{})
	if parameters is Dictionary:
		for entry in parameter_definitions(str(item.id)):
			if parameters.has(entry.key):
				var value = parameters[entry.key]
				if entry.type == TYPE_BOOL:
					skill.set(entry.key,bool(value))
				elif (value is float or value is int) and is_finite(float(value)):
					skill.set(entry.key,clampf(float(value),entry.min,entry.max))
	return skill
