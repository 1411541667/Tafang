class_name Projectile
extends Node2D
## 弹道：飞向锁定目标，接触时结算伤害。
##
## 【目标丢失怎么办】锁定目标中途死亡/漏怪/被释放时，弹道**不会**凭空消失在空中，
## 而是继续飞向目标最后已知的位置再消失 —— 否则玩家会看到子弹凭空蒸发。
## 但它不会造成任何伤害，因为伤害只能在「目标仍然存活」时结算。
##
## 【为什么用 Node2D】命中判定是纯距离比较，不走物理引擎。见 enemy.gd 顶部说明。

signal hit(at: Vector2, amount: float, kind: DamageType.Kind)

const HIT_RADIUS := 7.0
## 保底寿命，防止极端情况下有一发子弹永远追不上目标而泄漏在场上
const MAX_LIFETIME := 5.0
const COLOR_BODY := Color("#ffe066")
const COLOR_TRAIL := Color("#ffb703")

var speed: float = 520.0
var damage: float = 12.0
var kind: DamageType.Kind = DamageType.Kind.PHYSICAL
var target: Enemy = null

var _lifetime: float = 0.0
var _direction: Vector2 = Vector2.RIGHT
var _last_known_position: Vector2 = Vector2.ZERO
var _spent: bool = false

# ---------------------------------------------------------------------------
# 构造
# ---------------------------------------------------------------------------

static func create(from: Vector2, enemy: Enemy, tower_data: TowerData) -> Projectile:
	var projectile := Projectile.new()
	projectile.position = from
	projectile.target = enemy
	projectile.damage = maxf(tower_data.damage, 0.0)
	projectile.kind = tower_data.damage_type
	projectile.speed = maxf(tower_data.projectile_speed, 60.0)
	if enemy != null:
		projectile._last_known_position = enemy.global_position
		projectile._direction = (enemy.global_position - from).normalized()
		if projectile._direction == Vector2.ZERO:
			projectile._direction = Vector2.RIGHT
	return projectile

# ---------------------------------------------------------------------------
# 飞行
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _spent:
		return
	_lifetime += delta

	var target_valid := target != null and is_instance_valid(target) and target.alive
	if target_valid:
		_last_known_position = target.global_position

	var to_destination := _last_known_position - position
	var distance := to_destination.length()
	if distance > 0.0:
		_direction = to_destination / distance

	var step := speed * delta
	if distance <= maxf(step, HIT_RADIUS):
		position = _last_known_position
		if target_valid:
			_detonate()
		else:
			# 目标已经没了：飞到最后一个已知位置就消失，不结算伤害
			_spent = true
			queue_free()
		return

	position += _direction * step
	# 目标还活着就贴着它飞；目标没了就飞向最后已知位置，到了再消失
	if not target_valid and position.distance_to(_last_known_position) <= HIT_RADIUS:
		_spent = true
		queue_free()
		return

	rotation = _direction.angle()
	queue_redraw()

	if _lifetime >= MAX_LIFETIME:
		_spent = true
		queue_free()

func _detonate() -> void:
	_spent = true
	var dealt := target.take_damage(damage, kind)
	hit.emit(position, dealt, kind)
	queue_free()

# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	# 节点自身带 rotation，所以这里按「朝 +X 方向」画即可
	draw_line(Vector2(-10.0, 0.0), Vector2(-2.0, 0.0), COLOR_TRAIL, 3.0, true)
	draw_circle(Vector2.ZERO, 5.0, COLOR_BODY)
