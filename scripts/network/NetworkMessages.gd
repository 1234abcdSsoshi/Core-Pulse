# res://scripts/network/NetworkMessages.gd
# ------------------------------------------------------------
# Step 5: WebSocket message constants.
#
# This file only defines message names and helper constructors.
# It keeps string literals out of the gameplay code.
# ------------------------------------------------------------
class_name NetworkMessages
extends RefCounted

const TYPE_HELLO := "hello"
const TYPE_CREATE_ROOM := "create_room"
const TYPE_JOIN_ROOM := "join_room"
const TYPE_LEAVE_ROOM := "leave_room"
const TYPE_INPUT := "input"
const TYPE_ROOM_CREATED := "room_created"
const TYPE_JOINED_ROOM := "joined_room"
const TYPE_PLAYER_ASSIGNED := "player_assigned"
const TYPE_ERROR := "error"
const TYPE_PEER_JOINED := "peer_joined"
const TYPE_PEER_LEFT := "peer_left"

const TYPE_SET_NAME := "set_name"
const TYPE_SELECT_ROLE := "select_role"
const TYPE_READY := "ready"
const TYPE_START_GAME := "start_game"
const TYPE_ROOM_STATE := "room_state"
const TYPE_GAME_START := "game_start"
const TYPE_GAME_EVENT := "game_event"


static func hello(client_name: String) -> Dictionary:
	return {
		"type": TYPE_HELLO,
		"client_name": client_name
	}


static func create_room(stage_name: String = "story") -> Dictionary:
	return {
		"type": TYPE_CREATE_ROOM,
		"stage": stage_name
	}


static func join_room(room_id: String) -> Dictionary:
	return {
		"type": TYPE_JOIN_ROOM,
		"room_id": room_id
	}


static func input(room_id: String, player_id: int, frame: int, input_data: Dictionary) -> Dictionary:
	return {
		"type": TYPE_INPUT,
		"room_id": room_id,
		"player_id": player_id,
		"frame": frame,
		"input": input_data
	}


static func set_name(player_name: String) -> Dictionary:
	return {
		"type": TYPE_SET_NAME,
		"name": player_name
	}


static func select_role(role: String) -> Dictionary:
	return {
		"type": TYPE_SELECT_ROLE,
		"role": role
	}


static func ready(is_ready: bool) -> Dictionary:
	return {
		"type": TYPE_READY,
		"ready": is_ready
	}


static func start_game(stage_name: String = "story") -> Dictionary:
	return {
		"type": TYPE_START_GAME,
		"stage": stage_name
	}
