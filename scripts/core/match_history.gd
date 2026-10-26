extends RefCounted
## Only completed matches reach disk. Active and failed sessions are independent
## of arena lifetime so an immediate rematch cannot erase a finished record.
const Library = preload("res://scripts/core/character_library.gd")
const Catalog = preload("res://scripts/core/skill_catalog.gd")
var storage_root: String
var summaries: Array = []
var session: Dictionary = {}
var pending: Dictionary = {}
var last_error: String = ""
var last_record_id: String = ""

func _init(directory: String = "user://match_history") -> void:
	storage_root = directory
	reload()

func begin(config) -> String:
	discard()
	var id: String = "match_"+str(int(Time.get_unix_time_from_system()*1000))+"_"+Crypto.new().generate_random_bytes(8).hex_encode()
	var participants: Array = []
	for i in range(config.participants.size()):
		var slot: Dictionary = config.participants[i]
		var character: Dictionary = Library.to_data(slot.definition)
		for skill in character.skills:
			var template_id: String = str(skill.get("template_id",""))
			skill["name"] = Catalog.find(template_id).get("name","技能")
			skill["parameter_names"] = {}
			var parameters: Dictionary = skill.get("parameters",{})
			for parameter in Catalog.parameter_definitions(template_id):
				if not parameters.has(parameter.key):
					parameters[parameter.key] = parameter.default
				skill.parameter_names[parameter.key] = parameter.name
			skill.parameters = parameters
		participants.append({"slot":i,"team":i if config.mode == "ffa" else int(slot.get("team",0)),"movement":str(slot.get("movement",slot.definition.default_movement)),"character":character})
	session = {"version":1,"id":id,"completed":false,"started_at":Time.get_unix_time_from_system(),"game_version":ProjectSettings.get_setting("application/config/version",""),"configuration":{"mode":config.mode,"width":config.width,"height":config.height,"duration":config.duration,"seed":config.seed_value},"participants":participants,"events":[]}
	last_record_id = ""
	return id

func discard() -> void:
	session = {}

func append_event(event: Dictionary) -> void:
	if session.is_empty():
		return
	var data: Dictionary = json_value(event)
	data["sequence"] = session.events.size()+1
	session.events.append(data)

func complete(arena) -> String:
	if session.is_empty() or arena.running or arena.result.is_empty() or arena.result.get("reason","") not in ["elimination","timeout"]:
		return ""
	var record: Dictionary = session
	session = {}
	record.completed = true
	record["ended_at"] = Time.get_unix_time_from_system()
	record["elapsed"] = arena.elapsed
	record["ticks"] = arena.tick_count
	record["result"] = arena.result.duplicate(true)
	record["actors"] = []
	for actor in arena.fighters:
		record.actors.append({"slot":actor.side,"team":actor.team_id,"health":actor.health,"max_health":actor.definition.max_health,"alive":actor.alive,"damage_dealt":actor.damage_dealt,"damage_taken":actor.damage_taken,"healing_done":actor.healing_done})
	record["event_count"] = record.events.size()
	record["final_field"] = json_value({"bounds":arena.bounds,"scale":arena.shrink_scale,"cuts":arena.cut_walls})
	last_record_id = str(record.id)
	pending[record.id] = record
	_save_record(record)
	return last_record_id

func _save_record(record: Dictionary) -> bool:
	last_error = ""
	var path: String = storage_root.path_join(str(record.id)+".json")
	if not FileAccess.file_exists(path) and not _write_json(path,record):
		return false
	var summary: Dictionary = summarize(record)
	summaries = summaries.filter(func(item): return item.id != record.id)
	summaries.append(summary)
	_sort()
	if not _write_json(storage_root.path_join("index.json"),{"version":1,"entries":summaries}):
		return false
	pending.erase(record.id)
	return true

func retry_pending() -> bool:
	var success: bool = true
	for id in pending.keys():
		if not _save_record(pending[id]):
			success = false
	return success

func _write_json(path: String,data: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(storage_root) != OK:
		last_error = "无法创建对局记录目录，请检查存储空间或写入权限。"
		return false
	var temporary: String = path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null:
		last_error = "对局记录保存未完成，请检查存储空间后重试。"
		return false
	file.store_string(JSON.stringify(data))
	var error: Error = file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary,path) != OK:
		DirAccess.remove_absolute(temporary)
		last_error = "对局记录保存未完成，原有记录保持不变，可重试保存。"
		return false
	return true

func reload() -> Array:
	summaries.clear()
	var dir := DirAccess.open(storage_root)
	if dir == null:
		return summaries
	var index = _read_json(storage_root.path_join("index.json"))
	var indexed: Dictionary = {}
	var valid_index: bool = index is Dictionary and int(index.get("version",0)) == 1 and index.get("entries") is Array
	if valid_index:
		for entry in index.entries:
			if _valid_summary(entry) and FileAccess.file_exists(storage_root.path_join(str(entry.id)+".json")):
				indexed[str(entry.id)] = entry
	var repaired: bool = not valid_index or indexed.size() != index.entries.size()
	for file in dir.get_files():
		if file.ends_with(".json.tmp") and _safe_id(file.trim_suffix(".json.tmp")):
			DirAccess.remove_absolute(storage_root.path_join(file))
			continue
		if not file.ends_with(".json") or not _safe_id(file.trim_suffix(".json")):
			continue
		var id: String = file.trim_suffix(".json")
		if indexed.has(id):
			summaries.append(indexed[id])
		else:
			var record: Dictionary = load_record(id)
			if not record.is_empty():
				summaries.append(summarize(record))
				repaired = true
	_sort()
	if repaired:
		_write_json(storage_root.path_join("index.json"),{"version":1,"entries":summaries})
	return summaries

func load_record(id: String) -> Dictionary:
	if not _safe_id(id):
		return {}
	if pending.has(id):
		return pending[id]
	var record = _read_json(storage_root.path_join(id+".json"))
	if _valid_record(record,id):
		return record
	return {}

func delete_record(id: String) -> bool:
	if not _safe_id(id):
		return false
	var path: String = storage_root.path_join(id+".json")
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		last_error = "无法删除这份记录，请稍后重试。"
		return false
	pending.erase(id)
	summaries = summaries.filter(func(item): return item.id != id)
	return _write_json(storage_root.path_join("index.json"),{"version":1,"entries":summaries})

func clear_records() -> bool:
	var ids: Dictionary = pending.duplicate()
	var dir := DirAccess.open(storage_root)
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(".json") and _safe_id(file.trim_suffix(".json")):
				ids[file.trim_suffix(".json")] = true
	var success: bool = true
	var removed: Dictionary = {}
	for id in ids:
		if not _safe_id(str(id)):
			continue
		var path: String = storage_root.path_join(str(id)+".json")
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			success = false
			continue
		removed[id] = true
		pending.erase(id)
	summaries = summaries.filter(func(item): return not removed.has(item.id))
	if not _write_json(storage_root.path_join("index.json"),{"version":1,"entries":summaries}):
		return false
	if not success:
		last_error = "部分记录暂时无法删除，可稍后重试。"
	return success

func has_record(id: String) -> bool:
	return pending.has(id) or summaries.any(func(item): return item.id == id)

func _sort() -> void:
	summaries.sort_custom(func(a,b): return str(a.id) > str(b.id) if float(a.ended_at) == float(b.ended_at) else float(a.ended_at) > float(b.ended_at))

static func _safe_id(id: String) -> bool:
	return id.begins_with("match_") and id.is_valid_identifier() and id.length() <= 120

static func _valid_summary(value) -> bool:
	if not value is Dictionary or not _safe_id(str(value.get("id",""))) or not value.get("roles") is Array or not value.get("result") is Dictionary or not value.get("ended_at") is float and not value.get("ended_at") is int:
		return false
	for key in ["elapsed","seed"]:
		if not value.get(key) is float and not value.get(key) is int:
			return false
	if value.get("mode","") not in ["ffa","teams"] or not value.result.has("winning_team"):
		return false
	for role in value.roles:
		if not role is Dictionary or not role.has_all(["slot","team","name"]):
			return false
	return true

static func _valid_record(value,id: String) -> bool:
	if not value is Dictionary or int(value.get("version",0)) != 1 or value.get("completed",false) != true or value.get("id","") != id:
		return false
	if not value.get("participants") is Array or not value.get("actors") is Array or not value.get("events") is Array or not value.get("configuration") is Dictionary or not value.get("result") is Dictionary:
		return false
	if not value.configuration.has_all(["mode","width","height","duration","seed"]) or not value.result.has_all(["winning_team","draw","reason"]) or value.result.reason not in ["elimination","timeout"]:
		return false
	if not value.has_all(["ended_at","elapsed","game_version"]) or value.participants.size() < 2 or value.participants.size() > 8 or value.actors.size() != value.participants.size():
		return false
	for i in range(value.participants.size()):
		var slot = value.participants[i]
		var actor = value.actors[i]
		if not slot is Dictionary or not slot.has_all(["slot","team","movement","character"]) or int(slot.slot) != i or not slot.character is Dictionary or not slot.character.has_all(["name","max_health","speed","radius"]):
			return false
		if not actor is Dictionary or not actor.has_all(["health","max_health","alive","damage_dealt","damage_taken","healing_done"]):
			return false
	for event in value.events:
		if not event is Dictionary or not event.has_all(["kind","time","sequence"]):
			return false
	return true

static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK else null

static func summarize(record: Dictionary) -> Dictionary:
	var roles: Array = []
	for slot in record.participants:
		roles.append({"slot":slot.slot,"team":slot.team,"name":slot.character.name,"image":slot.character.get("normal_image","")})
	return {"id":record.id,"ended_at":record.ended_at,"elapsed":record.elapsed,"mode":record.configuration.mode,"seed":record.configuration.seed,"result":record.result.duplicate(true),"roles":roles,"event_count":record.events.size()}

static func json_value(value):
	match typeof(value):
		TYPE_VECTOR2,TYPE_VECTOR2I:
			return [value.x,value.y]
		TYPE_RECT2,TYPE_RECT2I:
			return {"position":json_value(value.position),"size":json_value(value.size)}
		TYPE_COLOR:
			return value.to_html()
		TYPE_DICTIONARY:
			var output: Dictionary = {}
			for key in value:
				output[str(key)] = json_value(value[key])
			return output
		TYPE_ARRAY:
			return value.map(json_value)
		TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING:
			return value
	return null
