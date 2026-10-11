class_name Enemy
extends Node2D
## 敌人：沿地图路点前进，走到终点就算「漏怪」。
##
## 【本版不做的事】敌人不会攻击防御塔（三种敌人的 attack_range 全部 < TILE_SIZE，
## 而塔位与路径的最小距离恰好是 TILE_SIZE，所以几何上永远够不到）。
## 相关的射程/攻速/伤害字段只做数据保留，见 EnemyData 与 DataRegistry 的不变式检查。
##
## 【为什么用 Node2D 而不是 Area2D】塔选敌与弹道命中全部用「距离比较」实现，
## 不依赖物理引擎。好处：完全确定性（--fixed-fps 下可复现）、
## 不需要配置碰撞层、也不会踩「物理回调里改物理属性被 block」的坑。
##
## 【确定性】所有移动都在 _physics_process 里按 delta 推进，不用 Tween / Timer 节点。

signal died(enemy: Enemy)      ## 被塔打死
signal leaked(enemy: Enemy)    ## 活着走到进怪口

const HEALTH_BAR_WIDTH := 30.0
const HEALTH_BAR_HEIGHT := 5.0
const HEALTH_BAR_OFFSET := 9.0
const COLOR_HEALTH_BG := Color(0.0, 0.0, 0.0, 0.65)
const COLOR_HEALTH_FILL := Color("#5ad469")
const COLOR_OUTLINE := Color(0.0, 0.0, 0.0, 0.45)
## 一帧内最多消费的路点数量，防止异常数据造成死循环
const MAX_WAYPOINTS_PER_FRAME := 64

var data: EnemyData = null
var hp: float = 0.0
var max_hp: float = 0.0
var move_speed: float = 0.0
var body_radius: float = 16.0
var body_color: Color = Color("#e04b4b")
var show_health_bar: bool = true
var alive: bool = true

var waypoints: PackedVector2Array = PackedVector2Array()
## 已经走过的路径长度（像素）。「最前」选敌用的就是它。
var traveled: float = 0.0

var _waypoint_index: int = 1
var _reached_goal: bool = false

# ---------------------------------------------------------------------------
# 构造
# ---------------------------------------------------------------------------

## 用「数据 + 路径」造一只敌人。hp_scale / speed_scale 来自出怪组。
## 注意：调用方仍需 add_child()，本函数不做入树操作。
static func create(enemy_data: EnemyData, path: PackedVector2Array,
		hp_scale: float = 1.0, speed_scale: float = 1.0) -> Enemy:
	var enemy := Enemy.new()
	enemy.data = enemy_data
	enemy.waypoints = path
	# maxf 守卫：倍率非法时退化成 1.0，绝不让血量/速度变成 0 或负数
	enemy.max_hp = enemy_data.max_health * maxf(hp_scale, 0.01)
	enemy.hp = enemy.max_hp
	enemy.move_speed = enemy_data.move_speed * maxf(speed_scale, 0.01)
	enemy.body_radius = maxf(enemy_data.body_radius, 1.0)
	enemy.body_color = enemy_data.color
	if path.size() > 0:
		enemy.position = path[0]
	enemy._waypoint_index = 1 if path.size() > 1 else path.size()
	return enemy

func _ready() -> void:
	add_to_group("enemies")

# ---------------------------------------------------------------------------
# 移动
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if waypoints.size() < 2:
		# 数据异常：路径不成立，直接当作到达终点，避免卡在场上永远不结算
		_on_reached_goal()
		return

	var remaining := move_speed * delta
	var guard := 0
	while remaining > 0.0 and _waypoint_index < waypoints.size():
		guard += 1
		if guard > MAX_WAYPOINTS_PER_FRAME:
			break
		var target: Vector2 = waypoints[_waypoint_index]
		var to_target := target - position
		var distance := to_target.length()
		if distance <= remaining:
			position = target
			traveled += distance
			remaining -= distance
			_waypoint_index += 1
		else:
			# 这里 distance > remaining >= 0，所以 distance 一定大于 0，除法安全
			position += to_target / distance * remaining
			traveled += remaining
			remaining = 0.0

	if _waypoint_index >= waypoints.size():
		_on_reached_goal()

## 已经走完的路径比例 0.0~1.0（仅用于显示）
func progress_ratio() -> float:
	if waypoints.size() < 2:
		return 1.0
	var total := 0.0
	for i in range(1, waypoints.size()):
		total += waypoints[i - 1].distance_to(waypoints[i])
	if total <= 0.0:
		return 1.0
	return clampf(traveled / total, 0.0, 1.0)

# ---------------------------------------------------------------------------
# 受伤 / 死亡 / 漏怪
# ---------------------------------------------------------------------------

## 扣血，返回**实际**扣掉的血量（0 表示已死或伤害被抗性完全吃掉了）。
## 塔和飘字都靠返回值判断，所以不能返回「请求值」。
func take_damage(amount: float, kind: DamageType.Kind) -> float:
	if not alive or data == null:
		return 0.0
	var dealt := Combat.compute_damage(amount, kind, data.physical_resist, data.magic_resist)
	if dealt <= 0.0:
		return 0.0
	hp = maxf(hp - dealt, 0.0)
	if hp <= 0.0:
		_die()
	else:
		queue_redraw()
	return dealt

func health_ratio() -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(hp / max_hp, 0.0, 1.0)

func _die() -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	died.emit(self)
	queue_free()

func _on_reached_goal() -> void:
	if _reached_goal:
		return
	_reached_goal = true
	if not alive:
		return
	alive = false
	leaked.emit(self)
	queue_free()

# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	draw_circle(Vector2.ZERO, body_radius, body_color)
	draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 24, COLOR_OUTLINE, 2.0)

	if not show_health_bar or max_hp <= 0.0 or hp >= max_hp:
		return

	var top_left := Vector2(-HEALTH_BAR_WIDTH * 0.5, -body_radius - HEALTH_BAR_OFFSET)
	draw_rect(Rect2(top_left, Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)), COLOR_HEALTH_BG)
	var inner_width := maxf((HEALTH_BAR_WIDTH - 2.0) * health_ratio(), 0.0)
	if inner_width > 0.0:
		draw_rect(Rect2(top_left + Vector2(1.0, 1.0), Vector2(inner_width, HEALTH_BAR_HEIGHT - 2.0)),
			COLOR_HEALTH_FILL)
