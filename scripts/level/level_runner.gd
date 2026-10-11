class_name LevelRunner
extends Node2D
## 一关的运行时大脑：关卡血量 / 金币 / 波次调度 / 出怪 / 漏怪判定 / 胜负 / 暂停。
##
## 【状态归属】关卡运行期的所有状态都放在这里，**不放进 GameState**。
## 因为 GameState 是 autoload，reload_current_scene() 不会重置它；
## 关卡状态跟着场景走，换关或重开时自然归零，不会串味。
##
## 【时间轴】所有推进都写在 _physics_process 里（不用 Timer 节点、不用 Tween），
## 配合 --fixed-fps 60 就能在测试里按帧精确复现整局游戏。
## 2 倍速走的是 Engine.time_scale，所以这里不需要为加速写任何分支。
##
## 【依赖方向】本文件不认识 HUD。UI 由场景里的同级节点（UI/CanvasLayer）自己挂上来，
## 这样 level/ 不需要反向依赖 ui/，就不会出现 class_name 循环。
##
## 【本版不做的事】防御塔不会受伤（TowerData 的血量/抗性字段只是保留），
## 近战敌人永远够不到塔（几何锁死，见 DataRegistry.validate_all 的不变式检查）。

signal health_changed(current: int, maximum: int)
signal gold_changed(amount: int)
signal wave_changed(current: int, total: int, remaining_spawns: int)
signal countdown_changed(remaining: float, total: float)
signal phase_changed(phase: Phase)
signal enemies_changed(alive: int)
signal records_changed()
signal paused_changed(is_paused: bool)
signal notice(text: String)
signal level_won()
signal level_lost()

enum Phase { PREP, WAVE, INTERVAL, WON, LOST }

const ENEMY_GROUP := "enemies"

# --- 关卡数据 -------------------------------------------------------------
## 可以直接在场景里指定 level_id；留空则读 GameState.selected_level_id
var level_id: String = ""
var level: LevelData = null
var map_data: MapData = null

# --- 运行期状态 -----------------------------------------------------------
var health: int = 0
var gold: int = 0
var phase: Phase = Phase.PREP
## 当前波次下标（-1 = 还没开始第一波）
var wave_index: int = -1
var countdown: float = 0.0
var paused: bool = false
var game_finished: bool = false

# --- 统计（HUD 与测试用） -------------------------------------------------
var shots_fired: int = 0
var damage_dealt: float = 0.0
var spawned_total: int = 0
var killed_total: int = 0
var leaked_total: int = 0

# --- 场景图层 -------------------------------------------------------------
var map_renderer: MapRenderer = null
var build_manager: BuildManager = null

var _enemies_layer: Node2D = null
var _projectiles_layer: Node2D = null
var _popups_layer: Node2D = null

var _spawn_queue: Array[Dictionary] = []
var _spawn_sequence: int = 0
var _wave_elapsed: float = 0.0
var _enemies_alive: int = 0
var _show_damage_popup: bool = true
var _show_enemy_health_bar: bool = true

# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------

func _ready() -> void:
	# 上一个场景可能是在暂停状态被切走的，必须清掉，否则新场景一动也不动
	get_tree().paused = false
	paused = false
	_build_layers()
	if not GameState.settings_changed.is_connected(_apply_settings):
		GameState.settings_changed.connect(_apply_settings)
	if level == null:
		var id := level_id
		if id.is_empty():
			id = GameState.selected_level_id
		var loaded: LevelData = DataRegistry.get_level(id)
		if loaded == null:
			push_error("[LevelRunner] 找不到关卡 '%s'" % id)
			return
		level = loaded
	_initialize_level()

## 供测试使用：在 add_child 之前直接把关卡塞进来
func setup(level_data: LevelData) -> void:
	level = level_data

func _initialize_level() -> void:
	map_data = DataRegistry.get_map(level.map_id)
	if map_data == null:
		push_error("[LevelRunner] 关卡 '%s' 引用的地图 '%s' 不存在" % [level.id, level.map_id])
		return

	health = maxi(level.base_health, 1)
	gold = maxi(level.starting_gold, 0)
	phase = Phase.PREP
	wave_index = -1
	countdown = maxf(level.prep_time, 0.0)
	game_finished = false

	map_renderer.setup(map_data)
	build_manager.setup(map_data, level)
	build_manager.set_tower_data(_first_allowed_tower())
	_apply_settings()
	_emit_all()

func _build_layers() -> void:
	map_renderer = MapRenderer.new()
	map_renderer.name = "MapRenderer"
	map_renderer.z_index = -10
	add_child(map_renderer)

	build_manager = BuildManager.new()
	build_manager.name = "BuildManager"
	build_manager.z_index = 0
	build_manager.tower_placed.connect(_on_tower_placed)
	build_manager.placement_rejected.connect(_on_placement_rejected)
	add_child(build_manager)

	_enemies_layer = _make_layer("Enemies", 10)
	_projectiles_layer = _make_layer("Projectiles", 20)
	_popups_layer = _make_layer("Popups", 30)

func _make_layer(layer_name: String, order: int) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	layer.z_index = order
	add_child(layer)
	return layer

func _first_allowed_tower() -> TowerData:
	for tower_id in level.allowed_tower_ids:
		var data: TowerData = DataRegistry.get_tower(tower_id)
		if data != null:
			return data
	return null

# ---------------------------------------------------------------------------
# 主循环
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if game_finished or paused or level == null or map_data == null:
		return
	match phase:
		Phase.PREP, Phase.INTERVAL:
			_tick_countdown(delta)
		Phase.WAVE:
			_tick_wave(delta)

func _tick_countdown(delta: float) -> void:
	# 只有「波间等待」才受 auto_next_wave 控制；开局准备时间总是自动倒数
	if phase == Phase.INTERVAL and not level.auto_next_wave:
		return
	countdown = maxf(countdown - delta, 0.0)
	countdown_changed.emit(countdown, _phase_total_seconds())
	if countdown <= 0.0:
		_start_wave(wave_index + 1)

func _phase_total_seconds() -> float:
	if phase == Phase.PREP:
		return maxf(level.prep_time, 0.0)
	return maxf(level.wave_interval, 0.0)

func _tick_wave(delta: float) -> void:
	_wave_elapsed += delta
	while not _spawn_queue.is_empty() and float(_spawn_queue[0]["time"]) <= _wave_elapsed:
		var entry: Dictionary = _spawn_queue.pop_front()
		_spawn_enemy(entry)
	if _spawn_queue.is_empty() and _enemies_alive <= 0:
		_finish_wave()

# ---------------------------------------------------------------------------
# 波次
# ---------------------------------------------------------------------------

## 玩家点「立即开始」时调用：跳过剩余倒计时，立刻开下一波。
func start_next_wave_now() -> void:
	if game_finished or level == null:
		return
	if phase == Phase.PREP or phase == Phase.INTERVAL:
		countdown = 0.0
		_start_wave(wave_index + 1)

func _start_wave(index: int) -> void:
	if game_finished:
		return
	if index < 0 or index >= level.waves.size():
		_win()
		return

	wave_index = index
	phase = Phase.WAVE
	_wave_elapsed = 0.0
	_spawn_sequence = 0
	_spawn_queue.clear()

	var wave: WaveData = level.waves[index]
	for group in wave.groups:
		var count := maxi(group.count, 0)
		for i in count:
			_spawn_queue.append({
				"time": group.delay + group.interval * float(i),
				"seq": _spawn_sequence,
				"enemy_id": group.enemy_id,
				"hp_scale": group.hp_scale,
				"speed_scale": group.speed_scale,
			})
			_spawn_sequence += 1
	# 出怪顺序按时刻排好（不同组可能互相穿插）；同一时刻用 seq 兜底，
	# 这样 sort_custom 不稳定也不会让出怪顺序随机化。
	_spawn_queue.sort_custom(_compare_spawn_entries)

	phase_changed.emit(phase)
	wave_changed.emit(wave_index + 1, level.waves.size(), _spawn_queue.size())
	notice.emit("第 %d 波开始" % (wave_index + 1))

static func _compare_spawn_entries(a: Dictionary, b: Dictionary) -> bool:
	var time_a := float(a["time"])
	var time_b := float(b["time"])
	if not is_equal_approx(time_a, time_b):
		return time_a < time_b
	return int(a["seq"]) < int(b["seq"])

func _finish_wave() -> void:
	if game_finished:
		return
	if wave_index >= level.waves.size() - 1:
		_win()
		return
	phase = Phase.INTERVAL
	countdown = maxf(level.wave_interval, 0.0)
	phase_changed.emit(phase)
	wave_changed.emit(wave_index + 1, level.waves.size(), 0)
	countdown_changed.emit(countdown, _phase_total_seconds())
	notice.emit("第 %d 波结束" % (wave_index + 1))

# ---------------------------------------------------------------------------
# 出怪
# ---------------------------------------------------------------------------

func _spawn_enemy(entry: Dictionary) -> void:
	var enemy_id := String(entry["enemy_id"])
	var enemy_data: EnemyData = DataRegistry.get_enemy(enemy_id)
	if enemy_data == null:
		push_error("[LevelRunner] 未知敌人 id '%s'" % enemy_id)
		return

	var enemy := Enemy.create(enemy_data, map_data.get_waypoints(),
		float(entry["hp_scale"]), float(entry["speed_scale"]))
	enemy.show_health_bar = _show_enemy_health_bar
	enemy.died.connect(_on_enemy_died)
	enemy.leaked.connect(_on_enemy_leaked)
	# tree_exited 是唯一可靠的「这只怪离场了」信号：
	# 不管是被打死、漏怪还是别的途径被释放，存活计数都不会漏减。
	enemy.tree_exited.connect(_on_enemy_exited)
	_enemies_layer.add_child(enemy)

	_enemies_alive += 1
	spawned_total += 1
	enemies_changed.emit(_enemies_alive)
	wave_changed.emit(wave_index + 1, level.waves.size(), _spawn_queue.size())

func _on_enemy_exited() -> void:
	_enemies_alive = maxi(_enemies_alive - 1, 0)
	enemies_changed.emit(_enemies_alive)

func _on_enemy_died(enemy: Enemy) -> void:
	killed_total += 1
	if enemy.data != null:
		gold += maxi(enemy.data.gold_reward, 0)
	gold_changed.emit(gold)
	records_changed.emit()

func _on_enemy_leaked(enemy: Enemy) -> void:
	leaked_total += 1
	records_changed.emit()
	_lose_health(GameRules.LEAK_DAMAGE)
	notice.emit("漏怪！关卡血量 -%d" % GameRules.LEAK_DAMAGE)

# ---------------------------------------------------------------------------
# 防御塔开火
# ---------------------------------------------------------------------------

func _on_tower_fired(tower: Tower, target: Enemy) -> void:
	shots_fired += 1
	if tower.data == null:
		return
	if target == null or not is_instance_valid(target) or not target.alive:
		return

	if tower.data.instant_hit:
		var dealt := target.take_damage(tower.data.damage, tower.data.damage_type)
		damage_dealt += dealt
		_spawn_damage_popup(target.global_position, dealt, tower.data.damage_type)
		return

	var projectile := Projectile.create(tower.global_position, target, tower.data)
	projectile.hit.connect(_on_projectile_hit)
	_projectiles_layer.add_child(projectile)

func _on_projectile_hit(at: Vector2, amount: float, kind: DamageType.Kind) -> void:
	damage_dealt += amount
	_spawn_damage_popup(at, amount, kind)

func _spawn_damage_popup(at: Vector2, amount: float, kind: DamageType.Kind) -> void:
	if not _show_damage_popup or amount <= 0.0:
		return
	_popups_layer.add_child(DamagePopup.create(at, amount, kind))

# ---------------------------------------------------------------------------
# 建造
# ---------------------------------------------------------------------------

func _on_tower_placed(tower: Tower) -> void:
	# 塔只发 fired 信号、不自己结算伤害；伤害/弹道/飘字全部由这里统一处理
	if not tower.fired.is_connected(_on_tower_fired):
		tower.fired.connect(_on_tower_fired)
	if level != null and level.enforce_cost and tower.data != null:
		gold = maxi(gold - tower.data.cost, 0)
		gold_changed.emit(gold)
	if tower.data != null:
		notice.emit("建造「%s」" % tower.data.display_name)

func _on_placement_rejected(cell: Vector2i, reason: String) -> void:
	notice.emit(reason)

func try_build_at(world_position: Vector2) -> Tower:
	if map_data == null:
		return null
	return build_manager.try_place(map_data.world_to_cell(world_position), gold)

# ---------------------------------------------------------------------------
# 胜负
# ---------------------------------------------------------------------------

func _lose_health(amount: int) -> void:
	if game_finished or amount <= 0:
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health, level.base_health)
	if health <= 0:
		_lose()

func _win() -> void:
	if game_finished:
		return
	game_finished = true
	phase = Phase.WON
	phase_changed.emit(phase)
	notice.emit("关卡通过！")
	level_won.emit()

func _lose() -> void:
	if game_finished:
		return
	game_finished = true
	phase = Phase.LOST
	phase_changed.emit(phase)
	notice.emit("关卡失败：漏怪太多")
	level_lost.emit()

# ---------------------------------------------------------------------------
# 暂停 / 设置 / 重开
# ---------------------------------------------------------------------------

func set_paused(value: bool) -> void:
	if game_finished:
		return
	if paused == value:
		return
	paused = value
	get_tree().paused = value
	paused_changed.emit(paused)

func toggle_paused() -> void:
	set_paused(not paused)

func _apply_settings() -> void:
	_show_damage_popup = GameState.show_damage_popup
	_show_enemy_health_bar = GameState.show_enemy_health_bar
	for node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		var enemy := node as Enemy
		if enemy != null:
			enemy.show_health_bar = _show_enemy_health_bar
			enemy.queue_redraw()

## 重开本关：直接重载场景即可（GameState.selected_level_id 会保持不变）。
## 注意先清掉暂停，否则新场景会在 get_tree().paused = true 的状态下起来，一动也不动。
func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# paused 也要拦：虽然引擎会因为节点是 PAUSABLE 而跳过输入回调，
	# 但这行让「暂停时不能操作战场」成为写在代码里的显式约束，而不是依赖默认行为。
	if game_finished or paused or level == null or map_data == null:
		return
	if event is InputEventMouseMotion:
		_update_hover(get_global_mouse_position())
		return
	# 注意：td_pause（P / ESC）不在这里处理 —— 暂停由 UI 层独家负责，
	# 否则同一次按键会被 UI 和这里各响应一次，表现为「开了又立刻关」。
	if event.is_action_pressed("td_speed_toggle"):
		GameState.toggle_game_speed()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("td_cancel"):
		if build_manager != null:
			build_manager.clear_hover()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("td_select"):
		if build_manager != null:
			build_manager.try_place(map_data.world_to_cell(get_global_mouse_position()), gold)
		get_viewport().set_input_as_handled()
		return

func _update_hover(world_position: Vector2) -> void:
	if build_manager == null or map_renderer == null:
		return
	var cell := map_data.world_to_cell(world_position)
	var valid := build_manager.set_hover(cell, gold)
	map_renderer.set_hover(cell, valid)

# ---------------------------------------------------------------------------
# 对外状态快照（HUD 与测试都读它）
# ---------------------------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"level_id": level.id if level != null else "",
		"map_id": map_data.id if map_data != null else "",
		"health": health,
		"max_health": level.base_health if level != null else 0,
		"gold": gold,
		"phase": phase,
		"wave_index": wave_index,
		"wave_total": level.waves.size() if level != null else 0,
		"countdown": countdown,
		"enemies_alive": _enemies_alive,
		"spawned": spawned_total,
		"killed": killed_total,
		"leaked": leaked_total,
		"shots": shots_fired,
		"damage": damage_dealt,
		"towers": build_manager.tower_count() if build_manager != null else 0,
		"paused": paused,
		"finished": game_finished,
	}

func enemies_alive() -> int:
	return _enemies_alive

func _emit_all() -> void:
	health_changed.emit(health, level.base_health)
	gold_changed.emit(gold)
	wave_changed.emit(maxi(wave_index + 1, 0), level.waves.size(), 0)
	countdown_changed.emit(countdown, _phase_total_seconds())
	phase_changed.emit(phase)
	enemies_changed.emit(_enemies_alive)
	records_changed.emit()
