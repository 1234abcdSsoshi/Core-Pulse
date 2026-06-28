# res://scripts/input/InputRouter.gd
# ------------------------------------------------------------
# Online input abstraction Step 4.
# Game code asks this router for P1/P2 input instead of reading keys directly.
# Step 4 adds fake online mode: local input + simulated remote input.
#
# Local mode:
#   P1 = WASD + F
#   P2 = Arrow keys + L
#
# Online preparation mode:
#   Local player = Arrow keys + Space
#   Remote player = NetworkInputProvider
# ------------------------------------------------------------
class_name InputRouter
extends Node

const PlayerInputStateScript := preload("res://scripts/input/PlayerInputState.gd")
const LocalInputProviderScript := preload("res://scripts/input/LocalInputProvider.gd")
const NetworkInputProviderScript := preload("res://scripts/input/NetworkInputProvider.gd")

var local_provider: LocalInputProvider
var network_provider: NetworkInputProvider

# Keep false for current local two-player mode.
# Set true later when connecting to a WebSocket room.
var online_input_mode: bool = false

# In online mode, this browser controls only this player.
var local_player_id: int = 1


func setup(local: LocalInputProvider, network: NetworkInputProvider) -> void:
	local_provider = local
	network_provider = network
	if local_provider != null:
		local_provider.ensure_online_input_actions()


func configure_online_mode(enabled: bool, player_id: int = 1) -> void:
	online_input_mode = enabled
	local_player_id = clampi(player_id, 1, 2)


func get_p1_input() -> PlayerInputState:
	return get_player_input(1)


func get_p2_input() -> PlayerInputState:
	return get_player_input(2)


func get_player_input(player_id: int) -> PlayerInputState:
	if local_provider == null:
		return PlayerInputState.new()

	if online_input_mode:
		if player_id == local_player_id:
			if player_id == 1:
				return local_provider.get_input_state(LocalInputProvider.InputProfile.ONLINE_P1)
			else:
				return local_provider.get_input_state(LocalInputProvider.InputProfile.ONLINE_P2)

		if network_provider != null:
			return network_provider.get_remote_input(player_id)

		return PlayerInputState.new()

	# Classic local mode keeps the current same-PC operation unchanged.
	if player_id == 1:
		return local_provider.get_input_state(LocalInputProvider.InputProfile.CLASSIC_P1)
	if player_id == 3:
		return local_provider.get_input_state(LocalInputProvider.InputProfile.CLASSIC_P3)
	if player_id >= 4:
		return PlayerInputState.new()  # P4+: gamepad/online (placeholder)
	return local_provider.get_input_state(LocalInputProvider.InputProfile.CLASSIC_P2)


func is_online_mode_enabled() -> bool:
	return online_input_mode


func get_local_player_id() -> int:
	return local_player_id
