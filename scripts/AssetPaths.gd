extends RefCounted

const PLAYERS := {
	"p1": "res://assets/players/player_azure_wing.png",
	"p2": "res://assets/players/player_solar_fang.png",
	"p3": "res://assets/players/player_emerald_claw.png",
	"p4": "res://assets/players/player_violet_phantom.png",
	"fusion": "res://assets/players/player_twin_core_fusion.png",
}

const ENEMIES := {
	"scout":           "res://assets/enemies/enemy_scout_drone.png",
	"attacker":        "res://assets/enemies/enemy_attacker_drone.png",
	"tank":            "res://assets/enemies/enemy_tank_unit.png",
	"elite":           "res://assets/enemies/enemy_elite_unit.png",
	"phantom_dart":    "res://assets/enemies/enemy_phantom_dart.png",
	"fortress_walker": "res://assets/enemies/enemy_fortress_walker.png",
	"split_cell":      "res://assets/enemies/enemy_split_cell.png",
	"bomber_drone":    "res://assets/enemies/enemy_bomber_drone.png",
}

const BOSSES := {
	"crimson": "res://assets/bosses/boss_crimson_dreadnought.png",
	"leviathan": "res://assets/bosses/boss_eclipse_leviathan.png",
	"leviathan_drone": "res://assets/bosses/boss_leviathan_drone.png",
	"weak_core": "res://assets/bosses/boss_leviathan_weak_core.png",
}

const PROJECTILES := {
	"basic": "res://assets/projectiles/projectile_basic_shot.png",
	"azure": "res://assets/projectiles/projectile_azure_shot.png",
	"solar": "res://assets/projectiles/projectile_solar_shot.png",
	"emerald": "res://assets/projectiles/emerald_shot.png",
	"violet": "res://assets/projectiles/violet_shot.png",
	"bomb_shot": "res://assets/projectiles/projectile_bomb_shot.png",
	"enemy": "res://assets/projectiles/projectile_enemy_bolt.png",
	"boss_orb": "res://assets/projectiles/projectile_boss_orb.png",
	"boss_ord": "res://assets/projectiles/projectile_boss_orb.png",
}

const EFFECTS := {
	"energy_tornado": "res://assets/effects/effect_energy_tornado.png",
	"twin_core_cannon": "res://assets/effects/effect_twin_core_cannon.png",
	"explosion_small": "res://assets/effects/effect_explosion_small.png",
	"explosion_large": "res://assets/effects/effect_explosion_large.png",
	"hit_spark": "res://assets/effects/effect_hit_spark.png",
	"shield_bubble": "res://assets/effects/effect_shield_bubble.png",
	"dash_trail": "res://assets/effects/effect_dash_trail.png",
	"support_aura": "res://assets/effects/effect_support_aura.png",
	"team_shield": "res://assets/effects/effect_team_shield.png",
}

const ITEMS := {
	"bomb": "res://assets/items/item_bomb.png",
	"heal": "res://assets/items/item_heal.png",
	"rapid_fire": "res://assets/items/item_rapid_fire.png",
	"shield": "res://assets/items/item_shield.png",
	"energy_core": "res://assets/items/item_energy_core.png",
	"power_boost": "res://assets/items/item_power_boost.png",
	"link_charge": "res://assets/items/item_link_charge.png",
	"crystal": "res://assets/items/item_crystal.png",
	"crystal_magnet": "res://assets/items/item_crystal_magnet.png",
	"emp_burst": "res://assets/items/item_emp_burst.png",
	"role_attacker": "res://assets/items/item_role_attacker.png",
	"role_defender": "res://assets/items/item_role_defender.png",
	"role_support": "res://assets/items/item_role_support.png",
	"role_bomber": "res://assets/items/item_role_bomber.png",
}

const WEAPONS := {
	"side_cannon":     "res://assets/weapons/weapon_side_cannon.png",
	"spread_shot":     "res://assets/weapons/weapon_spread_shot.png",
	"homing_missile":  "res://assets/weapons/weapon_homing_missile.png",
	"twin_laser":      "res://assets/weapons/weapon_twin_laser.png",
}

const TURRETS := {
	"auto_cannon":   "res://assets/turrets/turret_auto_cannon.png",
	"laser_tower":   "res://assets/turrets/turret_laser_tower.png",
	"missile_pod":   "res://assets/turrets/turret_missile_pod.png",
	"shield_wall":   "res://assets/turrets/turret_shield_wall.png",
}

const BACKGROUNDS := {
	"space": "res://assets/backgrounds/background_space_field.png",
	"astral": "res://assets/backgrounds/background_astral_court.png",
	"raid": "res://assets/backgrounds/background_eclipse_raid.png",
}

const STAGES := {
	"base_core": "res://assets/stages/stage_base_core.png",
	"astral_ring": "res://assets/stages/stage_astral_ring.png",
	"arena_obstacle": "res://assets/stages/stage_arena_obstacle.png",
}

const ENEMY_GATES := {
	"gate_0":  "res://assets/stages/stage_enemy_core.png",
	"gate_20": "res://assets/stages/stage_enemy_core_20.png",
	"gate_40": "res://assets/stages/stage_enemy_core_40.png",
	"gate_60": "res://assets/stages/stage_enemy_core_60.png",
	"gate_80": "res://assets/stages/stage_enemy_core_80.png",
	"gate_95": "res://assets/stages/stage_enemy_core_95.png",
}

const UI := {
	"hp": "res://assets/ui/ui_icon_hp.png",
	"shield": "res://assets/ui/ui_icon_shield.png",
	"link": "res://assets/ui/ui_icon_link.png",
	"boss_hp_back": "res://assets/ui/ui_bar_boss_hp_back.png",
	"link_fill": "res://assets/ui/ui_bar_link_fill.png",
	"shop": "res://assets/ui/ui_shop_icon.png",
	"logo": "res://assets/ui/logo_core_pulse.png",
}


const BGM := {
	"home": "res://assets/audio/bgm/bgm_home_menu.ogg",
	"story": "res://assets/audio/bgm/bgm_story_battle.ogg",
	"astral": "res://assets/audio/bgm/bgm_astral_court_duel.ogg",
	"eclipse": "res://assets/audio/bgm/bgm_eclipse_raid_phase1.ogg",
	"victory": "res://assets/audio/bgm/bgm_victory_result.ogg",
}

const SFX := {
	"shot_basic": "res://assets/audio/sfx/sfx_shot_basic.ogg",
	"shot_azure": "res://assets/audio/sfx/sfx_shot_azure.ogg",
	"shot_solar": "res://assets/audio/sfx/sfx_shot_solar.ogg",
	"shot_enemy": "res://assets/audio/sfx/sfx_shot_enemy.ogg",
	"shot_boss": "res://assets/audio/sfx/sfx_shot_boss.ogg",
	"twin_core_cannon": "res://assets/audio/sfx/sfx_twin_core_cannon.ogg",
	"blue_nova": "res://assets/audio/sfx/sfx_blue_nova.ogg",
	"golden_lance": "res://assets/audio/sfx/sfx_golden_lance.ogg",
	"hit_small": "res://assets/audio/sfx/sfx_hit_small.ogg",
	"hit_heavy": "res://assets/audio/sfx/sfx_hit_heavy.ogg",
	"explosion_small": "res://assets/audio/sfx/sfx_explosion_small.ogg",
	"explosion_large": "res://assets/audio/sfx/sfx_explosion_large.ogg",
	"core_damage": "res://assets/audio/sfx/sfx_core_damage.ogg",
	"item_pickup": "res://assets/audio/sfx/sfx_item_pickup.ogg",
	"item_heal": "res://assets/audio/sfx/sfx_item_heal.ogg",
	"item_rapid_fire": "res://assets/audio/sfx/sfx_item_rapid_fire.ogg",
	"item_shield": "res://assets/audio/sfx/sfx_item_shield.ogg",
	"item_power_boost": "res://assets/audio/sfx/sfx_item_power_boost.ogg",
	"item_link_charge": "res://assets/audio/sfx/sfx_item_link_charge.ogg",
	"shield_activate": "res://assets/audio/sfx/sfx_shield_activate.ogg",
	"shield_loop": "res://assets/audio/sfx/sfx_shield_loop.ogg",
	"shield_hit": "res://assets/audio/sfx/sfx_shield_hit.ogg",
	"shield_break": "res://assets/audio/sfx/sfx_shield_break.ogg",
	"dash": "res://assets/audio/sfx/sfx_dash.ogg",
	"charge_ready": "res://assets/audio/sfx/sfx_charge_ready.ogg",
	"link_ready": "res://assets/audio/sfx/sfx_link_ready.ogg",
	"overdrive_start": "res://assets/audio/sfx/sfx_overdrive_start.ogg",
	"ui_select": "res://assets/audio/sfx/sfx_ui_select.ogg",
	"ui_confirm": "res://assets/audio/sfx/sfx_ui_confirm.ogg",
	"stage_start": "res://assets/audio/sfx/sfx_stage_start.ogg",
	"game_over": "res://assets/audio/sfx/sfx_game_over.ogg",
	"victory": "res://assets/audio/sfx/sfx_victory.ogg",
}

static func path_exists(path: String) -> bool:
	return ResourceLoader.exists(path)

static func resolve_path(primary: String, fallback: String = "") -> String:
	if ResourceLoader.exists(primary):
		return primary
	if fallback != "" and ResourceLoader.exists(fallback):
		return fallback
	return primary

static func load_texture(path: String, placeholder_color: Color = Color(1, 1, 1, 1), placeholder_size: Vector2i = Vector2i(96, 96)) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	# .import ファイルがない場合でも直接 PNG を読み込む（エディタ実行時）
	var abs_path := ProjectSettings.globalize_path(path)
	var image := Image.new()
	if image.load(abs_path) == OK:
		return ImageTexture.create_from_image(image)
	return make_placeholder_texture(placeholder_size, placeholder_color)

static func make_placeholder_texture(size: Vector2i, color: Color) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

static func create_sprite(path: String, desired_size: Vector2, fallback_color: Color = Color.WHITE, z_index_value: int = 0) -> Sprite2D:
	var sprite := Sprite2D.new()
	var texture := load_texture(path, fallback_color)
	sprite.texture = texture
	sprite.z_index = z_index_value
	fit_sprite(sprite, desired_size)
	return sprite

static func fit_sprite(sprite: Sprite2D, desired_size: Vector2) -> void:
	if sprite == null or sprite.texture == null or desired_size == Vector2.ZERO:
		return
	var tex_size := sprite.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale_factor := minf(desired_size.x / tex_size.x, desired_size.y / tex_size.y)
	sprite.scale = Vector2(scale_factor, scale_factor)

static func make_life_core_texture() -> Texture2D:
	const SZ := 32
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
	var half := SZ * 0.5
	for y in range(SZ):
		for x in range(SZ):
			var px := float(x) + 0.5 - half
			var py := float(y) + 0.5 - half
			var d2 := px * px + py * py
			var R := half * 0.88
			if d2 > R * R:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var d := sqrt(d2)
			var nx := px / R
			var ny := py / R
			var nz := sqrt(maxf(0.0, 1.0 - nx * nx - ny * ny))
			var diff := maxf(0.0, nx * (-0.5774) + ny * (-0.5774) + nz * 0.5774)
			var dot2 := nx * (-0.5774) + ny * (-0.5774) + nz * 0.5774
			var rz := 2.0 * dot2 * nz - 0.5774
			var spec := pow(maxf(0.0, rz), 28.0)
			var rim := pow(1.0 - nz, 2.0)
			var cr := minf(1.0, 0.02 + 0.18 * diff + 0.95 * spec + 0.30 * rim)
			var cg := minf(1.0, 0.55 + 0.30 * diff + 0.85 * spec + 0.60 * rim)
			var cb := minf(1.0, 0.90 + 0.05 * diff + 0.75 * spec + 0.80 * rim)
			var edge := minf(1.0, (R - d) * 2.5)
			img.set_pixel(x, y, Color(cr, cg, cb, edge))
	return ImageTexture.create_from_image(img)
