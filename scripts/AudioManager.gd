# res://scripts/AudioManager.gd
# ------------------------------------------------------------
# AudioManager
#
# Step 8 purpose:
# - Can be used as an Autoload singleton.
# - Keeps BGM and SFX playback out of Main.gd.
# - Manually loops BGM and shield-loop SFX using the finished signal.
#
# Usage from any script:
#   AudioManager.play_bgm("story")
#   AudioManager.play_sfx("ui_confirm")
#
# Safety:
# - Missing keys and missing files are handled by push_warning() instead of hard errors.
# ------------------------------------------------------------
extends Node

const AssetPaths = preload("res://scripts/AssetPaths.gd")

var bgm_player: AudioStreamPlayer
var shield_loop_player: AudioStreamPlayer

var current_bgm_key: String = ""
var shield_loop_enabled: bool = false


func _ready() -> void:
	_ensure_players()


func _ensure_players() -> void:
	# Main BGM player.
	if bgm_player == null:
		bgm_player = AudioStreamPlayer.new()
		bgm_player.bus = "Master"
		add_child(bgm_player)

	if not bgm_player.finished.is_connected(_on_bgm_finished):
		bgm_player.finished.connect(_on_bgm_finished)

	# Dedicated loop player for shield ambience.
	if shield_loop_player == null:
		shield_loop_player = AudioStreamPlayer.new()
		shield_loop_player.bus = "Master"
		add_child(shield_loop_player)

	if not shield_loop_player.finished.is_connected(_on_shield_loop_finished):
		shield_loop_player.finished.connect(_on_shield_loop_finished)


func play_bgm(key: String, volume_db: float = -8.0) -> void:
	_ensure_players()

	# Avoid restarting the same BGM every frame.
	if current_bgm_key == key and bgm_player.playing:
		return

	if not AssetPaths.BGM.has(key):
		push_warning("BGM key not found: " + key)
		return

	var path: String = AssetPaths.BGM[key]
	if not ResourceLoader.exists(path):
		push_warning("BGM file not found: " + path)
		return

	current_bgm_key = key
	bgm_player.stop()
	bgm_player.stream = load(path)
	bgm_player.volume_db = volume_db
	bgm_player.play()


func stop_bgm() -> void:
	_ensure_players()
	current_bgm_key = ""
	bgm_player.stop()


func pause_bgm() -> void:
	_ensure_players()
	bgm_player.stream_paused = true


func resume_bgm() -> void:
	_ensure_players()
	bgm_player.stream_paused = false


func _on_bgm_finished() -> void:
	# AudioStreamPlayer.finished is emitted when playback reaches the end.
	# stop() does not emit this signal, so current_bgm_key safely controls looping.
	if current_bgm_key != "" and bgm_player != null and bgm_player.stream != null:
		bgm_player.play()


func play_sfx(key: String, volume_db: float = -4.0, pitch_scale: float = 1.0) -> void:
	_ensure_players()

	if not AssetPaths.SFX.has(key):
		push_warning("SFX key not found: " + key)
		return

	var path: String = AssetPaths.SFX[key]
	if not ResourceLoader.exists(path):
		push_warning("SFX file not found: " + path)
		return

	# One-shot SFX players delete themselves after playback.
	var player := AudioStreamPlayer.new()
	player.bus = "Master"
	player.stream = load(path)
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func start_shield_loop() -> void:
	_ensure_players()

	if not AssetPaths.SFX.has("shield_loop"):
		return

	var path: String = AssetPaths.SFX["shield_loop"]
	if not ResourceLoader.exists(path):
		return

	shield_loop_enabled = true

	if shield_loop_player.playing:
		return

	shield_loop_player.stream = load(path)
	shield_loop_player.volume_db = -16.0
	shield_loop_player.play()


func stop_shield_loop() -> void:
	_ensure_players()
	shield_loop_enabled = false

	if shield_loop_player.playing:
		shield_loop_player.stop()


func _on_shield_loop_finished() -> void:
	if shield_loop_enabled and shield_loop_player != null and shield_loop_player.stream != null:
		shield_loop_player.play()
