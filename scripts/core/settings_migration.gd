extends RefCounted
## Pure migration: keep custom maps and run the legacy-default change only once.
static func map_configuration(data: Dictionary, migrated: bool) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	if not migrated and float(result.get("width",500)) == 664.0 and float(result.get("height",500)) == 664.0:
		result["width"] = 500.0
		result["height"] = 500.0
	return result
