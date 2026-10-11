extends Node
##
## 无头冒烟测试：用真实场景、真实数据跑一遍，不 mock。
##
## 运行：
##   & $GODOT --headless --path <proj> --fixed-fps 60 --quit-after 40000 res://tests/smoke_test.tscn
##
## 退出码 0 = 全过，1 = 有失败（给 CI 用）。控制台末尾会打印 SMOKE_RESULT=OK / FAIL。
##
## 设计约束（来自本项目踩过的坑）：
##   1. 所有等待一律走 `await get_tree().physics_frame`（不是 process_frame），
##      配合 --fixed-fps 60 让帧数与游戏时间严格对应。
##   2. 断言用「相对/范围」而不是硬编码绝对值，避免顺路发生的正常行为被判成失败。
##   3. 任何可能为 NaN 的量都不做 `>` 比较（NaN 参与的比较恒为 false，会静默漏检）。
##   4. 覆盖 [A]~[L] 十二组：伤害公式 / 除零守卫 / 地图 / 数据完整性 / 近战不可达 /
##      中文字形 / 设置持久化 / 放置规则 / 敌人受伤 / 六图共跑 / 战斗集成 /
##      漏怪与胜负 / 波次 / 暂停。
##

const LEVEL_SCENE_PATH := "res://scenes/level.tscn"

const CJK_SAMPLE := "塔防关卡血金币波次暂停继续开始游戏设置返回首页立即加速射程攻速伤害抗性漏怪击杀防御"

var _passed := 0
var _failed := 0
var _failures: Array[String] = []


func _ready() -> void:
	print("========== 塔防冒烟测试 ==========")
	await _run_all()
	_report()


# ---------------------------------------------------------------------------
# 断言与工具
# ---------------------------------------------------------------------------

func _section(title: String) -> void:
	print("")
	print("--- %s ---" % title)


func _check(label: String, condition: bool, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
		return true
	_failed += 1
	var text := "  [FAIL] %s" % label
	if not detail.is_empty():
		text += "  —— %s" % detail
	_failures.append(text)
	print(text)
	return false


func _check_eq(label: String, actual: Variant, expected: Variant) -> bool:
	# 注意：actual/expected 是 Variant，这里绝不能用 `:=` 推断
	# （否则报 "Cannot infer the type of ok variable" → 整个脚本解析失败 → 进程挂死）
	var ok: bool = actual == expected
	var detail := ""
	if not ok:
		detail = "实际 = %s，期望 = %s" % [str(actual), str(expected)]
	return _check(label, ok, detail)


func _check_almost(label: String, actual: float, expected: float, tolerance: float = 0.0001) -> bool:
	var ok: bool = is_finite(actual) and absf(actual - expected) <= tolerance
	var detail := ""
	if not ok:
		detail = "实际 = %s，期望 ≈ %s" % [str(actual), str(expected)]
	return _check(label, ok, detail)


## 前进 n 个物理帧。
func _wait_physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


## 前进物理帧，直到 game_finished 或 stop_when 为真，或到达上限。返回实际帧数。
func _run_until(runner: LevelRunner, max_frames: int, stop_when: Callable = Callable()) -> int:
	var frames := 0
	while frames < max_frames:
		await get_tree().physics_frame
		frames += 1
		if not is_instance_valid(runner) or runner.game_finished:
			break
		if stop_when.is_valid() and bool(stop_when.call()):
			break
	return frames


## 实例化真实的 level.tscn 并注入关卡数据。调用方必须 await。
func _spawn_level(level_id: String) -> LevelRunner:
	var scene: PackedScene = load(LEVEL_SCENE_PATH)
	var runner: LevelRunner = scene.instantiate()
	var level: LevelData = DataRegistry.get_level(level_id)
	if level == null:
		_check("关卡存在：%s" % level_id, false, "DataRegistry 里找不到这个 id")
		runner.free()
		return null
	GameState.selected_level_id = level_id
	runner.setup(level)
	add_child(runner)
	await get_tree().physics_frame
	return runner


func _dispose(runner: LevelRunner) -> void:
	if runner == null or not is_instance_valid(runner):
		return
	get_tree().paused = false
	runner.queue_free()
	await _wait_physics(3)


## 取离某世界坐标最近的 n 个可建造格。
func _slots_near(map: MapData, world: Vector2, count: int) -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	slots.assign(map.build_slots)
	slots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return map.cell_to_world(a).distance_squared_to(world) \
			< map.cell_to_world(b).distance_squared_to(world))
	var result: Array[Vector2i] = []
	for i in mini(count, slots.size()):
		result.append(slots[i])
	return result


## 沿路径均匀取 count 个互不相同的塔位，保证任何形状的地图上塔都能真的打到怪。
func _spread_slots(map: MapData, count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var used := {}
	var step := maxi(count, 1)
	for i in count:
		var t := float(i) / float(step)
		var index := clampi(int(t * float(map.path.size() - 1)), 0, map.path.size() - 1)
		var anchor := map.cell_to_world(map.path[index])
		for slot in _slots_near(map, anchor, map.build_slots.size()):
			if not used.has(slot):
				used[slot] = true
				result.append(slot)
				break
	return result


# ---------------------------------------------------------------------------
# 测试主流程
# ---------------------------------------------------------------------------

func _run_all() -> void:
	_test_combat_math()
	_test_interval_and_division_guards()
	_test_map_data()
	_test_data_integrity()
	_test_geometry_invariant()
	_test_cjk_font()
	_test_settings_persistence()
	await _test_placement_rules()
	await _test_enemy_take_damage()
	await _test_all_levels_run()
	await _test_combat_integration()
	await _test_leak_and_win_condition()
	await _test_wave_system()
	await _test_pause()


# --- [A] 伤害公式纯函数 -------------------------------------------------------

func _test_combat_math() -> void:
	_section("[A] 伤害公式 Combat.compute_damage / resist_for")

	_check_almost("无抗性：12 物理 → 12", Combat.compute_damage(12.0, DamageType.Kind.PHYSICAL, 0.0, 0.0), 12.0)
	_check_almost("物抗 0.5：12 物理 → 6", Combat.compute_damage(12.0, DamageType.Kind.PHYSICAL, 0.5, 0.0), 6.0)
	_check_almost("物抗不影响法术：12 法术 → 12",
		Combat.compute_damage(12.0, DamageType.Kind.MAGIC, 0.5, 0.0), 12.0)
	_check_almost("法抗 0.5：12 法术 → 6",
		Combat.compute_damage(12.0, DamageType.Kind.MAGIC, 0.0, 0.5), 6.0)
	_check_almost("伤害 0 → 0", Combat.compute_damage(0.0, DamageType.Kind.PHYSICAL, 0.0, 0.0), 0.0)
	_check_almost("负伤害 → 0", Combat.compute_damage(-5.0, DamageType.Kind.PHYSICAL, 0.0, 0.0), 0.0)

	# 抗性上限：不做 clamp 的话抗性 1.0 会让伤害变 0，是数值设计上的死局
	_check_almost("抗性 2.0 被 clamp 到 0.9",
		Combat.resist_for(DamageType.Kind.PHYSICAL, 2.0, 0.0), Combat.MAX_RESIST)
	_check_almost("负抗性被 clamp 到 0", Combat.resist_for(DamageType.Kind.PHYSICAL, -1.0, 0.0), 0.0)
	_check("抗性上限 < 1", Combat.MAX_RESIST < 1.0, "否则该伤害类型永远无效")
	_check("最大抗性下伤害仍 > 0",
		Combat.compute_damage(12.0, DamageType.Kind.PHYSICAL, 1.0, 0.0) > 0.0)
	_check_almost("极端抗性不产生 NaN",
		Combat.compute_damage(12.0, DamageType.Kind.PHYSICAL, 99999.0, -99999.0), 1.2, 0.001)


# --- 除零守卫（踩过：运行时浮点除零静默返回 inf，inf 会污染成 NaN） -------------

func _test_interval_and_division_guards() -> void:
	_section("[A2] 除零守卫：攻速/出怪间隔为 0 时不能产出 inf")

	var tower := TowerData.new()
	tower.id = "test_zero_speed"
	tower.attack_speed = 0.0
	var interval := tower.get_attack_interval()
	_check("攻速 0 的攻击间隔是有限值", is_finite(interval),
		"实际 = %s（inf 会顺着乘法污染成 NaN）" % str(interval))
	_check("攻速 0 的攻击间隔 > 0", interval > 0.0, "实际 = %s" % str(interval))

	var negative := TowerData.new()
	negative.attack_speed = -3.0
	_check("负攻速的攻击间隔是有限值", is_finite(negative.get_attack_interval()))

	var group := SpawnGroup.new()
	group.count = 0
	group.interval = 1.0
	group.delay = 2.0
	_check_almost("出怪组 count=0 时最后出怪时刻 = delay", group.last_spawn_time(), 2.0)

	var group2 := SpawnGroup.new()
	group2.count = 4
	group2.interval = 0.5
	group2.delay = 1.0
	_check_almost("出怪组最后一个怪的时刻 = delay + interval*(count-1)", group2.last_spawn_time(), 2.5)


# --- [B] 地图数据 -------------------------------------------------------------

func _test_map_data() -> void:
	_section("[B] 六张地图的结构校验")

	var ids := DataRegistry.all_map_ids()
	_check_eq("地图数量", ids.size(), 6)

	for map_id in ids:
		var map: MapData = DataRegistry.get_map(map_id)
		if not _check("地图可加载：%s" % map_id, map != null):
			continue

		var problems := map.validate()
		_check("validate() 通过：%s" % map_id, problems.is_empty(), ", ".join(problems))
		_check("路径至少 2 格：%s" % map_id, map.path.size() >= 2)
		_check_eq("出怪口 = 路径首格：%s" % map_id, map.path[0], map.spawn_cell)
		_check_eq("进怪口 = 路径末格：%s" % map_id, map.path[map.path.size() - 1], map.goal_cell)
		_check("塔位非空：%s" % map_id, not map.build_slots.is_empty())

		# 独立复算：路径必须 4 连通、不自交（不依赖 validate 的自述）
		var seen := {}
		var duplicated := false
		var connected := true
		for i in map.path.size():
			var cell: Vector2i = map.path[i]
			if seen.has(cell):
				duplicated = true
			seen[cell] = true
			if i > 0:
				var prev: Vector2i = map.path[i - 1]
				if absi(cell.x - prev.x) + absi(cell.y - prev.y) != 1:
					connected = false
		_check("路径 4 连通（每步曼哈顿距离 1）：%s" % map_id, connected)
		_check("路径不自交：%s" % map_id, not duplicated)

		var in_bounds := true
		for cell in map.build_slots:
			if cell.x < 0 or cell.y < 0 or cell.x >= map.grid_size.x or cell.y >= map.grid_size.y:
				in_bounds = false
		_check("塔位都在网格内：%s" % map_id, in_bounds)

		var probe: Vector2i = map.path[map.path.size() / 2]
		_check_eq("world_to_cell(cell_to_world(c)) 往返：%s" % map_id,
			map.world_to_cell(map.cell_to_world(probe)), probe)

		var waypoints := map.get_waypoints()
		_check_eq("路点数量 = 路径格数：%s" % map_id, waypoints.size(), map.path.size())
		_check("路径像素长度 > 0：%s（%s px）" % [map_id, str(map.path_length())],
			map.path_length() > 0.0)


# --- [C] 数据完整性 -----------------------------------------------------------

func _test_data_integrity() -> void:
	_section("[C] 数据注册表完整性")

	var problems := DataRegistry.validate_all()
	_check("DataRegistry.validate_all() 无问题", problems.is_empty(),
		"发现 %d 条：%s" % [problems.size(), ", ".join(problems)])

	_check_eq("关卡数量（5 关 + 1 测试图）", DataRegistry.all_level_ids().size(), 6)
	_check_eq("防御塔种类（本版只要 1 种远程塔）", DataRegistry.all_tower_ids().size(), 1)
	_check_eq("敌人种类（本版 3 种近战）", DataRegistry.all_enemy_ids().size(), 3)

	for level_id in DataRegistry.all_level_ids():
		var level: LevelData = DataRegistry.get_level(level_id)
		if level == null:
			_check("关卡可加载：%s" % level_id, false)
			continue
		var level_problems := level.validate()
		_check("关卡 validate()：%s" % level_id, level_problems.is_empty(), ", ".join(level_problems))
		_check("关卡血量 > 0：%s" % level_id, level.base_health > 0)
		_check("波次非空：%s" % level_id, not level.waves.is_empty())
		_check("出怪总数 > 0：%s" % level_id, level.total_enemy_count() > 0)

		# id 引用完整性：关卡引用的地图必须真的解析得出来
		_check("关卡引用的地图可解析：%s → %s" % [level_id, level.map_id],
			DataRegistry.get_map(level.map_id) != null)

		for tower_id in level.allowed_tower_ids:
			_check("关卡允许的塔存在：%s → %s" % [level_id, tower_id],
				DataRegistry.get_tower(tower_id) != null)

		for wave in level.waves:
			for group in wave.groups:
				_check("敌人 id 存在：%s → %s" % [level_id, group.enemy_id],
					DataRegistry.get_enemy(group.enemy_id) != null)
				_check("出怪数 > 0：%s / %s" % [level_id, group.enemy_id], group.count > 0)
				_check("出怪间隔 > 0：%s / %s" % [level_id, group.enemy_id], group.interval > 0.0,
					"间隔为 0 会在一帧里吐完整组怪")

	var tower: TowerData = DataRegistry.get_tower("arrow_tower")
	if _check("arrow_tower 存在", tower != null):
		_check("arrow_tower 是远程（射程 > 近战上限）", tower.range > GameRules.MELEE_RANGE_MAX,
			"射程 = %s" % str(tower.range))
		_check("arrow_tower 有伤害", tower.damage > 0.0)
		_check("arrow_tower 有攻速", tower.attack_speed > 0.0)

	var names := {}
	for enemy_id in DataRegistry.all_enemy_ids():
		var enemy: EnemyData = DataRegistry.get_enemy(enemy_id)
		if enemy != null:
			names[enemy.display_name] = true
	_check_eq("三种敌人名字互不相同", names.size(), 3)
	_check("重甲真的带物理抗性（让抗性公式在游戏里可见）",
		DataRegistry.get_enemy("tank").physical_resist > 0.0)


# --- [H] 近战不可达不变式（本版核心几何约束） ----------------------------------

func _test_geometry_invariant() -> void:
	_section("[H] 近战不可达：敌人够不到塔（本版不实现塔受伤）")

	for enemy_id in DataRegistry.all_enemy_ids():
		var enemy: EnemyData = DataRegistry.get_enemy(enemy_id)
		if enemy == null:
			continue
		_check("敌人射程 < 格子尺寸（够不到塔位）：%s" % enemy_id,
			enemy.attack_range < float(GameRules.TILE_SIZE),
			"attack_range = %s，格子 = %d" % [str(enemy.attack_range), GameRules.TILE_SIZE])

	var min_clearance := INF
	for map_id in DataRegistry.all_map_ids():
		var map: MapData = DataRegistry.get_map(map_id)
		if map == null:
			continue

		var overlap := 0
		for cell in map.build_slots:
			if map.is_on_path(cell):
				overlap += 1
		_check("塔位与路径零重叠：%s" % map_id, overlap == 0, "重叠 %d 格" % overlap)

		var local_min := INF
		var local_max := 0.0
		for path_cell in map.path:
			var path_world := map.cell_to_world(path_cell)
			for slot in map.build_slots:
				var d := map.cell_to_world(slot).distance_to(path_world)
				local_min = minf(local_min, d)
				local_max = maxf(local_max, d)
		min_clearance = minf(min_clearance, local_min)
		_check("最近塔位-路径距离 >= 格子尺寸：%s（实际 %s）" % [map_id, str(local_min)],
			local_min >= float(GameRules.TILE_SIZE) - 0.001,
			"塔就在路上会破坏「敌人够不到塔」这条不变式")

	print("      （全部地图最小塔位-路径间距 = %s px，格子 = %d px）"
		% [str(min_clearance), GameRules.TILE_SIZE])

	# 塔本版不实现受伤（用户决策 4：血量/物抗/法抗只保留字段）
	var probe: Tower = Tower.new()
	_check("防御塔本版没有 take_damage（不实现被摧毁）", not probe.has_method("take_damage"))
	probe.free()


# --- [I] 中文字形（唯一能自动发现「中文变方框」的办法） ------------------------

func _test_cjk_font() -> void:
	_section("[I] 中文字形：界面用到的汉字都必须有字形")

	var font := UiKit.font()
	if not _check("UiKit 能拿到字体", font != null):
		return

	var missing := ""
	var checked := 0
	for i in CJK_SAMPLE.length():
		var code := CJK_SAMPLE[i].unicode_at(0)
		if code == 32:
			continue
		checked += 1
		if not font.has_char(code):
			missing += CJK_SAMPLE[i]
	_check("界面用到的汉字全部有字形（%d 个）" % checked, missing.is_empty(), "缺字形：%s" % missing)

	_check("project.godot 已配置自定义字体",
		str(ProjectSettings.get_setting("gui/theme/custom_font", "")) != "")

	var fallback: Font = ThemeDB.fallback_font
	if fallback != null:
		var fallback_missing := 0
		for i in CJK_SAMPLE.length():
			if not fallback.has_char(CJK_SAMPLE[i].unicode_at(0)):
				fallback_missing += 1
		print("      （内置 fallback 字体缺 %d / %d 个采样汉字 —— 这就是必须自带字体的原因）"
			% [fallback_missing, checked])


# --- [L] 设置持久化 -----------------------------------------------------------

func _test_settings_persistence() -> void:
	_section("[L] 设置写入 / 从磁盘读回 / 生效")

	var original_master := GameState.master_volume
	var original_speed := GameState.game_speed

	GameState.update_settings(func() -> void:
		GameState.master_volume = 0.42
		GameState.show_damage_popup = false
	)
	GameState.load_settings()
	_check_almost("主音量持久化 0.42", GameState.master_volume, 0.42, 0.001)
	_check_eq("伤害飘字开关持久化 false", GameState.show_damage_popup, false)

	GameState.set_game_speed(GameState.SPEED_FAST)
	_check_almost("2 倍速写入 Engine.time_scale", Engine.time_scale, GameState.SPEED_FAST, 0.001)
	_check("is_fast_forward() 为真", GameState.is_fast_forward())

	GameState.set_game_speed(GameState.SPEED_NORMAL)
	_check_almost("恢复 1 倍速", Engine.time_scale, GameState.SPEED_NORMAL, 0.001)
	_check("is_fast_forward() 为假", not GameState.is_fast_forward())

	GameState.update_settings(func() -> void:
		GameState.master_volume = original_master
		GameState.show_damage_popup = true
	)
	GameState.set_game_speed(original_speed)

	var path := ProjectSettings.globalize_path(GameState.SETTINGS_PATH)
	_check("配置文件写在 user:// 而不是 res://", path.contains("app_userdata"),
		"实际 = %s（res:// 导出后只读）" % path)


# --- [G] 放置规则 -------------------------------------------------------------

func _test_placement_rules() -> void:
	_section("[G] 建造规则")

	var runner := await _spawn_level("level_01")
	if runner == null:
		return

	var map := runner.map_data
	var builder := runner.build_manager
	if not _check("BuildManager 存在", builder != null):
		await _dispose(runner)
		return

	var path_cell: Vector2i = map.path[map.path.size() / 2]
	_check("路线上不能建造", not builder.can_place(path_cell, 99999).is_empty(),
		"返回空字符串说明竟然允许在敌人路线上建塔")

	var empty_cell := Vector2i(-1, -1)
	for y in map.grid_size.y:
		for x in map.grid_size.x:
			var cell := Vector2i(x, y)
			if not map.is_on_path(cell) and not map.has_build_slot(cell):
				empty_cell = cell
				break
		if empty_cell.x >= 0:
			break
	if _check("地图上存在既非路径也非塔位的空格", empty_cell.x >= 0):
		_check("非塔位不能建造", not builder.can_place(empty_cell, 99999).is_empty())

	var slots := _slots_near(map, map.cell_to_world(map.path[0]), 1)
	if _check("取到一个候选塔位", not slots.is_empty()):
		var slot: Vector2i = slots[0]
		var reason := builder.can_place(slot, 99999)
		_check("合法塔位可以建造", reason.is_empty(), "返回了拒绝理由：%s" % reason)

		var tower := builder.try_place(slot, runner.gold)
		if _check("try_place 返回了塔", tower != null):
			_check_eq("塔记录在对应格子上", builder.tower_at(slot), tower)
			_check_eq("塔数量 = 1", builder.tower_count(), 1)
			_check("同一格不能重复建造", not builder.can_place(slot, 99999).is_empty())
			_check_eq("塔的位置就是格子中心", tower.position, map.cell_to_world(slot))

			# 金币门槛：本版 enforce_cost = false，金币不足也放得下
			_check("本版关卡默认不启用金币门槛", not runner.level.enforce_cost)
			var others := _slots_near(map, map.cell_to_world(map.path[0]), 5)
			var free_slot: Vector2i = others[others.size() - 1]
			if builder.tower_at(free_slot) == null:
				_check("金币为 0 时仍可建造（本版无限制）",
					builder.can_place(free_slot, 0).is_empty())

				# 勾上门槛后同样的调用必须被拦住 —— 将来开启经济系统不需要改代码
				runner.level.enforce_cost = true
				_check("enforce_cost = true 且金币 0 → 被拒绝",
					not builder.can_place(free_slot, 0).is_empty())
				_check("enforce_cost = true 且金币充足 → 允许",
					builder.can_place(free_slot, 99999).is_empty())
				runner.level.enforce_cost = false

		# 悬停高亮
		builder.set_hover(slot, 0)
		_check_eq("悬停格被记录", builder.hover_cell(), slot)
		builder.clear_hover()
		_check_eq("clear_hover 后悬停格复位", builder.hover_cell(), Vector2i(-1, -1))

	await _dispose(runner)


# --- [E-part] 敌人受伤返回真实扣血量 -------------------------------------------

func _test_enemy_take_damage() -> void:
	_section("[E] 敌人受伤：返回值必须是实际扣血量（塔与飘字都靠它）")

	var map: MapData = DataRegistry.get_map("map_01")
	var path := map.get_waypoints()

	var grunt: Enemy = Enemy.create(DataRegistry.get_enemy("grunt"), path)
	add_child(grunt)
	_check_almost("小兵血量 = 60", grunt.hp, 60.0, 0.01)
	var dealt := grunt.take_damage(12.0, DamageType.Kind.PHYSICAL)
	_check_almost("小兵（0 物抗）挨 12 物理 → 实扣 12", dealt, 12.0)
	_check_almost("小兵剩余血量 48", grunt.hp, 48.0, 0.01)

	var tank: Enemy = Enemy.create(DataRegistry.get_enemy("tank"), path)
	add_child(tank)
	_check_almost("重甲血量 = 220", tank.hp, 220.0, 0.01)
	dealt = tank.take_damage(12.0, DamageType.Kind.PHYSICAL)
	_check_almost("重甲（0.5 物抗）挨 12 物理 → 实扣 6", dealt, 6.0)
	_check_almost("重甲剩余血量 214", tank.hp, 214.0, 0.01)
	dealt = tank.take_damage(12.0, DamageType.Kind.MAGIC)
	_check_almost("重甲（0 法抗）挨 12 法术 → 实扣 12", dealt, 12.0)
	_check_almost("重甲剩余血量 202", tank.hp, 202.0, 0.01)

	var died_fired := [false]
	grunt.died.connect(func(_e: Enemy) -> void: died_fired[0] = true)
	grunt.take_damage(9999.0, DamageType.Kind.PHYSICAL)
	_check("致命伤把血量打到 0", grunt.hp <= 0.001)
	_check("致命伤把 alive 置为 false", not grunt.alive)
	_check("致命伤发出 died 信号", died_fired[0])
	_check_almost("已死敌人再挨打 → 0（不能重复计分）",
		grunt.take_damage(50.0, DamageType.Kind.PHYSICAL), 0.0)

	tank.queue_free()
	if is_instance_valid(grunt):
		grunt.queue_free()
	await _wait_physics(3)


# --- [D] 六张地图在同一个 level.tscn 上各跑一段 --------------------------------

func _test_all_levels_run() -> void:
	_section("[D] 六张地图共用同一个 level.tscn，各跑 1200 物理帧（20 秒）")

	for level_id in DataRegistry.all_level_ids():
		var runner := await _spawn_level(level_id)
		if runner == null:
			continue

		var map := runner.map_data
		if not _check("关卡加载出地图：%s（map_id = %s）" % [level_id, runner.level.map_id],
			map != null):
			await _dispose(runner)
			continue

		_check_eq("关卡血量 = 配置值：%s" % level_id, runner.health, runner.level.base_health)
		_check_eq("初始金币 = 配置值：%s" % level_id, runner.gold, runner.level.starting_gold)

		var candidates := _spread_slots(map, 4)
		var placed := 0
		for slot in candidates:
			if runner.build_manager.try_place(slot, runner.gold) != null:
				placed += 1
		_check("沿路放下 4 座塔：%s" % level_id, placed == candidates.size(),
			"放下 %d / 计划 %d" % [placed, candidates.size()])

		await _run_until(runner, 1200)

		var snap := runner.snapshot()
		_check("有敌人出场：%s（spawned = %d）" % [level_id, int(snap["spawned"])],
			int(snap["spawned"]) > 0)
		_check("塔开过火：%s（shots = %d）" % [level_id, int(snap["shots"])],
			int(snap["shots"]) > 0)
		_check("造成了伤害：%s（damage = %s）" % [level_id, str(snap["damage"])],
			float(snap["damage"]) > 0.0)
		_check("血量在合法区间：%s（%d / %d）" % [level_id, int(snap["health"]), int(snap["max_health"])],
			int(snap["health"]) >= 0 and int(snap["health"]) <= int(snap["max_health"]))
		_check("击杀 + 漏怪 <= 出场总数：%s" % level_id,
			int(snap["killed"]) + int(snap["leaked"]) <= int(snap["spawned"]))

		var sane := true
		for node in get_tree().get_nodes_in_group(LevelRunner.ENEMY_GROUP):
			var e := node as Enemy
			if e == null:
				continue
			if not (is_finite(e.position.x) and is_finite(e.position.y)):
				sane = false
		_check("敌人坐标无 NaN/inf：%s" % level_id, sane)

		await _dispose(runner)

	get_tree().paused = false


# --- [E-integration] 防御塔真的能打死敌人 --------------------------------------

func _test_combat_integration() -> void:
	_section("[E] 战斗集成：塔 → 弹道 → 敌人扣血 → 死亡")

	var runner := await _spawn_level("level_test")
	if runner == null:
		return

	var map := runner.map_data
	var gold_before := runner.gold

	var built := 0
	for slot in _spread_slots(map, 4):
		if runner.build_manager.try_place(slot, runner.gold) != null:
			built += 1
	_check("测试图上放下 4 座塔", built == 4)
	_check_eq("放置不扣金币（本版无经济限制）", runner.gold, gold_before)

	await _run_until(runner, 3600, func() -> bool: return runner.killed_total > 0)
	var snap := runner.snapshot()

	_check("有敌人被打死（killed = %d）" % int(snap["killed"]), int(snap["killed"]) > 0)
	_check("累计伤害 > 0（damage = %s）" % str(snap["damage"]), float(snap["damage"]) > 0.0)
	_check("开火次数 >= 击杀数（shots = %d，killed = %d）"
		% [int(snap["shots"]), int(snap["killed"])],
		int(snap["shots"]) >= int(snap["killed"]))

	# 一只小兵 60 血、塔 12 伤害/发 → 至少 5 发才能打死一只
	var expected_min_shots := int(snap["killed"]) * 5
	_check("开火次数 >= 击杀数 * 5（每只小兵至少 5 发）：%d >= %d"
		% [int(snap["shots"]), expected_min_shots], int(snap["shots"]) >= expected_min_shots)
	_check("击杀 + 漏怪 <= 出场",
		int(snap["killed"]) + int(snap["leaked"]) <= int(snap["spawned"]))

	await _dispose(runner)


# --- [F] 漏怪计数与胜负 -------------------------------------------------------

func _test_leak_and_win_condition() -> void:
	_section("[F] 漏怪扣血：第 1 关不放塔，5 只全漏 → 血量 10 - 5 = 5，判胜")

	var runner := await _spawn_level("level_01")
	if runner == null:
		return

	var base_health := runner.level.base_health
	await _run_until(runner, 6000)

	var snap := runner.snapshot()
	_check_eq("出怪总数 = 关卡配置", int(snap["spawned"]), runner.level.total_enemy_count())
	_check_eq("漏怪数 = 5", int(snap["leaked"]), 5)
	_check_eq("击杀数 = 0（没放塔）", int(snap["killed"]), 0)
	_check_eq("关卡血量 = 10 - 5", int(snap["health"]), base_health - 5)
	_check_eq("每漏 1 只扣 1 点（血量损失 = 漏怪数）",
		base_health - int(snap["health"]), int(snap["leaked"]))
	_check("全部清空后判定为胜利（血量还有剩）", runner.phase == LevelRunner.Phase.WON,
		"phase = %d，game_finished = %s" % [runner.phase, str(runner.game_finished)])
	_check("存活敌人归零", runner.enemies_alive() == 0)

	await _dispose(runner)

	# 血量归零判负
	var runner2 := await _spawn_level("level_01")
	if runner2 == null:
		return
	runner2.health = 1
	await _run_until(runner2, 6000)
	_check("血量被打空后判负", runner2.phase == LevelRunner.Phase.LOST,
		"phase = %d，health = %d" % [runner2.phase, runner2.health])
	_check_eq("血量不会变成负数", runner2.health, 0)
	_check("判负后 game_finished 为真", runner2.game_finished)
	await _dispose(runner2)


# --- [J] 波次系统 -------------------------------------------------------------

func _test_wave_system() -> void:
	_section("[J] 波次系统：第 2 关（2 波共 14 只）不放塔跑到结束")

	var runner := await _spawn_level("level_02")
	if runner == null:
		return

	var level := runner.level
	_check_eq("本关波次数 = 2", level.waves.size(), 2)
	_check_eq("本关出怪总数 = 14", level.total_enemy_count(), 14)
	_check_eq("开局波次索引 = -1（尚未开始）", runner.wave_index, -1)

	var seen_phases := {}
	var seen_wave_indices := {}
	var frames := 0
	while frames < 8000:
		await get_tree().physics_frame
		frames += 1
		seen_phases[runner.phase] = true
		seen_wave_indices[runner.wave_index] = true
		if runner.game_finished:
			break

	var snap := runner.snapshot()
	_check("经历过准备阶段", seen_phases.has(LevelRunner.Phase.PREP))
	_check("经历过出怪阶段", seen_phases.has(LevelRunner.Phase.WAVE))
	_check("经历过波间等待", seen_phases.has(LevelRunner.Phase.INTERVAL),
		"两波之间的间隔就是被 auto_next_wave 控制的那一段")
	_check("走到了第 2 波", seen_wave_indices.has(1),
		"出现过的波次索引：%s" % str(seen_wave_indices.keys()))
	_check("没有走到不存在的第 3 波", not seen_wave_indices.has(2))
	_check_eq("出场总数 = 配置的 14 只", int(snap["spawned"]), 14)
	_check("14 只全漏 → 血量归零 → 判负", runner.phase == LevelRunner.Phase.LOST,
		"phase = %d，health = %d，leaked = %d"
			% [runner.phase, runner.health, runner.leaked_total])
	# 相对断言：血量归零的那一刻就判负并冻结战场，后面还在路上的怪不再结算，
	# 所以漏怪数应该恰好等于关卡血量，而不是出怪总数。
	_check_eq("漏怪数 = 关卡血量（判负即刻冻结，后面的怪不再结算）",
		runner.leaked_total, level.base_health)
	_check("判负时场上还留着没走完的敌人（战场确实被冻结了）", runner.enemies_alive() > 0,
		"还剩 %d 只在路上" % runner.enemies_alive())

	await _dispose(runner)

	# 「立即开始」按钮
	var runner3 := await _spawn_level("level_03")
	if runner3 == null:
		return
	_check("开局处于准备阶段", runner3.phase == LevelRunner.Phase.PREP)
	_check("准备阶段有倒计时", runner3.countdown > 0.0)
	runner3.start_next_wave_now()
	_check("点「立即开始」后进入出怪阶段", runner3.phase == LevelRunner.Phase.WAVE,
		"phase = %d" % runner3.phase)
	await _wait_physics(30)
	_check("立即开始后确实开始出怪", runner3.spawned_total > 0,
		"spawned = %d" % runner3.spawned_total)
	await _dispose(runner3)


# --- [K] 暂停 -----------------------------------------------------------------

func _test_pause() -> void:
	_section("[K] 暂停：场景时间真的停住，且能恢复")

	var runner := await _spawn_level("level_test")
	if runner == null:
		return

	await _run_until(runner, 2000, func() -> bool: return runner.spawned_total > 0)
	var spawned_at_pause := runner.spawned_total
	_check("暂停前已经有敌人出场", spawned_at_pause > 0)

	runner.set_paused(true)
	_check("runner.paused 为真", runner.paused)
	_check("SceneTree.paused 为真（整场冻结）", get_tree().paused)

	await _wait_physics(120)
	_check_eq("暂停期间不再出怪", runner.spawned_total, spawned_at_pause)

	var reference := Vector2.ZERO
	var has_reference := false
	for node in get_tree().get_nodes_in_group(LevelRunner.ENEMY_GROUP):
		var e := node as Enemy
		if e == null:
			continue
		reference = e.position
		has_reference = true
		break
	await _wait_physics(60)
	if has_reference:
		var enemy_moved := false
		for node in get_tree().get_nodes_in_group(LevelRunner.ENEMY_GROUP):
			var e := node as Enemy
			if e == null:
				continue
			if not e.position.is_equal_approx(reference):
				enemy_moved = true
		_check("暂停期间敌人不移动", not enemy_moved)

	runner.set_paused(false)
	_check("恢复后 runner.paused 为假", not runner.paused)
	_check("恢复后 SceneTree.paused 为假", not get_tree().paused)
	await _wait_physics(180)
	_check("恢复后继续出怪", runner.spawned_total > spawned_at_pause,
		"暂停时 %d，恢复后 %d" % [spawned_at_pause, runner.spawned_total])

	var before := runner.paused
	runner.toggle_paused()
	_check("toggle_paused 翻转状态", runner.paused != before)
	runner.set_paused(false)

	await _dispose(runner)
	get_tree().paused = false


# ---------------------------------------------------------------------------
# 收尾
# ---------------------------------------------------------------------------

func _report() -> void:
	get_tree().paused = false
	print("")
	print("========== 结果 ==========")
	print("通过 %d ，失败 %d" % [_passed, _failed])
	if _failed > 0:
		print("失败项：")
		for line in _failures:
			print(line)
		print("SMOKE_RESULT=FAIL")
	else:
		print("SMOKE_RESULT=OK")
	get_tree().quit(1 if _failed > 0 else 0)
