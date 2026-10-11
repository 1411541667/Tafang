extends Node
##
## 关卡可通关性 / 数值平衡测试（无头、确定性、不 mock）。
##
## 目的：冒烟测试只证明了「6 张图都能跑起来不报错」，没有证明**这些关卡真的打得赢**。
## 这个脚本给每一关做一次「合理的自动布防」，然后真的把整关跑完，看结果。
##
## 布防策略（确定性，不用随机、不用「重试 N 次取最后一次」那种有毒写法）：
##   1. 对每个可建造格，数出「射程覆盖到多少个路径格」；
##   2. 按覆盖数降序排序，同分按行优先（y 再 x）兜底 —— 保证同样输入永远同样布防；
##   3. 取前 K 个格子放塔，K = clamp(4 + 出怪总数 / 5, 4, 20)（怪多就多给几座塔）。
##   金币本版不设门槛（LevelData.enforce_cost = false），所以 K 是「预算」而不是「钱包」。
##
## 运行：
##   & $GODOT --headless --path <proj> --fixed-fps 60 --quit-after 400000 res://tests/balance_test.tscn
##
## 退出码 0 = 每一关都能通关，1 = 有打不赢的关卡（给 CI 用）。
##

const LEVEL_SCENE_PATH := "res://scenes/level.tscn"

## 单关最多跑多少物理帧。level_05 路径 4544 px、最慢的怪 45 px/s，
## 单趟就要 ~101 秒（6060 帧），再加上 4 波之间的间隔，给足余量。
const MAX_FRAMES_PER_LEVEL := 40000

var _passed := 0
var _failed := 0
var _failures: Array[String] = []
var _rows: Array[Dictionary] = []


func _ready() -> void:
	print("========== 塔防关卡可通关性 / 平衡测试 ==========")
	await _run_all()
	_report()


# ---------------------------------------------------------------------------
# 断言与工具
# ---------------------------------------------------------------------------

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


func _wait_physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _run_until(runner: LevelRunner, max_frames: int) -> int:
	var frames := 0
	while frames < max_frames:
		await get_tree().physics_frame
		frames += 1
		if not is_instance_valid(runner) or runner.game_finished:
			break
	return frames


func _spawn_level(level: LevelData) -> LevelRunner:
	var scene: PackedScene = load(LEVEL_SCENE_PATH)
	var runner: LevelRunner = scene.instantiate()
	GameState.selected_level_id = level.id
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


# ---------------------------------------------------------------------------
# 布防
# ---------------------------------------------------------------------------

## 这个塔位能盖住多少个路径格。
func _coverage(map: MapData, slot: Vector2i, range_squared: float) -> int:
	var center: Vector2 = map.cell_to_world(slot)
	var covered := 0
	for cell in map.path:
		if center.distance_squared_to(map.cell_to_world(cell)) <= range_squared:
			covered += 1
	return covered


## 确定性排序：覆盖多的在前，同分按行优先（先 y 后 x）。
static func _compare_entries(a: Dictionary, b: Dictionary) -> bool:
	var cover_a: int = int(a["cover"])
	var cover_b: int = int(b["cover"])
	if cover_a != cover_b:
		return cover_a > cover_b
	var y_a: int = int(a["y"])
	var y_b: int = int(b["y"])
	if y_a != y_b:
		return y_a < y_b
	return int(a["x"]) < int(b["x"])


## 按覆盖数挑出前 count 个塔位。
func _best_slots(map: MapData, tower: TowerData, count: int) -> Array[Vector2i]:
	var range_squared: float = tower.range * tower.range
	var entries: Array = []
	for slot in map.build_slots:
		entries.append({
			"cell": slot,
			"cover": _coverage(map, slot, range_squared),
			"y": slot.y,
			"x": slot.x,
		})
	entries.sort_custom(_compare_entries)

	var picked: Array[Vector2i] = []
	for entry in entries:
		if picked.size() >= count:
			break
		picked.append(entry["cell"] as Vector2i)
	return picked


func _budget_for(level: LevelData) -> int:
	return clampi(4 + level.total_enemy_count() / 5, 4, 20)


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

func _run_all() -> void:
	var ids: Array[String] = DataRegistry.all_level_ids()
	_check("关卡数量为 6", ids.size() == 6, "实际 = %d" % ids.size())

	for level_id in ids:
		await _test_level(level_id)

	_print_table()


func _test_level(level_id: String) -> void:
	print("")
	print("--- %s ---" % level_id)

	var level: LevelData = DataRegistry.get_level(level_id)
	if level == null:
		_check("关卡存在：%s" % level_id, false, "DataRegistry 里找不到")
		return
	var map: MapData = DataRegistry.get_map(level.map_id)
	if map == null:
		_check("地图存在：%s" % level_id, false, "map_id = %s 解析不到" % level.map_id)
		return

	var tower: TowerData = DataRegistry.get_tower(level.allowed_tower_ids[0])
	var runner: LevelRunner = await _spawn_level(level)

	var budget := _budget_for(level)
	var slots := _best_slots(map, tower, budget)
	var placed := 0
	for slot in slots:
		if runner.build_manager.try_place(slot, runner.gold) != null:
			placed += 1

	print("  关卡血量 %d · 波次 %d · 出怪 %d · 塔位 %d · 预算 %d 座塔 · 实际放下 %d 座" % [
		level.base_health, level.waves.size(), level.total_enemy_count(),
		map.build_slots.size(), budget, placed,
	])
	_check("%s 布防数量符合预算" % level_id, placed == mini(budget, map.build_slots.size()),
		"放下 %d / 预算 %d" % [placed, budget])

	runner.start_next_wave_now()
	var frames := await _run_until(runner, MAX_FRAMES_PER_LEVEL)
	var snap: Dictionary = runner.snapshot()
	await _dispose(runner)

	var won: bool = snap["phase"] == LevelRunner.Phase.WON
	var health_left: int = int(snap["health"])
	var spawned: int = int(snap["spawned"])
	var killed: int = int(snap["killed"])
	var leaked: int = int(snap["leaked"])

	print("  跑了 %d 帧（%.1f 秒游戏时间）→ %s" % [
		frames, float(frames) / 60.0, "通关" if won else "失败",
	])
	print("  出怪 %d · 击杀 %d · 漏怪 %d · 剩余血量 %d/%d · 开火 %d · 伤害 %d" % [
		spawned, killed, leaked, health_left, level.base_health,
		int(snap["shots"]), int(snap["damage"]),
	])

	# 这一关真的打完了（不是被帧数上限截断）
	_check("%s 跑到了结算（非超时截断）" % level_id, bool(snap["finished"]),
		"%d 帧后仍在 phase=%d" % [frames, int(snap["phase"])])
	# 出怪数量与配置一致
	_check("%s 出怪总数与配置一致" % level_id, spawned == level.total_enemy_count(),
		"实际 %d，配置 %d" % [spawned, level.total_enemy_count()])
	# 击杀 + 漏怪不超过出怪总数
	_check("%s 击杀 + 漏怪 ≤ 出怪" % level_id, killed + leaked <= spawned,
		"%d + %d > %d" % [killed, leaked, spawned])
	# 血量守恒：漏多少扣多少
	_check("%s 血量守恒（漏怪数 = 扣血量）" % level_id,
		health_left == maxi(level.base_health - leaked, 0),
		"血量 %d，初始 %d，漏怪 %d" % [health_left, level.base_health, leaked])
	# 核心断言：合理的布防下这一关能通关
	_check("%s 可以通关（%d 座塔）" % [level_id, placed], won,
		"漏了 %d 只，血量剩 %d" % [leaked, health_left])

	_rows.append({
		"id": level_id,
		"map": map.id,
		"towers": placed,
		"health": level.base_health,
		"left": health_left,
		"spawned": spawned,
		"killed": killed,
		"leaked": leaked,
		"won": won,
		"frames": frames,
	})


func _print_table() -> void:
	print("")
	print("========== 汇总 ==========")
	print("关卡        地图       塔数  血量  出怪  击杀  漏怪  剩余  结果")
	for row in _rows:
		print("%-11s %-10s %4d  %4d  %4d  %4d  %4d  %4d  %s" % [
			row["id"], row["map"], row["towers"], row["health"],
			row["spawned"], row["killed"], row["leaked"], row["left"],
			"通关" if bool(row["won"]) else "失败",
		])


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("========== 通过 %d ，失败 0 ==========" % _passed)
		print("BALANCE_RESULT=OK")
	else:
		print("========== 通过 %d ，失败 %d ==========" % [_passed, _failed])
		for text in _failures:
			print(text)
		print("BALANCE_RESULT=FAIL")
	get_tree().quit(1 if _failed > 0 else 0)
