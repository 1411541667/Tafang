class_name MapRenderer
extends Node2D
## 把 MapData 画成可见的战场：底色 / 网格 / 敌人行进路线 / 可放置塔位 / 出怪口 / 进怪口。
##
## 【为什么用 _draw 画而不是铺 TileMap】地图数据是运行时从 .tres 加载的，
## 用矢量绘制可以完全由代码驱动，不需要预先做图集；
## 而且每种元素用固定的纯色，颜色本身就是自动化像素测试的断言锚点
## （见 tests/capture_shot.gd：按颜色统计命中像素数与包围盒，不靠肉眼）。
##
## 【图层】本节点由 LevelRunner 挂在 z_index = -10，永远在所有实体之下。

const COLOR_BG := Color("#1b2430")
const COLOR_BG_EDGE := Color("#0f151d")
const COLOR_GRID := Color("#28323f")
const COLOR_PATH := Color("#775f3c")
const COLOR_PATH_EDGE := Color("#9a7d50")
const COLOR_SLOT := Color("#33506e")
const COLOR_SLOT_EDGE := Color("#4d78a8")
const COLOR_SPAWN := Color("#d8544f")
const COLOR_GOAL := Color("#57b06a")
const COLOR_HOVER_VALID := Color("#7dffa6")
const COLOR_HOVER_INVALID := Color("#ff9f43")

const SLOT_SIZE := 28.0
const GATE_RADIUS := 26.0
const HOVER_BORDER := 3.0
const GRID_LINE := 1.0

var map: MapData = null
## 当前鼠标指向的格子；(-1,-1) 表示没有指向任何格子（此时不画高亮）
var hover_cell: Vector2i = Vector2i(-1, -1)
var hover_valid: bool = false

func setup(map_data: MapData) -> void:
	map = map_data
	queue_redraw()

func set_hover(cell: Vector2i, valid: bool) -> void:
	if cell == hover_cell and valid == hover_valid:
		return
	hover_cell = cell
	hover_valid = valid
	queue_redraw()

func clear_hover() -> void:
	set_hover(Vector2i(-1, -1), false)

## 地图在屏幕上的像素尺寸
func pixel_size() -> Vector2:
	if map == null:
		return Vector2.ZERO
	return Vector2(map.grid_size) * float(map.tile_size)

func _draw() -> void:
	if map == null:
		return
	var tile := float(map.tile_size)
	var total := pixel_size()

	draw_rect(Rect2(Vector2.ZERO, total), COLOR_BG)
	draw_rect(Rect2(Vector2.ZERO, total), COLOR_BG_EDGE, false, 3.0)

	# 网格线
	for x in range(map.grid_size.x + 1):
		draw_line(Vector2(float(x) * tile, 0.0), Vector2(float(x) * tile, total.y), COLOR_GRID, GRID_LINE)
	for y in range(map.grid_size.y + 1):
		draw_line(Vector2(0.0, float(y) * tile), Vector2(total.x, float(y) * tile), COLOR_GRID, GRID_LINE)

	# 敌人行进路线
	for cell in map.path:
		var rect := Rect2(Vector2(cell) * tile, Vector2(tile, tile))
		draw_rect(rect, COLOR_PATH)
		draw_rect(rect.grow(-2.0), COLOR_PATH_EDGE, false, 2.0)

	# 可放置防御塔位置
	for cell in map.build_slots:
		var center := (Vector2(cell) + Vector2(0.5, 0.5)) * tile
		var half := SLOT_SIZE * 0.5
		var rect := Rect2(center - Vector2(half, half), Vector2(SLOT_SIZE, SLOT_SIZE))
		draw_rect(rect, COLOR_SLOT)
		draw_rect(rect, COLOR_SLOT_EDGE, false, 2.0)

	# 出怪口 / 进怪口
	draw_circle(_cell_center(map.spawn_cell, tile), GATE_RADIUS, COLOR_SPAWN)
	draw_circle(_cell_center(map.goal_cell, tile), GATE_RADIUS, COLOR_GOAL)

	# 鼠标高亮
	if hover_cell.x >= 0 and hover_cell.y >= 0:
		var hover_rect := Rect2(Vector2(hover_cell) * tile, Vector2(tile, tile))
		var color := COLOR_HOVER_VALID if hover_valid else COLOR_HOVER_INVALID
		draw_rect(hover_rect.grow(-HOVER_BORDER), color, false, HOVER_BORDER)

func _cell_center(cell: Vector2i, tile: float) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * tile
