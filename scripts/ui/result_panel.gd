class_name ResultPanel
extends Control
## 关卡结算面板：显示胜负与本局统计，提供重玩 / 返回关卡选择 / 返回首页。
##
## 统计数字全部来自 LevelRunner.snapshot()，不在这里重新算一遍 ——
## 保证界面上看到的和测试断言的是同一份数据。

signal restart_requested
signal quit_to_select_requested
signal quit_to_menu_requested

var _title_label: Label = null
var _subtitle_label: Label = null
var _stat_labels: Dictionary = {}

const STAT_ROWS := [
	["关卡血量", "health"],
	["出怪总数", "spawned"],
	["击退敌人", "killed"],
	["漏怪数量", "leaked"],
	["开火次数", "shots"],
	["造成伤害", "damage"],
	["建造防御塔", "towers"],
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.08, 0.80)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := UiKit.make_center()
	add_child(center)

	var panel := UiKit.make_panel(UiKit.PANEL_BG, UiKit.PANEL_BORDER, 28)
	center.add_child(panel)

	var column := UiKit.make_vbox(12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)

	_title_label = UiKit.make_label("", 38, UiKit.TEXT)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)

	_subtitle_label = UiKit.make_label("", 15, UiKit.TEXT_DIM)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_subtitle_label)

	column.add_child(UiKit.make_spacer(10))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)

	for row in STAT_ROWS:
		var caption := UiKit.make_label(String(row[0]), 17, UiKit.TEXT_DIM)
		grid.add_child(caption)
		var value := UiKit.make_label("-", 17, UiKit.TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(120, 0)
		grid.add_child(value)
		_stat_labels[String(row[1])] = value

	column.add_child(UiKit.make_spacer(14))

	column.add_child(_button("重玩本关", _on_restart))
	column.add_child(_button("返回关卡选择", _on_quit_select))
	column.add_child(_button("返回首页", _on_quit_menu))

func _button(text: String, handler: Callable) -> Button:
	var button := UiKit.make_button(text, Vector2(280, 48))
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button

## won=true 表示通关。stats 直接传 LevelRunner.snapshot() 的返回值。
func show_result(won: bool, stats: Dictionary) -> void:
	_title_label.text = "关卡通过" if won else "关卡失败"
	_title_label.add_theme_color_override("font_color", UiKit.OK if won else UiKit.DANGER)

	var max_health := int(stats.get("max_health", 0))
	var health := int(stats.get("health", 0))
	if won:
		_subtitle_label.text = "全部 %d 波敌人已被清空" % int(stats.get("wave_total", 0))
	else:
		_subtitle_label.text = "关卡血量耗尽，漏掉 %d 只敌人" % int(stats.get("leaked", 0))

	for key in _stat_labels:
		var label: Label = _stat_labels[key]
		match String(key):
			"health":
				label.text = "%d / %d" % [health, max_health]
			"damage":
				label.text = "%d" % int(round(float(stats.get("damage", 0.0))))
			_:
				label.text = "%d" % int(stats.get(String(key), 0))

	visible = true

func _on_restart() -> void:
	restart_requested.emit()

func _on_quit_select() -> void:
	quit_to_select_requested.emit()

func _on_quit_menu() -> void:
	quit_to_menu_requested.emit()
