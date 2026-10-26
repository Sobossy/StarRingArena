extends RefCounted
## Code-registered templates. Saved characters contain IDs, never executable paths.
const ITEMS := [
	{"id":"orbit", "name":"环绕飞剑", "type":"持续", "scene":"res://scenes/skills/orbit_blades.tscn"},
	{"id":"fireball", "name":"火球", "type":"主动", "scene":"res://scenes/skills/fireball.tscn"},
	{"id":"melee", "name":"近战重击", "type":"主动", "scene":"res://scenes/skills/melee.tscn"},
	{"id":"shield", "name":"周期护盾", "type":"被动", "scene":"res://scenes/skills/shield.tscn"},
	{"id":"counter", "name":"受击反击", "type":"被动", "scene":"res://scenes/skills/counter.tscn"},
	{"id":"dash", "name":"冲刺斩击", "type":"主动", "scene":"res://scenes/skills/dash_slash.tscn"},
	{"id":"bat_throw", "name":"毁灭·星 · 蓄力回旋球棒", "type":"主动", "scene":"res://scenes/skills/bat_throw.tscn", "charge_max":60.0, "default_charge":6.0},
	{"id":"collision_smash", "name":"毁灭·星 · 碰撞重击", "type":"被动", "scene":"res://scenes/skills/collision_smash.tscn"},
	{"id":"sparkle_revolver", "name":"花火 · 六膛惊喜左轮", "type":"持续", "scene":"res://scenes/skills/sparkle_revolver.tscn"},
	{"id":"yunli_guard", "name":"云璃 · 吃串防反与老铁", "type":"被动", "scene":"res://scenes/skills/yunli_guard.tscn"},
	{"id":"aglaea_threads", "name":"阿格莱雅 · 金线织途", "type":"持续", "scene":"res://scenes/skills/aglaea_threads.tscn"},
	{"id":"feiying_toast", "name":"绯英 · 吐司与大运", "type":"主动", "scene":"res://scenes/skills/feiying_toast.tscn", "default_charge":1.5},
	{"id":"memory_mimi", "name":"记忆·星 · 迷迷与时停", "type":"持续", "scene":"res://scenes/skills/memory_mimi.tscn"},
	{"id":"castorice_aura", "name":"遐蝶 · 泰坦印记与灰黯之手", "type":"持续", "scene":"res://scenes/skills/castorice_aura.tscn"},
	{"id":"acheron_slash", "name":"黄泉 · 斩断棋盘", "type":"主动", "scene":"res://scenes/skills/acheron_slash.tscn", "default_charge":7.0, "charge_max":60.0},
]
static var _parameter_cache: Dictionary = {}
const PARAMETER_NAMES := {
	"aim_wobble_degrees":"蓄力初始预警线摆动幅度（度）", "aim_jitter_interval":"预警线随机摆动间隔（秒）",
	"warning_lock_time":"蓄满后锁线预警（秒）", "slash_damage":"斩击伤害", "slash_half_width":"斩击判定半宽", "cut_wall_half_width":"切面墙半宽", "colour_expand_time":"灰白色扩散时间（秒）", "colour_hold_time":"完全灰白保持时间（秒）", "aim_tracking_speed":"预警线初始追踪速度", "aim_rotation_speed":"预警线初始旋转限速（度/秒）", "lost_chance_percent":"每次碰墙迷路概率（%）",
	"mimi_move_speed":"迷迷出击移动速度", "mimi_return_speed":"迷迷返回头顶速度",
	"punch_range":"迷迷攻击距离（双方碰撞边缘间距）", "punches_per_second":"迷迷每秒拳击次数", "punch_damage":"每次拳击伤害", "ally_hit_charge":"同阵营每次有效伤害充能（%）", "mimi_hit_charge":"自己的迷迷每拳充能（%）", "time_stop_duration":"时停持续时间（秒）", "stopped_range_bonus":"时停攻击距离增加", "mimi_size":"迷迷显示大小", "aura_radius":"伤害圈半径", "aura_damage":"伤害圈单次伤害", "aura_tick_interval":"伤害圈叠层间隔（秒）", "maximum_marks":"终结所需印记层数", "slow_base_percent":"印记基础减速（%）", "slow_per_mark_percent":"每层增加总减速（%）", "execution_damage":"碰撞终结伤害", "retreat_distance":"受伤额外后退距离", "shrink_interval":"灰黯之手缩圈间隔（秒）", "shrink_fraction":"每次缩小原场地比例", "minimum_arena_scale":"场地最小宽高比例",
	"toast_respawn_delay":"冲刺结束后吐司刷新延迟（秒）", "toast_radius":"吐司拾取判定半径", "toast_healing":"拾取吐司回复生命", "toast_seek_delay":"常态后主动找吐司的延迟（秒）", "ram_speed":"大运冲撞速度", "ram_hit_radius":"冲撞判定半径", "ram_damage":"大运冲撞伤害", "launch_strength":"大运击飞强度", "flight_duration":"腾空时间（秒）", "flight_height":"腾空最高高度", "fall_damage":"落地摔落伤害",
	"initial_thread_count":"初始所需金线段数", "threads_per_speed":"每点移速提升增加的金线段数", "speed_gain_per_dash":"每轮冲刺后移速提升", "thread_dash_speed":"沿金线冲刺速度", "thread_damage":"金线触碰伤害", "collision_damage":"身体碰撞伤害", "thread_hit_interval":"金线再次触碰间隔（秒）", "collision_hit_interval":"身体碰撞伤害间隔（秒）", "thread_dash_damage":"冲刺基础伤害", "speed_damage_ratio":"移速提升转冲刺伤害倍率", "thread_hit_radius":"金线判定宽度", "thread_dash_radius":"冲刺判定半径", "thread_dash_knockback":"冲刺击退强度",
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
		if key == "cooldown" and template_id in ["bat_throw","collision_smash","sparkle_revolver","yunli_guard","aglaea_threads","feiying_toast","memory_mimi","castorice_aura","acheron_slash"]:
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
	slot = migrate_slot(slot)
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

static func migrate_slot(original: Dictionary) -> Dictionary:
	var slot: Dictionary = original.duplicate(true)
	if slot.get("template_id","") != "acheron_slash":
		return slot
	if not slot.get("parameters",{}) is Dictionary:
		return slot
	var params: Dictionary = slot.get("parameters",{})
	if params.has("colour_recovery_time"):
		if not params.has("colour_hold_time"):
			var old: float = float(params.colour_recovery_time)
			var expand: float = float(params.get("colour_expand_time",.5))
			params.colour_hold_time = 1.5 if is_equal_approx(old,1.0) and is_equal_approx(expand,.5) else clampf(old-expand,0,10)
		params.erase("colour_recovery_time")
	slot.parameters = params
	return slot
