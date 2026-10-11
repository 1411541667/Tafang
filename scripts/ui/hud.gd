extends CanvasLayer
## 关卡内 HUD：顶部状态条 + 底部按钮条 + 提示 + 暂停面板 + 结算面板。
##
## 【这个节点是 LevelRunner 的子节点，但 _ready() 比父节点先跑】
## Godot 的 _ready() 是自底向上：子节点先就绪。所以 HUD 接信号时
## runner.level 还是 null（父节点的 _ready() 才会去读关卡数据）。
## 因此这里分两步：_ready() 只负责搭界面 + 接信号（此刻接上，
## 父节点随后 _emit_all() 的第一轮推送就不会漏），
## 需要 runner.level 的内容（关卡名）则在 _process 里惰性补齐。
##
## 【process_mode = ALWAYS】
## 暂停靠的是 get_tree().paused，而默认节点是 PAUSABLE —— 暂停后就收不到输入了，
## 于是「按 P 继续」永远按不动。整棵 HUD 子树显式设为 ALWAYS 才有法从暂停里出来。

const NOTICE_SECONDS := 1.8

var runner: LevelRunner = null

var _level_label: Label = null
var _health_label: Label = null
var _gold_label: Label = null
var _wave_label: Label = null
var _status_label: Label = null
var _enemies_label: Label = null
var _notice_label: Label = null
var _start_button: Button = null
var _pause_button: Button = null
var _speed_button: Button = null
var _pause_panel: PausePanel = null
var _result_panel: ResultPanel = null

var _wave_planned: int = 0
var _wave_spawn_baseline: int = 0
var _notice_left: float = 0.0

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	runner = get_parent() as LevelRunner

	_build_ui()

	if runner == null:
		push_error("[Hud] 父节点不是 LevelRunner，HUD 不会收到任何更新")
		return

	runner.health_changed.connect(_on_health_changed)
	runner.gold_changed.connect(_on_gold_changed)
	runner.wave_changed.connect(_on_wave_changed)
	runner.enemies_changed.connect(_on_enemies_changed)
	runner.paused_changed.connect(_on_paused_changed)
	runner.notice.connect(_on_notice)
	runner.level_won.connect(_on_level_won)
	runner.level_lost.connect(_on_level_lost)
	GameState.settings_changed.connect(_refresh_speed_button)

	_pause_panel.resume_requested.connect(_on_resume_requested)
	_pause_panel.restart_requested.connect(_on_restart_requested)
	_pause_panel.quit_to_select_requested.connect(_on_quit_to_select_requested)
	_result_panel.restart_requested.connect(_on_restart_requested)
	_result_panel.quit_to_select_requested.connect(_on_quit_to_select_requested)
	_result_panel.quit_to_menu_requested.connect(_on_quit_to_menu_requested)

	_refresh_speed_button()

# ---------------------------------------------------------------------------
# 搭界面
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_build_top_bar()
	_build_bottom_bar()
	_build_notice()

	_pause_panel = PausePanel.new()
	_pause_panel.name = "PausePanel"
	_pause_panel.visible = false
	add_child(_pause_panel)

	_result_panel = ResultPanel.new()
	_result_panel.name = "ResultPanel"
	_result_panel.visible = false
	add_child(_result_panel)

func _build_top_bar() -> void:
	var bar := UiKit.make_panel(Color("#152030"), UiKit.PANEL_BORDER, 10)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 62
	# 状态条只是显示，不拦鼠标 —— 否则最上面一行的塔位就点不到了
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var row := UiKit.make_hbox(26)
	bar.add_child(row)

	_level_label = _bar_label(row, "", 19, UiKit.TEXT, 232)
	_health_label = _bar_label(row, "", 19, UiKit.TEXT, 168)
	_gold_label = _bar_label(row, "", 19, UiKit.GOLD, 120)
	_wave_label = _bar_label(row, "", 19, UiKit.TEXT, 152)
	_status_label = _bar_label(row, "", 19, UiKit.ACCENT_HOVER, 196)
	_enemies_label = _bar_label(row, "", 19, UiKit.TEXT_DIM, 140)

func _bar_label(parent: Node, text: String, size: int, color: Color, min_width: float) -> Label:
	var label := UiKit.make_label(text, size, color)
	label.custom_minimum_size = Vector2(min_width, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

func _build_bottom_bar() -> void:
	var wrap := CenterContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.offset_top = -78
	wrap.offset_bottom = -16
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var row := UiKit.make_hbox(14)
	wrap.add_child(row)

	_start_button = _bar_button(row, "立即开始", Vector2(150, 46), _on_start_wave_pressed)
	_pause_button = _bar_button(row, "暂停", Vector2(110, 46), _on_pause_pressed)
	_speed_button = _bar_button(row, "加速 x1", Vector2(130, 46), _on_speed_pressed)

func _bar_button(parent: Node, text: String, size: Vector2, handler: Callable) -> Button:
	var button := UiKit.make_button(text, size)
	button.add_theme_font_size_override("font_size", 17)
	# 关掉焦点：空格是「加速」快捷键，聚焦的按钮会把空格当成按下
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	parent.add_child(button)
	return button

func _build_notice() -> void:
	var wrap := CenterContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.offset_top = -124
	wrap.offset_bottom = -84
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	_notice_label = UiKit.make_label("", 20, UiKit.GOLD)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(_notice_label)

# ---------------------------------------------------------------------------
# 每帧刷新
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if runner == null:
		return

	if runner.level != null and _level_label.text != runner.level.display_name:
		_level_label.text = runner.level.display_name

	_refresh_status()
	_refresh_buttons()

	if _notice_left > 0.0:
		_notice_left = maxf(_notice_left - delta, 0.0)
		if _notice_left <= 0.0:
			_notice_label.text = ""

func _refresh_status() -> void:
	if runner.level == null:
		return
	match runner.phase:
		LevelRunner.Phase.PREP:
			_status_label.text = "准备 %.1f 秒" % runner.countdown
		LevelRunner.Phase.INTERVAL:
			_status_label.text = "下一波 %.1f 秒" % runner.countdown
		LevelRunner.Phase.WAVE:
			_status_label.text = "出怪中 · 剩余 %d" % _remaining_spawns()
		LevelRunner.Phase.WON:
			_status_label.text = "关卡通过"
		LevelRunner.Phase.LOST:
			_status_label.text = "关卡失败"
		_:
			_status_label.text = ""

## 波内未出场的怪还有多少只。
## wave_changed 只在「波开始 / 波结束」时发，不逐只发；所以这里用
## 「本波出怪总数 - (全局已出怪数 - 本波开始时的全局已出怪数)」自己算，
## 不额外给 LevelRunner 加信号。
func _remaining_spawns() -> int:
	var spawned_this_wave := runner.spawned_total - _wave_spawn_baseline
	return maxi(_wave_planned - spawned_this_wave, 0)

func _refresh_buttons() -> void:
	var waiting := runner.phase == LevelRunner.Phase.PREP or runner.phase == LevelRunner.Phase.INTERVAL
	_start_button.disabled = not waiting or runner.game_finished
	_pause_button.disabled = runner.game_finished

# ---------------------------------------------------------------------------
# 信号回调
# ---------------------------------------------------------------------------

func _on_health_changed(current: int, maximum: int) -> void:
	_health_label.text = "关卡血量 %d / %d" % [current, maximum]
	var low := maximum > 0 and current * 3 <= maximum
	_health_label.add_theme_color_override("font_color", UiKit.DANGER if low else UiKit.TEXT)

func _on_gold_changed(amount: int) -> void:
	_gold_label.text = "金币 %d" % amount

func _on_wave_changed(current: int, total: int, remaining_spawns: int) -> void:
	_wave_label.text = "波次 %d / %d" % [current, total]
	if remaining_spawns > 0:
		_wave_planned = remaining_spawns
		_wave_spawn_baseline = runner.spawned_total

func _on_enemies_changed(alive: int) -> void:
	_enemies_label.text = "存活敌人 %d" % alive

func _on_paused_changed(is_paused: bool) -> void:
	if _pause_panel != null:
		_pause_panel.visible = is_paused

func _on_notice(text: String) -> void:
	_notice_label.text = text
	_notice_left = NOTICE_SECONDS

func _on_level_won() -> void:
	_show_result(true)

func _on_level_lost() -> void:
	_show_result(false)

func _show_result(won: bool) -> void:
	if _result_panel == null:
		return
	# 结算时把暂停面板收起来：两者叠在一起会挡住结算按钮
	if _pause_panel != null:
		_pause_panel.visible = false
	_result_panel.show_result(won, runner.snapshot())

func _on_start_wave_pressed() -> void:
	if runner != null:
		runner.start_next_wave_now()

func _on_pause_pressed() -> void:
	_toggle_pause()

func _on_speed_pressed() -> void:
	GameState.toggle_game_speed()

func _refresh_speed_button() -> void:
	if _speed_button != null:
		_speed_button.text = "加速 x2" if GameState.is_fast_forward() else "加速 x1"

# ---------------------------------------------------------------------------
# 面板请求
# ---------------------------------------------------------------------------

func _on_resume_requested() -> void:
	if runner != null:
		runner.set_paused(false)

func _on_restart_requested() -> void:
	if runner != null:
		runner.restart()

func _on_quit_to_select_requested() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")

func _on_quit_to_menu_requested() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ---------------------------------------------------------------------------
# 输入：暂停由 HUD 独家处理
# ---------------------------------------------------------------------------

func _toggle_pause() -> void:
	if runner == null or runner.game_finished:
		return
	runner.set_paused(not runner.paused)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("td_pause"):
		get_viewport().set_input_as_handled()
		_toggle_pause()
