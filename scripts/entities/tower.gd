class_name Tower
extends Node2D
## 防御塔（远程攻击）。射程内的敌人按 target_priority 选一个，按攻速开火。
##
## 【职责边界】塔只负责「选敌 + 冷却 + 开火」，它**不造成伤害**，也不生成弹道。
## 开火时只发 fired 信号，由 LevelRunner 决定是瞬发直伤还是生成弹道。
## 这样塔不需要认识 LevelRunner、Projectile 或任何上层节点，依赖方向保持单向。
##
## 【选敌】用 get_tree().get_nodes_in_group("enemies") 而不是物理重叠检测，
## 距离比较完全确定，并且能在测试里直接构造敌人来验证。

signal fired(tower: Tower, target: Enemy)

const BASE_RADIUS := 17.0
const COLOR_BASE := Color("#3f6ea8")
const COLOR_BASE_BORDER := Color("#8fc4f5")
const COLOR_BARREL := Color("#e8eef6")
const COLOR_BARREL_TIP := Color("#ffd166")
const COLOR_RANGE_FILL := Color(0.30, 0.68, 0.95, 0.10)
const COLOR_RANGE_EDGE := Color(0.45, 0.80, 1.00, 0.55)

enum Priority { FRONTMOST = 0, NEAREST = 1, HEALTHIEST = 2 }

var data: TowerData = null
var cell: Vector2i = Vector2i.ZERO

## 剩余冷却时间（秒）。归零即可开火。
var cooldown: float = 0.0
var target: Enemy = null
var aim_angle: float = -PI * 0.5
## 鼠标悬停时把射程圈画出来
var hovered: bool = false

var _range_squared: float = 0.0

# ---------------------------------------------------------------------------
# 构造
# ---------------------------------------------------------------------------

static func create(tower_data: TowerData, at_cell: Vector2i, world_position: Vector2) -> Tower:
	var tower := Tower.new()
	tower.data = tower_data
	tower.cell = at_cell
	tower.position = world_position
	tower._range_squared = maxf(tower_data.range, 0.0) * maxf(tower_data.range, 0.0)
	# 开局先压一个冷却，避免刚放下就打出第一发（也给玩家一点反应时间）
	tower.cooldown = minf(tower_data.get_attack_interval(), 0.35)
	return tower

func _ready() -> void:
	add_to_group("towers")

# ---------------------------------------------------------------------------
# 战斗
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if data == null:
		return

	cooldown = maxf(cooldown - delta, 0.0)

	if target != null and (not is_instance_valid(target) or not target.alive or not _is_in_range(target)):
		target = null
	if target == null:
		target = _pick_target()

	if target == null:
		return

	aim_angle = (target.global_position - global_position).angle()
	if cooldown <= 0.0:
		cooldown = data.get_attack_interval()
		fired.emit(self, target)
	queue_redraw()

func _is_in_range(enemy: Enemy) -> bool:
	return global_position.distance_squared_to(enemy.global_position) <= _range_squared

## 按 target_priority 选敌。评分越高越优先；同分时保留先遇到的那只（顺序稳定）。
func _pick_target() -> Enemy:
	var best: Enemy = null
	var best_score := 0.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not enemy.alive:
			continue
		var distance_squared := global_position.distance_squared_to(enemy.global_position)
		if distance_squared > _range_squared:
			continue
		var score := _score(enemy, distance_squared)
		if best == null or score > best_score:
			best = enemy
			best_score = score
	return best

func _score(enemy: Enemy, distance_squared: float) -> float:
	match data.target_priority:
		Priority.NEAREST:
			# 距离越小越优先 → 取负值参与「越大越好」的比较
			return -distance_squared
		Priority.HEALTHIEST:
			return enemy.hp
		_:
			return enemy.traveled

## 给测试用：直接跑一次选敌，不需要等一帧
func pick_target_now() -> Enemy:
	target = _pick_target()
	return target

# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	if data == null:
		return

	if hovered:
		draw_circle(Vector2.ZERO, data.range, COLOR_RANGE_FILL)
		draw_arc(Vector2.ZERO, data.range, 0.0, TAU, 64, COLOR_RANGE_EDGE, 2.0)

	draw_circle(Vector2.ZERO, BASE_RADIUS, COLOR_BASE)
	draw_arc(Vector2.ZERO, BASE_RADIUS, 0.0, TAU, 24, COLOR_BASE_BORDER, 2.5)

	var direction := Vector2.RIGHT.rotated(aim_angle)
	var muzzle := direction * (BASE_RADIUS + 6.0)
	draw_line(Vector2.ZERO, muzzle, COLOR_BARREL, 5.0, true)
	draw_circle(muzzle, 4.0, COLOR_BARREL_TIP)
