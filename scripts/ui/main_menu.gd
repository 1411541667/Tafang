extends Control
## 首页 UI：开始游戏 / 设置 / 退出。
##
## 【进场景第一件事是 get_tree().paused = false】
## 暂停是全局的（get_tree().paused），从暂停中的关卡退回首页时它还是 true。
## 不在这里解除的话，首页一进来就是冻住的 —— 而且看不到任何报错。

func _ready() -> void:
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	add_child(UiKit.make_background())

	var center := UiKit.make_center()
	add_child(center)

	var column := UiKit.make_vbox(16)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(column)

	var title := UiKit.make_label("塔  防", 60, UiKit.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := UiKit.make_label("经典路线塔防 · 在路边建造防御塔，别让敌人走到终点", 17, UiKit.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	column.add_child(UiKit.make_spacer(26))

	var start_button := UiKit.make_button("开始游戏", Vector2(280, 56))
	start_button.pressed.connect(_on_start_pressed)
	column.add_child(start_button)

	var settings_button := UiKit.make_button("设置", Vector2(280, 56))
	settings_button.pressed.connect(_on_settings_pressed)
	column.add_child(settings_button)

	var quit_button := UiKit.make_button("退出", Vector2(280, 56))
	quit_button.pressed.connect(_on_quit_pressed)
	column.add_child(quit_button)

	column.add_child(UiKit.make_spacer(20))

	var hint := UiKit.make_label("左键放置防御塔 · 右键取消 · 空格加速 · P / ESC 暂停", 15, UiKit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	start_button.grab_focus()

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings_menu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
