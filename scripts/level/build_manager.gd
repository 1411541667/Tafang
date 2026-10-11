class_name BuildManager
extends Node2D
## 防御塔的放置管理：放置规则校验 + 塔实例的持有与查询 + 悬停时的射程预览。
##
## 【为什么单独一层】放置规则（能不能建在这里）和「金币够不够」是两件事：
## 前者由地图决定（必须是塔位、不能压在敌人路线上、不能重复建造），
## 后者是关卡经济，且本版 enforce_cost = false 时完全不生效。
## 把规则收在这里，「建塔」这件事就只有一个判定入口，测试也能直接调用。
##
## 【金币】本层只**读取**当前金币用于判定，不扣钱 —— 扣钱是 LevelRunner 的事。

signal tower_placed(tower: Tower)
signal placement_rejected(cell: Vector2i, reason: String)

const COLOR_PREVIEW_FILL := Color(0.30, 0.68, 0.95, 0.10)
const COLOR_PREVIEW_EDGE := Color(0.45, 0.80, 1.00, 0.55)

var map: MapData = null
var level: LevelData = null
var tower_data: TowerData = null

var _towers_by_cell: Dictionary = {}
var _towers: Array[Tower] = []
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _available_gold: int = 0

func setup(map_data: MapData, level_data: LevelData) -> void:
	map = map_data
	level = level_data
	queue_redraw()

func set_tower_data(value: TowerData) -> void:
	tower_data = value
	queue_redraw()

# ---------------------------------------------------------------------------
# 放置规则
# ---------------------------------------------------------------------------

## 返回空字符串表示可以建造；否则返回给玩家看的中文原因。
func can_place(cell: Vector2i, available_gold: int) -> String:
	if map == null:
		return "地图未加载"
	if tower_data == null:
		return "本关没有可建造的防御塔"
	if not map.has_build_slot(cell):
		return "这里不是可建造位置"
	if map.is_on_path(cell):
		return "不能在敌人行进路线上建造"
	if _towers_by_cell.has(cell):
		return "这里已经有一座防御塔了"
	# 本版 enforce_cost = false，所以金币永远不会拦住放置；
	# 将来把关卡里的 enforce_cost 勾上即可生效，不需要改这里。
	if level != null and level.enforce_cost and available_gold < tower_data.cost:
		return "金币不足（需要 %d，现有 %d）" % [tower_data.cost, available_gold]
	return ""

## 校验通过就建一座塔并返回它；否则发 placement_rejected 并返回 null。
func try_place(cell: Vector2i, available_gold: int) -> Tower:
	var reason := can_place(cell, available_gold)
	if not reason.is_empty():
		placement_rejected.emit(cell, reason)
		return null
	return place(cell)

## 不做校验的强制建造（供内部与测试使用）
func place(cell: Vector2i) -> Tower:
	if map == null or tower_data == null:
		return null
	var tower := Tower.create(tower_data, cell, map.cell_to_world(cell))
	add_child(tower)
	_towers_by_cell[cell] = tower
	_towers.append(tower)
	tower_placed.emit(tower)
	queue_redraw()
	return tower

# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func tower_at(cell: Vector2i) -> Tower:
	var tower: Tower = _towers_by_cell.get(cell, null)
	return tower

func towers() -> Array[Tower]:
	return _towers

func tower_count() -> int:
	return _towers.size()

func total_cost() -> int:
	if tower_data == null:
		return 0
	return _towers.size() * tower_data.cost

func clear() -> void:
	for tower in _towers:
		if is_instance_valid(tower):
			tower.queue_free()
	_towers.clear()
	_towers_by_cell.clear()
	clear_hover()
	queue_redraw()

# ---------------------------------------------------------------------------
# 悬停
# ---------------------------------------------------------------------------

func set_hover(cell: Vector2i, available_gold: int) -> bool:
	_available_gold = available_gold
	if cell == _hover_cell:
		_refresh_hover_visuals()
		queue_redraw()
		return can_place(cell, _available_gold).is_empty()
	_hover_cell = cell
	_refresh_hover_visuals()
	queue_redraw()
	return can_place(cell, _available_gold).is_empty()

func clear_hover() -> void:
	set_hover(Vector2i(-1, -1), _available_gold)

func hover_cell() -> Vector2i:
	return _hover_cell

## 悬停在已有塔上时点亮那座塔的射程圈
func _refresh_hover_visuals() -> void:
	for cell in _towers_by_cell:
		var tower: Tower = _towers_by_cell[cell]
		if is_instance_valid(tower):
			tower.hovered = (cell == _hover_cell)

# ---------------------------------------------------------------------------
# 绘制：放置前的射程预览
# ---------------------------------------------------------------------------

func _draw() -> void:
	if map == null or tower_data == null:
		return
	if _hover_cell.x < 0 or _hover_cell.y < 0:
		return
	if not can_place(_hover_cell, _available_gold).is_empty():
		return
	var center := map.cell_to_world(_hover_cell)
	var radius := maxf(tower_data.range, 0.0)
	draw_circle(center, radius, COLOR_PREVIEW_FILL)
	draw_arc(center, radius, 0.0, TAU, 64, COLOR_PREVIEW_EDGE, 2.0)
