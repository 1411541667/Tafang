class_name PausePanel
extends Control
## 暂停面板：继续 / 重玩 / 返回关卡选择。
##
## 【为什么整块 Control 保留默认的 MOUSE_FILTER_STOP】
## 它铺满全屏，会吞掉所有鼠标事件 —— 这正是我们想要的：
## 暂停时点在战场上的任何地方都不该放置防御塔。

signal resume_requested
signal restart_requested
signal quit_to_select_requested

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.08, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := UiKit.make_center()
	add_child(center)

	var panel := UiKit.make_panel(UiKit.PANEL_BG, UiKit.PANEL_BORDER, 26)
	center.add_child(panel)

	var column := UiKit.make_vbox(14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)

	var title := UiKit.make_label("已暂停", 36, UiKit.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var hint := UiKit.make_label("按 P 或 ESC 也可以继续", 14, UiKit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	column.add_child(UiKit.make_spacer(8))

	column.add_child(_button("继续游戏", _on_resume))
	column.add_child(_button("重玩本关", _on_restart))
	column.add_child(_button("返回关卡选择", _on_quit))

func _button(text: String, handler: Callable) -> Button:
	var button := UiKit.make_button(text, Vector2(260, 50))
	# 关掉焦点：否则空格键会被已聚焦的按钮当作「按下」，
	# 和游戏里的「加速」快捷键撞车。
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button

func _on_resume() -> void:
	resume_requested.emit()

func _on_restart() -> void:
	restart_requested.emit()

func _on_quit() -> void:
	quit_to_select_requested.emit()
