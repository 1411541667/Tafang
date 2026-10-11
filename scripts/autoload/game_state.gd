extends Node
## AutoLoad 单例：跨场景的最小状态 + 设置读写 + 输入注册 + 音频总线。
##
## 【只放跨场景的东西】关卡运行期状态（关卡血量 / 金币 / 波次 / 已放置的塔）
## 一律留在 LevelRunner 里。这样 get_tree().reload_current_scene() 会自然重置它们，
## 不会踩「autoload 不随场景重载重置」的坑。
##
## 音频说明：本版没有任何声音资源（用户决策）。这里仍然程序化创建 3 条音频总线，
## 并让滑块把音量真正写进 AudioServer —— 将来加音效时设置层零改动。

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"

const BUS_MASTER := "Master"
const BUS_SFX := "SFX"
const BUS_BGM := "BGM"

const SPEED_NORMAL := 1.0
const SPEED_FAST := 2.0

## 关卡选择页写入这里，level.tscn 在 _ready() 里读取。
var selected_level_id: String = "level_01"

# --- 设置项（默认值）---
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var bgm_volume: float = 1.0
var fullscreen: bool = false
var show_damage_popup: bool = true
var game_speed: float = SPEED_NORMAL
var show_enemy_health_bar: bool = true

func _ready() -> void:
	# 顺序有讲究：先建总线，再读设置，最后应用
	_ensure_audio_buses()
	_register_input_actions()
	load_settings()
	apply_settings()

# ---------------------------------------------------------------------------
# 音频总线
# ---------------------------------------------------------------------------

func _ensure_audio_buses() -> void:
	for bus_name in [BUS_SFX, BUS_BGM]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, BUS_MASTER)

# ---------------------------------------------------------------------------
# 输入映射
# ---------------------------------------------------------------------------
# 用代码注册而不是写进 project.godot 的 [input] 段：
# Object(InputEventKey,...) 的序列化跨版本易碎，而且注册晚了会让
# Input.get_vector 每帧刷 "InputMap action doesn't exist" 错误。
# AutoLoad 的 _ready() 早于主场景，是唯一安全的注册时机。

func _register_input_actions() -> void:
	_ensure_action("td_select", [MOUSE_BUTTON_LEFT], [])
	# 右键只用来取消当前操作（清掉悬停高亮），不再兼职暂停
	_ensure_action("td_cancel", [MOUSE_BUTTON_RIGHT], [])
	_ensure_action("td_speed_toggle", [], [KEY_SPACE])
	# 暂停由 HUD 独家处理（HUD 是 PROCESS_MODE_ALWAYS，暂停时仍能收到输入）。
	# 如果 LevelRunner 也处理这个按键，会出现「按下一次开了又立刻关」的双响应。
	_ensure_action("td_pause", [], [KEY_P, KEY_ESCAPE])

func _ensure_action(action_name: String, mouse_buttons: Array, keycodes: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, 0.2)
	# 已经有任何绑定了就不再重复加（避免切换场景后越加越多）
	if not InputMap.action_get_events(action_name).is_empty():
		return
	for button: int in mouse_buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = button as MouseButton
		InputMap.action_add_event(action_name, mb)
	for keycode: int in keycodes:
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode as Key
		InputMap.action_add_event(action_name, ev)

# ---------------------------------------------------------------------------
# 设置读写
# ---------------------------------------------------------------------------

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # 首次运行没有配置文件，直接用默认值
	master_volume = clampf(_as_float(cfg, "audio", "master", master_volume), 0.0, 1.0)
	sfx_volume = clampf(_as_float(cfg, "audio", "sfx", sfx_volume), 0.0, 1.0)
	bgm_volume = clampf(_as_float(cfg, "audio", "bgm", bgm_volume), 0.0, 1.0)
	fullscreen = _as_bool(cfg, "video", "fullscreen", fullscreen)
	show_damage_popup = _as_bool(cfg, "gameplay", "show_damage_popup", show_damage_popup)
	show_enemy_health_bar = _as_bool(cfg, "gameplay", "show_enemy_health_bar", show_enemy_health_bar)
	game_speed = SPEED_FAST if _as_bool(cfg, "gameplay", "fast_forward", game_speed > SPEED_NORMAL) else SPEED_NORMAL

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "bgm", bgm_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("gameplay", "show_damage_popup", show_damage_popup)
	cfg.set_value("gameplay", "show_enemy_health_bar", show_enemy_health_bar)
	cfg.set_value("gameplay", "fast_forward", game_speed > SPEED_NORMAL)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("设置保存失败: %s" % error_string(err))

func apply_settings() -> void:
	_set_bus_volume(BUS_MASTER, master_volume)
	_set_bus_volume(BUS_SFX, sfx_volume)
	_set_bus_volume(BUS_BGM, bgm_volume)
	Engine.time_scale = game_speed
	_apply_window_mode()
	settings_changed.emit()

func _apply_window_mode() -> void:
	# headless（自动化测试）下没有真正的窗口，跳过以免刷警告
	if DisplayServer.get_name() == "headless":
		return
	var target := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target:
		DisplayServer.window_set_mode(target)

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	var clamped := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(index, clamped <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(clamped, 0.0001)))

## 改设置后统一走这里：写入 + 立即生效 + 通知 UI。
func update_settings(mutator: Callable) -> void:
	mutator.call()
	save_settings()
	apply_settings()

func set_game_speed(speed: float) -> void:
	game_speed = SPEED_FAST if speed > SPEED_NORMAL else SPEED_NORMAL
	Engine.time_scale = game_speed
	settings_changed.emit()

func toggle_game_speed() -> void:
	set_game_speed(SPEED_FAST if game_speed <= SPEED_NORMAL else SPEED_NORMAL)

func is_fast_forward() -> bool:
	return game_speed > SPEED_NORMAL

# ---------------------------------------------------------------------------
# 小工具：ConfigFile 取值一律显式转型，绝不用 := 接 Variant
# ---------------------------------------------------------------------------

func _as_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is float or raw is int:
		return float(raw)
	return fallback

func _as_bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is bool:
		return bool(raw)
	return fallback
