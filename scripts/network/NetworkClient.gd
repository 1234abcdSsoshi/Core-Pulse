# res://scripts/network/NetworkClient.gd
# ------------------------------------------------------------
# Step 8: Godot-side WebSocket input relay client.
#
# Goal:
# - Connect to a future WebSocket server.
# - Send local PlayerInputState as JSON.
# - Receive remote player input and pass it to Main.gd.
#
# This file is safe even when the server is not running.
# Connection failure is reported with print()/push_warning(), but the game
# continues to work in normal local mode.
# ------------------------------------------------------------
class_name NetworkClient
extends Node

const PlayerInputStateScript := preload("res://scripts/input/PlayerInputState.gd")
const NetworkMessagesScript := preload("res://scripts/network/NetworkMessages.gd")

signal status_changed(status: String)
signal message_received(message: Dictionary)
signal remote_input_received(player_id: int, input_data: Dictionary)
signal player_assigned(player_id: int)
signal room_changed(room_id: String)
signal peer_joined(player_id: int)
signal peer_left(player_id: int)
signal room_state_received(room_state: Dictionary)
signal game_start_received(stage_name: String)

var socket: WebSocketPeer = null
var server_url: String = "wss://twin-core-blasters-1-0.onrender.com"
var room_id: String = ""
var local_player_id: int = 1
var frame_counter: int = 0
var sent_input_count: int = 0
var received_input_count: int = 0

var _last_ready_state: int = WebSocketPeer.STATE_CLOSED


func _ready() -> void:
	set_process(false)


func connect_to_server(url: String = "wss://twin-core-blasters-1-0.onrender.com") -> void:
	# Close any previous socket before creating a new one.
	disconnect_from_server()

	server_url = url
	socket = WebSocketPeer.new()

	var err := socket.connect_to_url(server_url)
	if err != OK:
		socket = null
		push_warning("[NetworkClient] Failed to connect: " + server_url)
		status_changed.emit("connect_failed")
		return

	_last_ready_state = WebSocketPeer.STATE_CONNECTING
	set_process(true)
	status_changed.emit("connecting")
	print("[NetworkClient] Connecting to " + server_url)


func disconnect_from_server() -> void:
	if socket != null:
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_send_json({
				"type": NetworkMessagesScript.TYPE_LEAVE_ROOM,
				"room_id": room_id,
				"player_id": local_player_id
			})
		socket.close()

	socket = null
	room_id = ""
	set_process(false)
	_last_ready_state = WebSocketPeer.STATE_CLOSED
	status_changed.emit("disconnected")


func is_connected_to_server() -> bool:
	return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _process(_delta: float) -> void:
	if socket == null:
		return

	socket.poll()

	var state := socket.get_ready_state()
	if state != _last_ready_state:
		_last_ready_state = state
		_emit_state_status(state)

	if state == WebSocketPeer.STATE_OPEN:
		_read_packets()
	elif state == WebSocketPeer.STATE_CLOSED:
		set_process(false)


func _emit_state_status(state: int) -> void:
	match state:
		WebSocketPeer.STATE_CONNECTING:
			status_changed.emit("connecting")
			print("[NetworkClient] Connecting...")
		WebSocketPeer.STATE_OPEN:
			status_changed.emit("connected")
			print("[NetworkClient] Connected.")
			_send_json(NetworkMessagesScript.hello("godot_client"))
		WebSocketPeer.STATE_CLOSING:
			status_changed.emit("closing")
			print("[NetworkClient] Closing...")
		WebSocketPeer.STATE_CLOSED:
			status_changed.emit("closed")
			print("[NetworkClient] Closed.")


func _read_packets() -> void:
	while socket != null and socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		var text := packet.get_string_from_utf8()
		var parsed = JSON.parse_string(text)

		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("[NetworkClient] Invalid JSON received: " + text)
			continue

		var message: Dictionary = parsed
		message_received.emit(message)
		_handle_message(message)


func _handle_message(message: Dictionary) -> void:
	var message_type := str(message.get("type", ""))

	match message_type:
		NetworkMessagesScript.TYPE_ROOM_CREATED:
			room_id = str(message.get("room_id", ""))
			room_changed.emit(room_id)
			print("[NetworkClient] Room created: " + room_id)

		NetworkMessagesScript.TYPE_JOINED_ROOM:
			room_id = str(message.get("room_id", room_id))
			room_changed.emit(room_id)
			print("[NetworkClient] Joined room: " + room_id)

		NetworkMessagesScript.TYPE_PLAYER_ASSIGNED:
			local_player_id = int(message.get("player_id", local_player_id))
			player_assigned.emit(local_player_id)
			print("[NetworkClient] Assigned local player: P%d" % local_player_id)

		NetworkMessagesScript.TYPE_INPUT:
			var sender_id := int(message.get("player_id", 0))
			if sender_id != local_player_id:
				var input_data: Dictionary = message.get("input", {})
				received_input_count += 1
				remote_input_received.emit(sender_id, input_data)

		NetworkMessagesScript.TYPE_PEER_JOINED:
			var joined_id := int(message.get("player_id", 0))
			peer_joined.emit(joined_id)
			print("[NetworkClient] Peer joined: P%d" % joined_id)

		NetworkMessagesScript.TYPE_PEER_LEFT:
			var left_id := int(message.get("player_id", 0))
			peer_left.emit(left_id)
			print("[NetworkClient] Peer left: P%d" % left_id)

		NetworkMessagesScript.TYPE_ROOM_STATE:
			# Step 9-12: 繝ｭ繝薙・UI譖ｴ譁ｰ逕ｨ縺ｮ驛ｨ螻狗憾諷九〒縺吶・
			var room_state: Dictionary = message.get("room", {})
			room_state_received.emit(room_state)

		NetworkMessagesScript.TYPE_GAME_START:
			# Step 12: 蜈ｨ繧ｯ繝ｩ繧､繧｢繝ｳ繝医′蜷後§繧ｹ繝・・繧ｸ繧帝幕蟋九＠縺ｾ縺吶・
			var stage_name := str(message.get("stage", "story"))
			game_start_received.emit(stage_name)
			print("[NetworkClient] Game start: " + stage_name)

		NetworkMessagesScript.TYPE_ERROR:
			push_warning("[NetworkClient] Server error: " + str(message.get("message", "")))

		_:
			# Unknown messages are still emitted through message_received.
			pass


func create_room(stage_name: String = "story") -> void:
	if not is_connected_to_server():
		push_warning("[NetworkClient] Cannot create room: not connected.")
		return

	_send_json(NetworkMessagesScript.create_room(stage_name))


func join_room(target_room_id: String) -> void:
	if not is_connected_to_server():
		push_warning("[NetworkClient] Cannot join room: not connected.")
		return

	_send_json(NetworkMessagesScript.join_room(target_room_id))


func set_player_name(player_name: String) -> void:
	# Step 9: 繝ｭ繝薙・UI縺ｧ蜈･蜉帙＠縺溷錐蜑阪ｒ繧ｵ繝ｼ繝舌・縺ｫ騾√ｊ縺ｾ縺吶・
	if not is_connected_to_server():
		return
	_send_json(NetworkMessagesScript.set_name(player_name))


func select_role(role: String) -> void:
	# Step 10: P1/P2繧ｫ繝ｼ繝蛾∈謚槭ｒ繧ｵ繝ｼ繝舌・縺ｸ騾√ｊ縺ｾ縺吶・
	if not is_connected_to_server():
		return
	_send_json(NetworkMessagesScript.select_role(role))


func set_ready(is_ready: bool) -> void:
	# Step 11: Waiting Room縺ｮReady迥ｶ諷九ｒ繧ｵ繝ｼ繝舌・縺ｸ騾√ｊ縺ｾ縺吶・
	if not is_connected_to_server():
		return
	_send_json(NetworkMessagesScript.ready(is_ready))


func start_game(stage_name: String = "story") -> void:
	# Step 12: 繝帙せ繝医′繧ｲ繝ｼ繝髢句ｧ九ｒ隕∵ｱゅ＠縺ｾ縺吶・
	if not is_connected_to_server():
		return
	_send_json(NetworkMessagesScript.start_game(stage_name))


func send_input_state(state: PlayerInputState) -> void:
	if not is_connected_to_server():
		return

	if room_id.strip_edges() == "":
		return

	frame_counter += 1
	sent_input_count += 1
	_send_json(NetworkMessagesScript.input(
		room_id,
		local_player_id,
		frame_counter,
		state.to_dictionary()
	))


func _send_json(data: Dictionary) -> void:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var text := JSON.stringify(data)
	socket.send_text(text)
