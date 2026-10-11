class_name EnemyData
extends Resource
## 敌人数据。字段与需求一一对应：
## 射程 / 攻速 / 伤害 / 伤害类型 / 血量 / 物理抗性 / 法术抗性 / 特殊攻击
##
## 【本版范围】三种敌人射程都是近战（attack_range ≤ GameRules.MELEE_RANGE_MAX），
## 而塔位格与路径格永不重叠，所以敌人**永远够不到任何防御塔**。
## 因此 attack_range / attack_speed / damage / damage_type / special_attack
## 这五个字段本版只有数据、没有行为 —— 敌人不会主动攻击塔。
## 这条不变式由 tests/smoke_test.gd 的 [H] 组断言锁死。
##
## 注意这里**没有** base_damage：漏怪统一扣 1 点关卡血量（GameRules.LEAK_DAMAGE）。

@export_group("标识")
@export var id: String = ""
@export var display_name: String = "敌人"

@export_group("生存")
@export var max_health: float = 60.0                                    ## 血量
@export var move_speed: float = 70.0                                    ## 移速（像素/秒）
@export var physical_resist: float = 0.0                                ## 物理抗性 0.0~0.9
@export var magic_resist: float = 0.0                                   ## 法术抗性 0.0~0.9

@export_group("攻击（本版仅字段，敌人不会攻击塔）")
@export var attack_range: float = 40.0                                  ## 射程（近战，必须 < GameRules.TILE_SIZE）
@export var attack_speed: float = 1.0                                   ## 攻速：每秒攻击次数
@export var damage: float = 5.0                                         ## 伤害
@export var damage_type: DamageType.Kind = DamageType.Kind.PHYSICAL     ## 伤害类型
@export var special_attack: String = ""                                 ## 特殊攻击（占位）值域: "" | "slow" | "splash"

@export_group("表现与经济")
@export var gold_reward: int = 10                                       ## 击杀奖励（本版仅统计显示）
@export var body_radius: float = 16.0                                   ## 碰撞 / 绘制半径
@export var color: Color = Color("#e04b4b")                             ## 颜色（也是像素测试的锚点）

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("EnemyData.id 为空")
	if max_health <= 0.0:
		errors.append("%s: max_health 必须 > 0" % id)
	if move_speed <= 0.0:
		errors.append("%s: move_speed 必须 > 0" % id)
	if body_radius <= 0.0:
		errors.append("%s: body_radius 必须 > 0" % id)
	if gold_reward < 0:
		errors.append("%s: gold_reward 不能为负" % id)
	if attack_range < 0.0:
		errors.append("%s: attack_range 不能为负" % id)
	if not special_attack in ["", "slow", "splash"]:
		errors.append("%s: special_attack 取值非法 '%s'（值域: \"\" | \"slow\" | \"splash\"）" % [id, special_attack])
	return errors
