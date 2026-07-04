# res://scripts/input/NetworkInputProvider.gd
# ------------------------------------------------------------
# Online input abstraction Step 4.
#
# This provider stores remote player input.
# It now also has a "fake online" mode, which simulates the remote
# player's input without a WebSocket server.
#
# Purpose:
# - Test the game with local input and remote input separated.
# - Verify that Main.gd can treat P1/P2 as independent input sources.
# - Prepare for Step 5, where WebSocket messages will call set_remote_input().
# ------------------------------------------------------------
class_name NetworkInputProvider
extends Node

const PlayerInputStateScript := preload("res://scripts/input/PlayerInputState.gd")

var remote_inputs: Dictionary = {
	1: PlayerInputState.new(),
	2: PlayerInputState.new(),
	3: PlayerInputState.new(),
	4: PlayerInputState.new(),
}

# Fake online test settings.
var fake_online_enabled: bool = false
var fake_remote_player_id: int = 2
var fake_time: float = 0.0
var fake_shoot_timer: float = 0.0
var fake_bomb_timer: float = 0.0


func set_remote_input(player_id: int, data: Dictionary) -> void:
	# Future WebSocket receiver will call this with JSON-decoded input data.
	remote_inputs[player_id] = PlayerInputState.from_dictionary(data)


func set_remote_state(player_id: int, state: PlayerInputState) -> void:
	remote_inputs[player_id] = state.duplicate_state()


func get_remote_input(player_id: int) -> PlayerInputState:
	if not remote_inputs.has(player_id):
		remote_inputs[player_id] = PlayerInputState.new()
	return remote_inputs[player_id]


func configure_fake_online(enabled: bool, remote_player_id: int) -> void:
	# Enable this only for Step 4 local testing.
	fake_online_enabled = enabled
	fake_remote_player_id = clampi(remote_player_id, 1, 4)
	fake_time = 0.0
	fake_shoot_timer = 0.0
	fake_bomb_timer = 0.0
	if not fake_online_enabled:
		remote_inputs[fake_remote_player_id] = PlayerInputState.new()


func update_fake_remote(delta: float) -> void:
	# Simulates the remote player's movement and actions.
	# This is not meant to be a clever AI. It is a safe test input generator
	# for proving the online input routing layer works before WebSocket.
	if not fake_online_enabled:
		return

	fake_time += delta
	fake_shoot_timer -= delta
	fake_bomb_timer -= delta

	var state := PlayerInputState.new()

	# Smooth circular/elliptical movement.
	# This makes the remote player visibly move without needing a second keyboard.
	var x := sin(fake_time * 0.90)
	var y := cos(fake_time * 0.67)
	var move := Vector2(x, y)
	state.move = move.normalized() if move.length() > 0.05 else Vector2.ZERO
	state.aim = state.move

	# Periodic shooting.
	if fake_shoot_timer <= 0.0:
		state.shoot = true
		fake_shoot_timer = 0.42 if fake_remote_player_id == 1 else 0.85

	# Periodic bomb/action. Used mainly for fusion mode tests.
	if fake_bomb_timer <= 0.0:
		state.bomb = true
		fake_bomb_timer = 2.25

	remote_inputs[fake_remote_player_id] = state
