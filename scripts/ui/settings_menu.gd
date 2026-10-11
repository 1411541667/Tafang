extends Control
## 设置页：7 项设置，全部写进 user://settings.cfg 并在关闭游戏后保留。
##
## 本版没有音频资源，所以三个音量滑块只负责「保存数值 + 设置音频总线音量」，
## 不会真的听到变化 —— 界面上有一行提示说明这件事，避免以为是坏了。
##
## 所有改动都走 GameState.update_settings(mutator)：
## 它会「改值 → 存盘 → 应用 → 发 settings_changed」四件事一起做，
## 所以不存在「改了但没存」或者「存了但没生效」的中间态。

func _ready() -> void:
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	add_child(UiKit.make_background())

	var center := UiKit.make_center()
	add_child(center)

	var column := UiKit.make_vbox(14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(column)

	var title := UiKit.make_label("设置", 42, UiKit.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	column.add_child(UiKit.make_spacer(6))

	var panel := UiKit.make_panel(UiKit.PANEL_BG, UiKit.PANEL_BORDER, 18)
	column.add_child(panel)

	var rows := UiKit.make_vbox(12)
	panel.add_child(rows)

	rows.add_child(_section_label("音量"))
	rows.add_child(_volume_row("主音量", "master_volume", GameState.master_volume))
	rows.add_child(_volume_row("音效音量", "sfx_volume", GameState.sfx_volume))
	rows.add_child(_volume_row("背景音乐音量", "bgm_volume", GameState.bgm_volume))

	var audio_hint := UiKit.make_label("本版没有音频资源，三个音量只保存数值，暂时听不到效果", 13, UiKit.TEXT_DIM)
	audio_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(audio_hint)

	rows.add_child(UiKit.make_spacer(4))
	rows.add_child(_section_label("显示"))
	rows.add_child(_check_row("全屏显示", "fullscreen", GameState.fullscreen))
	rows.add_child(_check_row("伤害飘字", "show_damage_popup", GameState.show_damage_popup))
	rows.add_child(_check_row("显示敌人血条", "show_enemy_health_bar", GameState.show_enemy_health_bar))

	rows.add_child(UiKit.make_spacer(4))
	rows.add_child(_section_label("游戏"))
	rows.add_child(_speed_row())

	column.add_child(UiKit.make_spacer(14))

	var back_button := UiKit.make_button("返回首页", Vector2(240, 48))
	back_button.pressed.connect(_on_back_pressed)
	var back_wrap := CenterContainer.new()
	back_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_wrap.add_child(back_button)
	column.add_child(back_wrap)

# ---------------------------------------------------------------------------
# 行构件
# ---------------------------------------------------------------------------

func _section_label(text: String) -> Label:
	var label := UiKit.make_label(text, 19, UiKit.ACCENT_HOVER)
	return label

func _row(left_text: String) -> HBoxContainer:
	var row := UiKit.make_hbox(14)
	var label := UiKit.make_label(left_text, 17, UiKit.TEXT)
	label.custom_minimum_size = Vector2(190, 34)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row

func _volume_row(left_text: String, key: String, value: float) -> HBoxContainer:
	var row := _row(left_text)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	# 先设值再连信号：否则赋值本身就会触发一次回调（会在还没搭好 UI 时写盘）
	slider.value = value
	slider.custom_minimum_size = Vector2(300, 34)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label := UiKit.make_label(_percent(value), 16, UiKit.TEXT_DIM)
	value_label.custom_minimum_size = Vector2(64, 34)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)

	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = _percent(new_value)
		GameState.update_settings(func() -> void: GameState.set(key, new_value)))

	return row

func _check_row(left_text: String, key: String, value: bool) -> HBoxContainer:
	var row := _row(left_text)

	var button := UiKit.make_check("开启", value)
	button.custom_minimum_size = Vector2(300, 34)
	row.add_child(button)

	var filler := Control.new()
	filler.custom_minimum_size = Vector2(64, 34)
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(filler)

	button.toggled.connect(func(pressed: bool) -> void:
		button.text = "开启" if pressed else "关闭"
		GameState.update_settings(func() -> void: GameState.set(key, pressed)))

	return row

func _speed_row() -> HBoxContainer:
	var row := _row("游戏速度")

	var option := OptionButton.new()
	option.add_theme_font_override("font", UiKit.font())
	option.add_theme_font_size_override("font_size", 17)
	option.add_theme_color_override("font_color", UiKit.TEXT)
	option.add_item("1x（正常）", 0)
	option.add_item("2x（加速）", 1)
	option.selected = 1 if GameState.is_fast_forward() else 0
	option.custom_minimum_size = Vector2(300, 34)
	row.add_child(option)

	var filler := Control.new()
	filler.custom_minimum_size = Vector2(64, 34)
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(filler)

	option.item_selected.connect(func(index: int) -> void:
		var speed := GameState.SPEED_FAST if index == 1 else GameState.SPEED_NORMAL
		GameState.update_settings(func() -> void: GameState.game_speed = speed))

	return row

func _percent(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
