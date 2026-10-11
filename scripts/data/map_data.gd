class_name MapData
extends Resource
## 地图数据：可放置防御塔位置 / 敌人行进路线 / 出怪口 / 进怪口
##
## 【权威来源】tools/generate_data.gd 里的 ASCII 图，用 MapData.from_ascii() 解析。
## ASCII 图例：# = 路径  S = 出怪口  G = 进怪口  B = 可放塔位  . = 空
##
## 生成出来的 .tres 是普通文本资源，仍然可以在检查器里手改。
## 新增一张地图 = 在生成器里加一段 ASCII + 重跑一条命令，不需要写任何逻辑代码。

const ASCII_PATH := "#"
const ASCII_SPAWN := "S"
const ASCII_GOAL := "G"
const ASCII_BUILD := "B"
const ASCII_EMPTY := "."

## 4 连通邻居偏移。路径是「无分叉走廊」，所以每一步排除来路后候选必须恰好为 1。
const NEIGHBOUR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

@export var id: String = ""
@export var display_name: String = ""
@export var grid_size: Vector2i = Vector2i(20, 11)
@export var tile_size: int = GameRules.TILE_SIZE
@export var spawn_cell: Vector2i = Vector2i.ZERO                 ## 出怪口
@export var goal_cell: Vector2i = Vector2i.ZERO                  ## 进怪口
@export var path: Array[Vector2i] = []                           ## 敌人行进路线（有序，含出怪口与进怪口）
@export var build_slots: Array[Vector2i] = []                    ## 可放置防御塔位置

# ---------------------------------------------------------------------------
# 坐标换算
# ---------------------------------------------------------------------------

## 格子 -> 该格中心的世界坐标。
func cell_to_world(cell: Vector2i) -> Vector2:
	var half := float(tile_size) * 0.5
	return Vector2(cell) * float(tile_size) + Vector2(half, half)

## 世界坐标 -> 格子（floor，负数也正确）。
func world_to_cell(world: Vector2) -> Vector2i:
	var t := maxf(float(tile_size), 1.0)
	return Vector2i((world / t).floor())

func get_waypoints() -> PackedVector2Array:
	var points := PackedVector2Array()
	for cell in path:
		points.append(cell_to_world(cell))
	return points

func is_on_path(cell: Vector2i) -> bool:
	return path.has(cell)

func has_build_slot(cell: Vector2i) -> bool:
	return build_slots.has(cell)

## 路径总长度（像素）。用于换算敌人的行进进度百分比。
func path_length() -> float:
	var waypoints := get_waypoints()
	var total := 0.0
	for i in range(1, waypoints.size()):
		total += waypoints[i - 1].distance_to(waypoints[i])
	return total

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y

# ---------------------------------------------------------------------------
# 塔位自动生成
# ---------------------------------------------------------------------------

## 自动生成塔位：所有「与某个路径格正交相邻、且自身不在路径上」的格子。
##
## 【为什么这样生成】塔位与路径格正交相邻 → 中心距离恰好等于 tile_size，
## 也就是塔位到路径的最近距离不可能小于一个格子的边长。
## 又因为自动生成的塔位天然不与路径重叠，核心不变式
## 「近战敌人（attack_range < TILE_SIZE）永远够不到塔」被结构性地保证。
##
## 输出按行优先排序，保证同样的输入产生同样的 .tres（可重复生成、diff 干净）。
func fill_build_slots_adjacent_to_path() -> void:
	var path_set := {}
	for cell in path:
		path_set[cell] = true

	var seen := {}
	var slots: Array[Vector2i] = []
	for cell in path:
		for offset in NEIGHBOUR_OFFSETS:
			var neighbour: Vector2i = cell + offset
			if path_set.has(neighbour) or seen.has(neighbour):
				continue
			if not _in_bounds(neighbour):
				continue
			seen[neighbour] = true
			slots.append(neighbour)

	slots.sort_custom(_compare_cells_row_major)
	build_slots = slots

static func _compare_cells_row_major(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x

# ---------------------------------------------------------------------------
# 校验：新地图的护栏。生成时 + 冒烟测试里都会跑。
# ---------------------------------------------------------------------------

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("MapData.id 为空")
	if grid_size.x <= 0 or grid_size.y <= 0:
		errors.append("%s: grid_size 非法 %s" % [id, grid_size])
		return errors
	if tile_size <= 0:
		errors.append("%s: tile_size 必须 > 0，当前 %d" % [id, tile_size])
		return errors
	if path.size() < 2:
		errors.append("%s: path 至少需要 2 格（当前 %d）" % [id, path.size()])
		return errors

	# 首尾必须与出怪口 / 进怪口一致
	if path[0] != spawn_cell:
		errors.append("%s: path[0]=%s 与 spawn_cell=%s 不一致" % [id, path[0], spawn_cell])
	if path[path.size() - 1] != goal_cell:
		errors.append("%s: path[-1]=%s 与 goal_cell=%s 不一致" % [id, path[path.size() - 1], goal_cell])

	# 每一步必须 4 连通，否则敌人会在两格之间瞬移
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var manhattan := absi(a.x - b.x) + absi(a.y - b.y)
		if manhattan != 1:
			errors.append("%s: path[%d]=%s -> path[%d]=%s 不相邻（曼哈顿距离 %d）" % [id, i - 1, a, i, b, manhattan])

	# 路径不能自交（自交意味着地图有分叉或重叠，本版不支持）
	var seen := {}
	for i in path.size():
		var cell := path[i]
		if seen.has(cell):
			errors.append("%s: path 自交于 %s（下标 %d）" % [id, cell, i])
		seen[cell] = true
		if not _in_bounds(cell):
			errors.append("%s: path 含越界格 %s" % [id, cell])

	# 塔位：唯一、在图内、绝不与路径重叠
	var slot_seen := {}
	for cell in build_slots:
		if not _in_bounds(cell):
			errors.append("%s: build_slots 含越界格 %s" % [id, cell])
		if slot_seen.has(cell):
			errors.append("%s: build_slots 重复 %s" % [id, cell])
		slot_seen[cell] = true
		if path.has(cell):
			errors.append("%s: build_slots 与 path 重叠于 %s（会让近战敌人够得着塔，破坏核心不变式）" % [id, cell])

	if build_slots.is_empty():
		errors.append("%s: build_slots 为空，无处放塔" % id)

	return errors

# ---------------------------------------------------------------------------
# ASCII 解析
# ---------------------------------------------------------------------------

## 从 ASCII 图解析出一张地图，并自动推导有序路径。
##
## 顺序不靠人工维护：从 S 出发沿 4 连通路径格走，每步排除来路，
## 候选恰好 1 个才是合法走廊；走到 G 结束；走过格数必须等于路径格总数。
static func from_ascii(rows: PackedStringArray, new_id: String = "", new_display_name: String = "", new_tile_size: int = GameRules.TILE_SIZE) -> MapData:
	var map := MapData.new()
	map.id = new_id
	map.display_name = new_display_name
	map.tile_size = new_tile_size

	var height := rows.size()
	var width := 0
	for row in rows:
		width = maxi(width, row.length())
	map.grid_size = Vector2i(width, height)

	var path_cells := {}
	var spawn := Vector2i(-1, -1)
	var goal := Vector2i(-1, -1)
	var spawn_found := 0
	var goal_found := 0
	var slots: Array[Vector2i] = []

	for y in height:
		var row: String = rows[y]
		for x in row.length():
			var ch: String = row[x]
			var cell := Vector2i(x, y)
			match ch:
				ASCII_SPAWN:
					spawn = cell
					spawn_found += 1
					path_cells[cell] = true
				ASCII_GOAL:
					goal = cell
					goal_found += 1
					path_cells[cell] = true
				ASCII_PATH:
					path_cells[cell] = true
				ASCII_BUILD:
					slots.append(cell)
				ASCII_EMPTY, " ":
					pass
				_:
					push_error("MapData.from_ascii(%s): 第 %d 行第 %d 列出现非法字符 '%s'" % [new_id, y, x, ch])

	if spawn_found != 1:
		push_error("MapData.from_ascii(%s): 需要恰好 1 个 '%s'，实际 %d 个" % [new_id, ASCII_SPAWN, spawn_found])
	if goal_found != 1:
		push_error("MapData.from_ascii(%s): 需要恰好 1 个 '%s'，实际 %d 个" % [new_id, ASCII_GOAL, goal_found])

	map.spawn_cell = spawn
	map.goal_cell = goal
	map.build_slots = slots

	if spawn_found == 1 and goal_found == 1 and path_cells.size() >= 2:
		map.path = _walk_path(path_cells, spawn, goal, new_id)

	return map

## 从出怪口沿走廊走到进怪口，返回有序格子列表。
static func _walk_path(path_cells: Dictionary, spawn: Vector2i, goal: Vector2i, map_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var prev := Vector2i(-1, -1)
	var cur := spawn
	var limit := path_cells.size() + 2

	while true:
		result.append(cur)
		if cur == goal:
			break

		var candidates: Array[Vector2i] = []
		for offset in NEIGHBOUR_OFFSETS:
			var nxt: Vector2i = cur + offset
			if nxt == prev:
				continue
			if path_cells.has(nxt):
				candidates.append(nxt)

		if candidates.size() != 1:
			push_error("MapData.from_ascii(%s): 路径在 %s 处分叉或断头（候选 %d 个），请检查 ASCII 图" % [map_id, cur, candidates.size()])
			return result

		prev = cur
		cur = candidates[0]

		if result.size() > limit:
			push_error("MapData.from_ascii(%s): 路径回溯超过上限 %d，疑似成环" % [map_id, limit])
			return result

	if result.size() != path_cells.size():
		push_error("MapData.from_ascii(%s): 路径不连通，从出怪口只走过 %d 格，但图中共有 %d 格路径" % [map_id, result.size(), path_cells.size()])

	return result
