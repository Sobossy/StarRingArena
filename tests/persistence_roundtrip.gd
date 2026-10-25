extends SceneTree
const Library = preload("res://scripts/core/character_library.gd")

func _initialize() -> void:
	var library = Library.new("user://qa_roundtrip")
	library.reload()
	if "--write" in OS.get_cmdline_user_args():
		var definition = library.make_new()
		definition.id = "qa_persistent_character"
		definition.display_name = "跨进程存档测试"
		definition.max_health = 3456
		definition.attack = 78
		definition.speed = 210
		DirAccess.make_dir_recursive_absolute(library.storage_root)
		var image := Image.create(32,64,false,Image.FORMAT_RGBA8)
		image.fill(Color(0.4,0.8,0.9,0.5))
		var source: String = library.storage_root.path_join("source.png")
		image.save_png(source)
		var owned: String = library.import_png(source)
		definition.normal_image_path = owned
		definition.skill_slots[0].charge_image = owned
		definition.skill_slots[0].release_image = owned
		definition.skill_slots[0].charge_time = 0.65
		var success: bool = not owned.is_empty() and library.save_character(definition)
		DirAccess.remove_absolute(source)
		print("PERSISTENCE WRITE OK" if success else "PERSISTENCE WRITE FAILED")
		quit(0 if success else 1)
	else:
		var saved = library.get_character("qa_persistent_character")
		var success: bool = saved != null and saved.max_health == 3456 and saved.attack == 78 and saved.speed == 210 and saved.portrait != null and saved.skill_slots[0].charge_time == 0.65 and Library.texture_from_path(saved.skill_slots[0].release_image) != null
		print("PERSISTENCE READ OK" if success else "PERSISTENCE READ FAILED")
		if saved != null:
			DirAccess.remove_absolute(saved.normal_image_path)
			library.remove_or_restore(saved.id)
			DirAccess.remove_absolute(library.storage_root.path_join("images"))
			DirAccess.remove_absolute(library.storage_root)
		quit(0 if success else 1)
