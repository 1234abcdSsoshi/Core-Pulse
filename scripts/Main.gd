extends Node2D

const AssetPaths = preload("res://scripts/AssetPaths.gd")
const AudioManagerScript = preload("res://scripts/AudioManager.gd")
const PlayerInputStateScript := preload("res://scripts/input/PlayerInputState.gd")
const LocalInputProviderScript := preload("res://scripts/input/LocalInputProvider.gd")
const NetworkInputProviderScript := preload("res://scripts/input/NetworkInputProvider.gd")
const InputRouterScript := preload("res://scripts/input/InputRouter.gd")
const NetworkClientScript := preload("res://scripts/network/NetworkClient.gd")
const OnlineLobbyControllerScript := preload("res://scripts/ui/OnlineLobbyController.gd")

# Stage controller scripts.
# These are thin wrappers for now. They call the existing Main.gd gameplay
# functions, so we can test stage separation without moving everything at once.
const StoryStageScript = preload("res://scenes/stages/StoryStage.gd")
const AstralCourtStageScript = preload("res://scenes/stages/AstralCourtStage.gd")
const RaidStageScript = preload("res://scenes/stages/RaidStage.gd")

enum GameMode { TITLE, STORY, ASTRAL_COURT, RAID }

# ── ゲームバランス設定 ────────────────────────────────────────────────────────
# ここの値を変えるだけでバランス調整できます。
const CORE_HP_MAX := 1000      # コアの最大体力（Story Mode）
# ─────────────────────────────────────────────────────────────────────────────

var mode: GameMode = GameMode.TITLE

# StageRoot is added to Main.tscn.
# New stage controller nodes are instantiated under this node.
@onready var stage_root: Node2D = $StageRoot

# Current active stage controller.
# Main.gd keeps the existing gameplay functions for now, but the selected
# stage decides which update function is called.
var current_stage: StageBase = null

var screen_size := Vector2(1920, 1080)
var rng := RandomNumberGenerator.new()
var audio_manager: Node

# Online input abstraction Step 1-3.
# The game asks input_router for P1/P2 input instead of reading all keys directly.
var input_router: InputRouter
var local_input_provider: LocalInputProvider
var network_input_provider: NetworkInputProvider

# Keep false for current same-PC local play.
# Later, set true when entering an online room.
var online_input_mode: bool = false
var online_local_player_id: int = 1

# Step 4: fake online test mode.
# This mode uses the online input route without WebSocket.
# - Local player uses Arrow keys + Space.
# - Remote player is simulated by NetworkInputProvider.
# Hotkeys:
#   F8 = toggle fake online test mode
#   F9 = switch local player between P1 and P2
var fake_online_test_mode: bool = false

# Step 5: WebSocket client preparation.
# The client can connect to a future Node.js WebSocket server.
# It is safe when no server is running; normal local play still works.
var network_client: NetworkClient = null
var online_lobby: OnlineLobbyController = null
var online_player_name: String = "Player"
var online_selected_role: String = ""
var online_ready: bool = false
var network_server_url: String = "wss://twin-core-blasters-1-0.onrender.com"
var network_send_interval: float = 1.0 / 30.0
var network_send_accumulator: float = 0.0
var network_debug_room_id: String = "TEST"

# Step 7: room join flow.
# F7 enters a room code. Type A-Z / 0-9, then Enter or F12 to join.
# F11 creates a room and displays the code.
var network_join_room_code: String = ""
var network_room_entry_mode: bool = false
var network_last_status: String = "offline"
var network_last_message: String = ""
var network_peer_status: String = "waiting"

# Step 8: online input relay statistics.
# These counters make it easy to verify that local input is being sent
# and remote input is being received through the WebSocket server.
var network_input_send_count: int = 0
var network_input_receive_count: int = 0
var network_last_remote_player_id: int = 0
var network_last_remote_input_text: String = ""

# Step 13: 繧ｪ繝ｳ繝ｩ繧､繝ｳ繧ｲ繝ｼ繝髢句ｧ句ｾ後・迥ｶ諷狗ｮ｡逅・〒縺吶
# Start Game繧貞女縺大叙縺｣縺溘ｉ true 縺ｫ縺励√Ο繝薙・繧帝哩縺倥※繧ｲ繝ｼ繝逕ｻ髱｢縺ｸ遘ｻ陦後＠縺ｾ縺吶
var online_game_active: bool = false
var online_game_stage: String = "story"
var online_game_started_by_server: bool = false

var players: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var enemy_bullets: Array[Dictionary] = []
var items: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var bombs: Array[Dictionary] = []

var team_score := 0
var p1_score := 0
var p2_score := 0
var base_hp := CORE_HP_MAX
var core_shield_time := 0.0
var coop_link := 0.0
var story_wave := 1
var result_title := ""
var result_message := ""
var game_over := false

var enemy_spawn_timer := 1.2
var item_spawn_timer := 5.0
var shoot_cd_p1 := 0.0
var shoot_cd_p2 := 0.0

# Player individuality settings for Story Mode.
# P1 = Azure Wing: fast, precise, rapid-fire.
# P2 = Solar Fang: slower, heavy, high-damage and wide-area.
var player_specs := {
	1: {
		"name": "Azure Wing",
		"speed": 560.0,
		"shot_speed": 1250.0,
		"shoot_interval": 0.14,
		"rapid_interval": 0.07,
		"damage": 8,
		"bullet_size": 28.0,
		"power_mode": "piercing_laser"
	},
	2: {
		"name": "Solar Fang",
		"speed": 360.0,
		"shot_speed": 850.0,
		"shoot_interval": 0.42,
		"rapid_interval": 0.22,
		"damage": 26,
		"bullet_size": 48.0,
		"power_mode": "giant_bullet"
	}
}

# Story fusion mode: Fusion Siege Mode.
# In this mode, the fused ship does not rotate.
# - P1 controls a free pointer with WASD and fires toward it with F.
# - P2 moves the fused ship with Arrow keys and places bombs with L.
var story_fusion_active := false
var story_fusion_timer := 0.0
var story_fusion_position := Vector2.ZERO
var story_fusion_aim := Vector2.UP
var story_fusion_pointer_pos := Vector2.ZERO
var story_fusion_cannon_cd := 0.0
var story_fusion_bomb_cd := 0.0
var story_fusion_duration := 12.0
var story_pointer_min_distance := 80.0
var story_pointer_max_distance := 280.0
var story_pointer_speed := 620.0
var story_fusion_move_speed := 420.0
var story_bomb_max_count := 3
var story_bomb_cooldown := 0.8
var story_bomb_trigger_radius := 34.0

# Fusion flash & timer bar
var fusion_flash_timer := 0.0
var fusion_flash_rect: ColorRect
var fusion_bar_back: ColorRect
var fusion_bar_fill: ColorRect
var story_bomb_explosion_radius := 185.0
var story_bomb_fuse_time := 3.0
var story_bomb_strong_damage := 55

# Crystal & shop system
var crystals := 0
var crystal_objects: Array[Dictionary] = []
var crystal_magnet_timer := 0.0
var shop_active := false
var shop_page := 0  # 0=ITEMS  1=WEAPONS  2=TURRETS
var shop_layer: CanvasLayer
var hud_crystal_label: Label
var shop_notify_ring: ColorRect
var shop_hud_container: Control
var p1_weapon: String = ""
var p2_weapon: String = ""
var p1_weapon_cd := 0.0
var p2_weapon_cd := 0.0
var missiles: Array[Dictionary] = []
var turrets: Array[Dictionary] = []
var max_turrets := 3
var emp_stun_timer := 0.0

# Astral Court
var arena_time := 60.0
var arena_p1_hp := 100
var arena_p2_hp := 100
var p1_core := 0.0
var p2_core := 0.0
var p1_shield := 0.0
var p2_shield := 0.0
var p1_dash_cd := 0.0
var p2_dash_cd := 0.0
var p1_ult_ready := false
var p2_ult_ready := false
var arena_obstacles: Array[Rect2] = []
var astral_core_pos := Vector2.ZERO

# Raid
var raid_phase := 1
var raid_link := 0.0
var raid_attack_timer := 1.8
var raid_drone_timer := 4.0
var raid_weak_index := 1
var raid_weak_timer := 3.5
var raid_boss_hp := 700
var raid_boss_max_hp := 700
var raid_message := "Break the glowing weak core."
var raid_boss_time := 0.0
var raid_boss_center := Vector2.ZERO
var raid_weak_offsets: Array[Vector2] = [Vector2(-240, 70), Vector2(0, 92), Vector2(240, 70)]

# Visual nodes
var bg_sprite: Sprite2D
var base_sprite: Sprite2D
var base_shield_sprite: Sprite2D
var astral_ring_sprite: Sprite2D
var arena_obstacle_sprites: Array[Sprite2D] = []
var boss_sprite: Sprite2D
var raid_weak_sprites: Array[Sprite2D] = []
var fusion_sprite: Sprite2D
var fusion_pointer_line: Line2D
var fusion_pointer_reticle: Sprite2D

# UI
var ui_layer: CanvasLayer
var hud_label: Label
var title_layer: CanvasLayer
var title_label: Label
var title_options_label: Label
var title_buttons: Array[Button] = []
var instruction_layer: CanvasLayer
var instruction_title: Label
var instruction_body: Label
var instruction_start_button: Button
var instruction_back_button: Button
var instruction_visible: bool = false
var pending_stage_script: Script = null
var pending_stage_name: String = ""
var last_stage_script: Script = null
var game_over_layer: CanvasLayer
var game_over_title: Label
var game_over_detail: Label
var result_home_button: Button
var result_retry_button: Button
var banner_label: Label
var link_back: ColorRect
var link_fill: Sprite2D
var boss_hp_back: Sprite2D
var boss_hp_fill: ColorRect

# Story HUD bar (top compact bar)
var story_hud_container: Control      # master container — hide to remove all
var story_hud_bar: ColorRect
var story_mode_label: Label
var story_core_bar_bg: ColorRect
var story_core_bar_fill: ColorRect
var story_core_label: Label
var story_shield_bar_bg: ColorRect
var story_shield_bar_fill: ColorRect
var story_shield_label: Label         # "Xs" fallback when no shield
var story_score_label: Label
var story_link_container: Control     # shown only when coop_link > 0
var story_link_header_label: Label    # "CO-OP LINK" / "FUSION TIME"
var story_link_bar_bg: ColorRect
var story_link_bar_fill: ColorRect
var story_link_label: Label           # "XX%" or "💣x/y"
var story_fusion_label: Label
var core_shield_max := 0.0            # tracks max shield for bar ratio

# Step 13: 繧ｪ繝ｳ繝ｩ繧､繝ｳ繝励Ξ繧､荳ｭ縺縺題｡ｨ遉ｺ縺吶ｋ蟆上＆縺ｪ繧ｹ繝・・繧ｿ繧ｹHUD縺ｧ縺吶
# 繝ｭ繝薙・UI縺ｨ縺ｯ蛻･縺ｮCanvasLayer縺ｫ縺励※縲√ご繝ｼ繝逕ｻ髱｢縺ｮ荳翫↓蝗ｺ螳夊｡ｨ遉ｺ縺励∪縺吶
var online_status_layer: CanvasLayer
var online_status_panel: ColorRect
var online_status_label: Label
var online_return_button: Button

var paused := false
var pause_layer: CanvasLayer

func _unhandled_input(event: InputEvent) -> void:
	# Development hotkeys.
	# F6: print online input relay debug info.
	# F7: start room code input.
	# F8: toggle fake online test mode.
	# F9: swap fake-online local player.
	# F10: connect/disconnect WebSocket.
	# F11: create room.
	# F12: join typed room code.
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if network_room_entry_mode and _handle_room_code_input(key_event):
				get_viewport().set_input_as_handled()
				return

			if key_event.keycode == KEY_TAB:
				if mode == GameMode.STORY and not game_over:
					if shop_active:
						_close_shop()
					else:
						_open_shop()
					get_viewport().set_input_as_handled()
				return

			if shop_active:
				if key_event.keycode == KEY_ESCAPE:
					_close_shop()
					get_viewport().set_input_as_handled()
				return

			if key_event.keycode == KEY_F6:
				_print_network_input_debug()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_F7:
				_network_start_room_entry()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_F8:
				_toggle_fake_online_test_mode()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_F9:
				_switch_fake_online_local_player()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_F10:
				_toggle_network_connection()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_F11:
				_network_create_room()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_F12:
				_network_join_room()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_ESCAPE:
				if mode != GameMode.TITLE and not game_over:
					if paused:
						_resume_game()
					else:
						_pause_game()
					get_viewport().set_input_as_handled()

func _ready() -> void:
	rng.randomize()
	screen_size = get_viewport_rect().size
	_setup_input_abstraction()
	_setup_network_client()
	_setup_world()
	_setup_ui()
	# Prefer the Autoload AudioManager if it exists.
	# If the project is opened without Autoload setup, create a local fallback.
	audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		audio_manager = AudioManagerScript.new()
		add_child(audio_manager)
	_show_title()

func _process(delta: float) -> void:
	_update_fake_online_test(delta)
	_update_network_input_sending(delta)
	_update_online_status_hud()

	if game_over:
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		_update_ui()
		_update_effects(delta)
		return

	if mode == GameMode.TITLE:
		_handle_title_input()
		return

	if paused or shop_active:
		return

	shoot_cd_p1 = maxf(0.0, shoot_cd_p1 - delta)
	shoot_cd_p2 = maxf(0.0, shoot_cd_p2 - delta)

	# Common update shared by all current stages.
	# Later, these updates will move into StageBase or stage-specific files.
	_update_players(delta)
	_update_bullets(delta)
	_update_items(delta)
	_update_bombs(delta)
	_update_effects(delta)
	if mode == GameMode.STORY:
		_update_crystals(delta)
		_update_missiles(delta)
		_update_turrets(delta)

	# Stage-specific update now goes through the active stage controller.
	# This replaces the previous match statement:
	# STORY -> _update_story(delta)
	# ASTRAL_COURT -> _update_astral_court(delta)
	# RAID -> _update_raid(delta)
	if current_stage != null:
		current_stage.update_stage(delta)

	_update_ui()


func _setup_input_abstraction() -> void:
	# Step 1-3 online preparation:
	# Create a local input provider, a future network input holder, and a router.
	# In current local play, the router preserves the old key mapping:
	#   P1 = WASD + F
	#   P2 = Arrow keys + L
	# In future online play, each PC will use:
	#   Move = Arrow keys
	#   Shot / action = Space
	local_input_provider = LocalInputProviderScript.new()
	add_child(local_input_provider)

	network_input_provider = NetworkInputProviderScript.new()
	add_child(network_input_provider)

	input_router = InputRouterScript.new()
	add_child(input_router)
	input_router.setup(local_input_provider, network_input_provider)
	input_router.configure_online_mode(online_input_mode, online_local_player_id)



func _setup_network_client() -> void:
	# Step 5:
	# Create the WebSocket client node.
	# This does not connect automatically, so local play is unchanged.
	network_client = NetworkClientScript.new()
	add_child(network_client)

	network_client.status_changed.connect(_on_network_status_changed)
	network_client.message_received.connect(_on_network_message_received)
	network_client.remote_input_received.connect(_on_network_remote_input_received)
	network_client.player_assigned.connect(_on_network_player_assigned)
	network_client.room_changed.connect(_on_network_room_changed)
	if network_client.has_signal("peer_joined"):
		network_client.peer_joined.connect(_on_network_peer_joined)
	if network_client.has_signal("peer_left"):
		network_client.peer_left.connect(_on_network_peer_left)
	if network_client.has_signal("room_state_received"):
		network_client.room_state_received.connect(_on_network_room_state_received)
	if network_client.has_signal("game_start_received"):
		network_client.game_start_received.connect(_on_network_game_start_received)


func set_online_input_mode(enabled: bool, local_player_id: int = 1) -> void:
	# This is the switch that the future NetworkManager will call after room join.
	online_input_mode = enabled
	online_local_player_id = clampi(local_player_id, 1, 2)
	if input_router != null:
		input_router.configure_online_mode(online_input_mode, online_local_player_id)

	# If normal online mode is disabled, fake online must also be disabled.
	if not online_input_mode:
		fake_online_test_mode = false
		if network_input_provider != null and network_input_provider.has_method("configure_fake_online"):
			network_input_provider.configure_fake_online(false, 2)


func set_fake_online_test_mode(enabled: bool, local_player_id: int = 1) -> void:
	# Step 4 development mode.
	# This lets us test online-style input without a server.
	fake_online_test_mode = enabled
	online_input_mode = enabled
	online_local_player_id = clampi(local_player_id, 1, 2)
	if input_router != null:
		input_router.configure_online_mode(true, online_local_player_id)

	var remote_player_id := 2 if online_local_player_id == 1 else 1
	if network_input_provider != null and network_input_provider.has_method("configure_fake_online"):
		network_input_provider.configure_fake_online(fake_online_test_mode, remote_player_id)

	if fake_online_test_mode:
		print("[Fake Online] Enabled. Local player = P%d, Remote player = P%d" % [online_local_player_id, remote_player_id])
	else:
		# Return to classic same-PC local play.
		online_input_mode = false
		if input_router != null:
			input_router.configure_online_mode(false, 1)
		print("[Fake Online] Disabled. Back to classic local play.")


func _toggle_fake_online_test_mode() -> void:
	set_fake_online_test_mode(not fake_online_test_mode, online_local_player_id)


func _switch_fake_online_local_player() -> void:
	var next_player_id := 2 if online_local_player_id == 1 else 1
	set_fake_online_test_mode(true, next_player_id)


func _update_fake_online_test(delta: float) -> void:
	# Keep remote input changing during Step 4 fake online mode.
	if fake_online_test_mode and network_input_provider != null and network_input_provider.has_method("update_fake_remote"):
		network_input_provider.update_fake_remote(delta)



func _get_player_input(player_id: int) -> PlayerInputState:
	if input_router == null:
		return PlayerInputState.new()
	return input_router.get_player_input(player_id)


func _is_player_shooting(player_id: int) -> bool:
	return _get_player_input(player_id).shoot


func _is_player_bombing(player_id: int) -> bool:
	var state := _get_player_input(player_id)
	return state.bomb or state.shoot


func _is_any_online_action_pressed() -> bool:
	# Step 14:
	# 繧ｪ繝ｳ繝ｩ繧､繝ｳ譎ゅ・蜷ПC縺ｧ縲檎泙蜊ｰ繧ｭ繝ｼ + Space縲阪□縺代ｒ菴ｿ縺・∪縺吶・
	# 縺昴・縺溘ａ縲；/K/L/F 縺ｮ繧医≧縺ｪ繝ｭ繝ｼ繧ｫ繝ｫ2莠ｺ逕ｨ繧ｭ繝ｼ縺縺代↓鬆ｼ繧峨★縲・
	# InputRouter縺九ｉ蜿門ｾ励＠縺蘖1/P2蜈･蜉帙〒繧ゅう繝吶Φ繝医ｒ逋ｺ轣ｫ縺ｧ縺阪ｋ繧医≧縺ｫ縺励∪縺吶・
	if not online_input_mode:
		return false
	return _is_player_shooting(1) or _is_player_shooting(2) or _is_player_bombing(1) or _is_player_bombing(2)


func _toggle_network_connection() -> void:
	# Debug hotkey F10.
	# Connects/disconnects from a future WebSocket server.
	if network_client == null:
		return

	if network_client.is_connected_to_server():
		print("[Network] Disconnecting...")
		network_client.disconnect_from_server()
		set_online_input_mode(false, 1)
	else:
		print("[Network] Connecting to " + network_server_url)
		network_client.connect_to_server(network_server_url)


func _network_create_room() -> void:
	# F11: create a room on the WebSocket server.
	if network_client == null:
		return

	if not network_client.is_connected_to_server():
		print("[Network] Not connected. Press F10 first.")
		network_last_message = "Not connected. Press F10 first."
		return

	network_room_entry_mode = false
	network_last_message = "Creating room..."
	network_client.create_room("story")


func _network_start_room_entry() -> void:
	# F7: start typing a room code.
	# Type A-Z / 0-9, then press Enter or F12.
	network_room_entry_mode = true
	network_join_room_code = ""
	network_last_message = "Type room code, then Enter/F12."
	print("[Network] Room code entry started.")


func _handle_room_code_input(key_event: InputEventKey) -> bool:
	# Returns true when the key was consumed by room-code entry.
	if key_event.keycode == KEY_ESCAPE:
		network_room_entry_mode = false
		network_last_message = "Room entry canceled."
		print("[Network] Room entry canceled.")
		return true

	if key_event.keycode == KEY_BACKSPACE:
		if network_join_room_code.length() > 0:
			network_join_room_code = network_join_room_code.substr(0, network_join_room_code.length() - 1)
		return true

	if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER or key_event.keycode == KEY_F12:
		_network_join_room()
		return true

	var key_text := OS.get_keycode_string(key_event.keycode).to_upper()
	var allowed := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	if key_text.length() == 1 and allowed.find(key_text) >= 0:
		if network_join_room_code.length() < 8:
			network_join_room_code += key_text
			network_last_message = "Room code: " + network_join_room_code
		return true

	return false


func _network_join_room() -> void:
	# F12 or Enter while entering a room code.
	if network_client == null:
		return

	if not network_client.is_connected_to_server():
		print("[Network] Not connected. Press F10 first.")
		network_last_message = "Not connected. Press F10 first."
		return

	var target_room_id := network_join_room_code.strip_edges().to_upper()
	if target_room_id == "":
		print("[Network] No room code. Press F7 and type a code.")
		network_last_message = "No room code. Press F7 and type a code."
		return

	network_room_entry_mode = false
	network_last_message = "Joining room: " + target_room_id
	print("[Network] Joining room: " + target_room_id)
	network_client.join_room(target_room_id)


func _network_join_test_room() -> void:
	# Backward-compatible helper. Step 7 uses _network_join_room().
	_network_join_room()


func _update_network_input_sending(delta: float) -> void:
	# Step 8:
	# Send the local player's current input to the room at a fixed rate.
	# The server relays this message to the other client, where it becomes
	# NetworkInputProvider remote input.
	if network_client == null:
		return

	if not network_client.is_connected_to_server():
		return

	# Do not send gameplay input until the server assigns this client as P1 or P2.
	if not online_input_mode:
		return

	# Sending before joining a room only wastes packets, so wait for a room id.
	if network_join_room_code.strip_edges() == "":
		return

	if input_router == null:
		return

	network_send_accumulator += delta
	if network_send_accumulator < network_send_interval:
		return

	network_send_accumulator = 0.0

	var local_state := input_router.get_player_input(online_local_player_id)
	network_client.send_input_state(local_state)
	network_input_send_count += 1


func _on_network_status_changed(status: String) -> void:
	network_last_status = status
	print("[Network] Status: " + status)
	if online_lobby != null:
		online_lobby.set_network_status(status)
		if status == "connected" and network_client != null:
			network_client.set_player_name(online_player_name)


func _on_network_message_received(message: Dictionary) -> void:
	var message_type := str(message.get("type", ""))
	if message_type == "error":
		network_last_message = "Server error: " + str(message.get("message", ""))
		print("[Network] " + network_last_message)


func _on_network_remote_input_received(player_id: int, input_data: Dictionary) -> void:
	# Step 8:
	# Remote input enters the same NetworkInputProvider used by fake online mode.
	# From this point, InputRouter can treat the remote player exactly like a
	# local player and feed the data into normal gameplay functions.
	if network_input_provider != null:
		network_input_provider.set_remote_input(player_id, input_data)

	network_input_receive_count += 1
	network_last_remote_player_id = player_id

	var move_data: Dictionary = input_data.get("move", {})
	var shoot_text := "S" if bool(input_data.get("shoot", false)) else "-"
	var bomb_text := "B" if bool(input_data.get("bomb", false)) else "-"
	network_last_remote_input_text = "P%d move(%.1f, %.1f) %s%s" % [
		player_id,
		float(move_data.get("x", 0.0)),
		float(move_data.get("y", 0.0)),
		shoot_text,
		bomb_text
	]


func _on_network_player_assigned(player_id: int) -> void:
	# The server assigns this browser as P1 or P2.
	# Once assigned, switch to online input mode:
	# local player = arrows + Space, remote player = WebSocket input.
	print("[Network] This client is P%d" % player_id)
	network_last_message = "This client is P%d" % player_id
	set_online_input_mode(true, player_id)
	if online_lobby != null:
		online_lobby.set_local_player(player_id)
		online_lobby.set_status_message("This client is P%d" % player_id)


func _on_network_room_changed(new_room_id: String) -> void:
	network_join_room_code = new_room_id
	network_last_message = "Room: " + new_room_id
	print("[Network] Room: " + new_room_id)
	if online_lobby != null:
		online_lobby.set_room_id(new_room_id)
		online_lobby.set_status_message("Room: " + new_room_id)


func _on_network_peer_joined(player_id: int) -> void:
	network_peer_status = "P%d joined" % player_id
	network_last_message = network_peer_status
	print("[Network] Peer joined: P%d" % player_id)
	if online_lobby != null:
		online_lobby.set_status_message(network_peer_status)


func _on_network_peer_left(player_id: int) -> void:
	network_peer_status = "P%d left" % player_id
	network_last_message = network_peer_status
	print("[Network] Peer left: P%d" % player_id)
	if online_lobby != null:
		online_lobby.set_status_message(network_peer_status)


func _on_network_room_state_received(room_state: Dictionary) -> void:
	# Step 9-12:
	# 繧ｵ繝ｼ繝舌・縺九ｉ螻翫＞縺滄Κ螻九・迥ｶ諷九ｒ繝ｭ繝薙・UI縺ｸ蜿肴丐縺励∪縺吶・
	# 萓具ｼ啀1/P2縺ｮ蜷榊燕縲ヽeady迥ｶ諷九ヾtart蜿ｯ閭ｽ迥ｶ諷九↑縺ｩ縲・
	if online_lobby != null:
		online_lobby.apply_room_state(room_state)


func _on_network_game_start_received(stage_name: String) -> void:
	# Step 13:
	# 繧ｵ繝ｼ繝舌・縺九ｉstart_game縺悟ｱ翫＞縺溘ｉ縲√Ο繝薙・繧帝哩縺倥※繧ｪ繝ｳ繝ｩ繧､繝ｳ繧ｲ繝ｼ繝逕ｻ髱｢縺ｸ遘ｻ陦後＠縺ｾ縺吶・
	# 螳滄圀縺ｫ縺ｩ縺ｮ繧ｹ繝・・繧ｸ繧定ｪｭ縺ｿ霎ｼ繧縺九・ _start_online_game() 縺ｫ縺ｾ縺ｨ繧√※縺・∪縺吶・
	print("[Network] Game start: " + stage_name)
	_start_online_game(stage_name)


func _start_online_game(stage_name: String) -> void:
	# Step 13:
	# 繧ｪ繝ｳ繝ｩ繧､繝ｳ繝励Ξ繧､髢句ｧ区凾縺ｮ蜈ｱ騾壼・逅・〒縺吶・
	# 縺薙％縺ｧUI繧呈紛逅・＠縺ｦ縺九ｉ縲∵欠螳壹＆繧後◆繧ｹ繝・・繧ｸ繧定ｪｭ縺ｿ霎ｼ縺ｿ縺ｾ縺吶・
	online_game_active = true
	online_game_stage = stage_name
	online_game_started_by_server = true

	# 繝ｭ繝薙・繝ｻ繧ｿ繧､繝医Ν繝ｻ隱ｬ譏守判髱｢縺ｯ繧ｲ繝ｼ繝繝励Ξ繧､荳ｭ縺ｫ謫堺ｽ懊ｒ驍ｪ鬲斐＠縺ｪ縺・ｈ縺・撼陦ｨ遉ｺ縺ｫ縺励∪縺吶・
	if online_lobby != null:
		online_lobby.close_lobby()
	if title_layer != null:
		title_layer.visible = false
	if instruction_layer != null:
		instruction_layer.visible = false
	if game_over_layer != null:
		game_over_layer.visible = false
	instruction_visible = false
	game_over = false

	# 繧ｵ繝ｼ繝舌・縺九ｉP1/P2繧貞牡繧雁ｽ薙※貂医∩縺ｪ繧峨√◎縺ｮ蠖ｹ蜑ｲ繧棚nputRouter縺ｸ蝗ｺ螳壹＠縺ｾ縺吶・
	set_online_input_mode(true, online_local_player_id)
	_show_online_status_hud(true)

	match stage_name:
		"astral":
			_load_stage(AstralCourtStageScript)
		"raid":
			_load_stage(RaidStageScript)
		_:
			_load_stage(StoryStageScript)

	banner_label.text = "ONLINE GAME START"


func _return_to_online_lobby() -> void:
	# Step 13:
	# 繧ｪ繝ｳ繝ｩ繧､繝ｳ繧ｲ繝ｼ繝荳ｭ縺九ｉ繝ｭ繝薙・縺ｸ謌ｻ繧句・逅・〒縺吶・
	# 繝阪ャ繝医Ρ繝ｼ繧ｯ謗･邯壹・邯ｭ謖√＠縺溘∪縺ｾ縲∝・蠎ｦReady繧Тtart繧定ｩｦ縺帙ｋ繧医≧縺ｫ縺励∪縺吶・
	online_game_active = false
	_show_online_status_hud(false)
	_clear_game_objects()
	_show_title()
	_show_online_lobby()
	if online_lobby != null:
		online_lobby.set_status_message("Returned to lobby. Room: " + (network_join_room_code if network_join_room_code != "" else "-"))


func _setup_world() -> void:
	bg_sprite = AssetPaths.create_sprite(AssetPaths.BACKGROUNDS["space"], screen_size, Color(0.02, 0.02, 0.08), -100)
	bg_sprite.position = screen_size * 0.5
	add_child(bg_sprite)

	base_sprite = AssetPaths.create_sprite(AssetPaths.STAGES["base_core"], Vector2(190, 190), Color(0.2, 0.9, 1.0), 0)
	base_sprite.position = screen_size * 0.5
	add_child(base_sprite)

	base_shield_sprite = AssetPaths.create_sprite(AssetPaths.EFFECTS["shield_bubble"], Vector2(260, 260), Color(0.5, 0.9, 1.0, 0.7), 2)
	base_shield_sprite.position = base_sprite.position
	base_shield_sprite.visible = false
	add_child(base_shield_sprite)

	astral_ring_sprite = AssetPaths.create_sprite(AssetPaths.STAGES["astral_ring"], Vector2(900, 900), Color(0.9, 0.75, 0.25, 0.4), -20)
	astral_ring_sprite.position = screen_size * 0.5
	astral_ring_sprite.visible = false
	add_child(astral_ring_sprite)

	fusion_sprite = AssetPaths.create_sprite(AssetPaths.PLAYERS["fusion"], Vector2(220, 220), Color(0.4, 1.0, 0.7), 40)
	fusion_sprite.visible = false
	add_child(fusion_sprite)

	# Fusion Siege Mode pointer.
	# P1 moves this pointer with WASD. The ship itself remains upright.
	fusion_pointer_line = Line2D.new()
	fusion_pointer_line.width = 7.0
	fusion_pointer_line.default_color = Color(0.20, 0.95, 1.0, 0.80)
	fusion_pointer_line.z_index = 41
	fusion_pointer_line.visible = false
	add_child(fusion_pointer_line)

	fusion_pointer_reticle = AssetPaths.create_sprite(AssetPaths.EFFECTS["hit_spark"], Vector2(86, 86), Color(0.20, 0.95, 1.0, 0.85), 42)
	fusion_pointer_reticle.visible = false
	add_child(fusion_pointer_reticle)

	for i in range(2):
		var obstacle := AssetPaths.create_sprite(AssetPaths.STAGES["arena_obstacle"], Vector2(180, 130), Color(0.7, 0.8, 1.0, 0.5), 2)
		obstacle.visible = false
		add_child(obstacle)
		arena_obstacle_sprites.append(obstacle)

	boss_sprite = AssetPaths.create_sprite(AssetPaths.BOSSES["crimson"], Vector2(480, 250), Color(0.8, 0.0, 0.25), 5)
	boss_sprite.visible = false
	add_child(boss_sprite)

	for i in range(3):
		var weak := AssetPaths.create_sprite(AssetPaths.BOSSES["weak_core"], Vector2(86, 86), Color(1.0, 0.0, 0.6), 15)
		weak.visible = false
		add_child(weak)
		raid_weak_sprites.append(weak)

	_create_players()

func _setup_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	hud_label = Label.new()
	hud_label.position = Vector2(36, 28)
	hud_label.size = Vector2(820, 180)
	hud_label.add_theme_font_size_override("font_size", 30)
	hud_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	ui_layer.add_child(hud_label)

	banner_label = Label.new()
	banner_label.position = Vector2(0, 92)
	banner_label.size = Vector2(screen_size.x, 70)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 48)
	banner_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.22))
	ui_layer.add_child(banner_label)

	link_back = ColorRect.new()
	link_back.position = Vector2(screen_size.x * 0.5 - 330, screen_size.y - 80)
	link_back.size = Vector2(660, 26)
	link_back.color = Color(0.06, 0.08, 0.12, 0.86)
	link_back.visible = false
	ui_layer.add_child(link_back)

	link_fill = AssetPaths.create_sprite(AssetPaths.UI["link_fill"], Vector2(660, 26), Color(0.2, 1.0, 0.65), 100)
	link_fill.position = link_back.position + link_back.size * 0.5
	link_fill.visible = false
	ui_layer.add_child(link_fill)

	boss_hp_back = AssetPaths.create_sprite(AssetPaths.UI["boss_hp_back"], Vector2(700, 36), Color(0.18, 0.02, 0.05), 100)
	boss_hp_back.position = Vector2(screen_size.x * 0.5, 222)
	boss_hp_back.visible = false
	ui_layer.add_child(boss_hp_back)

	boss_hp_fill = ColorRect.new()
	boss_hp_fill.position = Vector2(screen_size.x * 0.5 - 330, 213)
	boss_hp_fill.size = Vector2(660, 18)
	boss_hp_fill.color = Color(1.0, 0.08, 0.25)
	boss_hp_fill.visible = false
	ui_layer.add_child(boss_hp_fill)

	title_layer = CanvasLayer.new()
	title_layer.layer = 20
	add_child(title_layer)

	var back := ColorRect.new()
	back.size = screen_size
	back.color = Color(0, 0, 0, 0.82)
	title_layer.add_child(back)

	title_label = Label.new()
	title_label.text = "TWIN CORE BLASTERS"
	title_label.position = Vector2(0, 210)
	title_label.size = Vector2(screen_size.x, 96)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 76)
	title_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.85))
	title_layer.add_child(title_label)

	title_options_label = Label.new()
	title_options_label.text = "Choose a stage with mouse or keyboard\n1 Story   2 Astral Court   3 Eclipse Leviathan\nClick ONLINE LOBBY for browser co-op"
	title_options_label.position = Vector2(0, 380)
	title_options_label.size = Vector2(screen_size.x, 120)
	title_options_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_options_label.add_theme_font_size_override("font_size", 34)
	title_options_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	title_layer.add_child(title_options_label)

	_setup_title_buttons()
	_setup_instruction_screen()
	_setup_online_lobby_ui()
	_setup_online_status_hud()

	game_over_layer = CanvasLayer.new()
	game_over_layer.layer = 30
	game_over_layer.visible = false
	add_child(game_over_layer)
	var over_back := ColorRect.new()
	over_back.position = Vector2.ZERO
	over_back.size = screen_size
	over_back.color = Color(0, 0, 0, 0.78)
	game_over_layer.add_child(over_back)
	var panel := ColorRect.new()
	panel.position = Vector2(screen_size.x * 0.5 - 430, screen_size.y * 0.5 - 190)
	panel.size = Vector2(860, 380)
	panel.color = Color(0.03, 0.06, 0.12, 0.92)
	game_over_layer.add_child(panel)
	game_over_title = Label.new()
	game_over_title.position = Vector2(0, screen_size.y * 0.5 - 145)
	game_over_title.size = Vector2(screen_size.x, 80)
	game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_title.add_theme_font_size_override("font_size", 62)
	game_over_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.24))
	game_over_layer.add_child(game_over_title)
	game_over_detail = Label.new()
	game_over_detail.position = Vector2(0, screen_size.y * 0.5 - 42)
	game_over_detail.size = Vector2(screen_size.x, 170)
	game_over_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_detail.add_theme_font_size_override("font_size", 32)
	game_over_detail.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	game_over_layer.add_child(game_over_detail)

	_setup_result_buttons()
	_setup_pause_menu()
	_setup_fusion_flash()
	_setup_shop_ui()
	_setup_shop_hud_button()

func _setup_pause_menu() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 40
	pause_layer.visible = false
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)

	var dim := ColorRect.new()
	dim.position = Vector2.ZERO
	dim.size = screen_size
	dim.color = Color(0, 0, 0, 0.72)
	pause_layer.add_child(dim)

	var pause_title := Label.new()
	pause_title.text = "PAUSED"
	pause_title.position = Vector2(0, screen_size.y * 0.5 - 180)
	pause_title.size = Vector2(screen_size.x, 100)
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_title.add_theme_font_size_override("font_size", 80)
	pause_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.85))
	pause_layer.add_child(pause_title)

	var hint := Label.new()
	hint.text = "Press ESC to resume"
	hint.position = Vector2(0, screen_size.y * 0.5 - 80)
	hint.size = Vector2(screen_size.x, 50)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 28)
	hint.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	pause_layer.add_child(hint)

	var btn_w := 360.0
	var btn_h := 78.0
	var gap := 40.0
	var cx := screen_size.x * 0.5
	var by := screen_size.y * 0.5 + 10.0

	var resume_btn := _create_premium_button("Resume", Vector2(cx - btn_w - gap * 0.5, by), Vector2(btn_w, btn_h))
	resume_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	resume_btn.pressed.connect(_on_pause_resume_pressed)
	pause_layer.add_child(resume_btn)

	var home_btn := _create_premium_button("Home", Vector2(cx + gap * 0.5, by), Vector2(btn_w, btn_h))
	home_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	home_btn.pressed.connect(_on_pause_home_pressed)
	pause_layer.add_child(home_btn)

func _pause_game() -> void:
	paused = true
	pause_layer.visible = true
	if audio_manager != null:
		audio_manager.pause_bgm()

func _resume_game() -> void:
	paused = false
	pause_layer.visible = false
	if audio_manager != null:
		audio_manager.resume_bgm()

func _on_pause_resume_pressed() -> void:
	_resume_game()

func _on_pause_home_pressed() -> void:
	_resume_game()
	if online_game_active:
		_return_to_online_lobby()
	else:
		_clear_game_objects()
		_show_title()

# ── Crystal system ───────────────────────────────────────────────────────────

func _spawn_crystals_from_enemy(pos: Vector2, kind: String) -> void:
	var counts := {
		"scout": [1, 1], "attacker": [2, 3], "tank": [5, 7], "elite": [7, 10],
		"phantom_dart": [1, 1], "fortress_walker": [12, 18],
		"split_cell": [2, 2], "split_cell_frag": [1, 1], "bomber_drone": [4, 6],
	}
	var range_arr: Array = counts.get(kind, [1, 2])
	var count := rng.randi_range(int(range_arr[0]), int(range_arr[1]))
	for i in range(count):
		var offset := Vector2(rng.randf_range(-28.0, 28.0), rng.randf_range(-28.0, 28.0))
		var cpos := pos + offset
		var sprite := AssetPaths.create_sprite(AssetPaths.ITEMS["crystal"], Vector2(28, 28), Color(0.3, 0.9, 1.0), 12)
		sprite.position = cpos
		add_child(sprite)
		crystal_objects.append({"pos": cpos, "sprite": sprite, "lifetime": 5.0, "attracting": false})

func _update_crystals(delta: float) -> void:
	if crystal_magnet_timer > 0.0:
		crystal_magnet_timer -= delta
	var attract_radius := 360.0 if crystal_magnet_timer > 0.0 else 120.0
	for i in range(crystal_objects.size() - 1, -1, -1):
		var c: Dictionary = crystal_objects[i]
		c["lifetime"] = float(c["lifetime"]) - delta
		if float(c["lifetime"]) <= 0.0:
			if is_instance_valid(c["sprite"]):
				(c["sprite"] as Sprite2D).queue_free()
			crystal_objects.remove_at(i)
			continue
		var cpos: Vector2 = c["pos"]
		var nearest_dist := INF
		var nearest_player_pos := Vector2.ZERO
		for p in players:
			if bool(p.get("alive", true)):
				var d := cpos.distance_to(p["pos"] as Vector2)
				if d < nearest_dist:
					nearest_dist = d
					nearest_player_pos = p["pos"]
		if nearest_dist < attract_radius:
			c["attracting"] = true
		if bool(c["attracting"]):
			var dir := (nearest_player_pos - cpos).normalized()
			cpos += dir * 480.0 * delta
			c["pos"] = cpos
			(c["sprite"] as Sprite2D).position = cpos
			if nearest_dist < 24.0:
				crystals += 1
				_update_hud_crystal_label()
				_check_shop_notify()
				if is_instance_valid(c["sprite"]):
					(c["sprite"] as Sprite2D).queue_free()
				crystal_objects.remove_at(i)
				if audio_manager != null:
					audio_manager.play_sfx("item_pickup", -10.0)

func _update_hud_crystal_label() -> void:
	if hud_crystal_label != null:
		hud_crystal_label.text = "💎 %d" % crystals

func _check_shop_notify() -> void:
	if shop_notify_ring == null:
		return
	var affordable := _has_affordable_item()
	shop_notify_ring.visible = affordable

func _has_affordable_item() -> bool:
	var prices := [20, 25, 15, 30, 25, 25, 30, 45, 60, 40, 55, 70, 35]
	for price in prices:
		if crystals >= price:
			return true
	return false

# ── Enemy drop (legacy items — kept for heal/rapid_fire field drops) ──────────

func _spawn_enemy_drop(pos: Vector2) -> void:
	var pool: Array[String] = ["heal", "heal", "rapid_fire", "shield", "power_boost"]
	var key: String = pool[rng.randi_range(0, pool.size() - 1)]
	var sprite := AssetPaths.create_sprite(AssetPaths.ITEMS[key], Vector2(58, 58), Color(1.0, 0.88, 0.22), 12)
	sprite.position = pos
	add_child(sprite)
	items.append({"key": key, "pos": pos, "sprite": sprite, "radius": 34.0})

# ── Fusion flash & timer bar ─────────────────────────────────────────────────

func _setup_fusion_flash() -> void:
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 50
	add_child(flash_layer)
	fusion_flash_rect = ColorRect.new()
	fusion_flash_rect.position = Vector2.ZERO
	fusion_flash_rect.size = screen_size
	fusion_flash_rect.color = Color(0.5, 0.9, 1.0, 0.0)
	fusion_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_layer.add_child(fusion_flash_rect)

	var bar_layer := CanvasLayer.new()
	bar_layer.layer = 22
	add_child(bar_layer)
	fusion_bar_back = ColorRect.new()
	fusion_bar_back.position = Vector2(screen_size.x * 0.5 - 340, 10)
	fusion_bar_back.size = Vector2(680, 18)
	fusion_bar_back.color = Color(0.08, 0.12, 0.2, 0.85)
	fusion_bar_back.visible = false
	bar_layer.add_child(fusion_bar_back)
	fusion_bar_fill = ColorRect.new()
	fusion_bar_fill.position = fusion_bar_back.position
	fusion_bar_fill.size = Vector2(680, 18)
	fusion_bar_fill.color = Color(0.25, 1.0, 0.75, 0.9)
	fusion_bar_fill.visible = false
	bar_layer.add_child(fusion_bar_fill)
	var bar_label := Label.new()
	bar_label.text = "FUSION"
	bar_label.position = Vector2(screen_size.x * 0.5 - 36, 6)
	bar_label.add_theme_font_size_override("font_size", 16)
	bar_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.85))
	bar_label.visible = false
	bar_layer.add_child(bar_label)

# ── Shop system ──────────────────────────────────────────────────────────────

func _setup_shop_ui() -> void:
	shop_layer = CanvasLayer.new()
	shop_layer.layer = 45
	shop_layer.visible = false
	shop_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(shop_layer)

func _open_shop() -> void:
	if game_over or mode == GameMode.TITLE:
		return
	shop_active = true
	shop_layer.visible = true
	_rebuild_shop_ui()
	if audio_manager != null:
		audio_manager.pause_bgm()

func _close_shop() -> void:
	shop_active = false
	shop_layer.visible = false
	if audio_manager != null:
		audio_manager.resume_bgm()

func _rebuild_shop_ui() -> void:
	for child in shop_layer.get_children():
		child.queue_free()

	# ── 背景 dim ──
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.size = screen_size
	dim.color = Color(0, 0, 0, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_layer.add_child(dim)

	# ── タイトル ──
	var title := Label.new()
	title.text = "CRYSTAL  SHOP"
	title.position = Vector2(0, 18)
	title.size = Vector2(screen_size.x, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0))
	shop_layer.add_child(title)

	# ── 所持クリスタル表示 ──
	var clbl := Label.new()
	clbl.text = "💎 %d" % crystals
	clbl.position = Vector2(screen_size.x - 280, 22)
	clbl.size = Vector2(200, 44)
	clbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clbl.add_theme_font_size_override("font_size", 34)
	clbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.9))
	shop_layer.add_child(clbl)

	# ── 閉じるボタン（×） ──
	var close_btn := Button.new()
	close_btn.text = "✕  CLOSE"
	close_btn.position = Vector2(screen_size.x - 170, 16)
	close_btn.size = Vector2(150, 46)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(_close_shop)
	shop_layer.add_child(close_btn)

	# ── ページタブ ──
	var tab_labels := ["  ITEMS  ", "  WEAPONS  ", "  TURRETS  "]
	var tab_colors := [Color(0.2, 1.0, 0.5), Color(0.2, 0.8, 1.0), Color(1.0, 0.6, 0.2)]
	var tab_total_w := 820.0
	var tab_x := screen_size.x * 0.5 - tab_total_w * 0.5
	var tab_y := 82.0
	var tab_widths := [240.0, 290.0, 270.0]
	var tab_gap := 10.0
	var tx := tab_x
	for ti in range(3):
		var tw: float = tab_widths[ti]
		var is_active := ti == shop_page
		var tab_bg := ColorRect.new()
		tab_bg.position = Vector2(tx, tab_y)
		tab_bg.size = Vector2(tw, 44)
		tab_bg.color = Color(tab_colors[ti].r * 0.25, tab_colors[ti].g * 0.25, tab_colors[ti].b * 0.25, 0.95) if is_active else Color(0.06, 0.08, 0.14, 0.9)
		tab_bg.mouse_filter = Control.MOUSE_FILTER_STOP
		shop_layer.add_child(tab_bg)
		if is_active:
			var underline := ColorRect.new()
			underline.position = Vector2(tx, tab_y + 41)
			underline.size = Vector2(tw, 3)
			underline.color = tab_colors[ti]
			shop_layer.add_child(underline)
		var tab_lbl := Label.new()
		tab_lbl.text = tab_labels[ti]
		tab_lbl.position = Vector2(tx, tab_y + 8)
		tab_lbl.size = Vector2(tw, 30)
		tab_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab_lbl.add_theme_font_size_override("font_size", 22)
		tab_lbl.add_theme_color_override("font_color", tab_colors[ti] if is_active else Color(0.5, 0.55, 0.6))
		shop_layer.add_child(tab_lbl)
		var tab_btn := Button.new()
		tab_btn.position = Vector2(tx, tab_y)
		tab_btn.size = Vector2(tw, 44)
		tab_btn.flat = true
		tab_btn.modulate = Color(1, 1, 1, 0)
		var captured_page := ti
		tab_btn.pressed.connect(func(): shop_page = captured_page; _rebuild_shop_ui())
		shop_layer.add_child(tab_btn)
		tx += tw + tab_gap

	# ── キーヒント ──
	var hint := Label.new()
	hint.text = "Tab / ESC  でゲームに戻る"
	hint.position = Vector2(0, screen_size.y - 40)
	hint.size = Vector2(screen_size.x, 32)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.45, 0.52, 0.62))
	shop_layer.add_child(hint)

	# ── ページ描画 ──
	var catalog := _build_shop_catalog()
	match shop_page:
		0: _draw_shop_items_page(catalog)
		1: _draw_shop_weapons_page(catalog)
		2: _draw_shop_turrets_page(catalog)

func _draw_shop_items_page(catalog: Dictionary) -> void:
	var ids := ["core_repair", "mega_bomb", "crystal_magnet", "overclock", "emp_burst"]
	var accent := Color(0.2, 1.0, 0.5)
	var card_w := 330.0
	var card_h := 680.0
	var gap := 22.0
	var total_w := card_w * ids.size() + gap * (ids.size() - 1)
	var sx := screen_size.x * 0.5 - total_w * 0.5
	var cy := 140.0
	for ci in range(ids.size()):
		var id: String = ids[ci]
		var info: Dictionary = catalog[id]
		var cx := sx + ci * (card_w + gap)
		_draw_shop_card(id, info, cx, cy, card_w, card_h, accent, false)

func _draw_shop_weapons_page(catalog: Dictionary) -> void:
	var ids := ["side_cannon", "spread_shot", "homing_missile", "twin_laser"]
	var accent := Color(0.2, 0.8, 1.0)
	var card_w := 430.0
	var card_h := 680.0
	var gap := 28.0
	var total_w := card_w * ids.size() + gap * (ids.size() - 1)
	var sx := screen_size.x * 0.5 - total_w * 0.5
	var cy := 140.0

	# 現在の装備状況
	var status_lbl := Label.new()
	status_lbl.text = "現在の装備 —  P1: %s   P2: %s" % [
		p1_weapon if p1_weapon != "" else "なし",
		p2_weapon if p2_weapon != "" else "なし"
	]
	status_lbl.position = Vector2(0, cy - 36)
	status_lbl.size = Vector2(screen_size.x, 30)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 22)
	status_lbl.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
	shop_layer.add_child(status_lbl)

	for ci in range(ids.size()):
		var id: String = ids[ci]
		var info: Dictionary = catalog[id]
		var cx := sx + ci * (card_w + gap)
		_draw_shop_card(id, info, cx, cy, card_w, card_h, accent, true)

func _draw_shop_turrets_page(catalog: Dictionary) -> void:
	var ids := ["auto_cannon", "laser_tower", "missile_pod", "shield_wall"]
	var accent := Color(1.0, 0.6, 0.2)
	var card_w := 430.0
	var card_h := 680.0
	var gap := 28.0
	var total_w := card_w * ids.size() + gap * (ids.size() - 1)
	var sx := screen_size.x * 0.5 - total_w * 0.5
	var cy := 140.0

	# 設置数表示
	var status_lbl := Label.new()
	status_lbl.text = "設置数: %d / %d  （購入すると自動でコア周囲に配置されます）" % [turrets.size(), max_turrets]
	status_lbl.position = Vector2(0, cy - 36)
	status_lbl.size = Vector2(screen_size.x, 30)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 22)
	status_lbl.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
	shop_layer.add_child(status_lbl)

	for ci in range(ids.size()):
		var id: String = ids[ci]
		var info: Dictionary = catalog[id]
		var cx := sx + ci * (card_w + gap)
		_draw_shop_card(id, info, cx, cy, card_w, card_h, accent, false)

func _draw_shop_card(id: String, info: Dictionary, cx: float, cy: float, card_w: float, card_h: float, accent: Color, is_weapon: bool) -> void:
	var can_buy := crystals >= int(info["price"])
	var dim_accent := Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35)

	# 背景
	var bg := ColorRect.new()
	bg.position = Vector2(cx, cy)
	bg.size = Vector2(card_w, card_h)
	bg.color = Color(0.05, 0.09, 0.18, 0.97) if can_buy else Color(0.04, 0.05, 0.10, 0.97)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_layer.add_child(bg)

	# 上部アクセントライン
	var border_top := ColorRect.new()
	border_top.position = Vector2(cx, cy)
	border_top.size = Vector2(card_w, 4)
	border_top.color = accent if can_buy else dim_accent
	shop_layer.add_child(border_top)

	# 左サイドライン
	var border_left := ColorRect.new()
	border_left.position = Vector2(cx, cy)
	border_left.size = Vector2(3, card_h)
	border_left.color = Color(accent.r, accent.g, accent.b, 0.4) if can_buy else Color(dim_accent.r, dim_accent.g, dim_accent.b, 0.3)
	shop_layer.add_child(border_left)

	# アイコン（大）
	var icon_path := _get_shop_icon_path(id)
	if icon_path != "":
		var icon_sprite := AssetPaths.create_sprite(icon_path, Vector2(110, 110), Color(0.6, 0.6, 0.6))
		icon_sprite.position = Vector2(cx + card_w * 0.5, cy + 76)
		icon_sprite.z_index = 46
		shop_layer.add_child(icon_sprite)

	# アイコン下のアクセント横線
	var sep1 := ColorRect.new()
	sep1.position = Vector2(cx + 20, cy + 140)
	sep1.size = Vector2(card_w - 40, 1)
	sep1.color = Color(accent.r, accent.g, accent.b, 0.25)
	shop_layer.add_child(sep1)

	# アイテム名
	var name_lbl := Label.new()
	name_lbl.text = String(info["name"])
	name_lbl.position = Vector2(cx + 8, cy + 150)
	name_lbl.size = Vector2(card_w - 16, 46)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.add_theme_color_override("font_color", accent if can_buy else dim_accent)
	shop_layer.add_child(name_lbl)

	# 概要テキスト
	var short_lbl := Label.new()
	short_lbl.text = String(info["short"])
	short_lbl.position = Vector2(cx + 8, cy + 200)
	short_lbl.size = Vector2(card_w - 16, 36)
	short_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	short_lbl.add_theme_font_size_override("font_size", 18)
	short_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0) if can_buy else Color(0.38, 0.42, 0.48))
	shop_layer.add_child(short_lbl)

	# 区切り線
	var sep2 := ColorRect.new()
	sep2.position = Vector2(cx + 20, cy + 244)
	sep2.size = Vector2(card_w - 40, 1)
	sep2.color = Color(accent.r, accent.g, accent.b, 0.18)
	shop_layer.add_child(sep2)

	# 詳細説明
	var detail_lbl := Label.new()
	detail_lbl.text = String(info["detail"])
	detail_lbl.position = Vector2(cx + 16, cy + 254)
	detail_lbl.size = Vector2(card_w - 32, 280)
	detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.add_theme_font_size_override("font_size", 17)
	detail_lbl.add_theme_color_override("font_color", Color(0.68, 0.76, 0.88) if can_buy else Color(0.32, 0.36, 0.42))
	shop_layer.add_child(detail_lbl)

	# 区切り線2
	var sep3 := ColorRect.new()
	sep3.position = Vector2(cx + 20, cy + card_h - 110)
	sep3.size = Vector2(card_w - 40, 1)
	sep3.color = Color(accent.r, accent.g, accent.b, 0.22)
	shop_layer.add_child(sep3)

	# 価格
	var price_lbl := Label.new()
	price_lbl.text = "💎  %d" % int(info["price"])
	price_lbl.position = Vector2(cx, cy + card_h - 102)
	price_lbl.size = Vector2(card_w, 36)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 28)
	price_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.65) if can_buy else Color(0.35, 0.38, 0.42))
	shop_layer.add_child(price_lbl)

	# 購入可否テキスト
	if not can_buy:
		var lack_lbl := Label.new()
		lack_lbl.text = "あと 💎 %d 必要" % (int(info["price"]) - crystals)
		lack_lbl.position = Vector2(cx, cy + card_h - 66)
		lack_lbl.size = Vector2(card_w, 28)
		lack_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lack_lbl.add_theme_font_size_override("font_size", 16)
		lack_lbl.add_theme_color_override("font_color", Color(0.6, 0.3, 0.3))
		shop_layer.add_child(lack_lbl)

	# BUYボタン
	if can_buy:
		var btn := Button.new()
		btn.text = "購入する  BUY"
		btn.position = Vector2(cx + 36, cy + card_h - 54)
		btn.size = Vector2(card_w - 72, 44)
		btn.add_theme_font_size_override("font_size", 20)
		var captured_id := id
		if is_weapon:
			btn.pressed.connect(_open_player_selector.bind(captured_id))
		else:
			btn.pressed.connect(_purchase.bind(captured_id, 0))
		shop_layer.add_child(btn)

func _open_player_selector(weapon_id: String) -> void:
	# Overlay a small P1/P2 picker on top of the shop
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.size = screen_size
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 10
	shop_layer.add_child(overlay)

	var panel := ColorRect.new()
	panel.position = Vector2(screen_size.x * 0.5 - 220, screen_size.y * 0.5 - 130)
	panel.size = Vector2(440, 260)
	panel.color = Color(0.05, 0.09, 0.18, 0.98)
	panel.z_index = 11
	shop_layer.add_child(panel)

	var ask := Label.new()
	ask.text = "Equip to which player?"
	ask.position = Vector2(panel.position.x, panel.position.y + 20)
	ask.size = Vector2(440, 50)
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ask.add_theme_font_size_override("font_size", 28)
	ask.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	ask.z_index = 12
	shop_layer.add_child(ask)

	var p1_btn := Button.new()
	p1_btn.text = "P1  Azure Wing"
	p1_btn.position = Vector2(panel.position.x + 30, panel.position.y + 90)
	p1_btn.size = Vector2(170, 50)
	p1_btn.add_theme_font_size_override("font_size", 20)
	p1_btn.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	p1_btn.z_index = 12
	p1_btn.pressed.connect(_purchase.bind(weapon_id, 1))
	p1_btn.pressed.connect(overlay.queue_free)
	p1_btn.pressed.connect(panel.queue_free)
	p1_btn.pressed.connect(ask.queue_free)
	p1_btn.pressed.connect(p1_btn.queue_free)
	shop_layer.add_child(p1_btn)

	var p2_btn := Button.new()
	p2_btn.text = "P2  Solar Fang"
	p2_btn.position = Vector2(panel.position.x + 240, panel.position.y + 90)
	p2_btn.size = Vector2(170, 50)
	p2_btn.add_theme_font_size_override("font_size", 20)
	p2_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	p2_btn.z_index = 12
	p2_btn.pressed.connect(_purchase.bind(weapon_id, 2))
	p2_btn.pressed.connect(overlay.queue_free)
	p2_btn.pressed.connect(panel.queue_free)
	p2_btn.pressed.connect(ask.queue_free)
	p2_btn.pressed.connect(p2_btn.queue_free)
	shop_layer.add_child(p2_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.position = Vector2(panel.position.x + 130, panel.position.y + 180)
	cancel_btn.size = Vector2(180, 40)
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.z_index = 12
	cancel_btn.pressed.connect(overlay.queue_free)
	cancel_btn.pressed.connect(panel.queue_free)
	cancel_btn.pressed.connect(ask.queue_free)
	cancel_btn.pressed.connect(cancel_btn.queue_free)
	shop_layer.add_child(cancel_btn)

func _purchase(id: String, player_target: int) -> void:
	var catalog := _build_shop_catalog()
	if not catalog.has(id):
		return
	var price := int(catalog[id]["price"])
	if crystals < price:
		return
	crystals -= price
	_update_hud_crystal_label()
	_check_shop_notify()
	match id:
		"core_repair":
			base_hp = min(CORE_HP_MAX, base_hp + 40)
		"mega_bomb":
			for e in enemies:
				e["hp"] = 0
		"crystal_magnet":
			crystal_magnet_timer = 60.0
		"overclock":
			for p in players:
				p["rapid"] = maxf(float(p.get("rapid", 0.0)), 30.0)
		"emp_burst":
			emp_stun_timer = 5.0
		"side_cannon", "spread_shot", "homing_missile", "twin_laser":
			if player_target == 1:
				p1_weapon = id
			elif player_target == 2:
				p2_weapon = id
		"auto_cannon", "laser_tower", "missile_pod", "shield_wall":
			if turrets.size() < max_turrets:
				_add_turret(id)
	_rebuild_shop_ui()

func _get_shop_icon_path(id: String) -> String:
	match id:
		"core_repair":     return AssetPaths.ITEMS["heal"]
		"mega_bomb":       return AssetPaths.ITEMS["bomb"]
		"crystal_magnet":  return AssetPaths.ITEMS["crystal_magnet"]
		"overclock":       return AssetPaths.ITEMS["rapid_fire"]
		"emp_burst":       return AssetPaths.ITEMS["emp_burst"]
		"side_cannon":     return AssetPaths.WEAPONS["side_cannon"]
		"spread_shot":     return AssetPaths.WEAPONS["spread_shot"]
		"homing_missile":  return AssetPaths.WEAPONS["homing_missile"]
		"twin_laser":      return AssetPaths.WEAPONS["twin_laser"]
		"auto_cannon":     return AssetPaths.TURRETS["auto_cannon"]
		"laser_tower":     return AssetPaths.TURRETS["laser_tower"]
		"missile_pod":     return AssetPaths.TURRETS["missile_pod"]
		"shield_wall":     return AssetPaths.TURRETS["shield_wall"]
	return ""

func _build_shop_catalog() -> Dictionary:
	return {
		"core_repair": {
			"name": "CORE REPAIR", "price": 20,
			"short": "コアのHPを回復する",
			"detail": "コアのHPを +40 回復します。\n\nHPが危険な状態のときに使うと\n生存率が大きく上がります。\n\n上限（CORE_HP_MAX）を\n超えては回復しません。",
		},
		"mega_bomb": {
			"name": "MEGA BOMB", "price": 35,
			"short": "画面上の全敵を一掃する",
			"detail": "購入した瞬間、フィールド上に\n存在する全ての敵のHPを 0 に\nして即座に撃破します。\n\n窮地の切り札として有効です。\nクリスタルも大量にドロップします。",
		},
		"crystal_magnet": {
			"name": "CRYSTAL MAGNET", "price": 15,
			"short": "クリスタルの吸引範囲を3倍に",
			"detail": "60秒間、クリスタルの自動吸引\n範囲が 120px → 360px に広がります。\n\n遠くに落ちたクリスタルも\n自動で集めてくれるため、\n序盤の資金集めに最適です。",
		},
		"overclock": {
			"name": "OVERCLOCK", "price": 30,
			"short": "射撃速度を30秒間1.5倍に",
			"detail": "P1・P2 両機体の射撃速度を\n30秒間 1.5倍に強化します。\n\nRapid Fire アイテムと\n組み合わせることで\nさらに高い連射が可能です。",
		},
		"emp_burst": {
			"name": "EMP BURST", "price": 25,
			"short": "全敵を5秒間スタンさせる",
			"detail": "購入した瞬間、フィールド上の\n全ての敵の動きと攻撃を\n5秒間完全に停止させます。\n\nコアへの突撃を止めたいときや\nフュージョンを溜めたいときに。",
		},
		"side_cannon": {
			"name": "SIDE CANNON", "price": 25,
			"short": "左右に追加弾を発射",
			"detail": "通常ショットに加えて、\n左右斜め方向に弾を 各1発\n同時に発射します。\n\n横から迫る敵に対して\n自動で対応できます。\n\n装備スロット: 1機体につき1種",
		},
		"spread_shot": {
			"name": "SPREAD SHOT", "price": 30,
			"short": "左右25°に追加弾2発",
			"detail": "通常ショットに加えて、\n左右 25° に広がる弾を\n各1発発射します（計2発追加）。\n\n広い範囲をカバーでき、\n複数の敵が並んでいるときに\n特に効果的です。\n\n装備スロット: 1機体につき1種",
		},
		"homing_missile": {
			"name": "HOMING MISSILE", "price": 45,
			"short": "2.5秒ごとに追尾ミサイルを発射",
			"detail": "2.5秒ごとに、フィールド上で\n最も近い敵へ自動追尾する\nミサイルを発射します。\n\n操作は不要で完全自動です。\nタンク・エリートなど\n硬い敵に特に有効です。\n\n装備スロット: 1機体につき1種",
		},
		"twin_laser": {
			"name": "TWIN LASER", "price": 60,
			"short": "平行した2本の追加レーザー",
			"detail": "通常ショットに加えて、\n機体の左右から平行した\nレーザー弾を各1発追加発射。\n\nダメージは通常弾と同等で、\n正面の敵に対する\n実質的な火力が大幅に向上します。\n\n装備スロット: 1機体につき1種",
		},
		"auto_cannon": {
			"name": "AUTO CANNON", "price": 40,
			"short": "最寄りの敵に1.2秒ごと射撃",
			"detail": "コア周囲に砲台を1基設置します。\n\n1.2秒ごとに、フィールド上で\n最も近い敵へ自動的に弾を\n発射し続けます。\n\n操作不要で常時稼働する\n最もバランスの良いタレットです。\n\n最大設置数: 3基",
		},
		"laser_tower": {
			"name": "LASER TOWER", "price": 55,
			"short": "連続レーザーで即時ダメージ",
			"detail": "コア周囲にレーザー砲台を設置。\n\n0.08秒ごとに最寄りの敵へ\n連続ダメージを与えます。\n射撃間隔が非常に短く、\n高速の敵も逃さず撃ち続けます。\n\nスカウト・アタッカーなど\n素早い敵の処理に最適です。\n\n最大設置数: 3基",
		},
		"missile_pod": {
			"name": "MISSILE POD", "price": 70,
			"short": "3.5秒ごとに敵3体へミサイル",
			"detail": "コア周囲にミサイルポッドを設置。\n\n3.5秒ごとに、近くの敵 3体を\n同時に追尾するミサイルを\n一斉発射します。\n\n範囲攻撃に近い効果があり、\n複数のタンクやエリートが\n同時に来る場面で力を発揮します。\n\n最大設置数: 3基",
		},
		"shield_wall": {
			"name": "SHIELD WALL", "price": 35,
			"short": "コアに近い敵を8秒に1回弾く",
			"detail": "コア周囲に防壁ユニットを設置。\n\n8秒に1回、コアに200px以内に\n近づいた敵を自動的に弾き飛ばします。\n\nダメージは与えませんが、\n敵の突撃をリセットする\n防衛的なタレットです。\nCore Repairと組み合わせると効果的。\n\n最大設置数: 3基",
		},
	}

# ── Shop HUD button ──────────────────────────────────────────────────────────

func _setup_shop_hud_button() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 20
	add_child(hud_layer)

	# ── Shop/crystal container — hidden until STORY mode ──────────────
	shop_hud_container = Control.new()
	shop_hud_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_hud_container.mouse_filter = Control.MOUSE_FILTER_PASS
	shop_hud_container.visible = false
	hud_layer.add_child(shop_hud_container)

	# Crystal label
	hud_crystal_label = Label.new()
	hud_crystal_label.text = "💎 0"
	hud_crystal_label.position = Vector2(screen_size.x - 260, 14)
	hud_crystal_label.size = Vector2(140, 40)
	hud_crystal_label.add_theme_font_size_override("font_size", 26)
	hud_crystal_label.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0))
	shop_hud_container.add_child(hud_crystal_label)

	# Shop button background
	var btn_bg := ColorRect.new()
	btn_bg.position = Vector2(screen_size.x - 112, 10)
	btn_bg.size = Vector2(100, 44)
	btn_bg.color = Color(0.05, 0.1, 0.22, 0.92)
	btn_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_hud_container.add_child(btn_bg)

	# Notify glow ring (visible when items are affordable)
	shop_notify_ring = ColorRect.new()
	shop_notify_ring.position = Vector2(screen_size.x - 114, 8)
	shop_notify_ring.size = Vector2(104, 48)
	shop_notify_ring.color = Color(0.2, 1.0, 0.6, 0.45)
	shop_notify_ring.visible = false
	shop_hud_container.add_child(shop_notify_ring)

	# Shop icon
	var shop_icon := AssetPaths.create_sprite(AssetPaths.UI["shop"], Vector2(32, 32), Color(0.3, 0.9, 1.0))
	shop_icon.position = Vector2(screen_size.x - 100, 32)
	shop_icon.z_index = 21
	shop_hud_container.add_child(shop_icon)

	# Shop label
	var shop_lbl := Label.new()
	shop_lbl.text = "SHOP"
	shop_lbl.position = Vector2(screen_size.x - 78, 18)
	shop_lbl.size = Vector2(70, 28)
	shop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_lbl.add_theme_font_size_override("font_size", 20)
	shop_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	shop_hud_container.add_child(shop_lbl)

	# Invisible clickable button over the shop area
	var shop_btn := Button.new()
	shop_btn.position = Vector2(screen_size.x - 114, 8)
	shop_btn.size = Vector2(104, 48)
	shop_btn.flat = true
	shop_btn.modulate = Color(1, 1, 1, 0)
	shop_btn.pressed.connect(_open_shop)
	shop_hud_container.add_child(shop_btn)

	# Key hint
	var key_hint := Label.new()
	key_hint.text = "[Tab]"
	key_hint.position = Vector2(screen_size.x - 116, 54)
	key_hint.size = Vector2(108, 24)
	key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_hint.add_theme_font_size_override("font_size", 14)
	key_hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
	shop_hud_container.add_child(key_hint)
	_setup_story_hud_bar(hud_layer)


func _setup_story_hud_bar(hud_layer: CanvasLayer) -> void:
	var BAR_H   := 52
	var BG_COL  := Color(0.04, 0.06, 0.14, 0.90)
	var SEP_COL := Color(0.25, 0.35, 0.55, 0.60)
	var sw      := screen_size.x

	# ── Master container — hiding this hides everything ──────────────
	story_hud_container = Control.new()
	story_hud_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_hud_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.visible = false        # hidden until STORY mode starts
	hud_layer.add_child(story_hud_container)

	# Background bar (child of container)
	story_hud_bar = ColorRect.new()
	story_hud_bar.position = Vector2(0, 0)
	story_hud_bar.size = Vector2(sw, BAR_H)
	story_hud_bar.color = BG_COL
	story_hud_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(story_hud_bar)

	# Helper lambdas — all children go into story_hud_container
	var _add_sep := func(x: float) -> void:
		var sep := ColorRect.new()
		sep.position = Vector2(x, 6)
		sep.size = Vector2(1, BAR_H - 12)
		sep.color = SEP_COL
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		story_hud_container.add_child(sep)

	var _add_header := func(parent: Control, x: float, txt: String) -> Label:
		var l := Label.new()
		l.text = txt
		l.position = Vector2(x, 4)
		l.size = Vector2(140, 18)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.45, 0.60, 0.80))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(l)
		return l

	var _add_bar := func(parent: Control, x: float, w: float, bg: Color) -> Array:
		var bg_rect := ColorRect.new()
		bg_rect.position = Vector2(x, 22)
		bg_rect.size = Vector2(w, 14)
		bg_rect.color = bg
		bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(bg_rect)
		var fill := ColorRect.new()
		fill.position = Vector2(x, 22)
		fill.size = Vector2(w, 14)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(fill)
		return [bg_rect, fill]

	# ── Mode label ───────────────────────────────── x=10
	story_mode_label = Label.new()
	story_mode_label.text = "CO-OP DEFENSE"
	story_mode_label.position = Vector2(10, 12)
	story_mode_label.size = Vector2(160, 30)
	story_mode_label.add_theme_font_size_override("font_size", 18)
	story_mode_label.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0))
	story_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(story_mode_label)
	_add_sep.call(176.0)

	# ── Core HP bar ──────────────────────────────── x=182
	_add_header.call(story_hud_container, 182.0, "CORE")
	var core_bars: Array = _add_bar.call(story_hud_container, 182.0, 130.0, Color(0.12, 0.04, 0.04))
	story_core_bar_bg   = core_bars[0]
	story_core_bar_fill = core_bars[1]
	story_core_bar_fill.color = Color(0.95, 0.22, 0.22)
	story_core_label = Label.new()
	story_core_label.position = Vector2(318, 14)
	story_core_label.size = Vector2(82, 28)
	story_core_label.add_theme_font_size_override("font_size", 18)
	story_core_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.75))
	story_core_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(story_core_label)
	_add_sep.call(403.0)

	# ── Shield bar ───────────────────────────────── x=410
	_add_header.call(story_hud_container, 410.0, "SHIELD")
	var shd_bars: Array = _add_bar.call(story_hud_container, 410.0, 110.0, Color(0.04, 0.08, 0.14))
	story_shield_bar_bg   = shd_bars[0]
	story_shield_bar_fill = shd_bars[1]
	story_shield_bar_fill.color = Color(0.30, 0.80, 1.0)
	story_shield_bar_fill.size.x = 0.0
	story_shield_label = Label.new()   # "--" when no shield
	story_shield_label.text = "--"
	story_shield_label.position = Vector2(524, 14)
	story_shield_label.size = Vector2(60, 28)
	story_shield_label.add_theme_font_size_override("font_size", 18)
	story_shield_label.add_theme_color_override("font_color", Color(0.30, 0.50, 0.65))
	story_shield_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(story_shield_label)
	_add_sep.call(588.0)

	# ── Score ────────────────────────────────────── x=596
	_add_header.call(story_hud_container, 596.0, "SCORE")
	story_score_label = Label.new()
	story_score_label.text = "0"
	story_score_label.position = Vector2(596, 18)
	story_score_label.size = Vector2(130, 28)
	story_score_label.add_theme_font_size_override("font_size", 20)
	story_score_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	story_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(story_score_label)

	# ── CO-OP LINK (RIGHT side, before crystal) — hidden until link starts ─
	# Position: sw-490 to sw-275  (crystal label starts at sw-260)
	var lx: float = sw - 490.0
	story_link_container = Control.new()
	story_link_container.position = Vector2.ZERO
	story_link_container.size = Vector2(sw, BAR_H)
	story_link_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_link_container.visible = false
	story_hud_container.add_child(story_link_container)

	_add_sep.call(lx - 8.0)   # separator before LINK section
	story_link_header_label = _add_header.call(story_link_container, lx, "CO-OP LINK")
	story_link_header_label.size = Vector2(200, 18)   # wider — "CO-OP LINK"/"FUSION TIME" needs room
	var lnk_bars: Array = _add_bar.call(story_link_container, lx, 130.0, Color(0.04, 0.10, 0.10))
	story_link_bar_bg   = lnk_bars[0]
	story_link_bar_fill = lnk_bars[1]
	story_link_bar_fill.color = Color(0.20, 1.0, 0.65)
	story_link_bar_fill.size.x = 0.0
	story_link_label = Label.new()
	story_link_label.position = Vector2(lx + 135.0, 14)
	story_link_label.size = Vector2(100, 28)
	story_link_label.add_theme_font_size_override("font_size", 14)
	story_link_label.add_theme_color_override("font_color", Color(0.20, 1.0, 0.65))
	story_link_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_link_container.add_child(story_link_label)

	# Fusion overlay (replaces link display during fusion)
	story_fusion_label = Label.new()
	story_fusion_label.position = Vector2(lx, 10)
	story_fusion_label.size = Vector2(230, 36)
	story_fusion_label.add_theme_font_size_override("font_size", 18)
	story_fusion_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.20))
	story_fusion_label.visible = false
	story_fusion_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_link_container.add_child(story_fusion_label)


# ── Weapon fire helpers ───────────────────────────────────────────────────────

func _fire_weapon_extra(player_id: int, base_pos: Vector2, base_vel: Vector2) -> void:
	var weapon := p1_weapon if player_id == 1 else p2_weapon
	if weapon == "":
		return
	var p_dict: Dictionary = {}
	for p in players:
		if int(p["id"]) == player_id:
			p_dict = p
			break
	var dmg := int(p_dict.get("damage", 8))
	var spd := float(p_dict.get("shot_speed", 1000.0))
	match weapon:
		"side_cannon":
			var left_vel := Vector2(-spd * 0.7, -spd * 0.7).normalized() * spd
			var right_vel := Vector2(spd * 0.7, -spd * 0.7).normalized() * spd
			_create_extra_bullet(player_id, base_pos + Vector2(-30, 0), left_vel, dmg, Color(0.3, 0.7, 1.0))
			_create_extra_bullet(player_id, base_pos + Vector2(30, 0), right_vel, dmg, Color(0.3, 0.7, 1.0))
		"spread_shot":
			for angle_deg in [-25.0, 25.0]:
				var rotated_vel := base_vel.rotated(deg_to_rad(angle_deg))
				_create_extra_bullet(player_id, base_pos, rotated_vel, dmg, Color(0.7, 0.4, 1.0))
		"twin_laser":
			_create_extra_bullet(player_id, base_pos + Vector2(-18, 0), base_vel, dmg, Color(0.2, 1.0, 0.85))
			_create_extra_bullet(player_id, base_pos + Vector2(18, 0), base_vel, dmg, Color(0.2, 1.0, 0.85))

func _create_extra_bullet(player_id: int, pos: Vector2, vel: Vector2, dmg: int, col: Color) -> void:
	var sprite := Sprite2D.new()
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(col)
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = pos
	sprite.rotation = vel.angle() + PI / 2
	sprite.z_index = 10
	add_child(sprite)
	bullets.append({"pos": pos, "vel": vel, "owner": player_id, "damage": dmg,
		"sprite": sprite, "radius": 7.0, "piercing": false})

# ── Missile update ────────────────────────────────────────────────────────────

func _update_missiles(delta: float) -> void:
	p1_weapon_cd = maxf(0.0, p1_weapon_cd - delta)
	p2_weapon_cd = maxf(0.0, p2_weapon_cd - delta)

	for pid in [1, 2]:
		var weapon := p1_weapon if pid == 1 else p2_weapon
		if weapon != "homing_missile":
			continue
		var cd := p1_weapon_cd if pid == 1 else p2_weapon_cd
		if cd > 0.0:
			continue
		if pid == 1:
			p1_weapon_cd = 2.5
		else:
			p2_weapon_cd = 2.5
		var p_pos := Vector2.ZERO
		for p in players:
			if int(p["id"]) == pid:
				p_pos = p["pos"]
				break
		if p_pos == Vector2.ZERO:
			continue
		var nearest_enemy := _find_nearest_enemy(p_pos)
		var target_pos := nearest_enemy if nearest_enemy != Vector2.ZERO else p_pos + Vector2.UP * 300
		var vel := (target_pos - p_pos).normalized() * 600.0
		var ms := Sprite2D.new()
		var img := Image.create(10, 18, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.6, 0.2))
		ms.texture = ImageTexture.create_from_image(img)
		ms.position = p_pos
		ms.z_index = 10
		add_child(ms)
		var dmg := 28 if pid == 1 else 40
		missiles.append({"pos": p_pos, "vel": vel, "owner": pid, "sprite": ms,
			"damage": dmg, "lifetime": 4.0})

	for i in range(missiles.size() - 1, -1, -1):
		var m: Dictionary = missiles[i]
		m["lifetime"] = float(m["lifetime"]) - delta
		if float(m["lifetime"]) <= 0.0:
			if is_instance_valid(m["sprite"]):
				(m["sprite"] as Sprite2D).queue_free()
			missiles.remove_at(i)
			continue
		var mpos: Vector2 = m["pos"]
		var target := _find_nearest_enemy(mpos)
		if target != Vector2.ZERO:
			var desired := (target - mpos).normalized() * 700.0
			var cur_vel: Vector2 = m["vel"]
			m["vel"] = cur_vel.lerp(desired, 3.0 * delta)
		mpos += (m["vel"] as Vector2) * delta
		m["pos"] = mpos
		(m["sprite"] as Sprite2D).position = mpos
		(m["sprite"] as Sprite2D).rotation = (m["vel"] as Vector2).angle() + PI / 2
		for j in range(enemies.size() - 1, -1, -1):
			var e: Dictionary = enemies[j]
			if mpos.distance_to(e["pos"] as Vector2) < 40.0:
				e["hp"] = int(e["hp"]) - int(m["damage"])
				_spawn_effect(AssetPaths.EFFECTS["explosion_small"], mpos, Vector2(80, 80), 0.25)
				if is_instance_valid(m["sprite"]):
					(m["sprite"] as Sprite2D).queue_free()
				missiles.remove_at(i)
				break

func _find_nearest_enemy(from_pos: Vector2) -> Vector2:
	var best := INF
	var result := Vector2.ZERO
	for e in enemies:
		var d := from_pos.distance_to(e["pos"] as Vector2)
		if d < best:
			best = d
			result = e["pos"]
	return result

# ── Turret system ─────────────────────────────────────────────────────────────

func _add_turret(kind: String) -> void:
	var angle := (turrets.size() * 120.0) * PI / 180.0
	var radius := 130.0
	var offset := Vector2(cos(angle), sin(angle)) * radius
	var tpos := base_sprite.position + offset
	var sprite := AssetPaths.create_sprite(_get_shop_icon_path(kind), Vector2(52, 52), Color(0.6, 0.8, 1.0), 9)
	sprite.position = tpos
	add_child(sprite)
	turrets.append({"kind": kind, "pos": tpos, "sprite": sprite,
		"timer": 0.0, "shield_cd": 0.0, "shield_active": false})

func _update_turrets(delta: float) -> void:
	if emp_stun_timer > 0.0:
		emp_stun_timer -= delta
	for turret in turrets:
		turret["timer"] = float(turret["timer"]) + delta
		var kind: String = turret["kind"]
		var tpos: Vector2 = turret["pos"]
		match kind:
			"auto_cannon":
				if float(turret["timer"]) >= 1.2:
					turret["timer"] = 0.0
					var target := _find_nearest_enemy(tpos)
					if target != Vector2.ZERO:
						var vel := (target - tpos).normalized() * 900.0
						_create_extra_bullet(0, tpos, vel, 18, Color(0.5, 0.8, 1.0))
			"laser_tower":
				if float(turret["timer"]) >= 0.08:
					turret["timer"] = 0.0
					var target := _find_nearest_enemy(tpos)
					if target != Vector2.ZERO:
						for e in enemies:
							if (e["pos"] as Vector2).distance_to(target) < 60.0:
								e["hp"] = int(e["hp"]) - 6
			"missile_pod":
				if float(turret["timer"]) >= 3.5:
					turret["timer"] = 0.0
					var sorted_enemies := enemies.duplicate()
					sorted_enemies.sort_custom(func(a, b): return (a["pos"] as Vector2).distance_to(tpos) < (b["pos"] as Vector2).distance_to(tpos))
					for ei in range(min(3, sorted_enemies.size())):
						var target_pos: Vector2 = sorted_enemies[ei]["pos"]
						var vel := (target_pos - tpos).normalized() * 620.0
						var ms := Sprite2D.new()
						var img := Image.create(8, 16, false, Image.FORMAT_RGBA8)
						img.fill(Color(1.0, 0.55, 0.1))
						ms.texture = ImageTexture.create_from_image(img)
						ms.position = tpos
						ms.z_index = 10
						add_child(ms)
						missiles.append({"pos": tpos, "vel": vel, "owner": 0, "sprite": ms,
							"damage": 22, "lifetime": 4.0})
			"shield_wall":
				turret["shield_cd"] = float(turret.get("shield_cd", 0.0)) + delta
				if float(turret["shield_cd"]) >= 8.0:
					turret["shield_cd"] = 0.0
					turret["shield_active"] = true
				if bool(turret.get("shield_active", false)):
					for e in enemies:
						if (e["pos"] as Vector2).distance_to(base_sprite.position) < 200.0:
							e["pos"] = (e["pos"] as Vector2) + ((e["pos"] as Vector2) - base_sprite.position).normalized() * 40.0
							turret["shield_active"] = false
							break

func _create_premium_button(text_value: String, position_value: Vector2, size_value: Vector2) -> Button:
	# Creates a reusable premium-style button.
	# The style is intentionally made in code so this ZIP works without extra UI assets.
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	button.add_theme_font_size_override("font_size", 30)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.035, 0.065, 0.13, 0.92)
	normal.border_color = Color(0.28, 0.92, 1.0, 0.70)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(18)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.08, 0.16, 0.26, 0.96)
	hover.border_color = Color(1.0, 0.86, 0.28, 0.95)
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(18)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.12, 0.22, 0.34, 0.98)
	pressed.border_color = Color(0.2, 1.0, 0.72, 1.0)
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(18)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.30))
	return button


func _setup_title_buttons() -> void:
	# Mouse-operable stage select buttons.
	var button_width := 460.0
	var button_height := 78.0
	var gap := 30.0
	var total_width := button_width * 3.0 + gap * 2.0
	var start_x := screen_size.x * 0.5 - total_width * 0.5
	var y := 560.0

	var story_button := _create_premium_button("STORY MODE", Vector2(start_x, y), Vector2(button_width, button_height))
	story_button.pressed.connect(_on_story_button_pressed)
	title_layer.add_child(story_button)
	title_buttons.append(story_button)

	var astral_button := _create_premium_button("ASTRAL COURT", Vector2(start_x + button_width + gap, y), Vector2(button_width, button_height))
	astral_button.pressed.connect(_on_astral_button_pressed)
	title_layer.add_child(astral_button)
	title_buttons.append(astral_button)

	var raid_button := _create_premium_button("ECLIPSE RAID", Vector2(start_x + (button_width + gap) * 2.0, y), Vector2(button_width, button_height))
	raid_button.pressed.connect(_on_raid_button_pressed)
	title_layer.add_child(raid_button)
	title_buttons.append(raid_button)

	# Step 9-12: 譛ｬ逡ｪ蜷代￠繧ｪ繝ｳ繝ｩ繧､繝ｳ繝ｭ繝薙・繧帝幕縺上・繧ｿ繝ｳ縺ｧ縺吶・
	# 譌｢蟄倥・F10/F11/F7繝・ヰ繝・げ謫堺ｽ懊・谿九＠縺溘∪縺ｾ縲√Θ繝ｼ繧ｶ繝ｼ蜷代￠UI繧定ｿｽ蜉縺励∪縺吶・
	var online_button := _create_premium_button("ONLINE LOBBY", Vector2(screen_size.x * 0.5 - 230.0, y + 112.0), Vector2(460.0, button_height))
	online_button.pressed.connect(_on_online_button_pressed)
	title_layer.add_child(online_button)
	title_buttons.append(online_button)


func _setup_instruction_screen() -> void:
	# InstructionScreen is a lightweight modal built in code.
	# It appears after selecting a stage and before starting gameplay.
	instruction_layer = CanvasLayer.new()
	instruction_layer.layer = 25
	instruction_layer.visible = false
	add_child(instruction_layer)

	var dim := ColorRect.new()
	dim.position = Vector2.ZERO
	dim.size = screen_size
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	instruction_layer.add_child(dim)

	var panel := ColorRect.new()
	panel.position = Vector2(screen_size.x * 0.5 - 560.0, screen_size.y * 0.5 - 290.0)
	panel.size = Vector2(1120, 580)
	panel.color = Color(0.025, 0.045, 0.09, 0.96)
	instruction_layer.add_child(panel)

	instruction_title = Label.new()
	instruction_title.position = Vector2(panel.position.x + 40.0, panel.position.y + 34.0)
	instruction_title.size = Vector2(panel.size.x - 80.0, 70.0)
	instruction_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_title.add_theme_font_size_override("font_size", 48)
	instruction_title.add_theme_color_override("font_color", Color(0.25, 1.0, 0.86))
	instruction_layer.add_child(instruction_title)

	instruction_body = Label.new()
	instruction_body.position = Vector2(panel.position.x + 86.0, panel.position.y + 135.0)
	instruction_body.size = Vector2(panel.size.x - 172.0, 270.0)
	instruction_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_body.add_theme_font_size_override("font_size", 30)
	instruction_body.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	instruction_layer.add_child(instruction_body)

	instruction_start_button = _create_premium_button("START", Vector2(panel.position.x + 230.0, panel.position.y + 450.0), Vector2(300, 76))
	instruction_start_button.pressed.connect(_start_pending_stage)
	instruction_layer.add_child(instruction_start_button)

	instruction_back_button = _create_premium_button("BACK", Vector2(panel.position.x + 590.0, panel.position.y + 450.0), Vector2(300, 76))
	instruction_back_button.pressed.connect(_hide_instruction_screen)
	instruction_layer.add_child(instruction_back_button)


func _setup_result_buttons() -> void:
	# Mouse buttons for the result screen.
	# R key still works, but these buttons make the UI playable with a mouse.
	result_retry_button = _create_premium_button("RETRY", Vector2(screen_size.x * 0.5 - 330.0, screen_size.y * 0.5 + 142.0), Vector2(280, 72))
	result_retry_button.pressed.connect(_on_result_retry_pressed)
	game_over_layer.add_child(result_retry_button)

	result_home_button = _create_premium_button("HOME", Vector2(screen_size.x * 0.5 + 50.0, screen_size.y * 0.5 + 142.0), Vector2(280, 72))
	result_home_button.pressed.connect(_on_result_home_pressed)
	game_over_layer.add_child(result_home_button)



func _setup_online_lobby_ui() -> void:
	# Step 9-12:
	# 繧ｪ繝ｳ繝ｩ繧､繝ｳ逕ｨ縺ｮ繝ｭ繝薙・UI繧樽ain縺ｮ荳翫↓驥阪・縺ｾ縺吶・
	# 縺薙％縺ｧ縺ｯUI繝弱・繝峨ｒ逶ｴ謗･Main縺ｫ菴懊ｉ縺壹∝ｰら畑Controller縺ｫ莉ｻ縺帙∪縺吶・
	online_lobby = OnlineLobbyControllerScript.new()
	# Online Lobby 縺ｯ繧ｿ繧､繝医Ν逕ｻ髱｢繧医ｊ蜑埼擇縺ｫ蜃ｺ縺吝ｿ・ｦ√′縺ゅｊ縺ｾ縺吶・
	# title_layer.layer = 20 縺ｪ縺ｮ縺ｧ縲∝香蛻・､ｧ縺阪＞蛟､縺ｫ縺励∪縺吶・
	online_lobby.layer = 80
	add_child(online_lobby)

	# UI縺九ｉ譚･縺滓桃菴懆ｦ∵ｱゅｒ縲｀ain蛛ｴ縺ｮNetworkClient縺ｫ讖区ｸ｡縺励＠縺ｾ縺吶・
	online_lobby.connect_requested.connect(_on_online_lobby_connect_requested)
	online_lobby.create_room_requested.connect(_on_online_lobby_create_room_requested)
	online_lobby.join_room_requested.connect(_on_online_lobby_join_room_requested)
	online_lobby.role_selected.connect(_on_online_lobby_role_selected)
	online_lobby.ready_requested.connect(_on_online_lobby_ready_requested)
	online_lobby.start_game_requested.connect(_on_online_lobby_start_game_requested)
	online_lobby.close_requested.connect(_on_online_lobby_close_requested)


func _setup_online_status_hud() -> void:
	# Step 13:
	# 繧ｪ繝ｳ繝ｩ繧､繝ｳ繧ｲ繝ｼ繝荳ｭ縺ｫ縲∵磁邯夂憾諷九・驛ｨ螻狗分蜿ｷ繝ｻ閾ｪ蛻・・蠖ｹ蜑ｲ繧貞ｸｸ縺ｫ遒ｺ隱阪〒縺阪ｋHUD縺ｧ縺吶・
	online_status_layer = CanvasLayer.new()
	online_status_layer.layer = 70
	online_status_layer.visible = false
	add_child(online_status_layer)

	online_status_panel = ColorRect.new()
	online_status_panel.position = Vector2(screen_size.x - 520.0, 24.0)
	online_status_panel.size = Vector2(490.0, 174.0)
	online_status_panel.color = Color(0.01, 0.025, 0.055, 0.86)
	online_status_layer.add_child(online_status_panel)

	online_status_label = Label.new()
	online_status_label.position = online_status_panel.position + Vector2(20.0, 14.0)
	online_status_label.size = Vector2(450.0, 112.0)
	online_status_label.add_theme_font_size_override("font_size", 22)
	online_status_label.add_theme_color_override("font_color", Color(0.88, 0.97, 1.0))
	online_status_label.text = "ONLINE"
	online_status_layer.add_child(online_status_label)

	online_return_button = _create_premium_button("LOBBY", online_status_panel.position + Vector2(300.0, 120.0), Vector2(150.0, 42.0))
	online_return_button.add_theme_font_size_override("font_size", 20)
	online_return_button.pressed.connect(_return_to_online_lobby)
	online_status_layer.add_child(online_return_button)


func _show_online_status_hud(enabled: bool) -> void:
	# Step 13:
	# 繧ｲ繝ｼ繝荳ｭ縺縺践UD繧定｡ｨ遉ｺ縺励∪縺吶ゅち繧､繝医Ν繧・Ο繝薙・縺ｧ縺ｯ髱櫁｡ｨ遉ｺ縺ｧ縺吶・
	if online_status_layer != null:
		online_status_layer.visible = enabled


func _update_online_status_hud() -> void:
	# Step 13:
	# 豈弱ヵ繝ｬ繝ｼ繝縲√が繝ｳ繝ｩ繧､繝ｳ迥ｶ諷九ｒHUD縺ｸ蜿肴丐縺励∪縺吶・
	if online_status_layer == null or not online_status_layer.visible:
		return
	var room_text := network_join_room_code if network_join_room_code != "" else "-"
	var local_text := "P%d" % online_local_player_id if online_input_mode else "-"
	var role_text := "Azure Wing" if online_local_player_id == 1 else "Solar Fang"
	online_status_label.text = "ONLINE MODE\nROOM %s   YOU %s\n%s\nARROWS + SPACE\nI/O %d / %d" % [
		room_text,
		local_text,
		role_text,
		network_input_send_count,
		network_input_receive_count
	]


func _on_online_button_pressed() -> void:
	# 繧ｿ繧､繝医Ν逕ｻ髱｢縺九ｉ繧ｪ繝ｳ繝ｩ繧､繝ｳ繝ｭ繝薙・繧帝幕縺阪∪縺吶・
	_show_online_lobby()


func _show_online_lobby() -> void:
	if online_lobby == null:
		return
	# Step 13: 繝ｭ繝薙・繧帝幕縺上→縺阪・縲√ご繝ｼ繝荳ｭHUD繧帝國縺励∪縺吶・
	_show_online_status_hud(false)

	# 繧ｿ繧､繝医Ν逕ｻ髱｢繧定｡ｨ遉ｺ縺励◆縺ｾ縺ｾ縺縺ｨ縲＾nline Lobby 縺悟ｾ後ｍ縺ｫ髫繧後※
	# LineEdit 繧・Button 繧呈桃菴懊〒縺阪↑縺上↑繧九◆繧√√Ο繝薙・陦ｨ遉ｺ荳ｭ縺ｯ髫縺励∪縺吶・
	if title_layer != null:
		title_layer.visible = false
	if instruction_layer != null:
		instruction_layer.visible = false
	instruction_visible = false

	if audio_manager != null:
		audio_manager.play_sfx("ui_select", -8.0)
	online_lobby.open_lobby(network_server_url)
	online_lobby.set_network_status(network_last_status)
	online_lobby.set_room_id(network_join_room_code)
	online_lobby.set_local_player(online_local_player_id if online_input_mode else 0)


func _on_online_lobby_close_requested() -> void:
	if online_lobby != null:
		online_lobby.close_lobby()

	# 繝ｭ繝薙・繧帝哩縺倥◆繧峨ち繧､繝医Ν逕ｻ髱｢縺ｸ謌ｻ縺励∪縺吶・
	# 繧ｲ繝ｼ繝荳ｭ縺ｫ蜻ｼ縺ｰ繧後◆蝣ｴ蜷医・縲√ち繧､繝医Ν繧貞享謇九↓蜃ｺ縺輔↑縺・ｈ縺・↓縺励∪縺吶・
	if mode == GameMode.TITLE and title_layer != null:
		title_layer.visible = true


func _on_online_lobby_connect_requested(player_name: String) -> void:
	# 繝ｦ繝ｼ繧ｶ繝ｼ蜷阪ｒ菫晏ｭ倥＠縺ｦ縺九ｉ繧ｵ繝ｼ繝舌・縺ｸ謗･邯壹＠縺ｾ縺吶・
	# 謗･邯壽ｸ医∩縺ｪ繧牙錐蜑阪□縺大・騾∽ｿ｡縺励∪縺吶・
	online_player_name = player_name.strip_edges()
	if online_player_name == "":
		online_player_name = "Player"
	if network_client == null:
		return
	if not network_client.is_connected_to_server():
		network_last_message = "Connecting..."
		network_client.connect_to_server(network_server_url)
	else:
		network_client.set_player_name(online_player_name)
	if online_lobby != null:
		online_lobby.set_status_message("Connecting / name: " + online_player_name)


func _on_online_lobby_create_room_requested(player_name: String) -> void:
	# 繝ｫ繝ｼ繝菴懈・繝懊ち繝ｳ縺九ｉ蜻ｼ縺ｰ繧後∪縺吶・
	# 譛ｬ逡ｪUI縺ｧ縺ｯ縲：11縺ｮ莉｣繧上ｊ縺ｫ縺薙・髢｢謨ｰ繧剃ｽｿ縺・∪縺吶・
	online_player_name = player_name.strip_edges()
	if online_player_name == "":
		online_player_name = "Player"
	if network_client == null or not network_client.is_connected_to_server():
		if online_lobby != null:
			online_lobby.set_status_message("Connect first.")
		return
	network_client.set_player_name(online_player_name)
	network_client.create_room("story")
	if online_lobby != null:
		online_lobby.set_status_message("Creating room...")


func _on_online_lobby_join_room_requested(player_name: String, room_code: String) -> void:
	# Join繝懊ち繝ｳ縺九ｉ蜻ｼ縺ｰ繧後∪縺吶・
	# 繝ｫ繝ｼ繝繧ｳ繝ｼ繝峨・螟ｧ譁・ｭ励↓邨ｱ荳縺励※騾∽ｿ｡縺励∪縺吶・
	online_player_name = player_name.strip_edges()
	if online_player_name == "":
		online_player_name = "Player"
	var code := room_code.strip_edges().to_upper()
	if code == "":
		if online_lobby != null:
			online_lobby.set_status_message("Enter a room code.")
		return
	if network_client == null or not network_client.is_connected_to_server():
		if online_lobby != null:
			online_lobby.set_status_message("Connect first.")
		return
	network_client.set_player_name(online_player_name)
	network_join_room_code = code
	network_client.join_room(code)
	if online_lobby != null:
		online_lobby.set_status_message("Joining room: " + code)


func _on_online_lobby_role_selected(role: String) -> void:
	# P1 / P2縺ｮ逕ｻ蜒上き繝ｼ繝峨ｒ繧ｯ繝ｪ繝・け縺励◆縺ｨ縺阪・蜃ｦ逅・〒縺吶・
	# 繧ｵ繝ｼ繝舌・蛛ｴ縺ｧ遨ｺ縺咲憾豕√ｒ遒ｺ隱阪＠縲〉oom_state縺ｧ蜈ｨ蜩｡縺ｸ蜿肴丐縺励∪縺吶・
	online_selected_role = role
	if network_client != null and network_client.is_connected_to_server():
		network_client.select_role(role)
	if online_lobby != null:
		online_lobby.set_status_message("Selecting " + role.to_upper() + "...")


func _on_online_lobby_ready_requested(ready: bool) -> void:
	# Waiting Room縺ｮREADY繝懊ち繝ｳ縺ｧ縺吶・
	online_ready = ready
	if network_client != null and network_client.is_connected_to_server():
		network_client.set_ready(ready)
	if online_lobby != null:
		online_lobby.set_status_message("Ready: " + str(ready))


func _on_online_lobby_start_game_requested() -> void:
	# 繝帙せ繝医′Start Game繧呈款縺励◆縺ｨ縺阪↓蜻ｼ縺ｰ繧後∪縺吶・
	# 繧ｵ繝ｼ繝舌・縺九ｉgame_start縺瑚ｿ斐ｋ縺ｨ縲∝・繧ｯ繝ｩ繧､繧｢繝ｳ繝医′蜷後§繧ｹ繝・・繧ｸ縺ｸ騾ｲ縺ｿ縺ｾ縺吶・
	if network_client != null and network_client.is_connected_to_server():
		network_client.start_game("story")
	if online_lobby != null:
		online_lobby.set_status_message("Requesting game start...")


func _on_story_button_pressed() -> void:
	_show_stage_instruction("story")


func _on_astral_button_pressed() -> void:
	_show_stage_instruction("astral")


func _on_raid_button_pressed() -> void:
	_show_stage_instruction("raid")


func _show_stage_instruction(stage_id: String) -> void:
	# Select the stage, show the explanation panel, then wait for START.
	if audio_manager != null:
		audio_manager.play_sfx("ui_select", -8.0)

	match stage_id:
		"story":
			pending_stage_script = StoryStageScript
			pending_stage_name = "Story Mode"
			instruction_title.text = "STORY MODE"
			instruction_body.text = "Co-op defense stage.\nP1 Azure Wing: fast precision fire.\nP2 Solar Fang: heavy wide fire.\nRapid / Power items now change each player differently.\nLink Charge or 100% Co-op Link activates Fusion Mode.\nFusion: P1 aims + fires with WASD/F, P2 moves + shields with Arrows/L."
		"astral":
			pending_stage_script = AstralCourtStageScript
			pending_stage_name = "Astral Court"
			instruction_title.text = "ASTRAL COURT"
			instruction_body.text = "Premium duel stage.\nControl the Stellar Core, use dash and shield, and defeat the rival pilot.\nP1: Q / E / G    P2: O / P / K"
		"raid":
			pending_stage_script = RaidStageScript
			pending_stage_name = "Eclipse Leviathan Raid"
			instruction_title.text = "ECLIPSE LEVIATHAN RAID"
			instruction_body.text = "Co-op raid stage.\nAttack the glowing weak core, stay close to charge Link,\nand unleash Twin Core Cannon at 100%."
		_:
			return

	instruction_visible = true
	instruction_layer.visible = true


func _hide_instruction_screen() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("ui_select", -10.0)
	instruction_visible = false
	pending_stage_script = null
	pending_stage_name = ""
	if instruction_layer != null:
		instruction_layer.visible = false


func _start_pending_stage() -> void:
	if pending_stage_script == null:
		return
	if audio_manager != null:
		audio_manager.play_sfx("ui_confirm", -6.0)
	_load_stage(pending_stage_script)


func _on_result_home_pressed() -> void:
	# A reload is the safest way to reset every gameplay array and UI layer.
	get_tree().reload_current_scene()


func _on_result_retry_pressed() -> void:
	# Retry the same stage when possible. If there is no last stage, return home.
	if last_stage_script == null:
		get_tree().reload_current_scene()
		return
	game_over = false
	game_over_layer.visible = false
	_load_stage(last_stage_script)


func _show_title() -> void:
	mode = GameMode.TITLE
	# Step 13: 繧ｿ繧､繝医Ν縺ｫ謌ｻ繧九→縺阪・縲√が繝ｳ繝ｩ繧､繝ｳ繧ｲ繝ｼ繝荳ｭHUD繧帝撼陦ｨ遉ｺ縺ｫ縺励∪縺吶・
	_show_online_status_hud(false)
	title_layer.visible = true
	if instruction_layer != null:
		instruction_layer.visible = false
	instruction_visible = false
	pending_stage_script = null
	pending_stage_name = ""
	banner_label.text = ""
	if audio_manager != null:
		audio_manager.play_bgm("home")

func _handle_title_input() -> void:
	# Step 8:
	# The title screen is now mouse-operable.
	# Keyboard input is kept as a fallback for quick testing.
	if instruction_visible:
		if Input.is_key_pressed(KEY_ESCAPE):
			_hide_instruction_screen()
		elif Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE):
			_start_pending_stage()
		return

	if Input.is_key_pressed(KEY_1) or Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE):
		_show_stage_instruction("story")
	elif Input.is_key_pressed(KEY_2):
		_show_stage_instruction("astral")
	elif Input.is_key_pressed(KEY_3):
		_show_stage_instruction("raid")

func _load_stage(stage_script: Script) -> void:
	# Hide menu overlays before starting gameplay.
	if instruction_layer != null:
		instruction_layer.visible = false
	instruction_visible = false
	last_stage_script = stage_script

	# Remove the previous stage controller if one exists.
	# This does not remove the visual game objects yet; the existing _start_*()
	# functions still call _clear_game_objects() as before.
	if current_stage != null:
		current_stage.queue_free()
		current_stage = null

	# Create a new stage controller node and attach the selected stage script.
	var stage_node := Node2D.new()
	stage_node.set_script(stage_script)
	stage_root.add_child(stage_node)

	current_stage = stage_node as StageBase
	if current_stage == null:
		push_error("Failed to load stage controller.")
		return

	# Connect the common stage-finished signal.
	# We will use this more when result screens are moved out of Main.gd.
	current_stage.stage_finished.connect(_on_stage_finished)

	# Give the stage a reference to Main.gd for this transition step.
	current_stage.setup_stage(self)
	current_stage.start_stage()

func _on_stage_finished(result: Dictionary) -> void:
	# Temporary debug hook.
	# Later this will show ResultScreen.tscn or return to the title menu.
	print("Stage finished: ", result)


func _get_player_spec(player_id: int) -> Dictionary:
	# Returns a safe player spec.
	# If a wrong ID is passed, P1's spec is used as a fallback.
	if player_specs.has(player_id):
		return player_specs[player_id]
	return player_specs[1]


func _create_players() -> void:
	players.clear()
	var p1: Dictionary = _create_player(1, AssetPaths.PLAYERS["p1"], Vector2(screen_size.x * 0.35, screen_size.y - 160), Color(0.2, 0.85, 1.0))
	var p2: Dictionary = _create_player(2, AssetPaths.PLAYERS["p2"], Vector2(screen_size.x * 0.65, screen_size.y - 160), Color(1.0, 0.66, 0.18))
	players.append(p1)
	players.append(p2)

func _create_player(id: int, path: String, pos: Vector2, color: Color) -> Dictionary:
	var spec: Dictionary = _get_player_spec(id)

	# P1 is smaller and agile. P2 is larger and heavier.
	var sprite_size := Vector2(92, 92) if id == 1 else Vector2(112, 112)
	var sprite := AssetPaths.create_sprite(path, sprite_size, color, 10)
	sprite.position = pos
	add_child(sprite)

	var shield := AssetPaths.create_sprite(AssetPaths.EFFECTS["shield_bubble"], Vector2(170, 170), Color(0.5, 0.9, 1.0, 0.5), 11)
	shield.visible = false
	add_child(shield)

	return {
		"id": id,
		"name": String(spec["name"]),
		"sprite": sprite,
		"shield_sprite": shield,
		"pos": pos,
		"hp": 100,
		"base_speed": float(spec["speed"]),
		"speed": float(spec["speed"]),
		"shot_speed": float(spec["shot_speed"]),
		"shoot_interval": float(spec["shoot_interval"]),
		"rapid_interval": float(spec["rapid_interval"]),
		"damage": int(spec["damage"]),
		"bullet_size": float(spec["bullet_size"]),
		"power_mode": String(spec["power_mode"]),
		"radius": 42.0 if id == 1 else 52.0,
		"rapid": 0.0,
		"power": 0.0,
	}

func _start_story() -> void:
	mode = GameMode.STORY
	title_layer.visible = false
	game_over = false
	team_score = 0
	p1_score = 0
	p2_score = 0
	base_hp = CORE_HP_MAX
	core_shield_time = 0.0
	core_shield_max  = 0.0
	coop_link = 0.0
	story_wave = 1
	result_title = ""
	result_message = ""
	game_over_layer.visible = false

	# Reset fusion mode for a clean Story Mode start.
	story_fusion_active = false
	story_fusion_timer = 0.0
	story_fusion_cannon_cd = 0.0
	story_fusion_bomb_cd = 0.0
	story_fusion_aim = Vector2.UP
	fusion_sprite.visible = false

	_clear_game_objects()
	_set_background(AssetPaths.BACKGROUNDS["space"])
	base_sprite.visible = true
	astral_ring_sprite.visible = false
	boss_sprite.visible = false
	boss_hp_back.visible = false
	boss_hp_fill.visible = false
	link_back.visible = false
	link_fill.visible = false

	for p in players:
		p["pos"] = Vector2(screen_size.x * (0.35 if p["id"] == 1 else 0.65), screen_size.y - 160)
		p["hp"] = 100
		p["rapid"] = 0.0
		p["power"] = 0.0
		p["speed"] = p["base_speed"]
		(p["sprite"] as Sprite2D).visible = true
		(p["shield_sprite"] as Sprite2D).visible = false

	banner_label.text = "STORY MODE"
	if audio_manager != null:
		audio_manager.play_bgm("story")
		audio_manager.play_sfx("stage_start")
		audio_manager.stop_shield_loop()

func _start_astral_court() -> void:
	mode = GameMode.ASTRAL_COURT
	title_layer.visible = false
	game_over = false
	game_over_layer.visible = false
	_clear_game_objects()
	_set_background(AssetPaths.BACKGROUNDS["astral"])
	base_sprite.visible = false
	base_shield_sprite.visible = false
	astral_ring_sprite.visible = true
	boss_sprite.visible = false
	boss_hp_back.visible = false
	boss_hp_fill.visible = false
	arena_time = 60.0
	arena_p1_hp = 100
	arena_p2_hp = 100
	p1_core = 0.0
	p2_core = 0.0
	p1_ult_ready = false
	p2_ult_ready = false
	astral_core_pos = screen_size * 0.5
	arena_obstacles = [
		Rect2(Vector2(screen_size.x * 0.5 - 260, screen_size.y * 0.5 - 80), Vector2(150, 120)),
		Rect2(Vector2(screen_size.x * 0.5 + 110, screen_size.y * 0.5 - 80), Vector2(150, 120)),
	]
	for i in range(arena_obstacle_sprites.size()):
		arena_obstacle_sprites[i].visible = true
		arena_obstacle_sprites[i].position = arena_obstacles[i].get_center()
	players[0]["pos"] = Vector2(220, screen_size.y * 0.5)
	players[1]["pos"] = Vector2(screen_size.x - 220, screen_size.y * 0.5)
	banner_label.text = "ASTRAL COURT"
	if audio_manager != null:
		audio_manager.play_bgm("astral")
		audio_manager.play_sfx("stage_start")
		audio_manager.stop_shield_loop()

func _start_raid() -> void:
	mode = GameMode.RAID
	title_layer.visible = false
	game_over = false
	game_over_layer.visible = false
	_clear_game_objects()
	_set_background(AssetPaths.BACKGROUNDS["raid"])
	base_sprite.visible = false
	base_shield_sprite.visible = false
	astral_ring_sprite.visible = false
	for s in arena_obstacle_sprites:
		s.visible = false
	boss_sprite.texture = AssetPaths.load_texture(AssetPaths.BOSSES["leviathan"], Color(0.45, 0.0, 0.6))
	AssetPaths.fit_sprite(boss_sprite, Vector2(560, 320))
	raid_boss_time = 0.0
	raid_boss_center = Vector2(screen_size.x * 0.5, 230)
	boss_sprite.position = raid_boss_center
	boss_sprite.visible = true
	raid_boss_hp = raid_boss_max_hp
	raid_phase = 1
	raid_link = 0.0
	raid_attack_timer = 1.6
	raid_drone_timer = 3.4
	raid_weak_index = 1
	players[0]["pos"] = Vector2(screen_size.x * 0.35, screen_size.y - 150)
	players[1]["pos"] = Vector2(screen_size.x * 0.65, screen_size.y - 150)
	boss_hp_back.visible = true
	boss_hp_fill.visible = true
	link_back.visible = true
	link_fill.visible = true
	banner_label.text = "ECLIPSE LEVIATHAN"
	if audio_manager != null:
		audio_manager.play_bgm("eclipse")
		audio_manager.play_sfx("stage_start")
		audio_manager.stop_shield_loop()

func _set_background(path: String) -> void:
	bg_sprite.texture = AssetPaths.load_texture(path, Color(0.02, 0.02, 0.08))
	AssetPaths.fit_sprite(bg_sprite, screen_size)
	bg_sprite.position = screen_size * 0.5

func _clear_game_objects() -> void:
	for arr in [bullets, enemy_bullets, enemies, items, effects, bombs]:
		for obj in arr:
			if obj.has("sprite") and is_instance_valid(obj["sprite"]):
				obj["sprite"].queue_free()
		arr.clear()

	for c in crystal_objects:
		if is_instance_valid(c["sprite"]):
			(c["sprite"] as Sprite2D).queue_free()
	crystal_objects.clear()
	for m in missiles:
		if is_instance_valid(m["sprite"]):
			(m["sprite"] as Sprite2D).queue_free()
	missiles.clear()
	for t in turrets:
		if is_instance_valid(t["sprite"]):
			(t["sprite"] as Sprite2D).queue_free()
	turrets.clear()
	crystals = 0
	p1_weapon = ""
	p2_weapon = ""
	p1_weapon_cd = 0.0
	p2_weapon_cd = 0.0
	crystal_magnet_timer = 0.0
	emp_stun_timer = 0.0
	_update_hud_crystal_label()

	for weak in raid_weak_sprites:
		weak.visible = false
	for s in arena_obstacle_sprites:
		s.visible = false

	story_fusion_active = false
	story_fusion_timer = 0.0
	story_fusion_cannon_cd = 0.0
	story_fusion_bomb_cd = 0.0
	fusion_sprite.visible = false
	if fusion_pointer_line != null:
		fusion_pointer_line.visible = false
	if fusion_pointer_reticle != null:
		fusion_pointer_reticle.visible = false

	for p in players:
		if p.has("sprite") and is_instance_valid(p["sprite"]):
			(p["sprite"] as Sprite2D).visible = true
		if p.has("shield_sprite") and is_instance_valid(p["shield_sprite"]):
			(p["shield_sprite"] as Sprite2D).visible = false

func _update_players(delta: float) -> void:
	# Story fusion mode replaces normal player movement.
	# P1: pointer + cannon. P2: movement + bomb.
	if mode == GameMode.STORY and story_fusion_active:
		_update_story_fusion(delta)
		return

	for p in players:
		var dir := Vector2.ZERO
		var player_id: int = int(p["id"])
		var rapid: float = float(p["rapid"])
		var power: float = float(p.get("power", 0.0))

		var input_state := _get_player_input(player_id)
		dir = input_state.move

		if player_id == 1:
			if input_state.shoot and shoot_cd_p1 <= 0.0:
				_shoot(1)
				shoot_cd_p1 = float(p["rapid_interval"]) if rapid > 0.0 else float(p["shoot_interval"])
		else:
			if input_state.shoot and shoot_cd_p2 <= 0.0:
				_shoot(2)
				shoot_cd_p2 = float(p["rapid_interval"]) if rapid > 0.0 else float(p["shoot_interval"])

		var pos: Vector2 = p["pos"]
		pos += dir * float(p["speed"]) * delta
		pos.x = clampf(pos.x, 60.0, screen_size.x - 60.0)
		pos.y = clampf(pos.y, 120.0, screen_size.y - 60.0)
		p["pos"] = pos
		p["rapid"] = maxf(0.0, rapid - delta)
		p["power"] = maxf(0.0, power - delta)
		(p["sprite"] as Sprite2D).position = pos
		(p["shield_sprite"] as Sprite2D).position = pos
		(p["shield_sprite"] as Sprite2D).visible = false

	if mode == GameMode.ASTRAL_COURT:
		_handle_arena_abilities(delta)

func _input_dir(up: Key, down: Key, left: Key, right: Key) -> Vector2:
	var d := Vector2.ZERO
	if Input.is_key_pressed(up): d.y -= 1.0
	if Input.is_key_pressed(down): d.y += 1.0
	if Input.is_key_pressed(left): d.x -= 1.0
	if Input.is_key_pressed(right): d.x += 1.0
	return d.normalized() if d.length() > 0.0 else Vector2.ZERO

func _shoot(player_id: int) -> void:
	var p: Dictionary = players[player_id - 1]
	var direction := Vector2.UP

	# Astral Court is a horizontal duel.
	if mode == GameMode.ASTRAL_COURT:
		direction = Vector2.RIGHT if player_id == 1 else Vector2.LEFT

	var path: String = AssetPaths.PROJECTILES["azure"] if player_id == 1 else AssetPaths.PROJECTILES["solar"]
	var origin: Vector2 = p["pos"]
	var damage: int = int(p["damage"])
	var shot_speed: float = float(p["shot_speed"])
	var bullet_size: float = float(p["bullet_size"])
	var power: float = float(p.get("power", 0.0))
	var is_piercing := false

	# Step B: personalized Power Boost behavior.
	if mode == GameMode.STORY and power > 0.0:
		if String(p["power_mode"]) == "piercing_laser":
			# P1: Azure Wing turns into a fast piercing laser.
			damage += 4
			shot_speed *= 1.18
			bullet_size = 42.0
			is_piercing = true
		elif String(p["power_mode"]) == "giant_bullet":
			# P2: Solar Fang fires a huge heavy projectile.
			damage += 20
			bullet_size *= 1.65
			shot_speed *= 0.92

	# Step B: personalized Rapid Fire behavior.
	# P2 rapid fire becomes a 3-shot burst. P1 simply fires extremely fast.
	if mode == GameMode.STORY and player_id == 2 and float(p["rapid"]) > 0.0:
		for angle_offset in [-0.18, 0.0, 0.18]:
			var burst_dir := direction.rotated(angle_offset)
			var burst_bullet: Dictionary = _create_bullet(origin + burst_dir * 58.0, burst_dir, player_id, damage, path, shot_speed, bullet_size, is_piercing)
			bullets.append(burst_bullet)
	else:
		var bullet: Dictionary = _create_bullet(origin + direction * 58.0, direction, player_id, damage, path, shot_speed, bullet_size, is_piercing)
		bullets.append(bullet)

	_fire_weapon_extra(player_id, origin, direction * shot_speed)

	if audio_manager != null:
		audio_manager.play_sfx("shot_azure" if player_id == 1 else "shot_solar", -8.0)

func _create_bullet(pos: Vector2, dir: Vector2, owner_id: int, damage: int, path: String, speed: float, size: float, piercing: bool = false) -> Dictionary:
	var sprite := AssetPaths.create_sprite(path, Vector2(size, size), Color.WHITE, 20)
	sprite.position = pos
	sprite.rotation = dir.angle() + PI / 2
	add_child(sprite)

	return {
		"pos": pos,
		"vel": dir.normalized() * speed,
		"owner": owner_id,
		"damage": damage,
		"sprite": sprite,
		"radius": size * 0.5,
		"life": 3.2,
		"piercing": piercing,
		"pierce_hits": 3 if piercing else 0,
		"hit_enemies": {},
	}

func _update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		var pos: Vector2 = b["pos"]
		var vel: Vector2 = b["vel"]
		var life: float = float(b["life"])
		pos += vel * delta
		life -= delta
		b["pos"] = pos
		b["life"] = life
		(b["sprite"] as Sprite2D).position = pos
		(b["sprite"] as Sprite2D).rotation = vel.angle() + PI / 2
		if life <= 0.0 or pos.x < -80 or pos.x > screen_size.x + 80 or pos.y < -80 or pos.y > screen_size.y + 80:
			_remove_bullet(i)
			continue
		_check_bullet_hits(i)

func _check_bullet_hits(index: int) -> void:
	if index < 0 or index >= bullets.size():
		return
	var b: Dictionary = bullets[index]
	var pos: Vector2 = b["pos"]
	var owner_id: int = int(b["owner"])
	var radius: float = float(b["radius"])
	if mode == GameMode.ASTRAL_COURT:
		if owner_id == 1 or owner_id == 2:
			var target: Dictionary = players[1] if owner_id == 1 else players[0]
			var target_pos: Vector2 = target["pos"]
			if pos.distance_to(target_pos) < radius + float(target["radius"]):
				if (owner_id == 1 and p2_shield > 0.0) or (owner_id == 2 and p1_shield > 0.0):
					_remove_bullet(index)
					return
				if owner_id == 1:
					arena_p2_hp = max(0, arena_p2_hp - int(b["damage"]))
					p1_score += 5
				else:
					arena_p1_hp = max(0, arena_p1_hp - int(b["damage"]))
					p2_score += 5
				_spawn_effect(AssetPaths.EFFECTS["hit_spark"], target_pos, Vector2(90, 90), 0.18)
				_remove_bullet(index)
				return
	elif mode == GameMode.RAID:
		if owner_id == 1 or owner_id == 2:
			var weak_pos := _raid_weak_pos(raid_weak_index)
			if pos.distance_to(weak_pos) < radius + 46.0:
				raid_boss_hp = max(0, raid_boss_hp - int(b["damage"]) * 5)
				raid_link = clampf(raid_link + 5.0, 0.0, 100.0)
				team_score += 12
				_spawn_effect(AssetPaths.EFFECTS["hit_spark"], weak_pos, Vector2(110, 110), 0.22)
				_remove_bullet(index)
				return
		elif owner_id == 9:
			for p in players:
				var player_pos: Vector2 = p["pos"]
				if pos.distance_to(player_pos) < radius + float(p["radius"]):
					base_hp = max(0, base_hp - int(b["damage"]))
					_spawn_effect(AssetPaths.EFFECTS["hit_spark"], player_pos, Vector2(90, 90), 0.18)
					if audio_manager != null:
						audio_manager.play_sfx("core_damage", -6.0)
					_remove_bullet(index)
					return
	else:
		if owner_id == 1 or owner_id == 2:
			for e in enemies:
				var enemy_pos: Vector2 = e["pos"]
				if pos.distance_to(enemy_pos) < radius + float(e["radius"]):
					var piercing: bool = bool(b.get("piercing", false))
					var enemy_id := int((e["sprite"] as Sprite2D).get_instance_id())
					var hit_enemies: Dictionary = b.get("hit_enemies", {})

					# Piercing bullets should not damage the same enemy repeatedly every frame.
					if piercing and hit_enemies.has(enemy_id):
						continue

					e["hp"] = int(e["hp"]) - int(b["damage"])
					_spawn_effect(AssetPaths.EFFECTS["hit_spark"], enemy_pos, Vector2(80, 80), 0.16)
					if audio_manager != null:
						audio_manager.play_sfx("hit_small", -8.0)

					if piercing:
						hit_enemies[enemy_id] = true
						b["hit_enemies"] = hit_enemies
						b["pierce_hits"] = int(b.get("pierce_hits", 0)) - 1
						bullets[index] = b
						if int(b["pierce_hits"]) <= 0:
							_remove_bullet(index)
						return

					_remove_bullet(index)
					return
			# Player bullets can destroy bomber drone projectiles
			if owner_id == 1 or owner_id == 2:
				for j in range(enemy_bullets.size() - 1, -1, -1):
					var eb: Dictionary = enemy_bullets[j]
					var eb_pos: Vector2 = eb["pos"]
					if pos.distance_to(eb_pos) < radius + float(eb["radius"]):
						_spawn_effect(AssetPaths.EFFECTS["hit_spark"], eb_pos, Vector2(60, 60), 0.14)
						if audio_manager != null:
							audio_manager.play_sfx("hit_small", -10.0)
						if is_instance_valid(eb["sprite"]):
							(eb["sprite"] as Sprite2D).queue_free()
						enemy_bullets.remove_at(j)
						_remove_bullet(index)
						return

func _remove_bullet(index: int) -> void:
	if index < 0 or index >= bullets.size():
		return
	var b: Dictionary = bullets[index]
	if is_instance_valid(b["sprite"]):
		(b["sprite"] as Sprite2D).queue_free()
	bullets.remove_at(index)

func _update_story(delta: float) -> void:
	if fusion_flash_timer > 0.0:
		fusion_flash_timer -= delta
		fusion_flash_rect.color.a = fusion_flash_timer / 0.35 * 0.82

	if story_fusion_active and fusion_bar_fill != null:
		var ratio := story_fusion_timer / story_fusion_duration
		fusion_bar_fill.size.x = 680.0 * clampf(ratio, 0.0, 1.0)

	enemy_spawn_timer -= delta
	item_spawn_timer -= delta
	core_shield_time = maxf(0.0, core_shield_time - delta)

	# Normal core shield display.
	# Fusion mode has its own shield display around the fusion ship.
	if not story_fusion_active:
		base_shield_sprite.visible = core_shield_time > 0.0
		base_shield_sprite.position = base_sprite.position

	if audio_manager != null:
		if core_shield_time > 0.0:
			audio_manager.start_shield_loop()
		else:
			audio_manager.stop_shield_loop()

	if not story_fusion_active:
		var p1_pos: Vector2 = players[0]["pos"] as Vector2
		var p2_pos: Vector2 = players[1]["pos"] as Vector2
		var near_players := p1_pos.distance_to(p2_pos) < 360.0
		var near_core := p1_pos.distance_to(base_sprite.position) < 430.0 and p2_pos.distance_to(base_sprite.position) < 430.0
		if near_players or near_core:
			var link_rate := 11.0
			coop_link = clampf(coop_link + link_rate * delta, 0.0, 100.0)
		else:
			coop_link = clampf(coop_link - 5.0 * delta, 0.0, 100.0)

		# Step C / Step 14:
		# 繝ｭ繝ｼ繧ｫ繝ｫ2莠ｺ繝励Ξ繧､縺ｧ縺ｯ G / K / Space 縺ｧ蜷井ｽ薙〒縺阪∪縺吶・
		# 繧ｪ繝ｳ繝ｩ繧､繝ｳ譎ゅ・蜷ПC縺ｮ Space 蜈･蜉帙′InputRouter邨檎罰縺ｧ螻翫￥縺溘ａ縲・
		# _is_any_online_action_pressed() 繧ょ粋菴薙ヨ繝ｪ繧ｬ繝ｼ縺ｫ蜷ｫ繧√∪縺吶・
		var fusion_trigger_pressed := (
			Input.is_key_pressed(KEY_G)
			or Input.is_key_pressed(KEY_K)
			or Input.is_key_pressed(KEY_SPACE)
			or _is_any_online_action_pressed()
		)
		if coop_link >= 100.0 and fusion_trigger_pressed:
			_activate_story_fusion("CO-OP LINK 100%")
	else:
		coop_link = 0.0

	if enemy_spawn_timer <= 0.0:
		_spawn_enemy()
		enemy_spawn_timer = rng.randf_range(0.65, 1.15)
	if item_spawn_timer <= 0.0:
		_spawn_item()
		item_spawn_timer = rng.randf_range(5.0, 8.0)
	_update_enemies(delta)
	_update_enemy_bullets(delta)
	if base_hp <= 0:
		_game_over("CORE DESTROYED", "The central core collapsed.\nTeam Score: %d\nPress R to return to Home" % team_score)


func _activate_story_fusion(reason: String = "LINK READY") -> void:
	if mode != GameMode.STORY:
		return

	story_fusion_active = true
	story_fusion_timer = story_fusion_duration
	story_fusion_cannon_cd = 0.0
	story_fusion_bomb_cd = 0.0
	coop_link = 0.0

	story_fusion_position = ((players[0]["pos"] as Vector2) + (players[1]["pos"] as Vector2)) * 0.5
	story_fusion_aim = Vector2.UP
	story_fusion_pointer_pos = story_fusion_position + story_fusion_aim * 210.0

	# Hide individual ships and show the fused mech.
	for p in players:
		(p["sprite"] as Sprite2D).visible = false
		(p["shield_sprite"] as Sprite2D).visible = false
		p["pos"] = story_fusion_position

	fusion_sprite.position = story_fusion_position
	fusion_sprite.rotation = 0.0
	fusion_sprite.visible = true
	_update_fusion_pointer_visuals()
	fusion_pointer_line.visible = true
	fusion_pointer_reticle.visible = true
	_spawn_effect(AssetPaths.EFFECTS["twin_core_cannon"], story_fusion_position, Vector2(420, 420), 0.55)

	banner_label.text = "TWIN CORE FUSION ACTIVATED"
	if audio_manager != null:
		audio_manager.play_sfx("twin_core_cannon", -4.0)
	fusion_flash_timer = 0.35
	if fusion_flash_rect != null:
		fusion_flash_rect.color = Color(0.5, 0.9, 1.0, 0.82)
	if fusion_bar_back != null:
		fusion_bar_back.visible = true
		fusion_bar_fill.visible = true
		fusion_bar_fill.size.x = 680.0


func _update_story_fusion(delta: float) -> void:
	story_fusion_timer -= delta
	story_fusion_cannon_cd = maxf(0.0, story_fusion_cannon_cd - delta)
	story_fusion_bomb_cd = maxf(0.0, story_fusion_bomb_cd - delta)

	if story_fusion_timer <= 0.0:
		_deactivate_story_fusion()
		return

	# Step 3: P2 controls only the fused ship movement.
	# The pointer is visually connected to the fused ship.
	# Therefore, when P2 moves the ship, the pointer moves together first.
	# After that, P1 can smoothly adjust only the pointer offset with WASD.
	var previous_fusion_position := story_fusion_position
	var p1_input := _get_player_input(1)
	var p2_input := _get_player_input(2)

	var move_dir := p2_input.move
	story_fusion_position += move_dir * story_fusion_move_speed * delta
	story_fusion_position.x = clampf(story_fusion_position.x, 90.0, screen_size.x - 90.0)
	story_fusion_position.y = clampf(story_fusion_position.y, 160.0, screen_size.y - 80.0)

	var fusion_delta := story_fusion_position - previous_fusion_position
	story_fusion_pointer_pos += fusion_delta

	# Step 1: P1 moves a connected pointer with WASD.
	# The fused ship itself stays visually upright and does not rotate.
	var pointer_move := p1_input.move
	if pointer_move.length() > 0.1:
		story_fusion_pointer_pos += pointer_move * story_pointer_speed * delta

	var pointer_offset := story_fusion_pointer_pos - story_fusion_position
	if pointer_offset.length() < story_pointer_min_distance:
		pointer_offset = story_fusion_aim * story_pointer_min_distance
	elif pointer_offset.length() > story_pointer_max_distance:
		pointer_offset = pointer_offset.normalized() * story_pointer_max_distance

	story_fusion_pointer_pos = story_fusion_position + pointer_offset
	if pointer_offset.length() > 0.1:
		story_fusion_aim = pointer_offset.normalized()

	# Step 2: P1 fires toward the pointer with F.
	if p1_input.shoot and story_fusion_cannon_cd <= 0.0:
		var cannon_bullet := _create_bullet(
			story_fusion_position + story_fusion_aim * 96.0,
			story_fusion_aim,
			1,
			64,
			AssetPaths.PROJECTILES["azure"],
			1350.0,
			78.0,
			true
		)
		bullets.append(cannon_bullet)
		story_fusion_cannon_cd = 0.82
		_spawn_effect(AssetPaths.EFFECTS["twin_core_cannon"], story_fusion_position + story_fusion_aim * 130.0, Vector2(280, 120), 0.22)
		if audio_manager != null:
			audio_manager.play_sfx("twin_core_cannon", -5.0)

	# Step 4: P2 places bombs with L.
	# Bombs explode on enemy contact or after a short fuse.
	if _is_player_bombing(2) and story_fusion_bomb_cd <= 0.0:
		_place_fusion_bomb()

	fusion_sprite.position = story_fusion_position
	fusion_sprite.rotation = 0.0
	_update_fusion_pointer_visuals()

	for p in players:
		p["pos"] = story_fusion_position
		(p["shield_sprite"] as Sprite2D).visible = false

	base_shield_sprite.visible = false


func _deactivate_story_fusion() -> void:
	story_fusion_active = false
	story_fusion_timer = 0.0
	story_fusion_cannon_cd = 0.0
	story_fusion_bomb_cd = 0.0
	fusion_sprite.visible = false
	if fusion_pointer_line != null:
		fusion_pointer_line.visible = false
	if fusion_pointer_reticle != null:
		fusion_pointer_reticle.visible = false

	# Return individual ships around the fusion position.
	if players.size() >= 2:
		players[0]["pos"] = story_fusion_position + Vector2(-80, 0)
		players[1]["pos"] = story_fusion_position + Vector2(80, 0)
		for p in players:
			(p["sprite"] as Sprite2D).visible = true
			(p["shield_sprite"] as Sprite2D).visible = false
			(p["sprite"] as Sprite2D).position = p["pos"]

	banner_label.text = "FUSION COMPLETE"
	if fusion_bar_back != null:
		fusion_bar_back.visible = false
		fusion_bar_fill.visible = false


func _update_fusion_pointer_visuals() -> void:
	# Draw a clean pointer line from the fixed-direction fusion ship to P1's aim reticle.
	if fusion_pointer_line != null:
		fusion_pointer_line.clear_points()
		fusion_pointer_line.add_point(story_fusion_position)
		fusion_pointer_line.add_point(story_fusion_pointer_pos)
		fusion_pointer_line.visible = story_fusion_active
	if fusion_pointer_reticle != null:
		fusion_pointer_reticle.position = story_fusion_pointer_pos
		fusion_pointer_reticle.rotation += 0.08
		fusion_pointer_reticle.visible = story_fusion_active


func _place_fusion_bomb() -> void:
	# Limit simultaneous bombs so the mode stays tactical instead of becoming spam.
	if bombs.size() >= story_bomb_max_count:
		return

	story_fusion_bomb_cd = story_bomb_cooldown
	var bomb_path := "res://assets/items/item_bomb.png"
	var sprite := AssetPaths.create_sprite(bomb_path, Vector2(82, 82), Color(1.0, 0.72, 0.18), 18)
	sprite.position = story_fusion_position
	add_child(sprite)

	bombs.append({
		"pos": story_fusion_position,
		"sprite": sprite,
		"radius": story_bomb_trigger_radius,
		"timer": story_bomb_fuse_time,
	})

	_spawn_effect(AssetPaths.EFFECTS["hit_spark"], story_fusion_position, Vector2(90, 90), 0.18)
	if audio_manager != null:
		audio_manager.play_sfx("item_power_boost", -8.0)


func _update_bombs(delta: float) -> void:
	for i in range(bombs.size() - 1, -1, -1):
		var bomb: Dictionary = bombs[i]
		var bomb_pos: Vector2 = bomb["pos"]
		var timer := float(bomb["timer"]) - delta
		bomb["timer"] = timer

		if is_instance_valid(bomb["sprite"]):
			var sprite := bomb["sprite"] as Sprite2D
			sprite.position = bomb_pos
			sprite.rotation += delta * 2.5
			var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.016)
			sprite.modulate = Color(1.0, pulse, 0.20, 1.0)

		var should_explode := timer <= 0.0
		if not should_explode:
			for e in enemies:
				var enemy_pos: Vector2 = e["pos"]
				if bomb_pos.distance_to(enemy_pos) < float(bomb["radius"]) + float(e["radius"]):
					should_explode = true
					break

		if should_explode:
			_explode_bomb(i)


func _explode_bomb(index: int) -> void:
	if index < 0 or index >= bombs.size():
		return

	var bomb: Dictionary = bombs[index]
	var bomb_pos: Vector2 = bomb["pos"]

	_spawn_effect(AssetPaths.EFFECTS["explosion_large"], bomb_pos, Vector2(story_bomb_explosion_radius * 2.0, story_bomb_explosion_radius * 2.0), 0.45)
	if audio_manager != null:
		audio_manager.play_sfx("explosion_large", -5.0)

	for e in enemies:
		var enemy_pos: Vector2 = e["pos"]
		if bomb_pos.distance_to(enemy_pos) <= story_bomb_explosion_radius + float(e["radius"]):
			var kind := String(e.get("kind", ""))
			# Step 5: weak enemies are destroyed by one bomb.
			# Strong enemies survive but take heavy area damage.
			if kind == "scout" or kind == "attacker":
				e["hp"] = 0
			else:
				e["hp"] = int(e["hp"]) - story_bomb_strong_damage

	if is_instance_valid(bomb["sprite"]):
		(bomb["sprite"] as Sprite2D).queue_free()
	bombs.remove_at(index)


func _story_twin_core_cannon() -> void:
	# Backward-compatible wrapper.
	# Older code used this as an instant screen-clear.
	# Step C changes it into a real cooperative fusion mode.
	_activate_story_fusion("CO-OP LINK 100%")

func _spawn_enemy() -> void:
	# Weighted pool — rare types (fortress_walker, tank, elite) appear ~6%
	var pool: Array[String] = [
		"scout", "scout", "scout",
		"attacker", "attacker", "attacker",
		"tank",
		"elite",
		"phantom_dart", "phantom_dart", "phantom_dart",
		"fortress_walker",
		"split_cell", "split_cell",
		"bomber_drone", "bomber_drone",
	]
	var key: String = pool[rng.randi_range(0, pool.size() - 1)]

	var hp_map     := {"scout":18,  "attacker":34,  "tank":70,   "elite":110,
	                   "phantom_dart":10, "fortress_walker":350, "split_cell":50, "bomber_drone":65}
	var speed_map  := {"scout":210.0,"attacker":150.0,"tank":90.0,"elite":125.0,
	                   "phantom_dart":380.0,"fortress_walker":45.0,"split_cell":100.0,"bomber_drone":75.0}
	var size_map   := {"scout":90.0, "attacker":90.0, "tank":90.0,"elite":90.0,
	                   "phantom_dart":60.0,"fortress_walker":130.0,"split_cell":100.0,"bomber_drone":110.0}
	var radius_map := {"scout":44.0, "attacker":44.0, "tank":44.0,"elite":44.0,
	                   "phantom_dart":28.0,"fortress_walker":65.0,"split_cell":50.0,"bomber_drone":55.0}

	var hp: int       = int(hp_map.get(key, 30))
	var speed: float  = float(speed_map.get(key, 150.0))
	var sz: float     = float(size_map.get(key, 90.0))
	var radius: float = float(radius_map.get(key, 44.0))

	var pos := Vector2(rng.randf_range(80.0, screen_size.x - 80.0), -80.0)
	var sprite := AssetPaths.create_sprite(AssetPaths.ENEMIES[key], Vector2(sz, sz), Color(0.9, 0.1, 0.2), 8)
	sprite.position = pos
	add_child(sprite)

	var data := {"pos": pos, "hp": hp, "speed": speed, "sprite": sprite, "radius": radius, "kind": key}
	if key == "bomber_drone":
		data["shoot_timer"] = rng.randf_range(1.0, 2.5)
		data["strafe_dir"]  = float(rng.randi_range(0, 1) * 2 - 1)
		data["strafe_timer"] = rng.randf_range(1.5, 3.0)
	enemies.append(data)


func _spawn_split_cell_frag(from_pos: Vector2) -> void:
	var offset := Vector2(rng.randf_range(-35.0, 35.0), rng.randf_range(-20.0, 20.0))
	var pos := from_pos + offset
	var sprite := AssetPaths.create_sprite(AssetPaths.ENEMIES["split_cell"], Vector2(55, 55), Color(0.2, 0.9, 0.2), 8)
	sprite.position = pos
	add_child(sprite)
	enemies.append({"pos": pos, "hp": 20, "speed": 160.0, "sprite": sprite,
	                "radius": 28.0, "kind": "split_cell_frag"})


func _fire_bomber_shot(from: Vector2, target: Vector2) -> void:
	var dir := (target - from).normalized()
	var b := _create_bullet(from, dir, 0, 6, AssetPaths.PROJECTILES["boss_orb"], 210.0, 30.0)
	enemy_bullets.append(b)


func _update_enemy_bullets(delta: float) -> void:
	var core_pos: Vector2 = base_sprite.position
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var b: Dictionary = enemy_bullets[i]
		var pos: Vector2 = b["pos"]
		var vel: Vector2 = b["vel"]
		pos += vel * delta
		b["pos"] = pos
		b["life"] = float(b["life"]) - delta
		(b["sprite"] as Sprite2D).position = pos
		if float(b["life"]) <= 0.0 or pos.x < -80 or pos.x > screen_size.x + 80 \
				or pos.y < -80 or pos.y > screen_size.y + 80:
			if is_instance_valid(b["sprite"]):
				(b["sprite"] as Sprite2D).queue_free()
			enemy_bullets.remove_at(i)
			continue
		# Hit core
		if pos.distance_to(core_pos) < 42.0 + float(b["radius"]):
			if core_shield_time > 0.0:
				core_shield_time = maxf(0.0, core_shield_time - 1.0)
				_spawn_effect(AssetPaths.EFFECTS["shield_bubble"], core_pos, Vector2(290, 290), 0.28)
				if audio_manager != null:
					audio_manager.play_sfx("shield_hit", -6.0)
			else:
				base_hp = max(0, base_hp - int(b["damage"]))
				if audio_manager != null:
					audio_manager.play_sfx("core_damage", -7.0)
			if is_instance_valid(b["sprite"]):
				(b["sprite"] as Sprite2D).queue_free()
			enemy_bullets.remove_at(i)

func _update_enemies(delta: float) -> void:
	var stunned := emp_stun_timer > 0.0
	for i in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[i]
		var target: Vector2 = base_sprite.position
		if mode != GameMode.STORY and players.size() > 0:
			target = players[i % players.size()]["pos"]
		var pos: Vector2 = e["pos"]
		var dir := (target - pos).normalized()
		var kind := String(e.get("kind", ""))

		# ── Bomber Drone: hover at range and fire ─────────────────────
		if kind == "bomber_drone":
			if not stunned:
				var dist := pos.distance_to(target)
				if dist > 300.0:
					pos += dir * float(e["speed"]) * delta
				else:
					var strafe_t: float = float(e.get("strafe_timer", 2.0)) - delta
					if strafe_t <= 0.0:
						e["strafe_dir"] = -float(e.get("strafe_dir", 1.0))
						strafe_t = rng.randf_range(1.5, 3.0)
					e["strafe_timer"] = strafe_t
					var perp := Vector2(-dir.y, dir.x) * float(e.get("strafe_dir", 1.0))
					pos += perp * float(e["speed"]) * 0.7 * delta
					pos.x = clampf(pos.x, 60.0, screen_size.x - 60.0)
				var shoot_t: float = float(e.get("shoot_timer", 2.5)) - delta
				if shoot_t <= 0.0 and mode == GameMode.STORY:
					_fire_bomber_shot(pos, target)
					shoot_t = 2.5
				e["shoot_timer"] = shoot_t
		elif not stunned:
			pos += dir * float(e["speed"]) * delta

		e["pos"] = pos
		(e["sprite"] as Sprite2D).position = pos

		if int(e["hp"]) <= 0:
			team_score += 20
			_spawn_effect(AssetPaths.EFFECTS["explosion_small"], pos, Vector2(120, 120), 0.35)
			if audio_manager != null:
				audio_manager.play_sfx("explosion_small", -7.0)
			if is_instance_valid(e["sprite"]):
				(e["sprite"] as Sprite2D).queue_free()
			enemies.remove_at(i)
			if mode == GameMode.STORY:
				_spawn_crystals_from_enemy(pos, kind)
				# Split Cell spawns 2 smaller fragments on death
				if kind == "split_cell":
					_spawn_split_cell_frag(pos)
					_spawn_split_cell_frag(pos)
		elif pos.y > screen_size.y + 100 or pos.distance_to(target) < 60.0:
			if mode == GameMode.STORY and core_shield_time > 0.0:
				core_shield_time = maxf(0.0, core_shield_time - 1.0)
				_spawn_effect(AssetPaths.EFFECTS["shield_bubble"], base_sprite.position, Vector2(290, 290), 0.28)
				if audio_manager != null:
					audio_manager.play_sfx("shield_hit", -6.0)
			else:
				base_hp = max(0, base_hp - 8)
				if audio_manager != null:
					audio_manager.play_sfx("core_damage", -7.0)
			if is_instance_valid(e["sprite"]):
				(e["sprite"] as Sprite2D).queue_free()
			enemies.remove_at(i)

func _spawn_item() -> void:
	# Weighted pool: heal×3, rapid_fire×2, shield×2, power_boost×2, link_charge×1 = 10 total
	var pool: Array[String] = [
		"heal", "heal", "heal",
		"rapid_fire", "rapid_fire",
		"shield", "shield",
		"power_boost", "power_boost",
		"link_charge",
	]
	var key: String = pool[rng.randi_range(0, pool.size() - 1)]
	var pos := Vector2(rng.randf_range(120.0, screen_size.x - 120.0), rng.randf_range(160.0, screen_size.y - 180.0))
	var sprite := AssetPaths.create_sprite(AssetPaths.ITEMS[key], Vector2(76, 76), Color(0.2, 1.0, 0.7), 12)
	sprite.position = pos
	add_child(sprite)
	items.append({"key": key, "pos": pos, "sprite": sprite, "radius": 42.0})

func _update_items(_delta: float) -> void:
	for i in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[i]
		var item_pos: Vector2 = item["pos"]
		for p in players:
			var player_pos: Vector2 = p["pos"]
			if item_pos.distance_to(player_pos) < float(item["radius"]) + float(p["radius"]):
				_apply_item(String(item["key"]), p)
				if is_instance_valid(item["sprite"]):
					(item["sprite"] as Sprite2D).queue_free()
				items.remove_at(i)
				return

func _apply_item(key: String, p: Dictionary) -> void:
	if audio_manager != null:
		audio_manager.play_sfx("item_pickup", -5.0)

	var player_id: int = int(p["id"])

	match key:
		"heal":
			base_hp = min(CORE_HP_MAX, base_hp + 20)
			if audio_manager != null:
				audio_manager.play_sfx("item_heal", -5.0)

		"rapid_fire":
			# Step B: Rapid Fire is personalized.
			# P1: ultra-fast precision fire.
			# P2: slower but powerful 3-shot burst.
			p["rapid"] = 7.0 if player_id == 1 else 6.0
			if audio_manager != null:
				audio_manager.play_sfx("item_rapid_fire", -5.0)

		"shield":
			# P2 is the defensive pilot, so Shield lasts longer when P2 collects it.
			core_shield_time = 10.0 if player_id == 2 else 7.0
			core_shield_max = core_shield_time
			_spawn_effect(AssetPaths.EFFECTS["shield_bubble"], base_sprite.position, Vector2(340, 340) if player_id == 2 else Vector2(300, 300), 0.55)
			if audio_manager != null:
				audio_manager.play_sfx("item_shield", -5.0)
				audio_manager.play_sfx("shield_activate", -5.0)
				audio_manager.start_shield_loop()

		"power_boost":
			# Step B: personalized Power Boost.
			# P1 becomes a piercing laser unit.
			# P2 fires huge heavy rounds.
			p["power"] = 8.0
			team_score += 50
			if audio_manager != null:
				audio_manager.play_sfx("item_power_boost", -5.0)

		"link_charge":
			# Step C: in Story Mode, Link Charge activates the fusion mech.
			# In Raid Mode, it still charges the raid Link Gauge.
			if mode == GameMode.STORY:
				_activate_story_fusion("LINK CHARGE ITEM")
			elif mode == GameMode.RAID:
				raid_link = clampf(raid_link + 20.0, 0.0, 100.0)
			else:
				if player_id == 1:
					p1_core = clampf(p1_core + 20.0, 0.0, 100.0)
				else:
					p2_core = clampf(p2_core + 20.0, 0.0, 100.0)

			if audio_manager != null:
				audio_manager.play_sfx("item_link_charge", -5.0)

func _handle_arena_abilities(delta: float) -> void:
	# Step 14:
	# Astral Court縺ｧ繧ゅ√が繝ｳ繝ｩ繧､繝ｳ譎ゅ・P1/P2縺ｮ蜈･蜉帙ｒInputRouter邨檎罰縺ｧ謇ｱ縺・∪縺吶・
	# 縺薙ｌ縺ｫ繧医ｊ縲∝挨PC縺九ｉ螻翫＞縺欖pace蜈･蜉帙〒繧６ltimate繧堤匱蜍輔〒縺阪∪縺吶・
	var p1_input := _get_player_input(1)
	var p2_input := _get_player_input(2)

	arena_time -= delta
	p1_shield = maxf(0.0, p1_shield - delta)
	p2_shield = maxf(0.0, p2_shield - delta)
	p1_dash_cd = maxf(0.0, p1_dash_cd - delta)
	p2_dash_cd = maxf(0.0, p2_dash_cd - delta)
	var p1_near := (players[0]["pos"] as Vector2).distance_to(astral_core_pos) < 180.0
	var p2_near := (players[1]["pos"] as Vector2).distance_to(astral_core_pos) < 180.0
	if p1_near: p1_core = clampf(p1_core + 16.0 * delta, 0.0, 100.0)
	if p2_near: p2_core = clampf(p2_core + 16.0 * delta, 0.0, 100.0)
	p1_ult_ready = p1_core >= 100.0
	p2_ult_ready = p2_core >= 100.0
	if Input.is_key_pressed(KEY_Q) and p1_dash_cd <= 0.0:
		_dash_player(0, Vector2.RIGHT)
		p1_dash_cd = 2.4
		if audio_manager != null:
			audio_manager.play_sfx("dash", -6.0)
	if Input.is_key_pressed(KEY_O) and p2_dash_cd <= 0.0:
		_dash_player(1, Vector2.LEFT)
		p2_dash_cd = 2.4
		if audio_manager != null:
			audio_manager.play_sfx("dash", -6.0)
	if Input.is_key_pressed(KEY_E): p1_shield = maxf(p1_shield, 0.8)
	if Input.is_key_pressed(KEY_P): p2_shield = maxf(p2_shield, 0.8)
	var p1_ultimate_trigger := Input.is_key_pressed(KEY_G) or (online_input_mode and p1_input.shoot)
	if p1_ultimate_trigger and p1_ult_ready:
		arena_p2_hp = max(0, arena_p2_hp - 30)
		p1_core = 0.0
		_spawn_effect(AssetPaths.EFFECTS["energy_tornado"], (players[1]["pos"] as Vector2), Vector2(190, 190), 0.55)
		if audio_manager != null:
			audio_manager.play_sfx("blue_nova", -5.0)
	var p2_ultimate_trigger := Input.is_key_pressed(KEY_K) or (online_input_mode and p2_input.shoot)
	if p2_ultimate_trigger and p2_ult_ready:
		arena_p1_hp = max(0, arena_p1_hp - 30)
		p2_core = 0.0
		_spawn_effect(AssetPaths.EFFECTS["energy_tornado"], (players[0]["pos"] as Vector2), Vector2(190, 190), 0.55)
		if audio_manager != null:
			audio_manager.play_sfx("golden_lance", -5.0)
	if arena_time <= 0.0 or arena_p1_hp <= 0 or arena_p2_hp <= 0:
		_finish_arena()

func _dash_player(index: int, dir: Vector2) -> void:
	var p: Dictionary = players[index]
	var pos: Vector2 = p["pos"]
	pos += dir * 180.0
	p["pos"] = pos
	_spawn_effect(AssetPaths.EFFECTS["dash_trail"], pos, Vector2(160, 90), 0.25)

func _finish_arena() -> void:
	var title := "DRAW"
	if arena_p1_hp > arena_p2_hp:
		title = "P1 WINS"
	elif arena_p2_hp > arena_p1_hp:
		title = "P2 WINS"
	_game_over(title, "P1 HP: %d   P2 HP: %d\nP1 Score: %d   P2 Score: %d\nPress R to return to Home" % [arena_p1_hp, arena_p2_hp, p1_score, p2_score])

func _update_astral_court(_delta: float) -> void:
	pass

func _update_raid(delta: float) -> void:
	raid_boss_time += delta
	_update_raid_boss_motion()
	if raid_boss_hp <= 0:
		_finish_raid(true)
		return
	if raid_boss_hp < raid_boss_max_hp * 0.33:
		raid_phase = 3
	elif raid_boss_hp < raid_boss_max_hp * 0.66:
		raid_phase = 2
	else:
		raid_phase = 1
	raid_attack_timer -= delta
	raid_drone_timer -= delta
	raid_weak_timer -= delta
	if raid_weak_timer <= 0.0:
		raid_weak_index = (raid_weak_index + 1) % 3
		raid_weak_timer = 3.2
	if raid_attack_timer <= 0.0:
		_spawn_raid_barrage()
		raid_attack_timer = maxf(0.65, 2.2 - raid_phase * 0.32)
	if raid_drone_timer <= 0.0:
		_spawn_raid_drone()
		raid_drone_timer = maxf(2.0, 5.2 - raid_phase * 0.7)
	var dist := (players[0]["pos"] as Vector2).distance_to(players[1]["pos"] as Vector2)
	if dist < 350.0:
		raid_link = clampf(raid_link + 10.0 * delta, 0.0, 100.0)
	else:
		raid_link = clampf(raid_link - 4.0 * delta, 0.0, 100.0)
	# Step 14:
	# 繝ｬ繧､繝峨・Twin Core Cannon繧ゅが繝ｳ繝ｩ繧､繝ｳ蜈･蜉帙↓蟇ｾ蠢懊＠縺ｾ縺吶・
	# 繝ｭ繝ｼ繧ｫ繝ｫ縺ｧ縺ｯ蠕捺擂縺ｩ縺翫ｊG/K縲√が繝ｳ繝ｩ繧､繝ｳ縺ｧ縺ｯ蜷ПC縺ｮSpace蜈･蜉帙〒繧ら匱蜍輔＠縺ｾ縺吶・
	var raid_cannon_trigger := Input.is_key_pressed(KEY_G) or Input.is_key_pressed(KEY_K) or _is_any_online_action_pressed()
	if raid_link >= 100.0 and raid_cannon_trigger:
		if audio_manager != null:
			audio_manager.play_sfx("twin_core_cannon", -3.0)
		raid_boss_hp = max(0, raid_boss_hp - 120)
		raid_link = 0.0
		_spawn_effect(AssetPaths.EFFECTS["twin_core_cannon"], Vector2(screen_size.x * 0.5, screen_size.y * 0.5), Vector2(720, 260), 0.55)
		fusion_sprite.position = ((players[0]["pos"] as Vector2) + (players[1]["pos"] as Vector2)) * 0.5
		fusion_sprite.visible = true
		team_score += 150
	_update_enemies(delta)
	_update_raid_visuals()

func _update_raid_boss_motion() -> void:
	var amp_x := 190.0 + float(raid_phase) * 70.0
	var amp_y := 24.0 + float(raid_phase) * 22.0
	var speed := 0.72 + float(raid_phase) * 0.20
	var wobble := sin(raid_boss_time * 2.2) * (18.0 if raid_phase >= 3 else 0.0)
	boss_sprite.position = raid_boss_center + Vector2(sin(raid_boss_time * speed) * amp_x, cos(raid_boss_time * speed * 1.4) * amp_y + wobble)
	boss_sprite.rotation = sin(raid_boss_time * 1.15) * (0.05 + raid_phase * 0.015)

func _spawn_raid_barrage() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("shot_boss", -8.0)
	var path: String = AssetPaths.resolve_path(AssetPaths.PROJECTILES["boss_orb"], AssetPaths.PROJECTILES["boss_ord"])
	for i in range(3 + raid_phase):
		var offset := (float(i) - float(2 + raid_phase) * 0.5) * 80.0
		var start := boss_sprite.position + Vector2(offset, 80)
		var dir := Vector2(offset * 0.002, 1.0).normalized()
		bullets.append(_create_bullet(start, dir, 9, 8 + raid_phase * 2, path, 340.0 + raid_phase * 60.0, 42.0))

func _spawn_raid_drone() -> void:
	var pos := boss_sprite.position + Vector2(rng.randf_range(-300, 300), 120)
	var sprite := AssetPaths.create_sprite(AssetPaths.BOSSES["leviathan_drone"], Vector2(95, 95), Color(0.7, 0.0, 0.8), 8)
	sprite.position = pos
	add_child(sprite)
	enemies.append({"pos": pos, "hp": 45 + raid_phase * 20, "speed": 100.0 + raid_phase * 25.0, "sprite": sprite, "radius": 44.0, "kind": "leviathan_drone"})

func _raid_weak_pos(index: int) -> Vector2:
	return boss_sprite.position + raid_weak_offsets[index]

func _update_raid_visuals() -> void:
	boss_hp_fill.size = Vector2(660.0 * float(raid_boss_hp) / float(raid_boss_max_hp), 18)
	link_fill.scale.x = maxf(0.01, raid_link / 100.0)
	link_fill.visible = true
	for i in range(raid_weak_sprites.size()):
		raid_weak_sprites[i].visible = true
		raid_weak_sprites[i].position = _raid_weak_pos(i)
		raid_weak_sprites[i].modulate = Color(1, 1, 1, 1) if i == raid_weak_index else Color(0.35, 0.2, 0.45, 0.55)

func _finish_raid(victory: bool) -> void:
	if victory:
		_game_over("RAID CLEAR", "Eclipse Leviathan defeated.\nTeam Score: %d\nPress R to return to Home" % team_score)
	else:
		_game_over("RAID FAILED", "Team Hull collapsed.\nTeam Score: %d\nPress R to retry" % team_score)

func _spawn_effect(path: String, pos: Vector2, size: Vector2, duration: float) -> void:
	var sprite := AssetPaths.create_sprite(path, size, Color(1, 1, 1, 0.7), 50)
	sprite.position = pos
	add_child(sprite)
	effects.append({"sprite": sprite, "time": duration, "max_time": duration})

func _update_effects(delta: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		var e: Dictionary = effects[i]
		e["time"] = float(e["time"]) - delta
		if is_instance_valid(e["sprite"]):
			(e["sprite"] as Sprite2D).modulate.a = maxf(0.0, float(e["time"]) / float(e["max_time"]))
		if float(e["time"]) <= 0.0:
			if is_instance_valid(e["sprite"]):
				(e["sprite"] as Sprite2D).queue_free()
			effects.remove_at(i)

func _update_ui() -> void:
	var in_story := (mode == GameMode.STORY)
	if story_hud_container != null:
		story_hud_container.visible = in_story
	if shop_hud_container != null:
		shop_hud_container.visible = in_story

	match mode:
		GameMode.TITLE:
			hud_label.text = ""
			banner_label.text = ""
		GameMode.STORY:
			# Hide legacy text HUD
			hud_label.text = ""
			banner_label.text = ""
			# Update new compact bar
			_update_story_hud_bar()
		GameMode.ASTRAL_COURT:
			hud_label.text = "ASTRAL COURT\nTIME %.0f   P1 HP %d   P2 HP %d\nP1 CORE %.0f%%   P2 CORE %.0f%%" % [arena_time, arena_p1_hp, arena_p2_hp, p1_core, p2_core]
			banner_label.text = "CONTROL THE STELLAR CORE"
		GameMode.RAID:
			hud_label.text = "ECLIPSE LEVIATHAN\nTEAM HULL %d   SCORE %d\nBOSS HP %d / %d   LINK %.0f%%" % [base_hp, team_score, raid_boss_hp, raid_boss_max_hp, raid_link]
			banner_label.text = "TWIN CORE CANNON READY" if raid_link >= 100.0 else "BREAK THE GLOWING CORE"

	if fake_online_test_mode and mode != GameMode.TITLE:
		var remote_player_id := 2 if online_local_player_id == 1 else 1
		hud_label.text += "\nFAKE ONLINE: LOCAL P%d / REMOTE P%d" % [online_local_player_id, remote_player_id]

	var network_text := _get_network_debug_text()
	if network_text != "":
		if mode == GameMode.TITLE:
			hud_label.text = network_text
		else:
			hud_label.text += "\n" + network_text


func _update_story_hud_bar() -> void:
	if story_hud_container == null:
		return
	var fusion := story_fusion_active

	# ── Core HP bar ──────────────────────────────────────────────────
	var hp_ratio := clampf(float(base_hp) / float(CORE_HP_MAX), 0.0, 1.0)
	story_core_bar_fill.size.x = 130.0 * hp_ratio
	story_core_label.text = "%d/%d" % [base_hp, CORE_HP_MAX]
	var r := 1.0 - hp_ratio * 0.55
	var g := hp_ratio * 0.80
	story_core_bar_fill.color = Color(r, g, 0.12)

	# ── Shield bar ───────────────────────────────────────────────────
	if core_shield_time > 0.0:
		var shd_ratio := clampf(core_shield_time / maxf(core_shield_max, 1.0), 0.0, 1.0)
		story_shield_bar_fill.size.x = 110.0 * shd_ratio
		story_shield_bar_bg.visible  = true
		story_shield_bar_fill.visible = true
		story_shield_label.visible   = false
	else:
		story_shield_bar_bg.visible   = false
		story_shield_bar_fill.visible = false
		story_shield_label.visible    = true
		story_shield_label.text       = "--"

	# ── Score ────────────────────────────────────────────────────────
	story_score_label.text = "%d" % team_score

	# ── CO-OP LINK / FUSION TIME (right side) ────────────────────────
	# Container visible when link is building or fusion is active
	var link_active := coop_link > 0.0 or fusion
	story_link_container.visible = link_active

	if link_active:
		if fusion:
			# Timer bar replaces link gauge — shrinks as fusion counts down
			var fuse_ratio := clampf(story_fusion_timer / maxf(story_fusion_duration, 1.0), 0.0, 1.0)
			story_link_header_label.text = "FUSION TIME"
			story_link_header_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
			story_link_bar_bg.color      = Color(0.10, 0.06, 0.02)
			story_link_bar_fill.size.x   = 130.0 * fuse_ratio
			story_link_bar_fill.color    = Color(1.0, 0.75, 0.10)
			story_link_label.text        = "💣%d/%d  %.0fs" % [bombs.size(), story_bomb_max_count, story_fusion_timer]
			story_link_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45))
			story_link_label.visible     = true
			story_fusion_label.visible   = false
			story_mode_label.text        = "FUSION MODE"
			story_mode_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
		else:
			# Link gauge — grows toward 100%
			var lk := clampf(coop_link / 100.0, 0.0, 1.0)
			story_link_header_label.text = "CO-OP LINK"
			story_link_header_label.add_theme_color_override("font_color", Color(0.45, 0.60, 0.80))
			story_link_bar_bg.color      = Color(0.04, 0.10, 0.10)
			story_link_bar_fill.size.x   = 130.0 * lk
			if coop_link >= 100.0:
				story_link_bar_fill.color = Color(1.0, 0.95, 0.20)
				story_link_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.20))
			else:
				story_link_bar_fill.color = Color(0.20, 1.0, 0.65)
				story_link_label.add_theme_color_override("font_color", Color(0.20, 1.0, 0.65))
			story_link_label.text        = "%.0f%%" % coop_link
			story_link_label.visible     = true
			story_fusion_label.visible   = false
			story_mode_label.text        = "CO-OP DEFENSE"
			story_mode_label.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0))


func _print_network_input_debug() -> void:
	var local_state := PlayerInputState.new()
	if input_router != null:
		local_state = input_router.get_player_input(online_local_player_id)

	var remote_player_id := 2 if online_local_player_id == 1 else 1
	var remote_state := PlayerInputState.new()
	if network_input_provider != null:
		remote_state = network_input_provider.get_remote_input(remote_player_id)

	print("[Network/Input] local=P%d move=%s shoot=%s bomb=%s" % [
		online_local_player_id,
		str(local_state.move),
		str(local_state.shoot),
		str(local_state.bomb)
	])
	print("[Network/Input] remote=P%d move=%s shoot=%s bomb=%s" % [
		remote_player_id,
		str(remote_state.move),
		str(remote_state.shoot),
		str(remote_state.bomb)
	])
	print("[Network/Input] sent=%d received=%d" % [network_input_send_count, network_input_receive_count])


func _get_network_debug_text() -> String:
	if network_client == null:
		return ""

	var room_text := network_join_room_code if network_join_room_code != "" else "-"
	var local_text := "P%d" % online_local_player_id if online_input_mode else "-"
	var entry_text := ""
	if network_room_entry_mode:
		entry_text = "  INPUT[" + network_join_room_code + "]"

	var msg_text := ""
	if network_last_message != "":
		msg_text = "  " + network_last_message

	var relay_text := "  I/O %d/%d" % [network_input_send_count, network_input_receive_count]
	var remote_text := ""
	if network_last_remote_input_text != "":
		remote_text = "  REM " + network_last_remote_input_text

	return "NET %s  ROOM %s  LOCAL %s%s%s%s%s" % [
		network_last_status,
		room_text,
		local_text,
		entry_text,
		msg_text,
		relay_text,
		remote_text
	]


func _game_over(title: String, message: String = "") -> void:
	game_over = true
	if audio_manager != null:
		audio_manager.stop_shield_loop()
		if title.find("CLEAR") >= 0 or title.find("WINS") >= 0:
			audio_manager.play_bgm("victory")
			audio_manager.play_sfx("victory", -4.0)
		else:
			audio_manager.stop_bgm()
			audio_manager.play_sfx("game_over", -4.0)
	result_title = title
	result_message = message if message != "" else "Team Score: %d\nP1 Score: %d   P2 Score: %d\nPress R to return to Home" % [team_score, p1_score, p2_score]
	banner_label.text = ""
	game_over_layer.visible = true
	game_over_title.text = result_title
	game_over_detail.text = result_message
