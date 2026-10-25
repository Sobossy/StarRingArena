extends Node
## Music is independent from combat time, pause and per-match lifetimes.
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
	apply_music_settings(enabled,music_volume)

func start_music() -> void:
	if not silent_runtime and not music_player.playing:
		music_player.play()

func apply_music_settings(on: bool, volume: float) -> void:
	enabled = on
	music_volume = clampf(volume,0.0,100.0)
	if music_player != null:
		music_player.volume_linear = music_volume / 100.0 if enabled else 0.0

func _process(delta: float) -> void:
	cheer_cooldown = maxf(0.0,cheer_cooldown - delta)

func play_cheer(_fighter_id: int) -> void:
	# Merge simultaneous eliminations into one crowd instead of stacking eight clips.
	if cheer_cooldown > 0.0:
		return
	cheer_cooldown = 0.18
	cheer_count += 1
	if not silent_runtime:
		cheer_player.play()

func stop_cheers() -> void:
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

func _exit_tree() -> void:
	for player in [music_player,cheer_player] + weapon_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
