# res://scripts/input/LocalInputProvider.gd
# ------------------------------------------------------------
# Online input abstraction Step 1-3.
# This provider converts local keyboard input into PlayerInputState.
#
# Classic profiles keep the current one-keyboard local two-player game working.
# Online profiles make P1 and P2 use the same keys on their own PC:
#   Move  : Arrow keys
#   Action: Space
# ------------------------------------------------------------
class_name LocalInputProvider
extends Node

const PlayerInputStateScript := preload("res://scripts/input/PlayerInputState.gd")

enum InputProfile {
	CLASSIC_P1,
	CLASSIC_P2,
	CLASSIC_P3,
	ONLINE_P1,
	ONLINE_P2
}


func _ready() -> void:
	ensure_online_input_actions()


func ensure_online_input_actions() -> void:
	# These actions are created at runtime so this patch does not need to edit
	# project.godot manually. Later, you can also register them in Project Settings.
	_add_key_action("online_move_left", KEY_LEFT)
	_add_key_action("online_move_right", KEY_RIGHT)
	_add_key_action("online_move_up", KEY_UP)
	_add_key_action("online_move_down", KEY_DOWN)
	_add_key_action("online_shoot", KEY_SPACE)
	_add_key_action("online_bomb", KEY_SPACE)
	# P3 local: Numpad 8/4/2/6 for movement, Numpad0 for shoot
	_add_key_action("p3_move_up",    KEY_KP_8)
	_add_key_action("p3_move_down",  KEY_KP_2)
	_add_key_action("p3_move_left",  KEY_KP_4)
	_add_key_action("p3_move_right", KEY_KP_6)
	_add_key_action("p3_shoot",      KEY_KP_0)


func get_input_state(profile: int) -> PlayerInputState:
	var state := PlayerInputState.new()

	match profile:
		InputProfile.CLASSIC_P1:
			# Current local P1 operation.
			state.move = _key_vector(KEY_A, KEY_D, KEY_W, KEY_S)
			state.aim = state.move
			state.shoot = Input.is_key_pressed(KEY_F)

		InputProfile.CLASSIC_P2:
			# Current local P2 operation.
			state.move = _key_vector(KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN)
			state.aim = state.move
			state.shoot = Input.is_key_pressed(KEY_L)
			state.bomb = Input.is_key_pressed(KEY_L)

		InputProfile.CLASSIC_P3:
			# P3 local: Numpad 8/4/2/6 + Numpad0
			state.move = Input.get_vector("p3_move_left", "p3_move_right", "p3_move_up", "p3_move_down")
			state.aim = state.move
			state.shoot = Input.is_action_pressed("p3_shoot")

		InputProfile.ONLINE_P1:
			# Online P1: arrows + Space.
			# In fusion mode, arrows become pointer movement and Space becomes cannon.
			state.move = _online_move_vector()
			state.aim = state.move
			state.shoot = Input.is_action_pressed("online_shoot")

		InputProfile.ONLINE_P2:
			# Online P2: arrows + Space.
			# In fusion mode, arrows move the fused ship and Space places a bomb.
			state.move = _online_move_vector()
			state.aim = state.move
			state.shoot = Input.is_action_pressed("online_shoot")
			state.bomb = Input.is_action_pressed("online_bomb")

	return state


func _online_move_vector() -> Vector2:
	return Input.get_vector(
		"online_move_left",
		"online_move_right",
		"online_move_up",
		"online_move_down"
	)


func _key_vector(left_key: Key, right_key: Key, up_key: Key, down_key: Key) -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(left_key):
		dir.x -= 1.0
	if Input.is_key_pressed(right_key):
		dir.x += 1.0
	if Input.is_key_pressed(up_key):
		dir.y -= 1.0
	if Input.is_key_pressed(down_key):
		dir.y += 1.0
	return dir.normalized() if dir.length() > 0.0 else Vector2.ZERO


func _add_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	# Avoid adding the same key repeatedly if the scene reloads.
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.keycode == keycode or key_event.physical_keycode == keycode:
				return

	var new_event := InputEventKey.new()
	new_event.keycode = keycode
	new_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, new_event)
