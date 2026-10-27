extends Node
## Music is independent from combat time, pause and per-match lifetimes.
const MIMI_RELEASE_TIME: float = 0.2
const MIMI_FADE_TIME: float = 0.12
var music_player: AudioStreamPlayer
var cheer_player: AudioStreamPlayer
var enabled: bool = true
var music_volume: float = 50.0
var silent_runtime: bool = false
var cheer_cooldown: float = 0.0
var cheer_count: int = 0
var weapon_players: Array[AudioStreamPlayer] = []
var weapon_streams: Dictionary = {}
var weapon_index: int = 0
var weapon_event_count: int = 0
var character_streams: Dictionary = {}
var character_players: Dictionary = {}
var character_arena = null
var application_backgrounded: bool = false
var time_stop_sound_count: int = 0
var memory_voice_active: bool = false
var music_duck_db: float = 0.0

func setup() -> void:
	silent_runtime = DisplayServer.get_name() == "headless"
	music_player = AudioStreamPlayer.new()
	var music: AudioStreamOggVorbis = load("res://assets/audio/arena_music.ogg").duplicate()
	music.loop = true
	music_player.stream = music
	add_child(music_player)
	cheer_player = AudioStreamPlayer.new()
	cheer_player.stream = load("res://assets/audio/elimination_cheer.ogg")
	cheer_player.max_polyphony = 2
	cheer_player.volume_db = -6.0
	add_child(cheer_player)
	for kind in ["dry_fire","revolver_shot","revolver_reload"]:
		weapon_streams[kind] = load("res://assets/audio/"+kind+".wav")
	for i in range(4):
		var player := AudioStreamPlayer.new()
		player.volume_db = -8
		add_child(player)
		weapon_players.append(player)
	for kind in ["mimi_ora","memory_time_stop","yunli_eating","feiying_horn"]:
		var voice: AudioStreamMP3 = load("res://assets/audio/"+kind+".mp3").duplicate()
		voice.loop = kind in ["mimi_ora","yunli_eating"]
		character_streams[kind] = voice
	apply_music_settings(enabled,music_volume)

func start_music() -> void:
	if not silent_runtime and not music_player.playing:
		music_player.play()

func apply_music_settings(on: bool, volume: float) -> void:
	enabled = on
	music_volume = clampf(volume,0.0,100.0)
	_apply_music_volume()

func _apply_music_volume() -> void:
	if is_instance_valid(music_player):
		music_player.volume_linear = music_volume / 100.0 * db_to_linear(music_duck_db) if enabled else 0.0

func _process(delta: float) -> void:
	cheer_cooldown = maxf(0.0,cheer_cooldown - delta)
	_refresh_memory_voice_state()
	music_duck_db = move_toward(music_duck_db,-8.0 if memory_voice_active else 0.0,(80.0 if memory_voice_active else 20.0)*delta)
	_apply_music_volume()

func play_cheer(_fighter_id: int) -> void:
	# Merge simultaneous eliminations into one crowd instead of stacking eight clips.
	if cheer_cooldown > 0.0:
		return
	cheer_cooldown = 0.18
	cheer_count += 1
	if not silent_runtime:
		cheer_player.play()

func stop_cheers() -> void:
	stop_character_audio()
	cheer_cooldown = 0.0
	if cheer_player != null:
		cheer_player.stop()
	for player in weapon_players:
		player.stop()

func play_weapon_event(kind: String) -> void:
	if not weapon_streams.has(kind):
		return
	weapon_event_count += 1
	if silent_runtime:
		return
	var player: AudioStreamPlayer = weapon_players[weapon_index]
	player.stream = weapon_streams[kind]
	player.volume_db = -14 if kind == "revolver_reload" else -8
	player.play()
	weapon_index = (weapon_index + 1) % weapon_players.size()

func stop_character_audio(only_arena = null) -> void:
	if only_arena != null and character_arena != only_arena:
		return
	for player in character_players.values():
		player.stop()
		player.free()
	character_players.clear()
	character_arena = null
	memory_voice_active = false

func _use_character_arena(battle_arena) -> void:
	if character_arena != battle_arena:
		stop_character_audio()
		character_arena = battle_arena

func _character_gain(kind: String) -> float:
	# These two supplied clips peak well below full scale. The former -10 dB
	# gain buried their speech beneath the music and rapid hit effects.
	if kind in ["mimi_ora","memory_time_stop"]:
		return 6.0
	return -16.0 if kind == "yunli_eating" else -10.0

func _refresh_memory_voice_state() -> void:
	memory_voice_active = false
	for player in character_players.values():
		if player.get_meta("kind") in ["mimi_ora","memory_time_stop"] and not player.stream_paused and (player.playing or silent_runtime):
			memory_voice_active = true
			return

func _new_character_player(actor_id: int, kind: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = character_streams[kind]
	player.set_meta("actor_id",actor_id)
	player.set_meta("kind",kind)
	player.volume_db = _character_gain(kind)
	add_child(player)
	character_players["%d:%s" % [actor_id,kind]] = player
	return player

func play_character_event(event: Dictionary, battle_arena, playback_speed: float = 1.0) -> void:
	var event_kind: String = str(event.get("kind",""))
	if event_kind not in ["time_stop_start","mimi_punch"] or not battle_arena.running:
		return
	_use_character_arena(battle_arena)
	var actor_id: int = int(event.get("side",-1))
	if actor_id < 0 or actor_id >= battle_arena.fighters.size() or not battle_arena.fighters[actor_id].alive:
		return
	var actor = battle_arena.fighters[actor_id]
	if event_kind == "mimi_punch" and (actor.airborne_remaining > 0 or battle_arena.is_time_stopped(actor)):
		return
	var kind: String = "memory_time_stop" if event_kind == "time_stop_start" else "mimi_ora"
	var key: String = "%d:%s" % [actor_id,kind]
	var player: AudioStreamPlayer = character_players.get(key)
	if player == null:
		player = _new_character_player(actor_id,kind)
	if kind == "mimi_ora":
		player.set_meta("release_start",-1.0)
		player.set_meta("release_gain",1.0)
	player.pitch_scale = clampf(playback_speed,0.5,2.0)
	player.stream_paused = application_backgrounded
	if event_kind == "time_stop_start":
		time_stop_sound_count += 1
	if not silent_runtime and (event_kind == "time_stop_start" or not player.playing):
		player.play()
		player.stream_paused = application_backgrounded
	_refresh_memory_voice_state()

func sync_character_audio(battle_arena, combat_paused: bool, playback_speed: float = 1.0) -> void:
	if battle_arena == null or not battle_arena.running:
		stop_character_audio()
		return
	_use_character_arena(battle_arena)
	var loops: Dictionary = {}
	var active_mimi: Dictionary = {}
	for actor in battle_arena.fighters:
		if not actor.alive:
			continue
		for skill in actor.skills:
			if not is_instance_valid(skill) or not skill.active:
				continue
			if skill.skill_id == "memory_mimi":
				active_mimi[actor.fighter_id] = true
			var kind: String = ""
			if skill.skill_id == "memory_mimi" and actor.airborne_remaining <= 0 and skill.attack_remaining > 0:
				kind = "mimi_ora"
			elif skill.skill_id == "yunli_guard" and not skill.guarding:
				kind = "yunli_eating"
			elif skill.skill_id == "feiying_toast" and skill.state == "charge" and skill.phase_remaining <= character_streams["feiying_horn"].get_length():
				kind = "feiying_horn"
			if not kind.is_empty():
				loops["%d:%s" % [actor.fighter_id,kind]] = {"actor":actor,"kind":kind,"remaining":skill.phase_remaining}
	for key in character_players.keys():
		var player: AudioStreamPlayer = character_players[key]
		var id: int = int(player.get_meta("actor_id"))
		var kind: String = str(player.get_meta("kind"))
		var alive: bool = id < battle_arena.fighters.size() and battle_arena.fighters[id].alive
		var finished_loop: bool = kind != "memory_time_stop" and not loops.has(key)
		if finished_loop and kind == "mimi_ora" and alive and active_mimi.has(id):
			var actor = battle_arena.fighters[id]
			if actor.airborne_remaining <= 0:
				# Actor-local simulation time freezes during pause and other actors' time stops.
				var start: float = float(player.get_meta("release_start",-1.0))
				if start < 0:
					start = actor.local_time
					player.set_meta("release_start",start)
				var elapsed: float = maxf(0,actor.local_time-start)
				finished_loop = elapsed >= MIMI_RELEASE_TIME - 0.000001
				player.set_meta("release_gain",clampf((MIMI_RELEASE_TIME-elapsed)/MIMI_FADE_TIME,0.0001,1.0))
		if not alive or finished_loop or (kind == "memory_time_stop" and not player.playing and not silent_runtime):
			player.stop()
			player.free()
			character_players.erase(key)
	for key in loops:
		if not character_players.has(key):
			var player: AudioStreamPlayer = _new_character_player(loops[key].actor.fighter_id,loops[key].kind)
			player.pitch_scale = clampf(playback_speed,0.5,2.0)
			if not silent_runtime:
				# Anchor the one-shot's end to the simulation's ram transition.
				var offset: float = maxf(0,player.stream.get_length()-float(loops[key].remaining)) if loops[key].kind == "feiying_horn" else 0.0
				player.play(offset)
		if loops[key].kind == "mimi_ora":
			character_players[key].set_meta("release_start",-1.0)
			character_players[key].set_meta("release_gain",1.0)
	var audible_counts: Dictionary = {}
	for player in character_players.values():
		var actor = battle_arena.fighters[int(player.get_meta("actor_id"))]
		player.pitch_scale = clampf(playback_speed,0.5,2.0)
		player.stream_paused = application_backgrounded or combat_paused or battle_arena.is_time_stopped(actor) or (player.get_meta("kind") == "feiying_horn" and actor.airborne_remaining > 0)
		if player.get_meta("kind") == "feiying_horn" and player.playing and not player.stream_paused:
			var key: String = "%d:feiying_horn" % actor.fighter_id
			var expected: float = maxf(0,player.stream.get_length()-float(loops[key].remaining))
			if absf(player.get_playback_position()-expected) > 0.04:
				player.seek(expected)
		if not player.stream_paused:
			var kind: String = str(player.get_meta("kind"))
			audible_counts[kind] = int(audible_counts.get(kind,0))+1
	for player in character_players.values():
		var kind: String = str(player.get_meta("kind"))
		var count: int = maxi(1,int(audible_counts.get(kind,1)))
		var compensation: float = 20.0 if kind in ["mimi_ora","memory_time_stop"] else 10.0
		player.volume_db = _character_gain(kind)-compensation*log(float(count))/log(10.0)
		if kind == "mimi_ora":
			player.volume_db += linear_to_db(float(player.get_meta("release_gain",1.0)))
	_refresh_memory_voice_state()

func set_character_backgrounded(backgrounded: bool) -> void:
	application_backgrounded = backgrounded
	if character_arena != null:
		# Foreground resumption is handled by the host's actual pause state.
		if backgrounded:
			for player in character_players.values():
				player.stream_paused = true

func _exit_tree() -> void:
	stop_character_audio()
	for player in [music_player,cheer_player] + weapon_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
