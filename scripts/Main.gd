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
const CORE_HP_MAX            := 1000   # コアの最大体力（Story Mode）
const GATE_HP_MAX_S1         := 1000   # ステージ1 敵ゲートの最大体力
const GATE_HP_MAX_S2         :=  800   # ステージ2 敵ゲートの最大体力（×2基）
const GATE_HP_MAX_S3         :=  600   # ステージ3 敵ゲートの最大体力（×3基）
const GATE_HP_MAX_S4         := 3000   # ステージ4 ボスゲートの最大体力
const GATE_BOSS_SHOOT_INTERVAL := 2.5  # ボスゲートの射撃間隔（秒）

# ── シングルモード 機種ステータス ──────────────────────────────────────────────
# キャラクター選択画面のバー表示値。0.0〜1.0（1.0 = そのカテゴリ最高値）
# 左から順に [SPEED, POWER, FIRE RATE] の相対値。
#                               SPEED  POWER  FIRE RATE
const SHIP_STATS_AZURE_WING    := [0.79, 0.47, 0.82]  # Azure Wing    バランス型
const SHIP_STATS_SOLAR_FANG    := [0.54, 0.82, 0.55]  # Solar Fang    重火力型
const SHIP_STATS_EMERALD_CLAW  := [1.00, 0.35, 1.00]  # Emerald Claw  高速型
const SHIP_STATS_VIOLET_PHANTOM := [0.67, 1.00, 0.40] # Violet Phantom 超火力型
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

# Settings panel
var settings_layer: CanvasLayer
var _settings_open: bool = false
var _settings_was_paused: bool = false
var _settings_bgm_slider: HSlider
var _settings_sfx_slider: HSlider
var _settings_fs_btn: Button
var _settings_bgm_val_lbl: Label
var _settings_sfx_val_lbl: Label

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
var debug_show_hitboxes: bool = false
# Carry-over data between stages (crystals, lives, active item timers).
# Populated in _on_result_next_stage_pressed(), consumed in _start_story().
var _stage_carry: Dictionary = {}
var _dbg_node: Node2D
var _entity_id_counter: int = 0

const PLAYER_LIVES_MAX := 5
const PLAYER_INV_DURATION := 1.5
var player_lives: Array[int] = [5, 5, 5, 5]
var player_inv_timer: Array[float] = [0.0, 0.0, 0.0, 0.0]
var player_count: int = 2  # 1=single, 2=co-op double, 4=co-op quad

const STORY_INTRO_DURATION := 1.8
const STORY_CORE_FADE_DURATION := 0.55
var story_intro_active := false
var story_intro_timer := 0.0
var story_core_fade_timer := 0.0

# Solo / co-op mode selection
var solo_mode: bool = false
var rhythm_bpm := 120.0          # beats per minute (solo mode)
var rhythm_beat_timer := 0.0     # seconds until next beat
var rhythm_beat_count := 0       # total beats elapsed this run
var rhythm_flash_timer := 0.0    # gate visual flash after beat
var player_ship_map: Array = [1, 2, 3, 4]   # ship_id per player slot
var player_name_map: Array = ["PLAYER 1", "PLAYER 2", "PLAYER 3", "PLAYER 4"]
var player_cpu_map: Array = [false, false, false, false]  # true = CPU AI per slot

# ── CPU Utility AI ────────────────────────────────────────────────────────────
var cpu_difficulty: int = 1  # 0=Easy  1=Normal  2=Hard  3=Expert
var cpu_state: Array = ["ATTACK", "ATTACK", "ATTACK", "ATTACK"]

# Story mode select screen
var story_mode_select_layer: CanvasLayer

# Character select screen
var char_select_layer: CanvasLayer
var char_select_mode: String = ""
var _cs_configs: Array = [
	{"name": "PLAYER 1", "ship_id": 1, "ready": false, "joined": true},
	{"name": "PLAYER 2", "ship_id": 2, "ready": false, "joined": false},
	{"name": "PLAYER 3", "ship_id": 3, "ready": false, "joined": false},
	{"name": "PLAYER 4", "ship_id": 4, "ready": false, "joined": false},
]
var _cs_panels: Array = []
var _cs_ship_btns: Array = []      # kept for size parity (unused)
var _cs_ship_imgs: Array = []
var _cs_name_edits: Array = []
var _cs_status_lbls: Array = []
var _cs_ready_btns: Array = []
var _cs_active_btns: Array = []    # enable-toggle Button per slot
var _cs_ship_opts: Array = []      # OptionButton dropdown per slot
var _cs_ctrl_btns: Array = []      # [[PLAYER_btn, CPU_btn]] per slot
var _cs_diff_btns: Array = []      # [EASY, NORMAL, HARD, EXPERT] buttons
var _cs_start_btn: Button
var _cs_room_area: Control
var _cs_room_lbl: Label
var _cs_join_edit: LineEdit
# Solo mode carousel
var _solo_carousel: Control = null
var _solo_cs_idx: int = 0
var _solo_preview_img: TextureRect = null
var _solo_name_lbl: Label = null
var _solo_desc_lbl: Label = null
var _solo_dots: Array = []
var _solo_stat_bars: Array = []
var _solo_drag_start_x: float = -1.0

var enemy_spawn_timer := 1.2
var item_spawn_timer := 5.0
var shoot_cd_p1 := 0.0
var shoot_cd_p2 := 0.0
var shoot_cd_p3 := 0.0
var shoot_cd_p4 := 0.0

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
		"power_mode": "giant_bullet"
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
	},
	3: {
		"name": "Emerald Claw",
		"speed": 480.0,
		"shot_speed": 1100.0,
		"shoot_interval": 0.18,
		"rapid_interval": 0.09,
		"damage": 12,
		"bullet_size": 32.0,
		"power_mode": "giant_bullet"
	},
	4: {
		"name": "Violet Phantom",
		"speed": 320.0,
		"shot_speed": 780.0,
		"shoot_interval": 0.55,
		"rapid_interval": 0.28,
		"damage": 34,
		"bullet_size": 52.0,
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
var gate_hit_sound_cd := 0.0   # throttle so gate-hit SFX doesn't spam
var gate_boss_shoot_timer := 0.0  # ボスゲート射撃タイマー（Stage 4）

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
var _base_sprite_natural_scale := Vector2.ONE
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
var result_next_stage_button: Button
var result_stage_button: Button
var stage_select_layer: CanvasLayer
var banner_label: Label
var link_back: ColorRect
var link_fill: Sprite2D
var boss_hp_back: Sprite2D
var boss_hp_fill: ColorRect

# Stage 1 gate
var gate_sprite: Sprite2D = null
var gate_hp := 0
var gate_pos := Vector2.ZERO
var gate_open := false
var gate_open_timer := 0.0
var gate_destroyed := false
var gate_clear_timer := 0.0
const GATE_OPEN_DELAY := 1.5
const GATE_CLEAR_DELAY := 3.0

# Stage 2 second gate
var story_stage_number := 1
var gate2_sprite: Sprite2D = null
var gate2_hp := 0
var gate2_pos := Vector2.ZERO
var gate2_open := false
var gate2_open_timer := 0.0
var gate2_destroyed := false

# Stage 3 third gate
var gate3_sprite: Sprite2D = null
var gate3_hp := 0
var gate3_pos := Vector2.ZERO
var gate3_open := false
var gate3_open_timer := 0.0
var gate3_destroyed := false

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
var story_p1_life_segs: Array = []
var story_p1_life_hi: Array = []
var story_p2_life_segs: Array = []
var story_p2_life_hi: Array = []
var story_p2_hud_header: Label
var story_p3_life_segs: Array = []
var story_p3_life_hi: Array = []
var story_p4_life_segs: Array = []
var story_p4_life_hi: Array = []
var story_p3_hud_header: Label
var story_p4_hud_header: Label
var story_p34_strip: ColorRect
var story_gate_bar_bg: ColorRect
var story_gate_bar_fill: ColorRect
var story_gate_label: Label
var story_gate_header_label: Label
var story_gate2_bar_bg: ColorRect
var story_gate2_bar_fill: ColorRect
var story_gate2_label: Label
var story_gate3_bar_bg: ColorRect
var story_gate3_bar_fill: ColorRect
var story_gate3_label: Label
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

			# Solo carousel keyboard navigation
			if char_select_layer != null and char_select_layer.visible and char_select_mode == "single":
				if key_event.keycode == KEY_LEFT:
					_solo_cs_navigate(-1)
					get_viewport().set_input_as_handled()
					return
				elif key_event.keycode == KEY_RIGHT:
					_solo_cs_navigate(1)
					get_viewport().set_input_as_handled()
					return
				elif key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
					_on_cs_start_game()
					get_viewport().set_input_as_handled()
					return

			if key_event.keycode == KEY_TAB:
				if mode == GameMode.STORY and not game_over:
					if shop_active:
						_close_shop()
						_send_game_event({"event": "ui_action", "action": "shop_close"})
					else:
						_open_shop()
						_send_game_event({"event": "ui_action", "action": "shop_open"})
					get_viewport().set_input_as_handled()
				return

			if shop_active:
				if key_event.keycode == KEY_ESCAPE:
					_close_shop()
					_send_game_event({"event": "ui_action", "action": "shop_close"})
					get_viewport().set_input_as_handled()
				return

			if key_event.keycode == KEY_F4:
				if _settings_open: _close_settings()
				else: _open_settings()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_F2:
				debug_show_hitboxes = !debug_show_hitboxes
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_F6:
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
				_on_settings_fullscreen_toggled()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_F12:
				_network_join_room()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_ESCAPE:
				if mode != GameMode.TITLE and not game_over:
					if paused:
						_resume_game()
						_send_game_event({"event": "ui_action", "action": "resume"})
					else:
						_pause_game()
						_send_game_event({"event": "ui_action", "action": "pause"})
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
	_setup_debug_overlay()
	_show_title()

func _process(delta: float) -> void:
	_update_fake_online_test(delta)
	_update_network_input_sending(delta)
	_update_online_status_hud()

	_update_ui()
	if _dbg_node != null:
		_dbg_node.queue_redraw()

	if game_over:
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		_update_effects(delta)
		return

	if mode == GameMode.TITLE:
		_handle_title_input()
		return

	if paused or shop_active:
		return

	shoot_cd_p1 = maxf(0.0, shoot_cd_p1 - delta)
	shoot_cd_p2 = maxf(0.0, shoot_cd_p2 - delta)
	shoot_cd_p3 = maxf(0.0, shoot_cd_p3 - delta)
	shoot_cd_p4 = maxf(0.0, shoot_cd_p4 - delta)

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
	if network_client.has_signal("game_event_received"):
		network_client.game_event_received.connect(_on_network_game_event)


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


func _is_game_host() -> bool:
	return not online_game_active or online_local_player_id == 1


func _next_entity_id() -> int:
	_entity_id_counter += 1
	return _entity_id_counter


func _send_game_event(event_data: Dictionary) -> void:
	if online_game_active and network_client != null:
		network_client.send_game_event(event_data)


func _on_network_game_event(ev: Dictionary) -> void:
	var event := str(ev.get("event", ""))
	match event:
		"enemy_spawn":
			_recv_enemy_spawn(ev)
		"enemy_died":
			_recv_entity_remove(enemies, int(ev.get("id", -1)))
		"item_spawn":
			_recv_item_spawn(ev)
		"ui_action":
			_recv_ui_action(str(ev.get("action", "")))
		"char_select":
			_recv_char_select(ev)
		"cs_start":
			_recv_cs_start(ev)


func _recv_entity_remove(arr: Array, id: int) -> void:
	for i in range(arr.size() - 1, -1, -1):
		if int(arr[i].get("id", -2)) == id:
			if is_instance_valid(arr[i]["sprite"]):
				(arr[i]["sprite"] as Sprite2D).queue_free()
			arr.remove_at(i)
			return


func _recv_enemy_spawn(ev: Dictionary) -> void:
	if mode != GameMode.STORY:
		return
	var id   := int(ev.get("id", -1))
	var key  := str(ev.get("kind", "scout"))
	var pos  := Vector2(float(ev.get("x", 0.0)), float(ev.get("y", -80.0)))
	var hp   := int(ev.get("hp", 30))
	var spd  := float(ev.get("speed", 150.0))
	var rad  := float(ev.get("radius", 44.0))
	var sz_map := {
		"scout":90.0, "attacker":90.0, "tank":90.0, "elite":90.0,
		"phantom_dart":60.0, "fortress_walker":130.0,
		"split_cell":100.0, "split_cell_frag":55.0, "bomber_drone":110.0
	}
	var asset_key := "split_cell" if key == "split_cell_frag" else key
	var sz := float(sz_map.get(key, 90.0))
	var sprite := AssetPaths.create_sprite(AssetPaths.ENEMIES[asset_key], Vector2(sz, sz), Color(0.9, 0.1, 0.2), 8)
	sprite.position = pos
	add_child(sprite)
	var data := {"id": id, "pos": pos, "hp": hp, "speed": spd, "sprite": sprite, "radius": rad, "kind": key}
	if key == "bomber_drone":
		data["shoot_timer"] = float(ev.get("shoot_timer", 2.0))
		data["strafe_dir"]  = float(ev.get("strafe_dir", 1.0))
		data["strafe_timer"] = float(ev.get("strafe_timer", 2.0))
	enemies.append(data)


func _recv_item_spawn(ev: Dictionary) -> void:
	if mode != GameMode.STORY:
		return
	var id  := int(ev.get("id", -1))
	var key := str(ev.get("key", "heal"))
	var pos := Vector2(float(ev.get("x", 0.0)), float(ev.get("y", 0.0)))
	var sprite := AssetPaths.create_sprite(AssetPaths.ITEMS[key], Vector2(76, 76), Color(0.2, 1.0, 0.7), 12)
	sprite.position = pos
	add_child(sprite)
	items.append({"id": id, "key": key, "pos": pos, "sprite": sprite, "radius": 42.0})


func _recv_ui_action(action: String) -> void:
	match action:
		"shop_open":
			if not shop_active:
				_open_shop()
		"shop_close":
			if shop_active:
				_close_shop()
		"pause":
			if not paused:
				_pause_game()
		"resume":
			if paused:
				_resume_game()



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
	print("[Network] This client is P%d" % player_id)
	network_last_message = "This client is P%d" % player_id
	set_online_input_mode(true, player_id)
	if char_select_layer != null and char_select_layer.visible:
		return
	if online_lobby != null:
		online_lobby.set_local_player(player_id)
		online_lobby.set_status_message("This client is P%d" % player_id)


func _on_network_room_changed(new_room_id: String) -> void:
	network_join_room_code = new_room_id
	network_last_message = "Room: " + new_room_id
	print("[Network] Room: " + new_room_id)
	if char_select_layer != null and char_select_layer.visible:
		if _cs_room_lbl != null:
			_cs_room_lbl.text = "ROOM: " + new_room_id
		return
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
	if char_select_layer != null and char_select_layer.visible:
		_cs_on_room_state(room_state)
		return
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

	base_sprite = AssetPaths.create_sprite(AssetPaths.STAGES["base_core"], Vector2(260, 260), Color(0.2, 0.9, 1.0), 0)
	base_sprite.position = Vector2(screen_size.x * 0.5, screen_size.y - 200)
	_base_sprite_natural_scale = base_sprite.scale
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

	# Show all 4 ships on title screen; player_count is reset before each game
	player_count = 4
	_create_players()
	player_count = 2  # restore default

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

	# CORE PULSE logo (replaces old text title)
	var logo_sprite := AssetPaths.create_sprite(AssetPaths.UI["logo"], Vector2(860, 380), Color.WHITE, 1)
	logo_sprite.position = Vector2(screen_size.x * 0.5, 270)
	title_layer.add_child(logo_sprite)

	# title_label kept for compatibility but not shown
	title_label = Label.new()
	title_label.visible = false
	title_layer.add_child(title_label)

	title_options_label = Label.new()
	title_options_label.text = "Keyboard: 1 Story  |  2 Astral Court  |  3 Eclipse Raid"
	title_options_label.position = Vector2(0, 502)
	title_options_label.size = Vector2(screen_size.x, 48)
	title_options_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_options_label.add_theme_font_size_override("font_size", 24)
	title_options_label.add_theme_color_override("font_color", Color(0.60, 0.75, 0.90))
	title_layer.add_child(title_options_label)

	_setup_title_buttons()
	_setup_instruction_screen()
	_setup_online_lobby_ui()
	_setup_online_status_hud()
	_setup_story_mode_select()
	_setup_char_select()
	_setup_stage_select()

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
	_setup_settings_button()

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
		hud_crystal_label.text = "%d" % crystals

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
	var crystal_hdr_icon := AssetPaths.create_sprite(AssetPaths.ITEMS["crystal"], Vector2(32, 32), Color(0.4, 1.0, 0.9))
	crystal_hdr_icon.position = Vector2(screen_size.x - 336, 34)
	shop_layer.add_child(crystal_hdr_icon)
	var clbl := Label.new()
	clbl.text = "%d" % crystals
	clbl.position = Vector2(screen_size.x - 300, 20)
	clbl.size = Vector2(126, 48)
	clbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	hint.text = "Tab / ESC  to return to game"
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
	status_lbl.text = "Equipped —  P1: %s   P2: %s" % [
		p1_weapon if p1_weapon != "" else "None",
		p2_weapon if p2_weapon != "" else "None"
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
	status_lbl.text = "Turrets: %d / %d  (auto-placed around core on purchase)" % [turrets.size(), max_turrets]
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

	# 価格（クリスタルアイコン＋数値）
	var price_col := Color(0.3, 1.0, 0.65) if can_buy else Color(0.35, 0.38, 0.42)
	var price_icon := AssetPaths.create_sprite(AssetPaths.ITEMS["crystal"], Vector2(24, 24), price_col)
	price_icon.position = Vector2(cx + card_w * 0.5 - 32.0, cy + card_h - 91.0)
	shop_layer.add_child(price_icon)
	var price_lbl := Label.new()
	price_lbl.text = "%d" % int(info["price"])
	price_lbl.position = Vector2(cx + card_w * 0.5 - 4.0, cy + card_h - 102)
	price_lbl.size = Vector2(60, 36)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	price_lbl.add_theme_font_size_override("font_size", 28)
	price_lbl.add_theme_color_override("font_color", price_col)
	shop_layer.add_child(price_lbl)

	# 購入可否テキスト
	if not can_buy:
		var need := int(info["price"]) - crystals
		var lack_icon := AssetPaths.create_sprite(AssetPaths.ITEMS["crystal"], Vector2(16, 16), Color(0.6, 0.3, 0.3))
		lack_icon.position = Vector2(cx + card_w * 0.5 - 54.0, cy + card_h - 57.0)
		shop_layer.add_child(lack_icon)
		var lack_lbl := Label.new()
		lack_lbl.text = "Need %d more" % need
		lack_lbl.position = Vector2(cx + card_w * 0.5 - 34.0, cy + card_h - 66)
		lack_lbl.size = Vector2(120, 28)
		lack_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lack_lbl.add_theme_font_size_override("font_size", 16)
		lack_lbl.add_theme_color_override("font_color", Color(0.6, 0.3, 0.3))
		shop_layer.add_child(lack_lbl)

	# BUYボタン
	if can_buy:
		var btn := Button.new()
		btn.text = "BUY"
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
			"short": "Restore Core HP by +40",
			"detail": "Restores Core HP by +40.\n\nUse when HP is critical to\nsignificantly improve survival.\n\nCannot exceed the\nmaximum Core HP.",
		},
		"mega_bomb": {
			"name": "MEGA BOMB", "price": 35,
			"short": "Wipe all enemies on screen",
			"detail": "Instantly destroys all enemies\non the field when purchased,\nsetting their HP to 0.\n\nA powerful last resort.\nDrops a large amount of crystals.",
		},
		"crystal_magnet": {
			"name": "CRYSTAL MAGNET", "price": 15,
			"short": "Triple crystal pickup range",
			"detail": "For 60 seconds, crystal auto-pickup\nrange expands from 120px to 360px.\n\nAutomatically collects distant\ncrystals — ideal for\nearly-game resource farming.",
		},
		"overclock": {
			"name": "OVERCLOCK", "price": 30,
			"short": "Fire rate x1.5 for 30 seconds",
			"detail": "Boosts fire rate of both\nP1 and P2 by 1.5x for 30 seconds.\n\nCombine with the Rapid Fire item\nfor even higher fire rates.",
		},
		"emp_burst": {
			"name": "EMP BURST", "price": 25,
			"short": "Stun all enemies for 5 seconds",
			"detail": "When purchased, completely\nstops all enemies on the field\nfor 5 seconds.\n\nUseful to stop core rushes\nor to build up the fusion gauge.",
		},
		"side_cannon": {
			"name": "SIDE CANNON", "price": 25,
			"short": "Fire extra shots left and right",
			"detail": "In addition to normal shots,\nfires 1 bullet each to the\nleft and right diagonals.\n\nAutomatically handles\nenemies approaching from the sides.\n\nEquip slot: 1 per ship",
		},
		"spread_shot": {
			"name": "SPREAD SHOT", "price": 30,
			"short": "Fire 2 extra shots at +/-25 deg",
			"detail": "In addition to normal shots,\nfires 1 bullet each spread\n25 degrees left and right.\n\nCovers a wide area and is\nespecially effective against\nmultiple lined-up enemies.\n\nEquip slot: 1 per ship",
		},
		"homing_missile": {
			"name": "HOMING MISSILE", "price": 45,
			"short": "Fire homing missiles every 2.5s",
			"detail": "Every 2.5 seconds, automatically\nfires a homing missile that\ntracks the nearest enemy.\n\nFully automatic — no input needed.\nEspecially effective against\ntough enemies like Tank and Elite.\n\nEquip slot: 1 per ship",
		},
		"twin_laser": {
			"name": "TWIN LASER", "price": 60,
			"short": "2 parallel extra laser shots",
			"detail": "In addition to normal shots,\nfires parallel laser bullets\nfrom the left and right of the ship.\n\nDamage equals normal shots,\ngreatly increasing effective\nfirepower against frontal enemies.\n\nEquip slot: 1 per ship",
		},
		"auto_cannon": {
			"name": "AUTO CANNON", "price": 40,
			"short": "Shoot nearest enemy every 1.2s",
			"detail": "Deploys a turret around the core.\n\nEvery 1.2 seconds, automatically\nfires at the nearest enemy\non the field.\n\nAlways active, no input needed —\nthe most well-balanced turret.\n\nMax deployed: 3",
		},
		"laser_tower": {
			"name": "LASER TOWER", "price": 55,
			"short": "Continuous laser instant damage",
			"detail": "Deploys a laser turret around the core.\n\nDeals continuous damage to the\nnearest enemy every 0.08 seconds.\nVery short interval — won't let\neven fast enemies escape.\n\nBest for eliminating fast enemies\nlike Scouts and Attackers.\n\nMax deployed: 3",
		},
		"missile_pod": {
			"name": "MISSILE POD", "price": 70,
			"short": "3 homing missiles every 3.5s",
			"detail": "Deploys a missile pod around the core.\n\nEvery 3.5 seconds, simultaneously\nlaunches homing missiles at\n3 nearby enemies.\n\nNear area-attack effectiveness —\nshines when multiple Tanks\nor Elites approach at once.\n\nMax deployed: 3",
		},
		"shield_wall": {
			"name": "SHIELD WALL", "price": 35,
			"short": "Repel nearby enemies every 8s",
			"detail": "Deploys a barrier unit around the core.\n\nEvery 8 seconds, automatically\nknocks back enemies within 200px.\n\nDeals no damage but resets\nenemy rushes — a defensive turret.\nCombines well with Core Repair.\n\nMax deployed: 3",
		},
	}

# ── Settings button & panel ──────────────────────────────────────────────────

func _setup_settings_button() -> void:
	# ── Gear button layer (always on top, always visible) ─────────────────
	var btn_layer := CanvasLayer.new()
	btn_layer.layer = 22
	btn_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(btn_layer)

	var btn_bg := ColorRect.new()
	btn_bg.position = Vector2(screen_size.x - 54.0, screen_size.y - 54.0)
	btn_bg.size = Vector2(46.0, 46.0)
	btn_bg.color = Color(0.05, 0.08, 0.20, 0.88)
	btn_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_layer.add_child(btn_bg)

	var gear_lbl := Label.new()
	gear_lbl.text = "⚙"
	gear_lbl.position = Vector2(screen_size.x - 54.0, screen_size.y - 57.0)
	gear_lbl.size = Vector2(46.0, 46.0)
	gear_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gear_lbl.add_theme_font_size_override("font_size", 26)
	gear_lbl.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0))
	btn_layer.add_child(gear_lbl)

	var open_btn := Button.new()
	open_btn.position = Vector2(screen_size.x - 56.0, screen_size.y - 56.0)
	open_btn.size = Vector2(50.0, 50.0)
	open_btn.flat = true
	open_btn.modulate = Color(1.0, 1.0, 1.0, 0.0)
	open_btn.pressed.connect(_open_settings)
	btn_layer.add_child(open_btn)

	# ── Settings panel layer (above pause at 40) ──────────────────────────
	settings_layer = CanvasLayer.new()
	settings_layer.layer = 45
	settings_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	settings_layer.visible = false
	add_child(settings_layer)

	# Full-screen dim overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.70)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_layer.add_child(overlay)

	var pw := 480.0; var ph := 460.0
	var px := (screen_size.x - pw) * 0.5
	var py := (screen_size.y - ph) * 0.5

	# Panel border (added first → renders behind panel)
	var border := ColorRect.new()
	border.position = Vector2(px - 1.0, py - 1.0)
	border.size = Vector2(pw + 2.0, ph + 2.0)
	border.color = Color(0.20, 0.45, 0.90, 0.55)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_layer.add_child(border)

	# Panel background (added after border → renders on top)
	var panel := ColorRect.new()
	panel.position = Vector2(px, py)
	panel.size = Vector2(pw, ph)
	panel.color = Color(0.04, 0.07, 0.16, 0.97)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_layer.add_child(panel)

	# Title
	var title_lbl := Label.new()
	title_lbl.text = "SETTINGS"
	title_lbl.position = Vector2(px, py + 14.0)
	title_lbl.size = Vector2(pw, 44.0)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	settings_layer.add_child(title_lbl)

	# Separator
	var sep := ColorRect.new()
	sep.position = Vector2(px + 28.0, py + 60.0)
	sep.size = Vector2(pw - 56.0, 1.0)
	sep.color = Color(0.2, 0.4, 0.7, 0.5)
	settings_layer.add_child(sep)

	var lbl_x  := px + 28.0
	var ctrl_x := px + 170.0
	var val_x  := px + pw - 58.0
	var ctrl_w := pw - 170.0 - 66.0  # slider width

	# ── BGM Volume row ────────────────────────────────────────────────────
	var ry1 := py + 82.0
	var bgm_lbl := Label.new()
	bgm_lbl.text = "BGM音量"
	bgm_lbl.position = Vector2(lbl_x, ry1 + 4.0)
	bgm_lbl.size = Vector2(140.0, 32.0)
	bgm_lbl.add_theme_font_size_override("font_size", 19)
	bgm_lbl.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	settings_layer.add_child(bgm_lbl)

	_settings_bgm_slider = _make_settings_slider(ctrl_x, ry1 + 2.0, ctrl_w, 100.0)
	settings_layer.add_child(_settings_bgm_slider)
	_settings_bgm_slider.value_changed.connect(_on_settings_bgm_changed)

	_settings_bgm_val_lbl = Label.new()
	_settings_bgm_val_lbl.text = "100%"
	_settings_bgm_val_lbl.position = Vector2(val_x, ry1 + 4.0)
	_settings_bgm_val_lbl.size = Vector2(52.0, 32.0)
	_settings_bgm_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_settings_bgm_val_lbl.add_theme_font_size_override("font_size", 19)
	_settings_bgm_val_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	settings_layer.add_child(_settings_bgm_val_lbl)

	# ── SE Volume row ─────────────────────────────────────────────────────
	var ry2 := ry1 + 72.0
	var sfx_lbl := Label.new()
	sfx_lbl.text = "SE音量"
	sfx_lbl.position = Vector2(lbl_x, ry2 + 4.0)
	sfx_lbl.size = Vector2(140.0, 32.0)
	sfx_lbl.add_theme_font_size_override("font_size", 19)
	sfx_lbl.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	settings_layer.add_child(sfx_lbl)

	_settings_sfx_slider = _make_settings_slider(ctrl_x, ry2 + 2.0, ctrl_w, 100.0)
	settings_layer.add_child(_settings_sfx_slider)
	_settings_sfx_slider.value_changed.connect(_on_settings_sfx_changed)

	_settings_sfx_val_lbl = Label.new()
	_settings_sfx_val_lbl.text = "100%"
	_settings_sfx_val_lbl.position = Vector2(val_x, ry2 + 4.0)
	_settings_sfx_val_lbl.size = Vector2(52.0, 32.0)
	_settings_sfx_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_settings_sfx_val_lbl.add_theme_font_size_override("font_size", 19)
	_settings_sfx_val_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	settings_layer.add_child(_settings_sfx_val_lbl)

	# ── テスト再生ボタン（BGM・SE それぞれ） ────────────────────────────
	var ry_test := ry2 + 52.0
	var test_hint := Label.new()
	test_hint.text = "※ BGMはスライダー操作でリアルタイム反映されます"
	test_hint.position = Vector2(lbl_x, ry_test)
	test_hint.size = Vector2(pw - 56.0, 24.0)
	test_hint.add_theme_font_size_override("font_size", 13)
	test_hint.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85))
	settings_layer.add_child(test_hint)

	var test_sfx_btn := Button.new()
	test_sfx_btn.text = "▶  SE テスト再生"
	test_sfx_btn.position = Vector2(px + (pw - 200.0) * 0.5, ry_test + 28.0)
	test_sfx_btn.size = Vector2(200.0, 38.0)
	test_sfx_btn.add_theme_font_size_override("font_size", 18)
	test_sfx_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	test_sfx_btn.pressed.connect(_on_settings_test_sfx)
	settings_layer.add_child(test_sfx_btn)

	# ── Fullscreen row ────────────────────────────────────────────────────
	var ry3 := ry_test + 80.0
	var fs_lbl := Label.new()
	fs_lbl.text = "フルスクリーン"
	fs_lbl.position = Vector2(lbl_x, ry3 + 4.0)
	fs_lbl.size = Vector2(140.0, 32.0)
	fs_lbl.add_theme_font_size_override("font_size", 19)
	fs_lbl.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	settings_layer.add_child(fs_lbl)

	_settings_fs_btn = Button.new()
	_settings_fs_btn.text = "OFF"
	_settings_fs_btn.position = Vector2(ctrl_x, ry3)
	_settings_fs_btn.size = Vector2(120.0, 36.0)
	_settings_fs_btn.add_theme_font_size_override("font_size", 19)
	_settings_fs_btn.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_settings_fs_btn.pressed.connect(_on_settings_fullscreen_toggled)
	settings_layer.add_child(_settings_fs_btn)

	# ── Close button ──────────────────────────────────────────────────────
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.position = Vector2(px + (pw - 140.0) * 0.5, py + ph - 62.0)
	close_btn.size = Vector2(140.0, 42.0)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	close_btn.pressed.connect(_close_settings)
	settings_layer.add_child(close_btn)


func _make_settings_slider(sx: float, sy: float, sw: float, init_val: float) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 1.0
	sl.value = init_val
	sl.position = Vector2(sx, sy)
	sl.size = Vector2(sw, 30.0)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.20, 0.38)
	track.set_corner_radius_all(4)
	sl.add_theme_stylebox_override("slider", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.60, 1.0)
	fill.set_corner_radius_all(4)
	sl.add_theme_stylebox_override("grabber_area", fill)

	var fill_hi := StyleBoxFlat.new()
	fill_hi.bg_color = Color(0.35, 0.70, 1.0)
	fill_hi.set_corner_radius_all(4)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill_hi)

	return sl


func _open_settings() -> void:
	if _settings_open:
		return
	_settings_open = true
	_settings_was_paused = paused
	settings_layer.visible = true
	var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_settings_fs_btn.text = "ON" if is_fs else "OFF"
	# Pause game logic but keep BGM playing so slider changes are heard immediately
	if mode == GameMode.STORY and not game_over and not paused:
		paused = true


func _close_settings() -> void:
	if not _settings_open:
		return
	_settings_open = false
	settings_layer.visible = false
	# Restore pause state to what it was before settings opened
	if mode == GameMode.STORY and not game_over:
		paused = _settings_was_paused


func _on_settings_bgm_changed(value: float) -> void:
	_settings_bgm_val_lbl.text = "%d%%" % int(value)
	var offset_db := lerpf(-40.0, 0.0, value / 100.0)
	audio_manager.set_bgm_volume_offset(offset_db)


func _on_settings_sfx_changed(value: float) -> void:
	_settings_sfx_val_lbl.text = "%d%%" % int(value)
	var offset_db := lerpf(-40.0, 0.0, value / 100.0)
	audio_manager.set_sfx_volume_offset(offset_db)


func _on_settings_test_sfx() -> void:
	# Play two distinct SFX back-to-back so the user can judge the SE volume clearly
	audio_manager.play_sfx("ui_confirm")
	audio_manager.play_sfx("item_pickup", -4.0, 1.0)


func _on_settings_fullscreen_toggled() -> void:
	var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_settings_fs_btn.text = "OFF"
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_settings_fs_btn.text = "ON"


# ── Shop HUD button ──────────────────────────────────────────────────────────

func _setup_shop_hud_button() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 20
	add_child(hud_layer)

	# Story HUD bar added first so shop elements render ON TOP of it
	_setup_story_hud_bar(hud_layer)

	# ── Shop/crystal container — hidden until STORY mode ──────────────
	# Added after story_hud_container so it draws on top of the dark bar bg
	shop_hud_container = Control.new()
	shop_hud_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_hud_container.mouse_filter = Control.MOUSE_FILTER_PASS
	shop_hud_container.visible = false
	hud_layer.add_child(shop_hud_container)

	# Crystal icon (item_crystal.png)
	var crystal_icon := AssetPaths.create_sprite(AssetPaths.ITEMS["crystal"], Vector2(30, 30), Color(0.4, 0.95, 1.0))
	crystal_icon.position = Vector2(screen_size.x - 260, 30)
	crystal_icon.z_index = 1
	shop_hud_container.add_child(crystal_icon)

	# Crystal count label (number only, icon replaces emoji)
	hud_crystal_label = Label.new()
	hud_crystal_label.text = "0"
	hud_crystal_label.position = Vector2(screen_size.x - 238, 14)
	hud_crystal_label.size = Vector2(90, 40)
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
	shop_icon.z_index = 1
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
	_add_sep.call(742.0)

	# ── P1 Lives bar ─────────────────────────── x=750
	_add_header.call(story_hud_container, 750.0, "P1 HP")
	story_p1_life_segs.clear()
	story_p1_life_hi.clear()
	const _SEG_W := 24.0
	const _SEG_H := 14.0
	const _SEG_GAP := 3.0
	const _SEG_Y := 22.0
	var _bar_total_w := _SEG_W * PLAYER_LIVES_MAX + _SEG_GAP * (PLAYER_LIVES_MAX - 1)
	var _lbg1 := ColorRect.new()
	_lbg1.position = Vector2(749, 21)
	_lbg1.size = Vector2(_bar_total_w + 2.0, _SEG_H + 2.0)
	_lbg1.color = Color(0.02, 0.04, 0.10)
	_lbg1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(_lbg1)
	for _si in range(PLAYER_LIVES_MAX):
		var _sx := 750.0 + _si * (_SEG_W + _SEG_GAP)
		var _fill := ColorRect.new()
		_fill.position = Vector2(_sx, _SEG_Y)
		_fill.size = Vector2(_SEG_W, _SEG_H)
		_fill.color = Color(0.15, 0.55, 1.0)
		_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		story_hud_container.add_child(_fill)
		story_p1_life_segs.append(_fill)
		var _hi := ColorRect.new()
		_hi.position = Vector2(_sx, _SEG_Y)
		_hi.size = Vector2(_SEG_W, 3.0)
		_hi.color = Color(0.55, 0.80, 1.0, 0.60)
		_hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		story_hud_container.add_child(_hi)
		story_p1_life_hi.append(_hi)
	_add_sep.call(750.0 + _bar_total_w + 14.0)

	# ── P2 Lives bar ─────────────────────────── x=902
	var _p2x := 750.0 + _bar_total_w + 22.0
	story_p2_hud_header = _add_header.call(story_hud_container, _p2x, "P2 HP")
	story_p2_life_segs.clear()
	story_p2_life_hi.clear()
	var _lbg2 := ColorRect.new()
	_lbg2.position = Vector2(_p2x - 1.0, 21)
	_lbg2.size = Vector2(_bar_total_w + 2.0, _SEG_H + 2.0)
	_lbg2.color = Color(0.07, 0.05, 0.02)
	_lbg2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(_lbg2)
	for _si in range(PLAYER_LIVES_MAX):
		var _sx := _p2x + _si * (_SEG_W + _SEG_GAP)
		var _fill := ColorRect.new()
		_fill.position = Vector2(_sx, _SEG_Y)
		_fill.size = Vector2(_SEG_W, _SEG_H)
		_fill.color = Color(0.95, 0.70, 0.05)
		_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		story_hud_container.add_child(_fill)
		story_p2_life_segs.append(_fill)
		var _hi := ColorRect.new()
		_hi.position = Vector2(_sx, _SEG_Y)
		_hi.size = Vector2(_SEG_W, 3.0)
		_hi.color = Color(1.0, 0.95, 0.45, 0.60)
		_hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		story_hud_container.add_child(_hi)
		story_p2_life_hi.append(_hi)

	# ── Gate HP bar ──────────────────────────── x≈1058
	var _gate_bar_x := _p2x + _bar_total_w + 22.0
	_add_sep.call(_gate_bar_x - 12.0)
	story_gate_header_label = _add_header.call(story_hud_container, _gate_bar_x, "GATE")
	var _gate_bars: Array = _add_bar.call(story_hud_container, _gate_bar_x, 140.0, Color(0.12, 0.04, 0.02))
	story_gate_bar_bg   = _gate_bars[0]
	story_gate_bar_fill = _gate_bars[1]
	story_gate_bar_fill.color = Color(1.0, 0.30, 0.05)
	story_gate_label = Label.new()
	story_gate_label.text = "---"
	story_gate_label.position = Vector2(_gate_bar_x + 146.0, 14)
	story_gate_label.size = Vector2(130, 28)
	story_gate_label.add_theme_font_size_override("font_size", 16)
	story_gate_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	story_gate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(story_gate_label)

	# ── Gate 2 HP bar (Stage 2 only) ───────── x≈1348
	var _gate2_bar_x := _gate_bar_x + 290.0
	_add_sep.call(_gate2_bar_x - 12.0)
	_add_header.call(story_hud_container, _gate2_bar_x, "GATE 2")
	var _gate2_bars: Array = _add_bar.call(story_hud_container, _gate2_bar_x, 140.0, Color(0.12, 0.04, 0.02))
	story_gate2_bar_bg   = _gate2_bars[0]
	story_gate2_bar_fill = _gate2_bars[1]
	story_gate2_bar_fill.color = Color(1.0, 0.30, 0.05)
	story_gate2_label = Label.new()
	story_gate2_label.text = "---"
	story_gate2_label.position = Vector2(_gate2_bar_x + 146.0, 14)
	story_gate2_label.size = Vector2(130, 28)
	story_gate2_label.add_theme_font_size_override("font_size", 16)
	story_gate2_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	story_gate2_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(story_gate2_label)
	story_gate2_bar_bg.visible  = false
	story_gate2_bar_fill.visible = false
	story_gate2_label.visible   = false

	# ── Gate 3 HP bar (Stage 3 only) ───────── x≈1638
	var _gate3_bar_x := _gate2_bar_x + 290.0
	_add_sep.call(_gate3_bar_x - 12.0)
	_add_header.call(story_hud_container, _gate3_bar_x, "GATE 3")
	var _gate3_bars: Array = _add_bar.call(story_hud_container, _gate3_bar_x, 140.0, Color(0.12, 0.04, 0.02))
	story_gate3_bar_bg   = _gate3_bars[0]
	story_gate3_bar_fill = _gate3_bars[1]
	story_gate3_bar_fill.color = Color(1.0, 0.30, 0.05)
	story_gate3_label = Label.new()
	story_gate3_label.text = "---"
	story_gate3_label.position = Vector2(_gate3_bar_x + 146.0, 14)
	story_gate3_label.size = Vector2(130, 28)
	story_gate3_label.add_theme_font_size_override("font_size", 16)
	story_gate3_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	story_gate3_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(story_gate3_label)
	story_gate3_bar_bg.visible  = false
	story_gate3_bar_fill.visible = false
	story_gate3_label.visible   = false

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

	# ── P3/P4 second HUD strip (4-player mode only) ──────────────────────
	story_p34_strip = ColorRect.new()
	story_p34_strip.position = Vector2(0, BAR_H)
	story_p34_strip.size = Vector2(sw, 38)
	story_p34_strip.color = Color(0.03, 0.05, 0.12, 0.88)
	story_p34_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_p34_strip.visible = false
	story_hud_container.add_child(story_p34_strip)

	# P3/P4 use same segment dimensions as P1/P2 — label at +4, segments at +22 (mirrors P1/P2 layout)
	const _S2Y := 22.0
	var _p3_lbl_x := 750.0
	story_p3_hud_header = Label.new()
	story_p3_hud_header.text = "P3 HP"
	story_p3_hud_header.position = Vector2(_p3_lbl_x, BAR_H + 4)
	story_p3_hud_header.size = Vector2(140, 18)
	story_p3_hud_header.add_theme_font_size_override("font_size", 12)
	story_p3_hud_header.add_theme_color_override("font_color", Color(0.15, 1.00, 0.35))
	story_p3_hud_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(story_p3_hud_header)
	var _lbg3 := ColorRect.new()
	_lbg3.position = Vector2(_p3_lbl_x - 1.0, BAR_H + 21)
	_lbg3.size = Vector2(_bar_total_w + 2.0, _SEG_H + 2.0)
	_lbg3.color = Color(0.02, 0.08, 0.04)
	_lbg3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(_lbg3)
	story_p3_life_segs.clear(); story_p3_life_hi.clear()
	for _si in range(PLAYER_LIVES_MAX):
		var _sx := _p3_lbl_x + _si * (_SEG_W + _SEG_GAP)
		var _f := ColorRect.new()
		_f.position = Vector2(_sx, BAR_H + _S2Y); _f.size = Vector2(_SEG_W, _SEG_H)
		_f.color = Color(0.15, 0.95, 0.30); _f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		story_hud_container.add_child(_f); story_p3_life_segs.append(_f)
		var _h := ColorRect.new()
		_h.position = Vector2(_sx, BAR_H + _S2Y); _h.size = Vector2(_SEG_W, 3.0)
		_h.color = Color(0.55, 1.0, 0.60, 0.60); _h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		story_hud_container.add_child(_h); story_p3_life_hi.append(_h)

	var _p4_lbl_x := _p3_lbl_x + _bar_total_w + 22.0
	story_p4_hud_header = Label.new()
	story_p4_hud_header.text = "P4 HP"
	story_p4_hud_header.position = Vector2(_p4_lbl_x, BAR_H + 4)
	story_p4_hud_header.size = Vector2(140, 18)
	story_p4_hud_header.add_theme_font_size_override("font_size", 12)
	story_p4_hud_header.add_theme_color_override("font_color", Color(0.75, 0.25, 1.00))
	story_p4_hud_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(story_p4_hud_header)
	var _lbg4 := ColorRect.new()
	_lbg4.position = Vector2(_p4_lbl_x - 1.0, BAR_H + 21)
	_lbg4.size = Vector2(_bar_total_w + 2.0, _SEG_H + 2.0)
	_lbg4.color = Color(0.06, 0.02, 0.10)
	_lbg4.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_hud_container.add_child(_lbg4)
	story_p4_life_segs.clear(); story_p4_life_hi.clear()
	for _si in range(PLAYER_LIVES_MAX):
		var _sx := _p4_lbl_x + _si * (_SEG_W + _SEG_GAP)
		var _f := ColorRect.new()
		_f.position = Vector2(_sx, BAR_H + _S2Y); _f.size = Vector2(_SEG_W, _SEG_H)
		_f.color = Color(0.70, 0.20, 1.0); _f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		story_hud_container.add_child(_f); story_p4_life_segs.append(_f)
		var _h := ColorRect.new()
		_h.position = Vector2(_sx, BAR_H + _S2Y); _h.size = Vector2(_SEG_W, 3.0)
		_h.color = Color(0.90, 0.60, 1.0, 0.60); _h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		story_hud_container.add_child(_h); story_p4_life_hi.append(_h)


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
	var cx := screen_size.x * 0.5
	var by := screen_size.y * 0.5 + 152.0
	var bw := 280.0
	var gap := 14.0

	# Upper center: NEXT STAGE (hidden until a stage clear that has a next stage)
	result_next_stage_button = _create_premium_button("NEXT STAGE →", Vector2(cx - 170.0, by - 100.0), Vector2(340.0, 72.0))
	result_next_stage_button.pressed.connect(_on_result_next_stage_pressed)
	result_next_stage_button.visible = false
	game_over_layer.add_child(result_next_stage_button)

	# Lower row: REPLAY | STAGE | HOME (always shown)
	var start := cx - 434.0
	result_retry_button = _create_premium_button("REPLAY", Vector2(start, by), Vector2(bw, 72))
	result_retry_button.pressed.connect(_on_result_retry_pressed)
	game_over_layer.add_child(result_retry_button)

	result_stage_button = _create_premium_button("STAGE", Vector2(start + bw + gap, by), Vector2(bw, 72))
	result_stage_button.pressed.connect(_on_result_stage_pressed)
	game_over_layer.add_child(result_stage_button)

	result_home_button = _create_premium_button("HOME", Vector2(start + (bw + gap) * 2.0, by), Vector2(bw, 72))
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
	_show_story_mode_select()


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
	story_stage_number = 1
	get_tree().reload_current_scene()


func _on_result_next_stage_pressed() -> void:
	game_over = false
	game_over_layer.visible = false
	if result_next_stage_button != null:
		result_next_stage_button.visible = false

	# Save state that should persist into the next stage.
	var _rapid_list: Array[float] = []
	var _power_list: Array[float] = []
	for _cp in players:
		_rapid_list.append(float(_cp.get("rapid", 0.0)))
		_power_list.append(float(_cp.get("power", 0.0)))
	_stage_carry = {
		"crystals":    crystals,
		"lives":       player_lives.duplicate(),
		"rapid":       _rapid_list,
		"power":       _power_list,
		"shield_time": core_shield_time,
		"shield_max":  core_shield_max,
	}

	story_stage_number += 1
	_load_stage(StoryStageScript)


func _on_result_retry_pressed() -> void:
	# Retry the same stage when possible. If there is no last stage, return home.
	if last_stage_script == null:
		get_tree().reload_current_scene()
		return
	game_over = false
	game_over_layer.visible = false
	_load_stage(last_stage_script)


func _on_result_stage_pressed() -> void:
	game_over = false
	game_over_layer.visible = false
	_stage_carry = {}
	_show_stage_select()


func _show_title() -> void:
	mode = GameMode.TITLE
	solo_mode = false
	if not online_game_active:
		set_online_input_mode(false, 1)
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
		_show_story_mode_select()
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
	var ship_id: int = int(player_ship_map[player_id - 1]) if player_id - 1 < player_ship_map.size() else player_id
	if player_specs.has(ship_id):
		return player_specs[ship_id]
	return player_specs[1]


func _create_players() -> void:
	players.clear()
	const _SHIP_PATHS: Array[String] = ["p1", "p2", "p3", "p4"]
	const _SHIP_COLORS: Array[Color] = [
		Color(0.2, 0.85, 1.0), Color(1.0, 0.66, 0.18),
		Color(0.15, 1.0, 0.35), Color(0.75, 0.25, 1.0)
	]
	const _INIT_POS_X: Array[float] = [0.25, 0.45, 0.55, 0.75]
	for _pi in range(player_count):
		var _ship_id: int = int(player_ship_map[_pi] if _pi < player_ship_map.size() else _pi + 1)
		var _sid: int = clampi(_ship_id - 1, 0, _SHIP_PATHS.size() - 1)
		var _path: String = AssetPaths.PLAYERS[_SHIP_PATHS[_sid]]
		var _col: Color = _SHIP_COLORS[_sid]
		players.append(_create_player(_pi + 1, _path, Vector2(screen_size.x * _INIT_POS_X[_pi], screen_size.y - 160), _col))

func _create_player(id: int, path: String, pos: Vector2, color: Color) -> Dictionary:
	var spec: Dictionary = _get_player_spec(id)

	# Size varies by player: P1 small/agile, P2 large/heavy, P3/P4 medium
	var sprite_size := Vector2(92, 92) if id == 1 else (Vector2(112, 112) if id == 2 else Vector2(100, 100))
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
		"radius": 42.0 if id == 1 else (52.0 if id == 2 else 46.0),
		"rapid": 0.0,
		"power": 0.0,
		"base_scale": sprite.scale,
	}

func _start_story() -> void:
	mode = GameMode.STORY
	title_layer.visible = false
	game_over = false
	team_score = 0
	p1_score = 0
	p2_score = 0
	base_hp = 9999999  # core has no HP; game ends only when all player lives reach 0
	core_shield_time = 0.0
	core_shield_max  = 0.0
	rhythm_beat_timer = 60.0 / rhythm_bpm
	rhythm_beat_count = 0
	rhythm_flash_timer = 0.0
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
	base_sprite.scale   = Vector2.ZERO
	base_sprite.modulate.a = 1.0
	story_core_fade_timer = 0.0

	astral_ring_sprite.visible = false
	boss_sprite.visible = false
	boss_hp_back.visible = false
	boss_hp_fill.visible = false
	link_back.visible = false
	link_fill.visible = false

	# Free old player sprites and recreate for current player_count
	for _op in players:
		if is_instance_valid(_op.get("sprite")):
			(_op["sprite"] as Sprite2D).queue_free()
		if is_instance_valid(_op.get("shield_sprite")):
			(_op["shield_sprite"] as Sprite2D).queue_free()
	_create_players()
	_rebuild_player_ships()
	var _intro_core_pos := base_sprite.position
	for p in players:
		var _pid := int(p["id"])
		p["pos"] = _intro_core_pos
		p["hp"] = 100
		p["rapid"] = 0.0
		p["power"] = 0.0
		p["speed"] = p["base_speed"]
		var _ispr := p["sprite"] as Sprite2D
		_ispr.visible = true
		_ispr.scale = Vector2.ZERO
		_ispr.position = _intro_core_pos
		(p["shield_sprite"] as Sprite2D).visible = false

	story_intro_active = true
	story_intro_timer = STORY_INTRO_DURATION
	player_lives = [PLAYER_LIVES_MAX, PLAYER_LIVES_MAX, PLAYER_LIVES_MAX, PLAYER_LIVES_MAX]
	player_inv_timer = [0.0, 0.0, 0.0, 0.0]
	# Zero out lives for inactive player slots
	for _li in range(player_count, 4):
		player_lives[_li] = 0
	var _show_p2  := player_count >= 2
	var _show_p3  := player_count >= 3
	var _show_p4  := player_count >= 4
	if story_p2_hud_header != null:
		story_p2_hud_header.visible = _show_p2
	for _si in story_p2_life_segs:
		(_si as CanvasItem).visible = _show_p2
	for _hi in story_p2_life_hi:
		(_hi as CanvasItem).visible = _show_p2
	if story_p34_strip != null:
		story_p34_strip.visible = _show_p3
	if story_p3_hud_header != null:
		story_p3_hud_header.visible = _show_p3
	if story_p4_hud_header != null:
		story_p4_hud_header.visible = _show_p4
	for _si in story_p3_life_segs:
		(_si as CanvasItem).visible = _show_p3
	for _hi in story_p3_life_hi:
		(_hi as CanvasItem).visible = _show_p3
	for _si in story_p4_life_segs:
		(_si as CanvasItem).visible = _show_p4
	for _hi in story_p4_life_hi:
		(_hi as CanvasItem).visible = _show_p4

	# ── Restore carry-over from previous stage ────────────────────────
	if not _stage_carry.is_empty():
		# Crystals (reset by _clear_game_objects; restore here)
		crystals = int(_stage_carry.get("crystals", 0))
		_update_hud_crystal_label()
		# Lives — restore per active player; inactive slots stay 0
		var _cl: Array = _stage_carry.get("lives", [])
		player_lives[0] = clampi(int(_cl[0]) if _cl.size() > 0 else PLAYER_LIVES_MAX, 1, PLAYER_LIVES_MAX)
		for _li in range(1, player_count):
			if _li < _cl.size():
				player_lives[_li] = clampi(int(_cl[_li]), 1, PLAYER_LIVES_MAX)
		# Per-player active item timers
		var _carry_rapid: Array = _stage_carry.get("rapid", [])
		var _carry_power: Array = _stage_carry.get("power", [])
		for _ci in range(players.size()):
			players[_ci]["rapid"] = float(_carry_rapid[_ci]) if _ci < _carry_rapid.size() else 0.0
			players[_ci]["power"] = float(_carry_power[_ci]) if _ci < _carry_power.size() else 0.0
		# Core shield (carry remaining time, capped to 10s)
		var _ct: float = float(_stage_carry.get("shield_time", 0.0))
		if _ct > 0.0:
			core_shield_time = minf(_ct, 10.0)
			core_shield_max  = float(_stage_carry.get("shield_max", core_shield_time))
		_stage_carry = {}

	_spawn_effect(AssetPaths.EFFECTS["twin_core_cannon"], _intro_core_pos, Vector2(260, 260), 0.5)

	# ── Gate setup (stage-dependent) ─────────────────────────────────
	for _gs in [gate_sprite, gate2_sprite, gate3_sprite]:
		if _gs != null and is_instance_valid(_gs):
			(_gs as Sprite2D).queue_free()
	gate_sprite = null; gate2_sprite = null; gate3_sprite = null

	if story_stage_number == 4:
		# Stage 4: single boss gate at center, high HP, shoots back
		gate_hp = GATE_HP_MAX_S4; gate_pos = Vector2(screen_size.x * 0.5, 148.0)
		gate_open = false; gate_open_timer = 0.0; gate_destroyed = false; gate_clear_timer = 0.0
		gate_sprite = AssetPaths.create_sprite(AssetPaths.ENEMY_GATES["gate_0"], Vector2(240, 240), Color(1.0, 0.65, 0.95), 5)
		gate_sprite.position = gate_pos; add_child(gate_sprite)
		gate2_destroyed = true; gate3_destroyed = true
		gate_boss_shoot_timer = GATE_BOSS_SHOOT_INTERVAL
		if story_gate_header_label != null:
			story_gate_header_label.text = "BOSS GATE"
		for _b in [story_gate2_bar_bg, story_gate2_bar_fill, story_gate2_label,
				   story_gate3_bar_bg, story_gate3_bar_fill, story_gate3_label]:
			if _b != null: (_b as CanvasItem).visible = false

	elif story_stage_number == 3:
		# Stage 3: three gates at 20%, 50%, 80%
		const _SZ3 := Vector2(175, 175)
		gate_hp = GATE_HP_MAX_S3; gate_pos = Vector2(screen_size.x * 0.20, 165.0)
		gate_open = false; gate_open_timer = 0.0; gate_destroyed = false; gate_clear_timer = 0.0
		gate_sprite = AssetPaths.create_sprite(AssetPaths.ENEMY_GATES["gate_0"], _SZ3, Color.WHITE, 5)
		gate_sprite.position = gate_pos; add_child(gate_sprite)

		gate2_hp = GATE_HP_MAX_S3; gate2_pos = Vector2(screen_size.x * 0.50, 165.0)
		gate2_open = false; gate2_open_timer = 0.0; gate2_destroyed = false
		gate2_sprite = AssetPaths.create_sprite(AssetPaths.ENEMY_GATES["gate_0"], _SZ3, Color.WHITE, 5)
		gate2_sprite.position = gate2_pos; add_child(gate2_sprite)

		gate3_hp = GATE_HP_MAX_S3; gate3_pos = Vector2(screen_size.x * 0.80, 165.0)
		gate3_open = false; gate3_open_timer = 0.0; gate3_destroyed = false
		gate3_sprite = AssetPaths.create_sprite(AssetPaths.ENEMY_GATES["gate_0"], _SZ3, Color.WHITE, 5)
		gate3_sprite.position = gate3_pos; add_child(gate3_sprite)

		if story_gate_header_label != null:
			story_gate_header_label.text = "GATE 1"
		for _b in [story_gate2_bar_bg, story_gate2_bar_fill, story_gate2_label,
				   story_gate3_bar_bg, story_gate3_bar_fill, story_gate3_label]:
			if _b != null: (_b as CanvasItem).visible = true

	elif story_stage_number == 2:
		# Stage 2: two gates at 30%, 70%
		gate_hp = GATE_HP_MAX_S2; gate_pos = Vector2(screen_size.x * 0.30, 160.0)
		gate_open = false; gate_open_timer = 0.0; gate_destroyed = false; gate_clear_timer = 0.0
		gate_sprite = AssetPaths.create_sprite(AssetPaths.ENEMY_GATES["gate_0"], Vector2(190, 190), Color.WHITE, 5)
		gate_sprite.position = gate_pos; add_child(gate_sprite)

		gate2_hp = GATE_HP_MAX_S2; gate2_pos = Vector2(screen_size.x * 0.70, 160.0)
		gate2_open = false; gate2_open_timer = 0.0; gate2_destroyed = false
		gate2_sprite = AssetPaths.create_sprite(AssetPaths.ENEMY_GATES["gate_0"], Vector2(190, 190), Color.WHITE, 5)
		gate2_sprite.position = gate2_pos; add_child(gate2_sprite)

		gate3_destroyed = true
		if story_gate_header_label != null:
			story_gate_header_label.text = "GATE 1"
		for _b in [story_gate2_bar_bg, story_gate2_bar_fill, story_gate2_label]:
			if _b != null: (_b as CanvasItem).visible = true
		for _b in [story_gate3_bar_bg, story_gate3_bar_fill, story_gate3_label]:
			if _b != null: (_b as CanvasItem).visible = false

	else:
		# Stage 1: single center gate
		gate_hp = GATE_HP_MAX_S1; gate_pos = Vector2(screen_size.x * 0.5, 150.0)
		gate_open = false; gate_open_timer = 0.0; gate_destroyed = false; gate_clear_timer = 0.0
		gate_sprite = AssetPaths.create_sprite(AssetPaths.ENEMY_GATES["gate_0"], Vector2(200, 200), Color.WHITE, 5)
		gate_sprite.position = gate_pos; add_child(gate_sprite)

		gate2_destroyed = true; gate3_destroyed = true
		if story_gate_header_label != null:
			story_gate_header_label.text = "GATE"
		for _b in [story_gate2_bar_bg, story_gate2_bar_fill, story_gate2_label,
				   story_gate3_bar_bg, story_gate3_bar_fill, story_gate3_label]:
			if _b != null: (_b as CanvasItem).visible = false

	banner_label.text = "STAGE %d" % story_stage_number
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
	if gate_sprite != null and is_instance_valid(gate_sprite):
		gate_sprite.queue_free()
		gate_sprite = null
	gate_open        = false
	gate_open_timer  = 0.0
	gate_destroyed   = false
	gate_clear_timer = 0.0
	if gate2_sprite != null and is_instance_valid(gate2_sprite):
		gate2_sprite.queue_free()
		gate2_sprite = null
	gate2_open        = false
	gate2_open_timer  = 0.0
	gate2_destroyed   = false
	if gate3_sprite != null and is_instance_valid(gate3_sprite):
		gate3_sprite.queue_free()
		gate3_sprite = null
	gate3_open        = false
	gate3_open_timer  = 0.0
	gate3_destroyed   = false
	gate_boss_shoot_timer = 0.0
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
		var _pid := int(p.get("id", 1)) - 1
		if p.has("sprite") and is_instance_valid(p["sprite"]):
			(p["sprite"] as Sprite2D).visible = (_pid < player_lives.size() and player_lives[_pid] > 0)
		if p.has("shield_sprite") and is_instance_valid(p["shield_sprite"]):
			(p["shield_sprite"] as Sprite2D).visible = false

func _update_players(delta: float) -> void:
	# Story fusion mode replaces normal player movement.
	# P1: pointer + cannon. P2: movement + bomb.
	if mode == GameMode.STORY and story_intro_active:
		return
	if mode == GameMode.STORY and story_fusion_active:
		_update_story_fusion(delta)
		return

	for p in players:
		var player_id: int = int(p["id"])
		if mode == GameMode.STORY and player_lives[player_id - 1] <= 0:
			continue
		var dir := Vector2.ZERO
		var rapid: float = float(p["rapid"])
		var power: float = float(p.get("power", 0.0))

		var input_state := _get_player_input(player_id)
		var _interval := float(p["rapid_interval"]) if rapid > 0.0 else float(p["shoot_interval"])
		var _is_cpu: bool = (player_id - 1) < player_cpu_map.size() and bool(player_cpu_map[player_id - 1])

		if _is_cpu:
			var _cpu_pos: Vector2 = p["pos"]
			var _slot := player_id - 1

			# ── Difficulty parameters ──────────────────────────────────────────
			var _threat_r: float  # repulsion radius (px)
			var _spd_mult: float
			var _w_hp:     float
			match cpu_difficulty:
				0: _threat_r = 180.0; _spd_mult = 0.95; _w_hp = 0.0
				1: _threat_r = 250.0; _spd_mult = 1.10; _w_hp = 0.4
				2: _threat_r = 320.0; _spd_mult = 1.25; _w_hp = 0.9
				_: _threat_r = 400.0; _spd_mult = 1.40; _w_hp = 1.5

			# ── 2D Repulsion field (bullets above CPU → horizontal escape only) ──
			var _repulsion := Vector2.ZERO
			var _max_danger := 0.0
			for _eb in enemy_bullets:
				var _bpos: Vector2 = _eb["pos"]
				if _bpos.y > _cpu_pos.y + 50.0:
					continue  # already passed
				var _dist: float = _cpu_pos.distance_to(_bpos)
				if _dist >= _threat_r:
					continue
				var _t: float = 1.0 - (_dist / _threat_r)  # linear falloff
				_max_danger = maxf(_max_danger, _t)
				var _away: Vector2 = _cpu_pos - _bpos
				if _away.y > 0.0:
					# Bullet is above CPU: push horizontally (not downward — useless in vertical shooter)
					var _hx: float = _away.x
					if absf(_hx) < 2.0:
						_hx = signf(_cpu_pos.x - screen_size.x * 0.5)
						if absf(_hx) < 0.1: _hx = 1.0
					_away = Vector2(_hx, 0.0)
				_repulsion += _away.normalized() * _t

			# Screen-edge repulsion: prevent wall hugging
			var _em := 80.0
			if _cpu_pos.x < _em:
				_repulsion.x += (1.0 - _cpu_pos.x / _em) * 1.5
			elif _cpu_pos.x > screen_size.x - _em:
				_repulsion.x -= (1.0 - (screen_size.x - _cpu_pos.x) / _em) * 1.5
			if _cpu_pos.y > screen_size.y - _em:
				_repulsion.y -= (1.0 - (screen_size.y - _cpu_pos.y) / _em) * 1.5

			# Symmetry fallback (bullets perfectly cancel out)
			if _max_danger > 0.25 and _repulsion.length() < 0.1:
				var _cx := screen_size.x * 0.5
				_repulsion = Vector2(signf(_cpu_pos.x - _cx), -0.1).normalized()
				if _repulsion.length() < 0.1: _repulsion = Vector2(1.0, 0.0)

			# ── Navigation target: gate is always the primary objective ──────
			# Find the current active gate position
			var _gx := screen_size.x * 0.5
			if gate_sprite != null and not gate_destroyed:         _gx = gate_sprite.position.x
			elif gate2_sprite != null and not gate2_destroyed:     _gx = gate2_sprite.position.x
			elif gate3_sprite != null and not gate3_destroyed:     _gx = gate3_sprite.position.x
			# Position below the gate so shots (fired straight UP) hit it
			var _gate_nav := Vector2(_gx, screen_size.y * 0.65)

			# Opportunistic item collection: only in lower half, close, near gate X
			var _item_target := Vector2.ZERO
			if cpu_difficulty >= 1 and _cpu_pos.y > screen_size.y * 0.52:
				for _it in items:
					var _itp: Vector2 = _it["pos"]
					var _itd: float = _cpu_pos.distance_to(_itp)
					if _itd < 150.0 and absf(_itp.x - _gx) < 200.0 and _itp.y > screen_size.y * 0.52:
						_item_target = _itp
						break

			# Upper-half guard: if CPU drifted above midpoint, force return to base
			var _retreating: bool = _cpu_pos.y < screen_size.y * 0.50
			var _nav := _gate_nav
			if not _retreating and _item_target != Vector2.ZERO:
				_nav = _item_target
				cpu_state[_slot] = "COLLECT_ITEM"
			elif _retreating:
				cpu_state[_slot] = "RETREAT"
			else:
				cpu_state[_slot] = "ATTACK"

			# ── Blend 2D repulsion with navigation ────────────────────────────
			# When retreating: cap dodge weight at 0.55 so nav always pulls CPU downward.
			# Horizontal repulsion still fires — CPU dodges sideways while descending.
			var _dodge_w: float
			if _retreating:
				_dodge_w = minf(_max_danger * 2.5, 0.55)
			else:
				_dodge_w = minf(_max_danger * 2.5, 1.0)
			var _nav_dir: Vector2 = (_nav - _cpu_pos).normalized() if _cpu_pos.distance_to(_nav) > 8.0 else Vector2.ZERO
			var _rep_dir: Vector2 = _repulsion.normalized() if _repulsion.length() > 0.01 else Vector2.ZERO
			var _combined: Vector2 = _rep_dir * _dodge_w + _nav_dir * (1.0 - _dodge_w)
			dir = _combined.normalized() * _spd_mult if _combined.length() > 0.01 else Vector2.ZERO

			if _max_danger > 0.0:
				cpu_state[_slot] = "DODGE"

			# ── Shoot only when aligned with a hittable target ────────────────
			# Shots fire straight UP, so X-alignment with target is required.
			# Tolerances are half the sprite widths for each target type.
			var _should_shoot := false

			# 1. Gate alignment (gate sprite ~200px wide → ±90px tolerance)
			const _AIM_GATE := 90.0
			if gate_sprite  != null and not gate_destroyed  and absf(_cpu_pos.x - gate_sprite.position.x)  < _AIM_GATE: _should_shoot = true
			if gate2_sprite != null and not gate2_destroyed and absf(_cpu_pos.x - gate2_sprite.position.x) < _AIM_GATE: _should_shoot = true
			if gate3_sprite != null and not gate3_destroyed and absf(_cpu_pos.x - gate3_sprite.position.x) < _AIM_GATE: _should_shoot = true

			# 2. Enemy alignment (~±40px)
			if not _should_shoot:
				for _en in enemies:
					if absf(_cpu_pos.x - (_en["pos"] as Vector2).x) < 40.0:
						_should_shoot = true; break

			# 3. Intercept incoming enemy bullets (~±28px)
			if not _should_shoot:
				for _eb in enemy_bullets:
					var _ebpos: Vector2 = _eb["pos"]
					if _ebpos.y < _cpu_pos.y + 20.0 and absf(_cpu_pos.x - _ebpos.x) < 28.0:
						_should_shoot = true; break

			if _should_shoot:
				match player_id:
					1: if shoot_cd_p1 <= 0.0: _shoot(1); shoot_cd_p1 = _interval
					2: if shoot_cd_p2 <= 0.0: _shoot(2); shoot_cd_p2 = _interval
					3: if shoot_cd_p3 <= 0.0: _shoot(3); shoot_cd_p3 = _interval
					4: if shoot_cd_p4 <= 0.0: _shoot(4); shoot_cd_p4 = _interval
		else:
			dir = input_state.move
			if player_id == 1:
				if input_state.shoot and shoot_cd_p1 <= 0.0:
					_shoot(1); shoot_cd_p1 = _interval
			elif player_id == 2:
				if input_state.shoot and shoot_cd_p2 <= 0.0:
					_shoot(2); shoot_cd_p2 = _interval
			elif player_id == 3:
				if input_state.shoot and shoot_cd_p3 <= 0.0:
					_shoot(3); shoot_cd_p3 = _interval
			elif player_id == 4:
				if input_state.shoot and shoot_cd_p4 <= 0.0:
					_shoot(4); shoot_cd_p4 = _interval

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

	var _shoot_sid := int(player_ship_map[player_id - 1]) if player_id - 1 < player_ship_map.size() else player_id
	var path: String
	match _shoot_sid:
		1: path = AssetPaths.PROJECTILES["azure"]
		2: path = AssetPaths.PROJECTILES["solar"]
		3: path = AssetPaths.PROJECTILES["emerald"]
		4: path = AssetPaths.PROJECTILES["violet"]
		_: path = AssetPaths.PROJECTILES["basic"]
	var origin: Vector2 = p["pos"]
	var damage: int = int(p["damage"])
	var shot_speed: float = float(p["shot_speed"])
	var bullet_size: float = float(p["bullet_size"])
	var power: float = float(p.get("power", 0.0))
	var is_piercing := false

	# Step B: Power Boost — giant bullet for both P1 and P2.
	if mode == GameMode.STORY and power > 0.0:
		if String(p["power_mode"]) == "giant_bullet":
			damage += 20
			bullet_size *= 1.65
			shot_speed *= 0.92

	# Step B: Rapid Fire — 3-shot spread burst for both P1 and P2.
	if mode == GameMode.STORY and float(p["rapid"]) > 0.0:
		for angle_offset in [-0.18, 0.0, 0.18]:
			var burst_dir := direction.rotated(angle_offset)
			var burst_bullet: Dictionary = _create_bullet(origin + burst_dir * 58.0, burst_dir, player_id, damage, path, shot_speed, bullet_size, is_piercing)
			bullets.append(burst_bullet)
	else:
		var bullet: Dictionary = _create_bullet(origin + direction * 58.0, direction, player_id, damage, path, shot_speed, bullet_size, is_piercing)
		bullets.append(bullet)

	_fire_weapon_extra(player_id, origin, direction * shot_speed)

	if audio_manager != null:
		var _sfx_key: String
		match _shoot_sid:
			1: _sfx_key = "shot_azure"
			3: _sfx_key = "shot_azure"
			_: _sfx_key = "shot_solar"
		audio_manager.play_sfx(_sfx_key, -8.0)

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
	gate_hit_sound_cd = maxf(0.0, gate_hit_sound_cd - delta)

	if fusion_flash_timer > 0.0:
		fusion_flash_timer -= delta
		fusion_flash_rect.color.a = fusion_flash_timer / 0.35 * 0.82

	# Old center fusion bar — only used in non-STORY modes (RAID etc.)
	if story_fusion_active and fusion_bar_fill != null and mode != GameMode.STORY:
		var ratio := story_fusion_timer / story_fusion_duration
		fusion_bar_fill.size.x = 680.0 * clampf(ratio, 0.0, 1.0)

	# ── Story intro: players emerge from core ──────────────────────────
	if story_intro_active:
		story_intro_timer = maxf(0.0, story_intro_timer - delta)
		var _prog := 1.0 - story_intro_timer / STORY_INTRO_DURATION

		# ── Target positions by player count ──────────────────────────
		var _dy := screen_size.y - 280.0
		var _targets: Array
		match player_count:
			1: _targets = [
				Vector2(screen_size.x * 0.50, _dy),
			]
			3: _targets = [
				Vector2(screen_size.x * 0.25, _dy),
				Vector2(screen_size.x * 0.50, _dy),
				Vector2(screen_size.x * 0.75, _dy),
			]
			4: _targets = [
				Vector2(screen_size.x * 0.20, _dy),
				Vector2(screen_size.x * 0.40, _dy),
				Vector2(screen_size.x * 0.60, _dy),
				Vector2(screen_size.x * 0.80, _dy),
			]
			_: _targets = [
				Vector2(screen_size.x * 0.30, _dy),
				Vector2(screen_size.x * 0.70, _dy),
			]

		# ── Phase 1 (0 → 30%): core pulses in ─────────────────────────
		var _core_scale := smoothstep(0.0, 0.30, _prog)
		if base_sprite != null:
			base_sprite.scale = _base_sprite_natural_scale * _core_scale

		# ── Phase 2 (25% → 100%): players emerge from core ────────────
		var _emerge := clampf((_prog - 0.25) / 0.75, 0.0, 1.0)
		var _scale_t := smoothstep(0.0, 0.45, _emerge)
		var _move_t  := smoothstep(0.0, 1.00, _emerge)
		var _core_p  := base_sprite.position
		var _anim_count := mini(players.size(), player_count)
		for _pi in range(_anim_count):
			if _pi >= _targets.size():
				break
			var _ip: Dictionary = players[_pi]
			var _ispr := _ip["sprite"] as Sprite2D
			_ispr.scale = (_ip.get("base_scale", Vector2.ONE) as Vector2) * _scale_t
			_ip["pos"] = _core_p.lerp(_targets[_pi], _move_t)
			_ispr.position = _ip["pos"]

		if story_intro_timer <= 0.0:
			story_intro_active = false
			base_sprite.scale = _base_sprite_natural_scale
			story_core_fade_timer = STORY_CORE_FADE_DURATION
			for _pi in range(_anim_count):
				if _pi >= _targets.size():
					break
				var _ip: Dictionary = players[_pi]
				var _ispr := _ip["sprite"] as Sprite2D
				_ispr.scale = _ip.get("base_scale", Vector2.ONE) as Vector2
				_ip["pos"] = _targets[_pi]
				_ispr.position = _ip["pos"]
				_spawn_effect(AssetPaths.EFFECTS["hit_spark"], _ip["pos"], Vector2(90, 90), 0.35)

	# Core fade-out after intro animation
	if story_core_fade_timer > 0.0:
		story_core_fade_timer = maxf(0.0, story_core_fade_timer - delta)
		if base_sprite != null:
			base_sprite.modulate.a = story_core_fade_timer / STORY_CORE_FADE_DURATION
			if story_core_fade_timer <= 0.0:
				base_sprite.visible = false
				base_sprite.modulate.a = 1.0

	if not story_intro_active:
		enemy_spawn_timer -= delta
		item_spawn_timer -= delta
	core_shield_time = maxf(0.0, core_shield_time - delta)

	if not story_fusion_active:
		for _pi in range(player_inv_timer.size()):
			if player_inv_timer[_pi] > 0.0:
				player_inv_timer[_pi] = maxf(0.0, player_inv_timer[_pi] - delta)
				if players.size() > _pi and player_lives[_pi] > 0:
					var _ispr := players[_pi]["sprite"] as Sprite2D
					if is_instance_valid(_ispr):
						_ispr.visible = fmod(player_inv_timer[_pi] * 8.0, 1.0) > 0.5
			elif players.size() > _pi and player_lives[_pi] > 0:
				var _ispr := players[_pi]["sprite"] as Sprite2D
				if is_instance_valid(_ispr):
					_ispr.visible = true

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

	coop_link = 0.0

	# ── Gate 1 ────────────────────────────────────────────────────────
	if gate_sprite != null and not gate_destroyed:
		if not gate_open and not story_intro_active:
			gate_open_timer += delta
			if gate_open_timer >= GATE_OPEN_DELAY:
				gate_open = true
				_spawn_effect(AssetPaths.EFFECTS["twin_core_cannon"], gate_pos, Vector2(220, 220), 0.5)
				_spawn_effect(AssetPaths.EFFECTS["shield_bubble"], gate_pos, Vector2(260, 260), 0.4)
				if audio_manager != null:
					audio_manager.play_sfx("shield_activate", -5.0)
		if gate_open and (not online_game_active or _is_game_host()):
			for _gi in range(bullets.size() - 1, -1, -1):
				var _gb: Dictionary = bullets[_gi]
				if (_gb["pos"] as Vector2).distance_to(gate_pos) < 90.0 + float(_gb["radius"]):
					gate_hp = max(0, gate_hp - int(_gb["damage"]))
					_spawn_effect(AssetPaths.EFFECTS["hit_spark"], _gb["pos"], Vector2(50, 50), 0.2)
					if audio_manager != null and gate_hit_sound_cd <= 0.0:
						audio_manager.play_sfx("hit_heavy", -4.0, 0.45)
						gate_hit_sound_cd = 0.15
					if is_instance_valid(_gb["sprite"]):
						(_gb["sprite"] as Sprite2D).queue_free()
					bullets.remove_at(_gi)
					_update_gate_sprite()
					if gate_hp <= 0:
						_destroy_gate()
						break

	# ── Boss Gate shooting (Stage 4) ────────────────────────────────
	if story_stage_number == 4 and gate_open and not gate_destroyed and (not online_game_active or _is_game_host()):
		gate_boss_shoot_timer -= delta
		if gate_boss_shoot_timer <= 0.0:
			gate_boss_shoot_timer = GATE_BOSS_SHOOT_INTERVAL
			_spawn_gate_boss_bullets()

	# ── Gate 2 (Stage 2+) ────────────────────────────────────────────
	if story_stage_number >= 2 and gate2_sprite != null and not gate2_destroyed:
		if not gate2_open and not story_intro_active:
			gate2_open_timer += delta
			if gate2_open_timer >= GATE_OPEN_DELAY:
				gate2_open = true
				_spawn_effect(AssetPaths.EFFECTS["twin_core_cannon"], gate2_pos, Vector2(220, 220), 0.5)
				_spawn_effect(AssetPaths.EFFECTS["shield_bubble"], gate2_pos, Vector2(260, 260), 0.4)
				if audio_manager != null:
					audio_manager.play_sfx("shield_activate", -5.0)
		if gate2_open and (not online_game_active or _is_game_host()):
			for _g2i in range(bullets.size() - 1, -1, -1):
				var _g2b: Dictionary = bullets[_g2i]
				if (_g2b["pos"] as Vector2).distance_to(gate2_pos) < 90.0 + float(_g2b["radius"]):
					gate2_hp = max(0, gate2_hp - int(_g2b["damage"]))
					_spawn_effect(AssetPaths.EFFECTS["hit_spark"], _g2b["pos"], Vector2(50, 50), 0.2)
					if audio_manager != null and gate_hit_sound_cd <= 0.0:
						audio_manager.play_sfx("hit_heavy", -4.0, 0.45)
						gate_hit_sound_cd = 0.15
					if is_instance_valid(_g2b["sprite"]):
						(_g2b["sprite"] as Sprite2D).queue_free()
					bullets.remove_at(_g2i)
					_update_gate2_sprite()
					if gate2_hp <= 0:
						_destroy_gate2()
						break

	# ── Gate 3 (Stage 3 only) ────────────────────────────────────────
	if story_stage_number >= 3 and gate3_sprite != null and not gate3_destroyed:
		if not gate3_open and not story_intro_active:
			gate3_open_timer += delta
			if gate3_open_timer >= GATE_OPEN_DELAY:
				gate3_open = true
				_spawn_effect(AssetPaths.EFFECTS["twin_core_cannon"], gate3_pos, Vector2(220, 220), 0.5)
				_spawn_effect(AssetPaths.EFFECTS["shield_bubble"], gate3_pos, Vector2(260, 260), 0.4)
				if audio_manager != null:
					audio_manager.play_sfx("shield_activate", -5.0)
		if gate3_open and (not online_game_active or _is_game_host()):
			for _g3i in range(bullets.size() - 1, -1, -1):
				var _g3b: Dictionary = bullets[_g3i]
				if (_g3b["pos"] as Vector2).distance_to(gate3_pos) < 90.0 + float(_g3b["radius"]):
					gate3_hp = max(0, gate3_hp - int(_g3b["damage"]))
					_spawn_effect(AssetPaths.EFFECTS["hit_spark"], _g3b["pos"], Vector2(50, 50), 0.2)
					if audio_manager != null and gate_hit_sound_cd <= 0.0:
						audio_manager.play_sfx("hit_heavy", -4.0, 0.45)
						gate_hit_sound_cd = 0.15
					if is_instance_valid(_g3b["sprite"]):
						(_g3b["sprite"] as Sprite2D).queue_free()
					bullets.remove_at(_g3i)
					_update_gate3_sprite()
					if gate3_hp <= 0:
						_destroy_gate3()
						break

	if not story_intro_active:
		if not online_game_active or _is_game_host():
			var any_gate_open := gate_open or (story_stage_number >= 2 and gate2_open) or (story_stage_number >= 3 and gate3_open)
			var all_gates_gone := gate_destroyed and gate2_destroyed and gate3_destroyed
			# Rhythm beat drives gate attacks and item spawning (all modes)
			var _beat_interval := 60.0 / rhythm_bpm
			rhythm_beat_timer -= delta
			rhythm_flash_timer = maxf(0.0, rhythm_flash_timer - delta)
			if gate_sprite != null and not gate_destroyed:
				var _fi := clampf(rhythm_flash_timer / 0.10, 0.0, 1.0)
				gate_sprite.modulate = Color(1.0 + _fi, 1.0 + _fi * 0.5, 1.0 - _fi * 0.5, 1.0)
			if rhythm_beat_timer <= 0.0 and not all_gates_gone:
				rhythm_beat_timer += _beat_interval
				_on_rhythm_beat(any_gate_open, all_gates_gone)
			if item_spawn_timer <= 0.0:
				_spawn_item()
				item_spawn_timer = rng.randf_range(6.0, 10.0)
	_update_enemies(delta)
	_update_enemy_bullets(delta)
	# game over is triggered directly from _on_player_hit when all lives reach 0


func _activate_story_fusion(_reason: String = "LINK READY") -> void:
	return  # fusion mechanic disabled
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
	if fusion_bar_back != null and mode != GameMode.STORY:
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
	var pool: Array[String]
	if story_stage_number >= 4:
		# Stage 4: boss stage — only the toughest enemies
		pool = [
			"attacker", "attacker",
			"tank", "tank",
			"elite", "elite", "elite",
			"phantom_dart", "phantom_dart",
			"fortress_walker",
			"bomber_drone", "bomber_drone",
		]
	elif story_stage_number >= 3:
		# Stage 3: hardest mix — all enemy types
		pool = [
			"scout", "scout",
			"attacker", "attacker",
			"tank", "tank",
			"elite", "elite",
			"phantom_dart", "phantom_dart",
			"fortress_walker",
			"split_cell",
			"bomber_drone", "bomber_drone",
		]
	elif story_stage_number == 2:
		# Stage 2: stronger variety including tanks and elites
		pool = [
			"scout", "scout",
			"attacker", "attacker", "attacker",
			"tank",
			"elite", "elite",
			"phantom_dart",
		]
	elif gate_sprite != null or gate_destroyed:
		# Stage 1: scout / attacker / elite only
		pool = [
			"scout", "scout", "scout",
			"attacker", "attacker", "attacker",
			"elite", "elite",
		]
	else:
		pool = [
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

	var pos: Vector2
	if story_stage_number >= 2:
		# Stage 2+: pick spawn gate randomly from whichever gates are still open
		var open_gates: Array[Vector2] = []
		if gate_open and not gate_destroyed:
			open_gates.append(gate_pos)
		if gate2_open and not gate2_destroyed:
			open_gates.append(gate2_pos)
		if story_stage_number >= 3 and gate3_open and not gate3_destroyed:
			open_gates.append(gate3_pos)
		if open_gates.size() > 0:
			var chosen_gate: Vector2 = open_gates[rng.randi_range(0, open_gates.size() - 1)]
			pos = Vector2(chosen_gate.x + rng.randf_range(-45.0, 45.0), chosen_gate.y + 95.0)
		else:
			pos = Vector2(rng.randf_range(80.0, screen_size.x - 80.0), -80.0)
	elif gate_open and not gate_destroyed:
		pos = Vector2(gate_pos.x + rng.randf_range(-50.0, 50.0), gate_pos.y + 95.0)
	else:
		pos = Vector2(rng.randf_range(80.0, screen_size.x - 80.0), -80.0)
	var sprite := AssetPaths.create_sprite(AssetPaths.ENEMIES[key], Vector2(sz, sz), Color(0.9, 0.1, 0.2), 8)
	sprite.position = pos
	add_child(sprite)

	var id := _next_entity_id()
	var data := {"id": id, "pos": pos, "hp": hp, "speed": speed, "sprite": sprite, "radius": radius, "kind": key}
	if key == "bomber_drone":
		data["shoot_timer"] = rng.randf_range(1.0, 2.5)
		data["strafe_dir"]  = float(rng.randi_range(0, 1) * 2 - 1)
		data["strafe_timer"] = rng.randf_range(1.5, 3.0)
	enemies.append(data)

	if online_game_active:
		var ev := {"event": "enemy_spawn", "id": id, "kind": key,
				   "x": pos.x, "y": pos.y, "hp": hp, "speed": speed, "radius": radius}
		if key == "bomber_drone":
			ev["shoot_timer"] = float(data["shoot_timer"])
			ev["strafe_dir"]  = float(data["strafe_dir"])
			ev["strafe_timer"] = float(data["strafe_timer"])
		_send_game_event(ev)


func _spawn_split_cell_frag(from_pos: Vector2) -> void:
	var offset := Vector2(rng.randf_range(-35.0, 35.0), rng.randf_range(-20.0, 20.0))
	var pos := from_pos + offset
	var sprite := AssetPaths.create_sprite(AssetPaths.ENEMIES["split_cell"], Vector2(55, 55), Color(0.2, 0.9, 0.2), 8)
	sprite.position = pos
	add_child(sprite)
	var id := _next_entity_id()
	enemies.append({"id": id, "pos": pos, "hp": 20, "speed": 160.0, "sprite": sprite,
					"radius": 28.0, "kind": "split_cell_frag"})
	if online_game_active:
		_send_game_event({"event": "enemy_spawn", "id": id, "kind": "split_cell_frag",
						  "x": pos.x, "y": pos.y, "hp": 20, "speed": 160.0, "radius": 28.0})


func _fire_bomber_shot(from: Vector2, target: Vector2) -> void:
	var dir := (target - from).normalized()
	var b := _create_bullet(from, dir, 0, 6, AssetPaths.PROJECTILES["boss_orb"], 210.0, 30.0)
	enemy_bullets.append(b)


func _on_rhythm_beat(any_gate_open: bool, all_gates_gone: bool) -> void:
	rhythm_flash_timer = 0.10
	rhythm_beat_count += 1
	if not any_gate_open or all_gates_gone or players.is_empty():
		return
	# Fire one bullet per beat from gate toward each player
	if gate_sprite != null and gate_open and not gate_destroyed:
		for _rp in players:
			if int(_rp["id"]) - 1 < player_lives.size() and player_lives[int(_rp["id"]) - 1] > 0:
				var _dir := ((_rp["pos"] as Vector2) - gate_pos).normalized()
				_spawn_gate_bullet(gate_pos, _dir)
	# Every 4th beat: spawn an extra enemy
	if rhythm_beat_count % 4 == 0 and not all_gates_gone:
		_spawn_enemy()
	# Every 8th beat: double volley (extra spread shot)
	if rhythm_beat_count % 8 == 0 and gate_sprite != null and gate_open and not gate_destroyed:
		for _rp in players:
			if int(_rp["id"]) - 1 < player_lives.size() and player_lives[int(_rp["id"]) - 1] > 0:
				var _base_dir := ((_rp["pos"] as Vector2) - gate_pos).normalized()
				var _spread := 0.28
				_spawn_gate_bullet(gate_pos, _base_dir.rotated(-_spread))
				_spawn_gate_bullet(gate_pos, _base_dir.rotated(_spread))


func _spawn_gate_bullet(from_pos: Vector2, direction: Vector2) -> void:
	var _speed := 380.0 + rhythm_beat_count * 0.5  # gradually speeds up
	_speed = minf(_speed, 650.0)
	var spr := AssetPaths.create_sprite(AssetPaths.PROJECTILES["enemy"], Vector2(22, 22), Color(1.0, 0.35, 0.20), 8)
	spr.position = from_pos
	add_child(spr)
	var b := {
		"id": _next_entity_id(), "pos": from_pos, "vel": direction * _speed,
		"sprite": spr, "damage": 1, "owner": 0,
		"radius": 9.0, "life": 5.0,
	}
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
		# Hit players
		var _hit_player := false
		for _pi in range(players.size()):
			if player_inv_timer[_pi] > 0.0 or player_lives[_pi] <= 0:
				continue
			var _pp: Dictionary = players[_pi]
			if pos.distance_to(_pp["pos"]) < float(_pp["radius"]) + float(b["radius"]):
				_on_player_hit(_pi)
				if is_instance_valid(b["sprite"]):
					(b["sprite"] as Sprite2D).queue_free()
				enemy_bullets.remove_at(i)
				_hit_player = true
				break
		if _hit_player:
			continue

func _update_enemies(delta: float) -> void:
	var stunned := emp_stun_timer > 0.0
	for i in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[i]
		var target: Vector2 = base_sprite.position
		if players.size() > 0:
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

		# Player collision (story mode)
		if mode == GameMode.STORY:
			for _pi in range(players.size()):
				if player_inv_timer[_pi] > 0.0 or player_lives[_pi] <= 0:
					continue
				var _pp: Dictionary = players[_pi]
				if pos.distance_to(_pp["pos"]) < float(_pp["radius"]) + float(e["radius"]) * 0.55:
					_on_player_hit(_pi)

		if int(e["hp"]) <= 0:
			team_score += 20
			_spawn_effect(AssetPaths.EFFECTS["explosion_small"], pos, Vector2(120, 120), 0.35)
			if audio_manager != null:
				audio_manager.play_sfx("explosion_small", -7.0)
			if online_game_active:
				_send_game_event({"event": "enemy_died", "id": int(e.get("id", -1))})
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
			if online_game_active:
				_send_game_event({"event": "enemy_died", "id": int(e.get("id", -1))})
			if is_instance_valid(e["sprite"]):
				(e["sprite"] as Sprite2D).queue_free()
			enemies.remove_at(i)

func _on_player_hit(pi: int) -> void:
	if pi < 0 or pi >= player_lives.size():
		return
	player_lives[pi] = max(0, player_lives[pi] - 1)
	player_inv_timer[pi] = PLAYER_INV_DURATION
	var p: Dictionary = players[pi]
	_spawn_effect(AssetPaths.EFFECTS["hit_spark"], p["pos"], Vector2(100, 100), 0.5)
	if audio_manager != null:
		audio_manager.play_sfx("hit_heavy", -2.0)
	if player_lives[pi] <= 0:
		if is_instance_valid(p["sprite"]):
			(p["sprite"] as Sprite2D).visible = false
		var _all_dead := true
		for _ali in range(player_count):
			if player_lives[_ali] > 0:
				_all_dead = false
				break
		if _all_dead:
			_game_over("GAME OVER", "All pilots lost.\nScore: %d\nPress R to return to Home" % team_score)

func _gate_damage_key(ratio: float) -> String:
	if ratio > 0.80: return "gate_0"
	elif ratio > 0.60: return "gate_20"
	elif ratio > 0.40: return "gate_40"
	elif ratio > 0.20: return "gate_60"
	elif ratio > 0.05: return "gate_80"
	return "gate_95"


func _update_gate_sprite() -> void:
	if gate_sprite == null or not is_instance_valid(gate_sprite):
		return
	var max_hp: int
	var sz: Vector2
	if story_stage_number >= 4:
		max_hp = GATE_HP_MAX_S4; sz = Vector2(240, 240)
	elif story_stage_number >= 3:
		max_hp = GATE_HP_MAX_S3; sz = Vector2(175, 175)
	elif story_stage_number == 2:
		max_hp = GATE_HP_MAX_S2; sz = Vector2(190, 190)
	else:
		max_hp = GATE_HP_MAX_S1; sz = Vector2(200, 200)
	var key := _gate_damage_key(float(gate_hp) / float(max_hp))
	gate_sprite.texture = AssetPaths.load_texture(AssetPaths.ENEMY_GATES[key], Color.WHITE)
	AssetPaths.fit_sprite(gate_sprite, sz)


func _update_gate2_sprite() -> void:
	if gate2_sprite == null or not is_instance_valid(gate2_sprite):
		return
	var max_hp2 := GATE_HP_MAX_S3 if story_stage_number >= 3 else GATE_HP_MAX_S2
	var sz2 := Vector2(175, 175) if story_stage_number >= 3 else Vector2(190, 190)
	var key := _gate_damage_key(float(gate2_hp) / float(max_hp2))
	gate2_sprite.texture = AssetPaths.load_texture(AssetPaths.ENEMY_GATES[key], Color.WHITE)
	AssetPaths.fit_sprite(gate2_sprite, sz2)


func _update_gate3_sprite() -> void:
	if gate3_sprite == null or not is_instance_valid(gate3_sprite):
		return
	var key := _gate_damage_key(float(gate3_hp) / float(GATE_HP_MAX_S3))
	gate3_sprite.texture = AssetPaths.load_texture(AssetPaths.ENEMY_GATES[key], Color.WHITE)
	AssetPaths.fit_sprite(gate3_sprite, Vector2(175, 175))


func _spawn_gate_boss_bullets() -> void:
	if players.is_empty():
		return
	# Target the nearest alive player
	var target_pos: Vector2 = base_sprite.position
	for _bp in players:
		var _bpid: int = int(_bp["id"]) - 1
		if _bpid < player_lives.size() and player_lives[_bpid] > 0:
			target_pos = _bp["pos"] as Vector2
			break
	var origin := gate_pos + Vector2(0.0, 90.0)
	var base_dir := (target_pos - origin).normalized()
	# 5-bullet spread: -40, -20, 0, +20, +40 degrees
	for _angle_deg in [-40.0, -20.0, 0.0, 20.0, 40.0]:
		var dir := base_dir.rotated(deg_to_rad(_angle_deg))
		var _bs := AssetPaths.create_sprite(AssetPaths.PROJECTILES["boss_orb"], Vector2(38, 38), Color(1.0, 0.35, 0.9), 9)
		_bs.position = origin
		_bs.rotation = dir.angle() + PI * 0.5
		add_child(_bs)
		enemy_bullets.append({
			"pos": origin,
			"vel": dir * 290.0,
			"damage": 20,
			"sprite": _bs,
			"radius": 19.0,
			"life": 5.0,
		})
	if audio_manager != null:
		audio_manager.play_sfx("shot_boss", -6.0)
	_spawn_effect(AssetPaths.EFFECTS["hit_spark"], gate_pos + Vector2(0, 60), Vector2(80, 80), 0.18)


func _gate_explosion(pos: Vector2) -> void:
	_spawn_effect(AssetPaths.EFFECTS["explosion_large"], pos, Vector2(300, 300), 1.0)
	_spawn_effect(AssetPaths.EFFECTS["explosion_small"], pos + Vector2(50, -30), Vector2(120, 120), 0.55)
	_spawn_effect(AssetPaths.EFFECTS["explosion_small"], pos + Vector2(-50, 25), Vector2(100, 100), 0.65)
	if audio_manager != null:
		audio_manager.play_sfx("explosion_large", -4.0)


func _check_stage_clear() -> void:
	var all_gone := gate_destroyed and gate2_destroyed and gate3_destroyed
	if not all_gone:
		return
	match story_stage_number:
		1: _game_over("STAGE 1 CLEAR", "Gate destroyed!\nTeam Score: %d" % team_score)
		2: _game_over("STAGE 2 CLEAR", "Both gates destroyed!\nTeam Score: %d" % team_score)
		3: _game_over("STAGE 3 CLEAR", "All three gates destroyed!\nTeam Score: %d" % team_score)
		4: _game_over("STAGE 4 CLEAR", "Boss Gate destroyed!\nTeam Score: %d" % team_score)
		_: _game_over("STAGE %d CLEAR" % story_stage_number, "Team Score: %d" % team_score)


func _destroy_gate() -> void:
	gate_destroyed = true
	if gate_sprite != null and is_instance_valid(gate_sprite):
		_gate_explosion(gate_pos)
		gate_sprite.queue_free()
		gate_sprite = null
	banner_label.text = "GATE 1 DESTROYED" if story_stage_number >= 2 else "GATE DESTROYED"
	_check_stage_clear()


func _destroy_gate2() -> void:
	gate2_destroyed = true
	if gate2_sprite != null and is_instance_valid(gate2_sprite):
		_gate_explosion(gate2_pos)
		gate2_sprite.queue_free()
		gate2_sprite = null
	banner_label.text = "GATE 2 DESTROYED"
	_check_stage_clear()


func _destroy_gate3() -> void:
	gate3_destroyed = true
	if gate3_sprite != null and is_instance_valid(gate3_sprite):
		_gate_explosion(gate3_pos)
		gate3_sprite.queue_free()
		gate3_sprite = null
	banner_label.text = "GATE 3 DESTROYED"
	_check_stage_clear()


func _spawn_item() -> void:
	# Weighted pool: heal×3, rapid_fire×2, shield×2, power_boost×2, link_charge×1 = 10 total
	# In solo mode, link_charge is omitted (no partner to fuse with)
	var pool: Array[String]
	pool = [
		"heal", "heal", "heal",
		"rapid_fire", "rapid_fire",
		"shield", "shield",
		"power_boost", "power_boost",
	]
	var key: String = pool[rng.randi_range(0, pool.size() - 1)]
	var pos := Vector2(rng.randf_range(120.0, screen_size.x - 120.0), rng.randf_range(160.0, screen_size.y - 180.0))
	var sprite := AssetPaths.create_sprite(AssetPaths.ITEMS[key], Vector2(76, 76), Color(0.2, 1.0, 0.7), 12)
	sprite.position = pos
	add_child(sprite)
	var id := _next_entity_id()
	items.append({"id": id, "key": key, "pos": pos, "sprite": sprite, "radius": 42.0})
	if online_game_active:
		_send_game_event({"event": "item_spawn", "id": id, "key": key, "x": pos.x, "y": pos.y})

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
			# Restore 1 life to the collecting pilot
			var _pi := int(p["id"]) - 1
			if _pi >= 0 and _pi < player_lives.size():
				player_lives[_pi] = mini(player_lives[_pi] + 1, PLAYER_LIVES_MAX)
			if audio_manager != null:
				audio_manager.play_sfx("item_heal", -5.0)

		"rapid_fire":
			p["rapid"] = 6.0
			if audio_manager != null:
				audio_manager.play_sfx("item_rapid_fire", -5.0)

		"shield":
			# Grant personal invincibility to the collector
			var _spi := player_id - 1
			if _spi >= 0 and _spi < player_inv_timer.size():
				player_inv_timer[_spi] = maxf(player_inv_timer[_spi], 5.0)
			_spawn_effect(AssetPaths.EFFECTS["shield_bubble"], p["pos"], Vector2(200, 200), 0.55)
			if audio_manager != null:
				audio_manager.play_sfx("item_shield", -5.0)
				audio_manager.play_sfx("shield_activate", -5.0)

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



func _update_story_hud_bar() -> void:
	if story_hud_container == null:
		return
	# Core and shield bars hidden (no core HP mechanic)
	story_core_bar_bg.visible    = false
	story_core_bar_fill.visible  = false
	story_core_label.visible     = false
	story_shield_bar_bg.visible  = false
	story_shield_bar_fill.visible = false
	story_shield_label.visible   = false

	# ── Score ────────────────────────────────────────────────────────
	story_score_label.text = "%d" % team_score

	# ── Player lives (segmented bar) ─────────────────────────────────
	for _si in range(story_p1_life_segs.size()):
		var _active := _si < player_lives[0]
		var _low := player_lives[0] <= 2
		(story_p1_life_segs[_si] as ColorRect).color = \
			(Color(1.0, 0.18, 0.12) if _low else Color(0.15, 0.55, 1.0)) if _active else Color(0.02, 0.04, 0.12)
		(story_p1_life_hi[_si] as ColorRect).color.a = 0.60 if _active else 0.0
	for _si in range(story_p2_life_segs.size()):
		var _active := _si < player_lives[1]
		var _low := player_lives[1] <= 2
		(story_p2_life_segs[_si] as ColorRect).color = \
			(Color(1.0, 0.28, 0.05) if _low else Color(0.95, 0.70, 0.05)) if _active else Color(0.14, 0.09, 0.02)
		(story_p2_life_hi[_si] as ColorRect).color.a = 0.60 if _active else 0.0
	for _si in range(story_p3_life_segs.size()):
		var _active := _si < player_lives[2]
		var _low := player_lives[2] <= 2
		(story_p3_life_segs[_si] as ColorRect).color = \
			(Color(0.20, 1.0, 0.15) if _low else Color(0.15, 0.95, 0.30)) if _active else Color(0.04, 0.10, 0.04)
		(story_p3_life_hi[_si] as ColorRect).color.a = 0.60 if _active else 0.0
	for _si in range(story_p4_life_segs.size()):
		var _active := _si < player_lives[3]
		var _low := player_lives[3] <= 2
		(story_p4_life_segs[_si] as ColorRect).color = \
			(Color(1.0, 0.20, 1.0) if _low else Color(0.70, 0.20, 1.0)) if _active else Color(0.10, 0.04, 0.14)
		(story_p4_life_hi[_si] as ColorRect).color.a = 0.60 if _active else 0.0

	# ── Gate HP bar ──────────────────────────────────────────────────
	if story_gate_bar_fill != null and story_gate_label != null:
		var _max_hp1: int
		if story_stage_number >= 4: _max_hp1 = GATE_HP_MAX_S4
		elif story_stage_number >= 3: _max_hp1 = GATE_HP_MAX_S3
		elif story_stage_number == 2: _max_hp1 = GATE_HP_MAX_S2
		else: _max_hp1 = GATE_HP_MAX_S1
		var _gate_ratio := clampf(float(gate_hp) / float(_max_hp1), 0.0, 1.0)
		story_gate_bar_fill.size.x = 140.0 * _gate_ratio
		var _gr := 0.85 + 0.15 * _gate_ratio
		var _gg := _gate_ratio * 0.55
		story_gate_bar_fill.color = Color(_gr, _gg, 0.05)
		if gate_sprite != null or gate_destroyed:
			story_gate_label.text = "%d/%d" % [gate_hp, _max_hp1]
		else:
			story_gate_label.text = "---"

	if story_stage_number >= 2 and story_gate2_bar_fill != null and story_gate2_label != null:
		var _max_hp2 := GATE_HP_MAX_S3 if story_stage_number >= 3 else GATE_HP_MAX_S2
		var _gate2_ratio := clampf(float(gate2_hp) / float(_max_hp2), 0.0, 1.0)
		story_gate2_bar_fill.size.x = 140.0 * _gate2_ratio
		var _gr2 := 0.85 + 0.15 * _gate2_ratio
		var _gg2 := _gate2_ratio * 0.55
		story_gate2_bar_fill.color = Color(_gr2, _gg2, 0.05)
		if gate2_sprite != null or gate2_destroyed:
			story_gate2_label.text = "%d/%d" % [gate2_hp, _max_hp2]
		else:
			story_gate2_label.text = "---"

	if story_stage_number >= 3 and story_gate3_bar_fill != null and story_gate3_label != null:
		var _gate3_ratio := clampf(float(gate3_hp) / float(GATE_HP_MAX_S3), 0.0, 1.0)
		story_gate3_bar_fill.size.x = 140.0 * _gate3_ratio
		var _gr3 := 0.85 + 0.15 * _gate3_ratio
		var _gg3 := _gate3_ratio * 0.55
		story_gate3_bar_fill.color = Color(_gr3, _gg3, 0.05)
		if gate3_sprite != null or gate3_destroyed:
			story_gate3_label.text = "%d/%d" % [gate3_hp, GATE_HP_MAX_S3]
		else:
			story_gate3_label.text = "---"

	# Link/Fusion bar hidden (no fusion mechanic)
	story_link_container.visible = false



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
	var show_next := title.find("STAGE 1 CLEAR") >= 0 or title.find("STAGE 2 CLEAR") >= 0 or title.find("STAGE 3 CLEAR") >= 0
	if result_next_stage_button != null:
		result_next_stage_button.visible = show_next
	_layout_result_buttons(show_next)


func _layout_result_buttons(show_next_stage: bool) -> void:
	if result_next_stage_button != null:
		result_next_stage_button.visible = show_next_stage


class _DebugDraw extends Node2D:
	var main_ref: Node

	func _draw() -> void:
		if main_ref == null or not main_ref._debug_active():
			return

		var player_colors := [Color(0.0, 1.0, 1.0, 0.45), Color(1.0, 0.65, 0.0, 0.45)]
		for i in range((main_ref.players as Array).size()):
			var p: Dictionary = (main_ref.players as Array)[i]
			var col: Color = player_colors[i] if i < player_colors.size() else Color(0.0, 1.0, 1.0, 0.45)
			draw_circle(p["pos"], float(p["radius"]), col)
			draw_arc(p["pos"], float(p["radius"]), 0.0, TAU, 32, col.lightened(0.5), 1.5)

		for e in (main_ref.enemies as Array):
			draw_circle(e["pos"], float(e["radius"]), Color(1.0, 0.2, 0.2, 0.35))
			draw_arc(e["pos"], float(e["radius"]), 0.0, TAU, 32, Color(1.0, 0.3, 0.3, 0.9), 1.5)

		for b in (main_ref.bullets as Array):
			draw_circle(b["pos"], float(b["radius"]), Color(1.0, 1.0, 0.0, 0.55))

		for eb in (main_ref.enemy_bullets as Array):
			draw_circle(eb["pos"], float(eb["radius"]), Color(1.0, 0.2, 1.0, 0.55))

		var core_spr: Node = main_ref.base_sprite
		if core_spr != null:
			var cpos: Vector2 = (core_spr as Node2D).position
			draw_circle(cpos, 42.0, Color(0.4, 0.8, 1.0, 0.30))
			draw_arc(cpos, 42.0, 0.0, TAU, 48, Color(0.4, 0.8, 1.0, 0.95), 2.0)

		for item in (main_ref.items as Array):
			draw_circle(item["pos"], float(item["radius"]), Color(0.2, 1.0, 0.4, 0.35))
			draw_arc(item["pos"], float(item["radius"]), 0.0, TAU, 32, Color(0.3, 1.0, 0.5, 0.9), 1.5)


func _debug_active() -> bool:
	return debug_show_hitboxes and mode != GameMode.TITLE


func _setup_debug_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 99
	add_child(canvas)
	_dbg_node = _DebugDraw.new()
	(_dbg_node as _DebugDraw).main_ref = self
	canvas.add_child(_dbg_node)


# ─── Player ship rebuild ──────────────────────────────────────────────────────

func _rebuild_player_ships() -> void:
	const _SHIP_PATHS: Array[String] = ["p1", "p2", "p3", "p4"]
	const _SHIP_COLORS: Array[Color] = [
		Color(0.2, 0.85, 1.0), Color(1.0, 0.66, 0.18),
		Color(0.15, 1.0, 0.35), Color(0.75, 0.25, 1.0)
	]
	for p in players:
		var _pid: int = int(p["id"]) - 1
		var _sid: int = clampi(int(player_ship_map[_pid] if _pid < player_ship_map.size() else _pid + 1) - 1, 0, _SHIP_PATHS.size() - 1)
		var _path: String = AssetPaths.PLAYERS[_SHIP_PATHS[_sid]]
		var _col: Color = _SHIP_COLORS[_sid]
		(p["sprite"] as Sprite2D).texture = AssetPaths.load_texture(_path, _col)
		var _spec := _get_player_spec(_pid + 1)
		p["base_speed"]     = float(_spec["speed"])
		p["speed"]          = float(_spec["speed"])
		p["shoot_interval"] = float(_spec["shoot_interval"])
		p["rapid_interval"] = float(_spec["rapid_interval"])
		p["damage"]         = int(_spec["damage"])
		p["bullet_size"]    = float(_spec["bullet_size"])
		p["power_mode"]     = str(_spec["power_mode"])
		if _pid < player_name_map.size():
			p["name"] = player_name_map[_pid]


# ─── Story Mode Select ────────────────────────────────────────────────────────

func _setup_story_mode_select() -> void:
	story_mode_select_layer = CanvasLayer.new()
	story_mode_select_layer.layer = 22
	story_mode_select_layer.visible = false
	add_child(story_mode_select_layer)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.00, 0.02, 0.07, 0.95)
	story_mode_select_layer.add_child(bg)

	var title := Label.new()
	title.text = "STORY MODE"
	title.position = Vector2(0, 160)
	title.size = Vector2(screen_size.x, 88)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.18, 1.0, 0.88))
	story_mode_select_layer.add_child(title)

	var sub := Label.new()
	sub.text = "SELECT PLAY STYLE"
	sub.position = Vector2(0, 268)
	sub.size = Vector2(screen_size.x, 36)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color(0.50, 0.72, 0.88))
	story_mode_select_layer.add_child(sub)

	var bw := 420.0
	var bh := 120.0
	var cx := screen_size.x * 0.5
	var by := 360.0
	var gap := 60.0

	var s_btn := _create_premium_button("SINGLE PLAYER", Vector2(cx - bw - gap * 0.5, by), Vector2(bw, bh))
	s_btn.pressed.connect(_on_story_single_selected)
	story_mode_select_layer.add_child(s_btn)

	var m_btn := _create_premium_button("MULTI PLAYER", Vector2(cx + gap * 0.5, by), Vector2(bw, bh))
	m_btn.pressed.connect(_on_story_multi_selected)
	story_mode_select_layer.add_child(m_btn)

	var desc_s := Label.new()
	desc_s.text = "Solo — fight alone\nChoose your ship from 4 types"
	desc_s.position = Vector2(cx - bw - gap * 0.5, by + bh + 12.0)
	desc_s.size = Vector2(bw, 60)
	desc_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_s.add_theme_font_size_override("font_size", 18)
	desc_s.add_theme_color_override("font_color", Color(0.50, 0.72, 0.88))
	story_mode_select_layer.add_child(desc_s)

	var desc_m := Label.new()
	desc_m.text = "2–4 players local co-op\nP1:WASD+F  P2:Arrow+L  P3:Numpad"
	desc_m.position = Vector2(cx + gap * 0.5, by + bh + 12.0)
	desc_m.size = Vector2(bw, 60)
	desc_m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_m.add_theme_font_size_override("font_size", 18)
	desc_m.add_theme_color_override("font_color", Color(0.50, 0.72, 0.88))
	story_mode_select_layer.add_child(desc_m)

	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.position = Vector2(cx - 130.0, by + bh + 110.0)
	back_btn.size = Vector2(260, 56)
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.pressed.connect(func():
		story_mode_select_layer.visible = false
		title_layer.visible = true
	)
	story_mode_select_layer.add_child(back_btn)


func _show_story_mode_select() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("ui_select", -8.0)
	title_layer.visible = false
	story_mode_select_layer.visible = true


func _on_story_single_selected() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("ui_confirm", -6.0)
	story_mode_select_layer.visible = false
	char_select_mode = "single"
	_cs_configs[0]["joined"] = true
	_cs_configs[0]["ready"] = false
	_cs_configs[1]["joined"] = false
	_solo_cs_idx = clampi(int(_cs_configs[0].get("ship_id", 1)) - 1, 0, 3)
	_update_char_select()
	char_select_layer.visible = true


func _on_story_multi_selected() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("ui_confirm", -6.0)
	story_mode_select_layer.visible = false
	char_select_mode = "multi"
	_cs_configs[0]["joined"] = true;  _cs_configs[0]["ready"] = false
	for _mi in range(1, 4):
		_cs_configs[_mi]["joined"] = false
		_cs_configs[_mi]["ready"] = false
	_update_char_select()
	char_select_layer.visible = true


# ─── Character Select ─────────────────────────────────────────────────────────

const _CS_SHIP_NAMES := ["Azure Wing", "Solar Fang", "Emerald Claw", "Violet Phantom"]
const _CS_SHIP_COLORS := [Color(0.20, 0.85, 1.00), Color(1.00, 0.66, 0.18), Color(0.15, 1.00, 0.35), Color(0.75, 0.25, 1.00)]
const _CS_PREVIEW_PATHS: Array[String] = [
	"res://assets/players/player_azure_wing.png",
	"res://assets/players/player_solar_fang.png",
	"res://assets/players/player_emerald_claw.png",
	"res://assets/players/player_violet_phantom.png",
]
const _CS_SHIP_DESCS: Array[String] = [
	"A balanced all-rounder ready for any mission. Reliable speed and a steady fire rate make it the ideal first choice for pilots of all skill levels.",
	"A heavy assault striker built for pure power. Each shot delivers devastating damage — but its slow reload demands precise, deliberate timing.",
	"A speed-focused interceptor with lightning reflexes. Rapid-fire bursts and elite mobility let it weave through even the densest bullet storms.",
	"An obliterator-class gunship packing the heaviest ordnance available. One clean shot changes the fight — but patience is the price you pay.",
]

func _setup_char_select() -> void:
	char_select_layer = CanvasLayer.new()
	char_select_layer.layer = 23
	char_select_layer.visible = false
	add_child(char_select_layer)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.00, 0.02, 0.07, 0.96)
	char_select_layer.add_child(bg)

	var title := Label.new()
	title.text = "CHARACTER SELECT"
	title.position = Vector2(0, 30)
	title.size = Vector2(screen_size.x, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.18, 1.0, 0.88))
	char_select_layer.add_child(title)

	# Room area — shown for DOUBLE mode only
	_cs_room_area = Control.new()
	_cs_room_area.position = Vector2(0, 106)
	_cs_room_area.size = Vector2(screen_size.x, 50)
	char_select_layer.add_child(_cs_room_area)

	_cs_room_lbl = Label.new()
	_cs_room_lbl.text = "ROOM: ----"
	_cs_room_lbl.position = Vector2(screen_size.x * 0.5 - 440, 10)
	_cs_room_lbl.size = Vector2(200, 32)
	_cs_room_lbl.add_theme_font_size_override("font_size", 24)
	_cs_room_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_cs_room_area.add_child(_cs_room_lbl)

	var create_btn := Button.new()
	create_btn.text = "CREATE ROOM"
	create_btn.position = Vector2(screen_size.x * 0.5 - 230, 8)
	create_btn.size = Vector2(220, 36)
	create_btn.add_theme_font_size_override("font_size", 18)
	create_btn.pressed.connect(_on_cs_create_room)
	_cs_room_area.add_child(create_btn)

	_cs_join_edit = LineEdit.new()
	_cs_join_edit.placeholder_text = "ROOM CODE"
	_cs_join_edit.position = Vector2(screen_size.x * 0.5 + 0, 8)
	_cs_join_edit.size = Vector2(140, 36)
	_cs_join_edit.max_length = 4
	_cs_join_edit.add_theme_font_size_override("font_size", 18)
	_cs_room_area.add_child(_cs_join_edit)

	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.position = Vector2(screen_size.x * 0.5 + 150, 8)
	join_btn.size = Vector2(90, 36)
	join_btn.add_theme_font_size_override("font_size", 18)
	join_btn.pressed.connect(_on_cs_join_room)
	_cs_room_area.add_child(join_btn)

	# Player panels (4 slots always created; visibility controlled by mode)
	_cs_panels.clear(); _cs_ship_btns.clear(); _cs_ship_imgs.clear()
	_cs_name_edits.clear(); _cs_status_lbls.clear(); _cs_ready_btns.clear()
	_cs_active_btns.clear(); _cs_ship_opts.clear(); _cs_ctrl_btns.clear()
	const PANEL_W := 440.0
	const PANEL_H := 540.0
	const PANEL_GAP := 20.0
	var panel_y := 174.0
	for _si in range(4):
		var _panel := _cs_make_panel(_si, 0.0, panel_y, PANEL_W, PANEL_H)
		char_select_layer.add_child(_panel)
		_cs_panels.append(_panel)

	# ── CPU Difficulty row ──────────────────────────────────────────────
	var diff_row_y := panel_y + PANEL_H + 16.0
	var diff_lbl := Label.new()
	diff_lbl.text = "CPU DIFFICULTY"
	diff_lbl.position = Vector2(screen_size.x * 0.5 - 380.0, diff_row_y + 12)
	diff_lbl.size = Vector2(220, 32)
	diff_lbl.add_theme_font_size_override("font_size", 17)
	diff_lbl.add_theme_color_override("font_color", Color(0.55, 0.72, 0.88))
	diff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	char_select_layer.add_child(diff_lbl)

	const DIFF_LABELS: Array[String] = ["EASY", "NORMAL", "HARD", "EXPERT"]
	const DIFF_COLORS: Array[Color]  = [Color(0.30, 1.00, 0.40), Color(0.95, 0.85, 0.20), Color(1.00, 0.50, 0.10), Color(1.00, 0.20, 0.20)]
	_cs_diff_btns.clear()
	for _di in range(4):
		var _db := Button.new()
		_db.text = DIFF_LABELS[_di]
		_db.position = Vector2(screen_size.x * 0.5 - 150.0 + _di * 82.0, diff_row_y)
		_db.size = Vector2(74, 52)
		_db.add_theme_font_size_override("font_size", 15)
		_db.pressed.connect(_on_cs_diff_selected.bind(_di))
		char_select_layer.add_child(_db)
		_cs_diff_btns.append(_db)

	# START and BACK buttons
	var btn_y := panel_y + PANEL_H + 86.0
	_cs_start_btn = _create_premium_button("START GAME", Vector2(screen_size.x * 0.5 - 220.0, btn_y), Vector2(440.0, 70.0))
	_cs_start_btn.pressed.connect(_on_cs_start_game)
	char_select_layer.add_child(_cs_start_btn)

	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.position = Vector2(screen_size.x * 0.5 + 240.0, btn_y + 10.0)
	back_btn.size = Vector2(160, 50)
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.pressed.connect(_on_cs_back)
	char_select_layer.add_child(back_btn)

	# Solo mode slide carousel (built once, shown/hidden by mode)
	_setup_solo_carousel()

	# Connect network signals
	if network_client != null:
		if not network_client.peer_joined.is_connected(_on_cs_peer_joined):
			network_client.peer_joined.connect(_on_cs_peer_joined)
		if not network_client.room_changed.is_connected(_on_cs_room_changed):
			network_client.room_changed.connect(_on_cs_room_changed)


func _setup_solo_carousel() -> void:
	_solo_carousel = Control.new()
	_solo_carousel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_solo_carousel.visible = false
	char_select_layer.add_child(_solo_carousel)

	var cx := screen_size.x * 0.5
	const PREVIEW_Y := 120.0
	const PREVIEW_SZ := 280.0

	# Ship preview image
	_solo_preview_img = TextureRect.new()
	_solo_preview_img.position = Vector2(cx - PREVIEW_SZ * 0.5, PREVIEW_Y)
	_solo_preview_img.size = Vector2(PREVIEW_SZ, PREVIEW_SZ)
	_solo_preview_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_solo_preview_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_solo_carousel.add_child(_solo_preview_img)

	# Left / right arrow buttons
	var left_btn := Button.new()
	left_btn.text = "◀"
	left_btn.position = Vector2(cx - 380.0, PREVIEW_Y + PREVIEW_SZ * 0.5 - 44.0)
	left_btn.size = Vector2(88.0, 88.0)
	left_btn.add_theme_font_size_override("font_size", 38)
	left_btn.pressed.connect(func(): _solo_cs_navigate(-1))
	_solo_carousel.add_child(left_btn)

	var right_btn := Button.new()
	right_btn.text = "▶"
	right_btn.position = Vector2(cx + 292.0, PREVIEW_Y + PREVIEW_SZ * 0.5 - 44.0)
	right_btn.size = Vector2(88.0, 88.0)
	right_btn.add_theme_font_size_override("font_size", 38)
	right_btn.pressed.connect(func(): _solo_cs_navigate(1))
	_solo_carousel.add_child(right_btn)

	# Mouse drag area (swipe left/right over the preview)
	var drag_area := Control.new()
	drag_area.position = Vector2(cx - PREVIEW_SZ * 0.5, PREVIEW_Y)
	drag_area.size = Vector2(PREVIEW_SZ, PREVIEW_SZ)
	drag_area.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_area.gui_input.connect(_on_solo_carousel_drag)
	_solo_carousel.add_child(drag_area)

	# Ship name
	_solo_name_lbl = Label.new()
	_solo_name_lbl.position = Vector2(0.0, PREVIEW_Y + PREVIEW_SZ + 20.0)
	_solo_name_lbl.size = Vector2(screen_size.x, 60.0)
	_solo_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_solo_name_lbl.add_theme_font_size_override("font_size", 48)
	_solo_carousel.add_child(_solo_name_lbl)

	# Dot indicators (4 dots)
	_solo_dots.clear()
	for _di in range(4):
		var dot := ColorRect.new()
		dot.size = Vector2(14.0, 14.0)
		dot.position = Vector2(cx - 27.0 + _di * 18.0, PREVIEW_Y + PREVIEW_SZ + 90.0)
		dot.color = Color(0.25, 0.35, 0.50)
		_solo_carousel.add_child(dot)
		_solo_dots.append(dot)

	# Stat bars: SPEED, POWER, FIRE RATE
	const STAT_NAMES := ["SPEED", "POWER", "FIRE RATE"]
	const STAT_COLORS: Array[Color] = [
		Color(0.20, 0.90, 1.00),
		Color(1.00, 0.42, 0.18),
		Color(0.22, 1.00, 0.52),
	]
	const BAR_W := 280.0
	_solo_stat_bars.clear()
	for _si in range(3):
		var _sy := PREVIEW_Y + PREVIEW_SZ + 118.0 + _si * 42.0
		var _lbl := Label.new()
		_lbl.text = STAT_NAMES[_si]
		_lbl.position = Vector2(cx - 240.0, _sy)
		_lbl.size = Vector2(110.0, 30.0)
		_lbl.add_theme_font_size_override("font_size", 17)
		_lbl.add_theme_color_override("font_color", Color(0.55, 0.72, 0.88))
		_solo_carousel.add_child(_lbl)

		var _bg := ColorRect.new()
		_bg.position = Vector2(cx - 120.0, _sy + 5.0)
		_bg.size = Vector2(BAR_W, 20.0)
		_bg.color = Color(0.06, 0.10, 0.16)
		_solo_carousel.add_child(_bg)

		var _fill := ColorRect.new()
		_fill.position = Vector2(cx - 120.0, _sy + 5.0)
		_fill.size = Vector2(0.0, 20.0)
		_fill.color = STAT_COLORS[_si]
		_solo_carousel.add_child(_fill)
		_solo_stat_bars.append(_fill)

	# Description text
	_solo_desc_lbl = Label.new()
	_solo_desc_lbl.position = Vector2(cx - 440.0, PREVIEW_Y + PREVIEW_SZ + 252.0)
	_solo_desc_lbl.size = Vector2(880.0, 80.0)
	_solo_desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_solo_desc_lbl.add_theme_font_size_override("font_size", 20)
	_solo_desc_lbl.add_theme_color_override("font_color", Color(0.78, 0.88, 0.95))
	_solo_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_solo_carousel.add_child(_solo_desc_lbl)

	# START GAME and BACK buttons
	const BTN_Y := 820.0
	var start_btn := _create_premium_button(
		"START GAME", Vector2(cx - 220.0, BTN_Y), Vector2(440.0, 70.0))
	start_btn.pressed.connect(_on_cs_start_game)
	_solo_carousel.add_child(start_btn)

	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.position = Vector2(cx + 240.0, BTN_Y + 10.0)
	back_btn.size = Vector2(160.0, 50.0)
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.pressed.connect(_on_cs_back)
	_solo_carousel.add_child(back_btn)

	_update_solo_carousel()


func _update_solo_carousel() -> void:
	if _solo_carousel == null:
		return
	var idx := clampi(_solo_cs_idx, 0, 3)
	_cs_configs[0]["ship_id"] = idx + 1

	# Ship image — use AssetPaths.load_texture so PNGs without .import still load
	if _solo_preview_img != null:
		_solo_preview_img.texture = AssetPaths.load_texture(
			_CS_PREVIEW_PATHS[idx], _CS_SHIP_COLORS[idx], Vector2i(280, 280))

	# Name + colour
	if _solo_name_lbl != null:
		_solo_name_lbl.text = _CS_SHIP_NAMES[idx]
		_solo_name_lbl.add_theme_color_override("font_color", _CS_SHIP_COLORS[idx])

	# Dot indicators
	for _di in range(_solo_dots.size()):
		var _dot := _solo_dots[_di] as ColorRect
		_dot.color = _CS_SHIP_COLORS[idx] if _di == idx else Color(0.18, 0.26, 0.38)
		_dot.size = Vector2(18.0, 18.0) if _di == idx else Vector2(12.0, 12.0)

	# Stat bars — values come from top-of-file SHIP_STATS_* constants
	const _STATS_TABLE: Array = [
		SHIP_STATS_AZURE_WING,
		SHIP_STATS_SOLAR_FANG,
		SHIP_STATS_EMERALD_CLAW,
		SHIP_STATS_VIOLET_PHANTOM,
	]
	const BAR_W := 280.0
	var _sv: Array = _STATS_TABLE[idx]
	for _si in range(_solo_stat_bars.size()):
		var _bar := _solo_stat_bars[_si] as ColorRect
		_bar.size.x = BAR_W * float(_sv[_si])

	# Description
	if _solo_desc_lbl != null:
		_solo_desc_lbl.text = _CS_SHIP_DESCS[idx]


func _solo_cs_navigate(dir: int) -> void:
	_solo_cs_idx = (_solo_cs_idx + dir + 4) % 4
	if audio_manager != null:
		audio_manager.play_sfx("ui_select", -6.0)
	_update_solo_carousel()


func _on_solo_carousel_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var _mb := event as InputEventMouseButton
		if _mb.button_index == MOUSE_BUTTON_LEFT:
			if _mb.pressed:
				_solo_drag_start_x = _mb.position.x
			elif _solo_drag_start_x >= 0.0:
				var _dx := _mb.position.x - _solo_drag_start_x
				if _dx < -40.0:
					_solo_cs_navigate(1)
				elif _dx > 40.0:
					_solo_cs_navigate(-1)
				_solo_drag_start_x = -1.0


func _cs_make_panel(slot: int, px: float, py: float, pw: float, ph: float) -> Control:
	const SLOT_COLORS: Array[Color] = [Color(0.20, 0.85, 1.00), Color(1.00, 0.66, 0.18), Color(0.15, 1.00, 0.35), Color(0.75, 0.25, 1.00)]
	var slot_col: Color = SLOT_COLORS[clampi(slot, 0, SLOT_COLORS.size() - 1)]

	var panel := Control.new()
	panel.position = Vector2(px, py)
	panel.size = Vector2(pw, ph)

	var border := ColorRect.new()
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.color = Color(slot_col.r, slot_col.g, slot_col.b, 0.22)
	panel.add_child(border)

	var inner := ColorRect.new()
	inner.position = Vector2(2, 2)
	inner.size = Vector2(pw - 4, ph - 4)
	inner.color = Color(0.04, 0.06, 0.12)
	panel.add_child(inner)

	# ── Active toggle (P1 = always active) ──────────────────────────
	var is_joined: bool = bool(_cs_configs[slot].get("joined", false))
	var active_btn := Button.new()
	active_btn.text = "P%d  ●  ACTIVE" % (slot + 1) if is_joined else "P%d  —  ACTIVATE" % (slot + 1)
	active_btn.position = Vector2(12, 10)
	active_btn.size = Vector2(pw - 24, 52)
	active_btn.add_theme_font_size_override("font_size", 21)
	if is_joined:
		active_btn.add_theme_color_override("font_color", slot_col)
	active_btn.pressed.connect(_on_cs_active_toggled.bind(slot))
	panel.add_child(active_btn)
	_cs_active_btns.append(active_btn)

	# ── Name input ───────────────────────────────────────────────────
	var name_lbl := Label.new()
	name_lbl.text = "NAME"
	name_lbl.position = Vector2(14, 76)
	name_lbl.size = Vector2(70, 28)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.55, 0.72, 0.88))
	panel.add_child(name_lbl)

	var name_edit := LineEdit.new()
	name_edit.text = str(_cs_configs[slot].get("name", "PLAYER %d" % (slot + 1)))
	name_edit.position = Vector2(90, 74)
	name_edit.size = Vector2(pw - 104, 32)
	name_edit.max_length = 16
	name_edit.add_theme_font_size_override("font_size", 18)
	name_edit.text_changed.connect(func(t: String): _cs_on_name_changed(slot, t))
	panel.add_child(name_edit)
	_cs_name_edits.append(name_edit)

	# ── Ship dropdown (OptionButton) ─────────────────────────────────
	var ship_lbl := Label.new()
	ship_lbl.text = "SHIP"
	ship_lbl.position = Vector2(14, 120)
	ship_lbl.size = Vector2(70, 28)
	ship_lbl.add_theme_font_size_override("font_size", 16)
	ship_lbl.add_theme_color_override("font_color", Color(0.55, 0.72, 0.88))
	panel.add_child(ship_lbl)

	var ship_opt := OptionButton.new()
	for _shi in range(4):
		ship_opt.add_item(_CS_SHIP_NAMES[_shi])
	var _init_ship := clampi(int(_cs_configs[slot].get("ship_id", slot + 1)) - 1, 0, 3)
	ship_opt.selected = _init_ship
	ship_opt.position = Vector2(90, 116)
	ship_opt.size = Vector2(pw - 104, 36)
	ship_opt.add_theme_font_size_override("font_size", 17)
	ship_opt.item_selected.connect(_on_cs_ship_option.bind(slot))
	panel.add_child(ship_opt)
	_cs_ship_opts.append(ship_opt)
	_cs_ship_btns.append([])  # size parity only

	# ── Ship preview image ────────────────────────────────────────────
	var preview_img := TextureRect.new()
	preview_img.position = Vector2(pw * 0.5 - 56, 162)
	preview_img.size = Vector2(112, 112)
	preview_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_img.texture = AssetPaths.load_texture(_CS_PREVIEW_PATHS[_init_ship], _CS_SHIP_COLORS[_init_ship], Vector2i(112, 112))
	panel.add_child(preview_img)
	_cs_ship_imgs.append(preview_img)

	# ── Control type: PLAYER / CPU ────────────────────────────────────
	var ctrl_lbl := Label.new()
	ctrl_lbl.text = "CONTROL"
	ctrl_lbl.position = Vector2(14, 286)
	ctrl_lbl.size = Vector2(pw - 20, 24)
	ctrl_lbl.add_theme_font_size_override("font_size", 15)
	ctrl_lbl.add_theme_color_override("font_color", Color(0.55, 0.72, 0.88))
	panel.add_child(ctrl_lbl)

	var half_w := (pw - 36.0) * 0.5
	var human_btn := Button.new()
	human_btn.text = "PLAYER"
	human_btn.position = Vector2(12, 314)
	human_btn.size = Vector2(half_w, 38)
	human_btn.add_theme_font_size_override("font_size", 17)
	human_btn.pressed.connect(_on_cs_ctrl_toggled.bind(slot, false))
	panel.add_child(human_btn)

	var cpu_btn := Button.new()
	cpu_btn.text = "CPU"
	cpu_btn.position = Vector2(12.0 + half_w + 12.0, 314)
	cpu_btn.size = Vector2(half_w, 38)
	cpu_btn.add_theme_font_size_override("font_size", 17)
	cpu_btn.pressed.connect(_on_cs_ctrl_toggled.bind(slot, true))
	panel.add_child(cpu_btn)
	_cs_ctrl_btns.append([human_btn, cpu_btn])

	# ── Status label ──────────────────────────────────────────────────
	var status_lbl := Label.new()
	status_lbl.text = "Waiting..."
	status_lbl.position = Vector2(0, ph - 118)
	status_lbl.size = Vector2(pw, 34)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 20)
	status_lbl.add_theme_color_override("font_color", Color(0.60, 0.70, 0.80))
	panel.add_child(status_lbl)
	_cs_status_lbls.append(status_lbl)

	# ── Ready button ──────────────────────────────────────────────────
	var ready_btn := Button.new()
	ready_btn.text = "READY"
	ready_btn.position = Vector2(12, ph - 76)
	ready_btn.size = Vector2(pw - 24, 58)
	ready_btn.add_theme_font_size_override("font_size", 24)
	ready_btn.pressed.connect(_on_cs_ready_toggled.bind(slot))
	panel.add_child(ready_btn)
	_cs_ready_btns.append(ready_btn)

	return panel


func _on_cs_active_toggled(slot: int) -> void:
	if slot == 0:
		return  # P1 always active
	var cfg: Dictionary = _cs_configs[slot]
	var was_joined: bool = bool(cfg.get("joined", false))
	cfg["joined"] = not was_joined
	if was_joined:
		cfg["ready"] = false
	_update_char_select()
	_cs_broadcast()


func _on_cs_ship_option(idx: int, slot: int) -> void:
	_cs_configs[slot]["ship_id"] = idx + 1
	_update_char_select()
	_cs_broadcast()


func _on_cs_ctrl_toggled(slot: int, is_cpu: bool) -> void:
	_cs_configs[slot]["is_cpu"] = is_cpu
	_update_char_select()
	_cs_broadcast()


func _on_cs_diff_selected(level: int) -> void:
	cpu_difficulty = clampi(level, 0, 3)
	_update_char_select()


func _cs_on_name_changed(slot: int, text: String) -> void:
	_cs_configs[slot]["name"] = text
	_cs_broadcast()


func _update_char_select() -> void:
	if char_select_layer == null:
		return
	var is_multi  := char_select_mode == "multi"
	var is_single := char_select_mode == "single"

	# Single mode uses the dedicated carousel — skip the panel layout entirely
	if _solo_carousel != null:
		_solo_carousel.visible = is_single
	if is_single:
		for _sp in _cs_panels:
			(_sp as Control).visible = false
		if _cs_start_btn != null:
			_cs_start_btn.visible = false
		_cs_room_area.visible = false
		for _db in _cs_diff_btns:
			(_db as Button).visible = false
		_update_solo_carousel()
		return

	# Multi mode: room area hidden (local-only)
	_cs_room_area.visible = false

	# All 4 panels visible in multi mode
	const PANEL_W := 440.0
	const PANEL_GAP := 20.0
	const SHOWN := 4
	var total_w := PANEL_W * SHOWN + PANEL_GAP * (SHOWN - 1)
	var start_x := screen_size.x * 0.5 - total_w * 0.5
	for si in range(_cs_panels.size()):
		var panel := _cs_panels[si] as Control
		panel.visible = true
		panel.position.x = start_x + si * (PANEL_W + PANEL_GAP)

	# Control key hints per slot (shown when unjoined)
	const JOIN_HINTS: Array[String] = [
		"P1  WASD + F",
		"P2  Arrow + L",
		"P3  Numpad 8/4/2/6 + 0",
		"P4  (Controller — soon)",
	]

	for si in range(_cs_panels.size()):
		var panel := _cs_panels[si] as Control
		var cfg: Dictionary = _cs_configs[si]
		var joined: bool = bool(cfg.get("joined", false))
		var ready:  bool = bool(cfg.get("ready",  false))

		# Dim un-joined panels so the player count is obvious at a glance
		panel.modulate = Color(1.0, 1.0, 1.0, 1.0) if joined else Color(0.7, 0.7, 0.8, 0.45)

		(_cs_name_edits[si] as LineEdit).editable = joined
		(_cs_name_edits[si] as LineEdit).modulate.a = 1.0 if joined else 0.5

		var sel_ship := int(cfg.get("ship_id", si + 1))

		# ── Active button appearance ──────────────────────────────────
		if si < _cs_active_btns.size():
			var abtn := _cs_active_btns[si] as Button
			if joined:
				abtn.text = "P%d  ●  ACTIVE" % (si + 1)
				abtn.add_theme_color_override("font_color", _CS_SHIP_COLORS[clampi(si, 0, _CS_SHIP_COLORS.size() - 1)])
			else:
				abtn.text = "P%d  —  ACTIVATE" % (si + 1)
				abtn.remove_theme_color_override("font_color")

		# ── OptionButton ship dropdown ────────────────────────────────
		if si < _cs_ship_opts.size():
			var sopt := _cs_ship_opts[si] as OptionButton
			sopt.disabled = not joined
			var _sidx := clampi(sel_ship - 1, 0, 3)
			if sopt.selected != _sidx:
				sopt.selected = _sidx

		# ── Ship preview ──────────────────────────────────────────────
		if si < _cs_ship_imgs.size():
			var pidx := clampi(sel_ship - 1, 0, _CS_PREVIEW_PATHS.size() - 1)
			var prev := _cs_ship_imgs[si] as TextureRect
			prev.texture = AssetPaths.load_texture(_CS_PREVIEW_PATHS[pidx], _CS_SHIP_COLORS[pidx], Vector2i(112, 112))

		# ── PLAYER / CPU buttons ──────────────────────────────────────
		if si < _cs_ctrl_btns.size():
			var _cbpair := _cs_ctrl_btns[si] as Array
			var _is_cpu := bool(cfg.get("is_cpu", false))
			if _cbpair.size() >= 2:
				(_cbpair[0] as Button).disabled = not joined
				(_cbpair[1] as Button).disabled = not joined
				(_cbpair[0] as Button).modulate = Color(1.0, 1.0, 1.0, 1.0) if (joined and not _is_cpu) else Color(0.45, 0.45, 0.45, 0.8)
				(_cbpair[1] as Button).modulate = Color(1.0, 0.65, 0.15, 1.0) if (joined and _is_cpu) else Color(0.45, 0.45, 0.45, 0.8)

		var status_lbl := _cs_status_lbls[si] as Label
		var ready_btn  := _cs_ready_btns[si]  as Button

		if not joined:
			status_lbl.text = JOIN_HINTS[si]
			status_lbl.add_theme_color_override("font_color", Color(0.38, 0.52, 0.70))
			status_lbl.visible = true
			ready_btn.text    = "JOIN"
			ready_btn.visible = true
		elif ready:
			status_lbl.text = "READY!"
			status_lbl.add_theme_color_override("font_color", Color(0.30, 1.00, 0.45))
			status_lbl.visible = true
			ready_btn.text    = "CANCEL"
			ready_btn.visible = true
		else:
			status_lbl.text = "Press READY when set"
			status_lbl.add_theme_color_override("font_color", Color(0.60, 0.70, 0.80))
			status_lbl.visible = true
			ready_btn.text    = "READY"
			ready_btn.visible = true

	# ── CPU Difficulty button highlights ─────────────────────────────
	const _DIFF_ACTIVE_COLS: Array[Color] = [Color(0.30, 1.00, 0.40), Color(0.95, 0.85, 0.20), Color(1.00, 0.50, 0.10), Color(1.00, 0.20, 0.20)]
	for _di in range(_cs_diff_btns.size()):
		var _db := _cs_diff_btns[_di] as Button
		_db.visible = true
		if _di == cpu_difficulty:
			_db.modulate = Color(1.0, 1.0, 1.0, 1.0)
			_db.add_theme_color_override("font_color", _DIFF_ACTIVE_COLS[_di])
		else:
			_db.modulate = Color(0.45, 0.45, 0.45, 0.8)
			_db.remove_theme_color_override("font_color")

	# START available when at least P1 is ready and all joined players are ready
	_cs_start_btn.visible = _cs_all_joined_ready()


func _cs_is_host() -> bool:
	return not online_game_active or online_local_player_id == 1


func _cs_all_joined_ready() -> bool:
	for si in range(_cs_configs.size()):
		var cfg: Dictionary = _cs_configs[si]
		if bool(cfg.get("joined", false)) and not bool(cfg.get("ready", false)):
			return false
	return true


func _on_cs_ship_selected(slot: int, ship_id: int) -> void:
	_cs_configs[slot]["ship_id"] = ship_id
	_update_char_select()
	_cs_broadcast()


func _on_cs_ready_toggled(slot: int) -> void:
	var cfg: Dictionary = _cs_configs[slot]
	if char_select_mode == "multi" and not bool(cfg.get("joined", false)):
		# First press = JOIN (become active; ship select becomes available)
		cfg["joined"] = true
		cfg["ready"]  = false
	else:
		cfg["ready"] = not bool(cfg.get("ready", false))
	_update_char_select()
	_cs_broadcast()


func _cs_broadcast() -> void:
	if not online_game_active or network_client == null:
		return
	var local_slot: int = maxi(0, online_local_player_id - 1)
	if local_slot >= _cs_configs.size():
		return
	var cfg: Dictionary = _cs_configs[local_slot]
	_send_game_event({
		"event": "char_select",
		"slot": local_slot,
		"name": str(cfg.get("name", "")),
		"ship_id": int(cfg.get("ship_id", local_slot + 1)),
		"ready": bool(cfg.get("ready", false)),
	})


func _recv_char_select(ev: Dictionary) -> void:
	var slot := int(ev.get("slot", 1))
	if slot < 0 or slot >= _cs_configs.size():
		return
	_cs_configs[slot]["name"] = str(ev.get("name", "PLAYER %d" % (slot + 1)))
	_cs_configs[slot]["ship_id"] = int(ev.get("ship_id", slot + 1))
	_cs_configs[slot]["ready"] = bool(ev.get("ready", false))
	_cs_configs[slot]["joined"] = true
	if slot < _cs_name_edits.size():
		(_cs_name_edits[slot] as LineEdit).text = str(_cs_configs[slot]["name"])
	_update_char_select()


func _recv_cs_start(ev: Dictionary) -> void:
	# P2 receives this when host starts the game
	for si in range(mini(ev.get("slot_count", 2), _cs_configs.size())):
		var key := "p%d" % si
		var slot_data: Dictionary = ev.get(key, {}) as Dictionary
		if slot_data.size() > 0:
			_cs_configs[si]["ship_id"] = int(slot_data.get("ship_id", si + 1))
			_cs_configs[si]["name"] = str(slot_data.get("name", "PLAYER %d" % (si + 1)))
	_apply_cs_configs_and_start()


func _on_cs_create_room() -> void:
	if network_client == null:
		return
	if online_lobby != null:
		online_lobby.close_lobby()
	if not network_client.is_connected_to_server():
		network_client.connect_to_server()
		await get_tree().create_timer(1.0).timeout
	network_client.create_room("story")
	online_game_active = true
	online_local_player_id = 1
	_update_char_select()


func _on_cs_join_room() -> void:
	var code := (_cs_join_edit as LineEdit).text.strip_edges().to_upper()
	if code.length() < 1:
		return
	if network_client == null:
		return
	if online_lobby != null:
		online_lobby.close_lobby()
	if not network_client.is_connected_to_server():
		network_client.connect_to_server()
		await get_tree().create_timer(1.0).timeout
	network_client.join_room(code)
	online_game_active = true
	online_local_player_id = 2
	_cs_configs[1]["joined"] = true
	_update_char_select()


func _on_cs_peer_joined(_player_id: int) -> void:
	if char_select_layer != null and char_select_layer.visible:
		_cs_configs[1]["joined"] = true
		_update_char_select()


func _on_cs_room_changed(room_id: String) -> void:
	if char_select_layer != null and char_select_layer.visible:
		_cs_room_lbl.text = "ROOM: %s" % (room_id if room_id != "" else "----")


func _cs_on_room_state(room_state: Dictionary) -> void:
	if room_state.has("room_id"):
		var rid := str(room_state.get("room_id", ""))
		if rid != "" and _cs_room_lbl != null:
			_cs_room_lbl.text = "ROOM: " + rid
	var players_data: Dictionary = room_state.get("players", {}) as Dictionary
	var p2_data: Dictionary = players_data.get("p2", {}) as Dictionary
	if bool(p2_data.get("occupied", false)):
		_cs_configs[1]["joined"] = true
		var p2name := str(p2_data.get("name", "PLAYER 2"))
		if p2name != "" and _cs_name_edits.size() > 1:
			_cs_configs[1]["name"] = p2name
			(_cs_name_edits[1] as LineEdit).text = p2name
	_update_char_select()


func _on_cs_back() -> void:
	char_select_layer.visible = false
	story_mode_select_layer.visible = true


func _on_cs_start_game() -> void:
	if audio_manager != null:
		audio_manager.play_sfx("ui_confirm", -6.0)
	_apply_cs_configs_and_start()


func _apply_cs_configs_and_start() -> void:
	match char_select_mode:
		"single":
			player_count = 1
		"multi":
			player_count = 0
			for _cfg in _cs_configs:
				if bool(_cfg.get("joined", false)):
					player_count += 1
			player_count = clampi(player_count, 1, 4)
		_:
			player_count = 2
	solo_mode = (player_count == 1)
	# Compact ONLY joined configs into consecutive player slots so that
	# player_ship_map[0..player_count-1] matches exactly who is playing.
	var _ji := 0
	for si in range(_cs_configs.size()):
		if not bool(_cs_configs[si].get("joined", false)):
			continue
		if _ji < player_ship_map.size():
			player_ship_map[_ji] = int(_cs_configs[si].get("ship_id", si + 1))
		if _ji < player_name_map.size():
			player_name_map[_ji] = str(_cs_configs[si].get("name", "PLAYER %d" % (_ji + 1)))
		if _ji < player_cpu_map.size():
			player_cpu_map[_ji] = bool(_cs_configs[si].get("is_cpu", false))
		_ji += 1
	if solo_mode:
		online_game_active = false
		set_online_input_mode(true, 1)
	char_select_layer.visible = false
	_show_stage_select()


# ─── Stage Select ──────────────────────────────────────────────────────────────

func _setup_stage_select() -> void:
	stage_select_layer = CanvasLayer.new()
	stage_select_layer.layer = 24
	stage_select_layer.visible = false
	add_child(stage_select_layer)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.02, 0.06, 0.97)
	stage_select_layer.add_child(bg)

	var title_lbl := Label.new()
	title_lbl.text = "SELECT STAGE"
	title_lbl.position = Vector2(0.0, 72.0)
	title_lbl.size = Vector2(screen_size.x, 100.0)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 68)
	title_lbl.add_theme_color_override("font_color", Color(0.24, 1.0, 0.86))
	stage_select_layer.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "Choose your mission"
	sub_lbl.position = Vector2(0.0, 175.0)
	sub_lbl.size = Vector2(screen_size.x, 44.0)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 28)
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.82, 1.0))
	stage_select_layer.add_child(sub_lbl)

	const _CARD_BG: Array[Color] = [
		Color(0.04, 0.10, 0.26),
		Color(0.18, 0.09, 0.02),
		Color(0.20, 0.03, 0.04),
		Color(0.14, 0.02, 0.22),
	]
	const _CARD_BORDER: Array[Color] = [
		Color(0.24, 0.68, 1.0),
		Color(1.0, 0.55, 0.12),
		Color(1.0, 0.22, 0.10),
		Color(0.85, 0.22, 1.0),
	]
	const _GATE_TEXT: Array[String] = ["1 GATE", "2 GATES", "3 GATES", "BOSS GATE"]
	const _DIFF_TEXT: Array[String] = ["NORMAL", "HARD", "VERY HARD", "EXTREME"]

	var card_w := 540.0
	var card_h := 520.0
	var card_gap := 20.0
	var card_y := 240.0
	var start_x := (screen_size.x - (card_w * 4.0 + card_gap * 3.0)) * 0.5

	for i in range(4):
		var cx_card := start_x + float(i) * (card_w + card_gap)
		var stage_n := i + 1

		var card_bg := ColorRect.new()
		card_bg.position = Vector2(cx_card, card_y)
		card_bg.size = Vector2(card_w, card_h)
		card_bg.color = _CARD_BG[i]
		stage_select_layer.add_child(card_bg)

		var _add_border := func(pos: Vector2, sz: Vector2) -> void:
			var r := ColorRect.new()
			r.position = pos; r.size = sz; r.color = _CARD_BORDER[i]
			stage_select_layer.add_child(r)
		_add_border.call(Vector2(cx_card, card_y), Vector2(card_w, 3.0))
		_add_border.call(Vector2(cx_card, card_y + card_h - 3.0), Vector2(card_w, 3.0))
		_add_border.call(Vector2(cx_card, card_y), Vector2(3.0, card_h))
		_add_border.call(Vector2(cx_card + card_w - 3.0, card_y), Vector2(3.0, card_h))

		var num_lbl := Label.new()
		num_lbl.text = "STAGE %d" % stage_n
		num_lbl.position = Vector2(cx_card, card_y + 55.0)
		num_lbl.size = Vector2(card_w, 85.0)
		num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num_lbl.add_theme_font_size_override("font_size", 50)
		num_lbl.add_theme_color_override("font_color", _CARD_BORDER[i])
		stage_select_layer.add_child(num_lbl)

		var sep := ColorRect.new()
		sep.position = Vector2(cx_card + 50.0, card_y + 163.0)
		sep.size = Vector2(card_w - 100.0, 2.0)
		sep.color = Color(_CARD_BORDER[i].r, _CARD_BORDER[i].g, _CARD_BORDER[i].b, 0.45)
		stage_select_layer.add_child(sep)

		var gate_lbl := Label.new()
		gate_lbl.text = _GATE_TEXT[i]
		gate_lbl.position = Vector2(cx_card, card_y + 195.0)
		gate_lbl.size = Vector2(card_w, 65.0)
		gate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gate_lbl.add_theme_font_size_override("font_size", 38)
		gate_lbl.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0))
		stage_select_layer.add_child(gate_lbl)

		var diff_lbl := Label.new()
		diff_lbl.text = _DIFF_TEXT[i]
		diff_lbl.position = Vector2(cx_card, card_y + 278.0)
		diff_lbl.size = Vector2(card_w, 50.0)
		diff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		diff_lbl.add_theme_font_size_override("font_size", 28)
		diff_lbl.add_theme_color_override("font_color", Color(0.65, 0.78, 0.90, 0.85))
		stage_select_layer.add_child(diff_lbl)

		var start_btn := Button.new()
		start_btn.text = "START"
		start_btn.position = Vector2(cx_card + 110.0, card_y + 402.0)
		start_btn.size = Vector2(320.0, 70.0)
		start_btn.add_theme_font_size_override("font_size", 30)
		var _norm := StyleBoxFlat.new()
		_norm.bg_color = Color(_CARD_BORDER[i].r * 0.28, _CARD_BORDER[i].g * 0.28, _CARD_BORDER[i].b * 0.28)
		_norm.border_color = _CARD_BORDER[i]
		_norm.set_border_width_all(2)
		_norm.set_corner_radius_all(14)
		start_btn.add_theme_stylebox_override("normal", _norm)
		var _hov := StyleBoxFlat.new()
		_hov.bg_color = Color(_CARD_BORDER[i].r * 0.52, _CARD_BORDER[i].g * 0.52, _CARD_BORDER[i].b * 0.52)
		_hov.border_color = Color.WHITE
		_hov.set_border_width_all(3)
		_hov.set_corner_radius_all(14)
		start_btn.add_theme_stylebox_override("hover", _hov)
		start_btn.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
		start_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.85))
		start_btn.pressed.connect(_on_stage_number_selected.bind(stage_n))
		stage_select_layer.add_child(start_btn)

	var back_btn := _create_premium_button("← BACK", Vector2(screen_size.x * 0.5 - 140.0, 830.0), Vector2(280.0, 64.0))
	back_btn.pressed.connect(_on_stage_select_back)
	stage_select_layer.add_child(back_btn)


func _show_stage_select() -> void:
	stage_select_layer.visible = true


func _on_stage_select_back() -> void:
	stage_select_layer.visible = false
	char_select_layer.visible = true


func _on_stage_number_selected(n: int) -> void:
	story_stage_number = n
	stage_select_layer.visible = false
	_load_stage(StoryStageScript)
