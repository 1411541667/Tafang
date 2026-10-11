extends Control
## 关卡选择：6 个关卡全部直接可选，不做解锁限制。
##
## 每个关卡的按钮文案由它自己的数据渲染出来（关卡血量 / 地图 / 波数 / 总怪数），
## 所以新增关卡只要在生成器里加一项，这里会自动多出一个按钮 —— 不需要改 UI 代码。
##
## 关卡数据有任一字段非法时按钮会变成禁用状态，并附上原因，
## 避免「点进去发现关卡是坏的」这种要跑起来才知道的问题。

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

	var title := UiKit.make_label("选择关卡", 42, UiKit.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := UiKit.make_label("每个关卡都用同一套函数与类，新增地图只需在生成器里加一项", 15, UiKit.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	column.add_child(UiKit.make_spacer(8))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)

	for level_id in DataRegistry.all_level_ids():
		grid.add_child(_make_level_button(level_id))

	column.add_child(UiKit.make_spacer(12))

	var back_button := UiKit.make_button("返回首页", Vector2(240, 48))
	back_button.pressed.connect(_on_back_pressed)
	var back_wrap := CenterContainer.new()
	back_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_wrap.add_child(back_button)
	column.add_child(back_wrap)

func _make_level_button(level_id: String) -> Button:
	var level: LevelData = DataRegistry.get_level(level_id)
	if level == null:
		var broken := UiKit.make_button("关卡 %s（数据缺失）" % level_id, Vector2(440, 64))
		broken.disabled = true
		return broken

	var map: MapData = DataRegistry.get_map(level.map_id)
	var map_name := "未知地图"
	if map != null:
		map_name = map.display_name

	var problems := level.validate()
	if map == null:
		problems.append("引用的地图 '%s' 不存在" % level.map_id)

	var button := UiKit.make_button("", Vector2(440, 64))
	button.add_theme_font_size_override("font_size", 17)
	if problems.is_empty():
		button.text = "%s\n地图 %s · 血量 %d · %d 波 · 共 %d 只怪" % [
			level.display_name, map_name, level.base_health,
			level.waves.size(), level.total_enemy_count()]
		button.pressed.connect(_on_level_pressed.bind(level_id))
	else:
		button.text = "%s（数据有问题）" % level.display_name
		button.disabled = true
		button.tooltip_text = "\n".join(problems)
	return button

func _on_level_pressed(level_id: String) -> void:
	GameState.selected_level_id = level_id
	get_tree().change_scene_to_file("res://scenes/level.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
