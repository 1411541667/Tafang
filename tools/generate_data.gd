extends SceneTree
## 数据生成器：把「地图 / 防御塔 / 敌人 / 关卡波次」的定义写成 .tres 资源。
##
## 运行：
##   & $GODOT --headless --path <项目> -s res://tools/generate_data.gd --quit-after 900
##
## 【设计】可重复运行、覆盖式。这里是所有游戏数据的权威来源。
## 【新增一张地图】= 在 MAP_SPECS 里加一项（网格 + 拐点），重跑本命令。
## 【新增一个关卡】= 在 LEVEL_SPECS 里加一项，重跑本命令。
## 【新增一个兵种 / 塔】= 在 ENEMY_SPECS / TOWER_SPECS 里加一项，同时更新 DataRegistry 的路径表。
##
## 地图用小写 ASCII 画一遍（render_ascii），再交给 MapData.from_ascii() 解析出有序路径 ——
## 所以「路径顺序」是推导出来的，不需要人工维护，也不会写错。
## 塔位则自动生成（紧邻路径的正交相邻格），保证「塔位与路径永不重叠」这条核心不变式。

# ---------------------------------------------------------------------------
# 地图定义：网格 + 轴对齐拐点
# ---------------------------------------------------------------------------
# corners 是敌人行进路线的拐点序列；相邻两点必须共行或共列。
# build_slots 不在下面写死 —— 由 MapData.fill_build_slots_adjacent_to_path() 自动生成。

var MAP_SPECS := [
	{
		"id": "map_01", "name": "直线走廊", "grid": Vector2i(20, 11),
		"corners": [Vector2i(0, 5), Vector2i(19, 5)],
	},
	{
		"id": "map_02", "name": "Z 形折返", "grid": Vector2i(20, 11),
		"corners": [Vector2i(0, 2), Vector2i(15, 2), Vector2i(15, 8), Vector2i(19, 8)],
	},
	{
		"id": "map_03", "name": "蛇形长路", "grid": Vector2i(20, 11),
		"corners": [
			Vector2i(0, 1), Vector2i(18, 1), Vector2i(18, 4),
			Vector2i(1, 4), Vector2i(1, 7), Vector2i(18, 7), Vector2i(18, 9),
		],
	},
	{
		"id": "map_04", "name": "U 形回廊", "grid": Vector2i(20, 11),
		"corners": [Vector2i(0, 1), Vector2i(0, 9), Vector2i(19, 9), Vector2i(19, 1)],
	},
	{
		"id": "map_05", "name": "回形迷宫", "grid": Vector2i(20, 11),
		"corners": [
			Vector2i(0, 0), Vector2i(19, 0), Vector2i(19, 10),
			Vector2i(0, 10), Vector2i(0, 3), Vector2i(16, 3),
		],
	},
	{
		"id": "map_test", "name": "测试地图 · 直线", "grid": Vector2i(20, 11),
		"corners": [Vector2i(0, 5), Vector2i(19, 5)],
	},
]

# ---------------------------------------------------------------------------
# 防御塔定义
# ---------------------------------------------------------------------------
# special_attack 值域: "" | "slow" | "splash"（本版均不生效，仅占位）

var TOWER_SPECS := [
	{
		"id": "arrow_tower", "name": "箭塔",
		"range": 160.0, "attack_speed": 1.2, "damage": 12.0,
		"damage_type": DamageType.Kind.PHYSICAL, "special_attack": "",
		"target_priority": 0,
		"max_health": 120.0, "physical_resist": 0.0, "magic_resist": 0.0,
		"projectile_speed": 520.0, "instant_hit": false, "cost": 50,
	},
]

# ---------------------------------------------------------------------------
# 敌人定义（三种，射程全部是近战 —— 够不到防御塔）
# ---------------------------------------------------------------------------

var ENEMY_SPECS := [
	{
		"id": "grunt", "name": "小兵",
		"max_health": 60.0, "move_speed": 70.0,
		"physical_resist": 0.0, "magic_resist": 0.0,
		"attack_range": 40.0, "attack_speed": 1.0, "damage": 5.0,
		"damage_type": DamageType.Kind.PHYSICAL, "special_attack": "",
		"gold_reward": 10, "body_radius": 16.0, "color": "#e04b4b",
	},
	{
		"id": "runner", "name": "疾行",
		"max_health": 40.0, "move_speed": 120.0,
		"physical_resist": 0.0, "magic_resist": 0.0,
		"attack_range": 36.0, "attack_speed": 1.2, "damage": 4.0,
		"damage_type": DamageType.Kind.PHYSICAL, "special_attack": "",
		"gold_reward": 8, "body_radius": 13.0, "color": "#f0952f",
	},
	{
		"id": "tank", "name": "重甲",
		"max_health": 220.0, "move_speed": 45.0,
		"physical_resist": 0.5, "magic_resist": 0.0,
		"attack_range": 48.0, "attack_speed": 0.7, "damage": 12.0,
		"damage_type": DamageType.Kind.PHYSICAL, "special_attack": "",
		"gold_reward": 25, "body_radius": 20.0, "color": "#a259d8",
	},
]

# ---------------------------------------------------------------------------
# 关卡定义：关卡血量 / 地图 / 防御塔 / 敌人
# ---------------------------------------------------------------------------
# waves 是「波次数组」，每个波次是「出怪组数组」。
# 出怪组字段：enemy（必填）、count、interval、delay、hp_scale、speed_scale

var LEVEL_SPECS := [
	{
		"id": "level_01", "name": "第 1 关 · 直线走廊", "map": "map_01",
		"base_health": 10, "starting_gold": 150,
		"prep_time": 8.0, "wave_interval": 12.0,
		"waves": [
			[{"enemy": "grunt", "count": 5, "interval": 1.0}],
		],
	},
	{
		"id": "level_02", "name": "第 2 关 · Z 形折返", "map": "map_02",
		"base_health": 12, "starting_gold": 180,
		"prep_time": 8.0, "wave_interval": 12.0,
		"waves": [
			[{"enemy": "grunt", "count": 6, "interval": 1.0}],
			[
				{"enemy": "grunt", "count": 4, "interval": 1.0},
				{"enemy": "runner", "count": 4, "interval": 0.8, "delay": 4.0},
			],
		],
	},
	{
		"id": "level_03", "name": "第 3 关 · 蛇形长路", "map": "map_03",
		"base_health": 15, "starting_gold": 220,
		"prep_time": 8.0, "wave_interval": 12.0,
		"waves": [
			[{"enemy": "grunt", "count": 8, "interval": 0.9}],
			[{"enemy": "runner", "count": 10, "interval": 0.6}],
			[
				{"enemy": "grunt", "count": 6, "interval": 1.0},
				{"enemy": "runner", "count": 6, "interval": 0.8, "delay": 3.0},
			],
		],
	},
	{
		"id": "level_04", "name": "第 4 关 · U 形回廊", "map": "map_04",
		"base_health": 18, "starting_gold": 260,
		"prep_time": 8.0, "wave_interval": 12.0,
		"waves": [
			[{"enemy": "grunt", "count": 8, "interval": 0.9}],
			[
				{"enemy": "grunt", "count": 6, "interval": 1.0},
				{"enemy": "tank", "count": 2, "interval": 3.0, "delay": 2.0},
			],
			[
				{"enemy": "runner", "count": 8, "interval": 0.7},
				{"enemy": "tank", "count": 3, "interval": 2.5, "delay": 4.0},
			],
		],
	},
	{
		"id": "level_05", "name": "第 5 关 · 回形迷宫", "map": "map_05",
		"base_health": 20, "starting_gold": 320,
		"prep_time": 8.0, "wave_interval": 12.0,
		"waves": [
			[{"enemy": "grunt", "count": 10, "interval": 0.8}],
			[{"enemy": "runner", "count": 12, "interval": 0.5}],
			[
				{"enemy": "grunt", "count": 8, "interval": 0.9},
				{"enemy": "tank", "count": 4, "interval": 2.5, "delay": 3.0},
			],
			[
				{"enemy": "runner", "count": 10, "interval": 0.6},
				{"enemy": "tank", "count": 6, "interval": 2.0, "delay": 5.0, "hp_scale": 1.3},
			],
		],
	},
	{
		"id": "level_test", "name": "测试地图 · 直线", "map": "map_test",
		"base_health": 99, "starting_gold": 999,
		"prep_time": 3.0, "wave_interval": 12.0,
		"waves": [
			[{"enemy": "grunt", "count": 20, "interval": 0.3}],
		],
	},
]

const TOWER_DIR := "res://data/towers/"
const ENEMY_DIR := "res://data/enemies/"
const MAP_DIR := "res://data/maps/"
const LEVEL_DIR := "res://data/levels/"

var _errors: Array[String] = []
var _written: Array[String] = []

func _initialize() -> void:
	print("[generate_data] 开始生成数据……")
	var maps := _generate_maps()
	if maps.is_empty():
		_finish()
		return
	_generate_towers()
	_generate_enemies()
	_generate_levels()
	_finish()

func _finish() -> void:
	print("")
	_verify_roundtrip()

	print("[generate_data] 已写入 %d 个资源：" % _written.size())
	for path in _written:
		print("    " + path)

	# 生成后立即做一次全量校验（含 id 引用完整性 + 近战不可达不变式）
	var data_errors := DataRegistry.validate_all()
	for e in data_errors:
		_errors.append("[校验] " + e)

	print("")
	if _errors.is_empty():
		print("GENERATE_RESULT=OK")
		print("[generate_data] 全部数据生成并通过校验 ✅")
		quit(0)
		return

	printerr("[generate_data] 生成失败，共 %d 个问题：" % _errors.size())
	for e in _errors:
		printerr("    " + e)
	print("GENERATE_RESULT=FAIL")
	quit(1)

# ---------------------------------------------------------------------------
# 往返校验：把刚写下的 .tres 从磁盘重新读一遍，逐字段对照规格表
# ---------------------------------------------------------------------------
#
# 【为什么必须做】Godot 的 .tres 文本保存器会「省略等于脚本默认值的属性」。
# 如果某个 @export 的默认值和规格表里的值撞上，那个字段就会被静默省略 ——
# 文件看起来完全正常，数据却是错的（或者更糟：改了默认值，旧文件语义悄悄变了）。
# 只有「写出 → 从磁盘读回 → 逐字段比对」才能发现这类问题。

func _verify_roundtrip() -> void:
	print("[generate_data] 往返校验（从磁盘重新读取）……")

	for spec: Dictionary in MAP_SPECS:
		_verify_map(spec)

	for spec: Dictionary in TOWER_SPECS:
		var path: String = TOWER_DIR + String(spec["id"]) + ".tres"
		var raw: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var tower: TowerData = raw as TowerData
		if tower == null:
			_errors.append("[往返] %s 无法作为 TowerData 从磁盘加载" % path)
			continue
		_expect(tower.id == spec["id"], "%s: id" % path)
		_expect(tower.range == float(spec["range"]), "%s: range" % path)
		_expect(tower.attack_speed == float(spec["attack_speed"]), "%s: attack_speed" % path)
		_expect(tower.damage == float(spec["damage"]), "%s: damage" % path)
		_expect(tower.damage_type == spec["damage_type"], "%s: damage_type" % path)
		_expect(tower.cost == int(spec["cost"]), "%s: cost" % path)

	for spec: Dictionary in ENEMY_SPECS:
		var path: String = ENEMY_DIR + String(spec["id"]) + ".tres"
		var raw: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var enemy: EnemyData = raw as EnemyData
		if enemy == null:
			_errors.append("[往返] %s 无法作为 EnemyData 从磁盘加载" % path)
			continue
		_expect(enemy.id == spec["id"], "%s: id" % path)
		_expect(enemy.max_health == float(spec["max_health"]), "%s: max_health" % path)
		_expect(enemy.move_speed == float(spec["move_speed"]), "%s: move_speed" % path)
		_expect(enemy.physical_resist == float(spec["physical_resist"]), "%s: physical_resist" % path)
		_expect(enemy.attack_range == float(spec["attack_range"]), "%s: attack_range" % path)
		_expect(enemy.gold_reward == int(spec["gold_reward"]), "%s: gold_reward" % path)

	for spec: Dictionary in LEVEL_SPECS:
		_verify_level(spec)

	# 关卡必须用 id 引用地图：关卡文件里不能再出现地图数据的副本，
	# 否则改地图文件不会影响任何关卡（数据静默分叉）。
	for spec: Dictionary in LEVEL_SPECS:
		var level_id: String = spec["id"]
		var path: String = LEVEL_DIR + level_id + ".tres"
		var raw: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var level: LevelData = raw as LevelData
		if level == null:
			continue
		if DataRegistry.get_map(level.map_id) == null:
			_errors.append("[往返] %s: map_id '%s' 无法在注册表解析" % [path, level.map_id])
		var map_path: String = MAP_DIR + String(spec["map"]) + ".tres"
		var map_raw: Resource = ResourceLoader.load(map_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var map: MapData = map_raw as MapData
		if map == null:
			_errors.append("[往返] %s: 引用的地图 %s 无法独立从磁盘加载" % [path, map_path])
		elif map.id != String(spec["map"]):
			_errors.append("[往返] %s: 引用的地图 %s 内 id 为 '%s'" % [path, map_path, map.id])

## 单张地图：独立从磁盘读回，并守住「塔位与路径永不重叠」这条核心不变式。
func _verify_map(spec: Dictionary) -> void:
	var map_id: String = spec["id"]
	var path: String = MAP_DIR + map_id + ".tres"
	var raw: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var map: MapData = raw as MapData
	if map == null:
		_errors.append("[往返] %s 无法作为 MapData 从磁盘加载" % path)
		return

	_expect(map.id == map_id, "%s: id" % path)
	_expect(map.resource_path == path, "%s: resource_path 应为自身路径（实际 '%s'）" % [path, map.resource_path])
	_expect(map.path.size() >= 2, "%s: path 至少要有 2 格" % path)
	_expect(not map.build_slots.is_empty(), "%s: build_slots 为空" % path)
	if not map.path.is_empty():
		_expect(map.spawn_cell == map.path[0], "%s: spawn_cell 应为路径首格" % path)
		_expect(map.goal_cell == map.path[map.path.size() - 1], "%s: goal_cell 应为路径末格" % path)

	var path_set := {}
	for cell in map.path:
		path_set[cell] = true
	for cell in map.build_slots:
		if path_set.has(cell):
			_errors.append("[往返] %s: build_slots 与 path 重叠于 %s（破坏近战不可达不变式）" % [path, cell])
			break

	if map.resource_path == path:
		var corners: Array = spec["corners"]
		_expect(map.spawn_cell == corners[0], "%s: spawn_cell 应为拐点首项" % path)
		_expect(map.goal_cell == corners[corners.size() - 1], "%s: goal_cell 应为拐点末项" % path)

func _verify_level(spec: Dictionary) -> void:
	var level_id: String = spec["id"]
	var path: String = LEVEL_DIR + level_id + ".tres"
	var raw: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var level: LevelData = raw as LevelData
	if level == null:
		_errors.append("[往返] %s 无法作为 LevelData 从磁盘加载" % path)
		return

	_expect(level.id == level_id, "%s: id" % path)
	_expect(level.base_health == int(spec["base_health"]), "%s: base_health" % path)
	_expect(level.starting_gold == int(spec["starting_gold"]), "%s: starting_gold" % path)
	if level.map_id != String(spec["map"]):
		_errors.append("[往返] %s: map_id 期望 '%s'，实际 '%s'" % [path, spec["map"], level.map_id])
	_expect(not level.allowed_tower_ids.is_empty(), "%s: allowed_tower_ids 为空" % path)

	var wave_specs: Array = spec["waves"]
	if level.waves.size() != wave_specs.size():
		_errors.append("[往返] %s: 波次数量期望 %d，实际 %d" % [
			path, wave_specs.size(), level.waves.size()])
		return

	for w in wave_specs.size():
		var group_specs: Array = wave_specs[w]
		var wave: WaveData = level.waves[w]
		if wave.groups.size() != group_specs.size():
			_errors.append("[往返] %s 第 %d 波: 出怪组数量期望 %d，实际 %d" % [
				path, w + 1, group_specs.size(), wave.groups.size()])
			continue
		for g in group_specs.size():
			var gs: Dictionary = group_specs[g]
			var group: SpawnGroup = wave.groups[g]
			var ctx := "%s 第 %d 波第 %d 组" % [path, w + 1, g + 1]
			if group.enemy_id != String(gs["enemy"]):
				_errors.append("[往返] %s: enemy_id 期望 %s，实际 %s" % [ctx, gs["enemy"], group.enemy_id])
			_expect(group.count == int(gs.get("count", 1)), "%s: count" % ctx)
			_expect(group.interval == float(gs.get("interval", 1.0)), "%s: interval" % ctx)
			_expect(group.delay == float(gs.get("delay", 0.0)), "%s: delay" % ctx)
			_expect(group.hp_scale == float(gs.get("hp_scale", 1.0)), "%s: hp_scale" % ctx)
			_expect(group.speed_scale == float(gs.get("speed_scale", 1.0)), "%s: speed_scale" % ctx)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_errors.append("[往返] 字段不一致：%s" % label)


# ---------------------------------------------------------------------------
# 地图
# ---------------------------------------------------------------------------

func _generate_maps() -> Dictionary:
	var result := {}
	for spec: Dictionary in MAP_SPECS:
		var map_id: String = spec["id"]
		var grid: Vector2i = spec["grid"]
		var corners: Array = spec["corners"]

		# 1) 按拐点渲染一张 ASCII 图（人可读，也是解析的输入）
		var rows := _render_ascii(map_id, grid, corners)
		if rows.is_empty():
			continue

		# 2) 解析出有序路径（路径顺序是推导出来的，不是人工维护的）
		var map := MapData.from_ascii(rows, map_id, spec["name"], GameRules.TILE_SIZE)

		# 3) 自动生成塔位：紧邻路径的正交相邻格 → 天然满足「塔位与路径永不重叠」
		map.fill_build_slots_adjacent_to_path()

		# 4) 存盘
		var path: String = MAP_DIR + map_id + ".tres"
		if not _save(map, path):
			continue
		_written.append(path)

		# 5) 单图校验
		for e in map.validate():
			_errors.append("[%s] %s" % [map_id, e])

		print("[generate_data] %s  %s  路径 %d 格 / 塔位 %d 个 / 长度 %d px" % [
			map_id, spec["name"], map.path.size(), map.build_slots.size(), int(map.path_length())])
		print(_ascii_block(rows))

		result[map_id] = map
	return result

## 按轴对齐拐点渲染 ASCII 图。返回空数组表示渲染失败。
func _render_ascii(map_id: String, grid: Vector2i, corners: Array) -> PackedStringArray:
	var cells: Array = []
	for y in grid.y:
		var row: Array = []
		for x in grid.x:
			row.append(MapData.ASCII_EMPTY)
		cells.append(row)

	for i in range(1, corners.size()):
		var a: Vector2i = corners[i - 1]
		var b: Vector2i = corners[i]
		if a.x != b.x and a.y != b.y:
			_errors.append("[%s] 拐点 %s -> %s 不是轴对齐线段（必须共行或共列）" % [map_id, a, b])
			return PackedStringArray()
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var cur := a
		while true:
			if not _in_grid(cur, grid):
				_errors.append("[%s] 拐点 %s -> %s 画出了边界：%s 越界" % [map_id, a, b, cur])
				return PackedStringArray()
			cells[cur.y][cur.x] = MapData.ASCII_PATH
			if cur == b:
				break
			cur += step

	var first: Vector2i = corners[0]
	var last: Vector2i = corners[corners.size() - 1]
	if first == last:
		_errors.append("[%s] 出怪口与进怪口是同一格 %s" % [map_id, first])
		return PackedStringArray()
	cells[first.y][first.x] = MapData.ASCII_SPAWN
	cells[last.y][last.x] = MapData.ASCII_GOAL

	var rows := PackedStringArray()
	for y in grid.y:
		var line := ""
		for x in grid.x:
			var ch: String = cells[y][x]
			line += ch
		rows.append(line)
	return rows

func _in_grid(cell: Vector2i, grid: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid.x and cell.y < grid.y

func _ascii_block(rows: PackedStringArray) -> String:
	var text := ""
	for row in rows:
		text += "        " + row + "\n"
	return text

# ---------------------------------------------------------------------------
# 防御塔
# ---------------------------------------------------------------------------

func _generate_towers() -> void:
	for spec: Dictionary in TOWER_SPECS:
		var tower := TowerData.new()
		tower.id = spec["id"]
		tower.display_name = spec["name"]
		tower.range = float(spec["range"])
		tower.attack_speed = float(spec["attack_speed"])
		tower.damage = float(spec["damage"])
		tower.damage_type = spec["damage_type"]
		tower.special_attack = spec["special_attack"]
		tower.target_priority = int(spec["target_priority"])
		tower.max_health = float(spec["max_health"])
		tower.physical_resist = float(spec["physical_resist"])
		tower.magic_resist = float(spec["magic_resist"])
		tower.projectile_speed = float(spec["projectile_speed"])
		tower.instant_hit = bool(spec["instant_hit"])
		tower.cost = int(spec["cost"])

		var path: String = TOWER_DIR + tower.id + ".tres"
		if _save(tower, path):
			_written.append(path)
			print("[generate_data] %s  %s  射程 %.0f / 攻速 %.2f / 伤害 %.0f %s" % [
				tower.id, tower.display_name, tower.range, tower.attack_speed,
				tower.damage, DamageType.display_name(tower.damage_type)])

# ---------------------------------------------------------------------------
# 敌人
# ---------------------------------------------------------------------------

func _generate_enemies() -> void:
	for spec: Dictionary in ENEMY_SPECS:
		var enemy := EnemyData.new()
		enemy.id = spec["id"]
		enemy.display_name = spec["name"]
		enemy.max_health = float(spec["max_health"])
		enemy.move_speed = float(spec["move_speed"])
		enemy.physical_resist = float(spec["physical_resist"])
		enemy.magic_resist = float(spec["magic_resist"])
		enemy.attack_range = float(spec["attack_range"])
		enemy.attack_speed = float(spec["attack_speed"])
		enemy.damage = float(spec["damage"])
		enemy.damage_type = spec["damage_type"]
		enemy.special_attack = spec["special_attack"]
		enemy.gold_reward = int(spec["gold_reward"])
		enemy.body_radius = float(spec["body_radius"])
		enemy.color = Color(spec["color"])

		var path: String = ENEMY_DIR + enemy.id + ".tres"
		if _save(enemy, path):
			_written.append(path)
			print("[generate_data] %s  %s  血量 %.0f / 移速 %.0f / 物抗 %.2f / 近战射程 %.0f" % [
				enemy.id, enemy.display_name, enemy.max_health, enemy.move_speed,
				enemy.physical_resist, enemy.attack_range])

# ---------------------------------------------------------------------------
# 关卡
# ---------------------------------------------------------------------------

func _generate_levels() -> void:
	for spec: Dictionary in LEVEL_SPECS:
		var level := LevelData.new()
		level.id = spec["id"]
		level.display_name = spec["name"]
		level.base_health = int(spec["base_health"])
		level.starting_gold = int(spec["starting_gold"])
		level.enforce_cost = false   # 本版不做金币限制（用户决策 3）
		level.prep_time = float(spec["prep_time"])
		level.wave_interval = float(spec["wave_interval"])
		level.auto_next_wave = true
		level.allowed_tower_ids = PackedStringArray(["arrow_tower"])

		# 地图按 id 引用（不持有 MapData 对象），运行时由 DataRegistry 解析
		var map_id: String = String(spec["map"])
		level.map_id = map_id

		var waves: Array[WaveData] = []
		for wave_spec: Array in spec["waves"]:
			waves.append(_make_wave(wave_spec, level.id))
		level.waves = waves

		var path: String = LEVEL_DIR + level.id + ".tres"
		if _save(level, path):
			_written.append(path)
			print("[generate_data] %s  %s  关卡血量 %d / 地图 %s / %d 波 / 共 %d 只怪" % [
				level.id, level.display_name, level.base_health, map_id,
				level.waves.size(), level.total_enemy_count()])

func _make_wave(groups_spec: Array, level_id: String) -> WaveData:
	var wave := WaveData.new()
	var groups: Array[SpawnGroup] = []
	for group_spec: Dictionary in groups_spec:
		var group := SpawnGroup.new()
		group.enemy_id = String(group_spec["enemy"])
		group.count = int(group_spec.get("count", 1))
		group.interval = float(group_spec.get("interval", 1.0))
		group.delay = float(group_spec.get("delay", 0.0))
		group.hp_scale = float(group_spec.get("hp_scale", 1.0))
		group.speed_scale = float(group_spec.get("speed_scale", 1.0))
		groups.append(group)
	wave.groups = groups
	return wave

# ---------------------------------------------------------------------------
# 存盘
# ---------------------------------------------------------------------------

func _save(resource: Resource, path: String) -> bool:
	# FLAG_CHANGE_PATH 让资源记住自己的存放路径。
	# 没有它，保存关卡时 Godot 看不到 map 的 resource_path，会把整份地图数据
	# 内嵌成 SubResource 复制一份 —— 那样改 map_01.tres 就不会影响任何关卡了。
	var err := ResourceSaver.save(resource, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		_errors.append("写入失败 %s : %s" % [path, error_string(err)])
		return false
	return true
