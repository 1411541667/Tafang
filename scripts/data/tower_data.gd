class_name TowerData
extends Resource
## 防御塔数据。字段与需求一一对应：
## 射程 / 攻速 / 伤害 / 伤害类型 / 血量 / 物理抗性 / 法术抗性 / 特殊攻击
##
## 【本版范围】塔的 血量 / 物理抗性 / 法术抗性 只有字段、不参与任何逻辑：
## 三种敌人都是近战并且够不到塔（见 GameRules.MELEE_RANGE_MAX），所以塔不会受伤，
## Tower 类里没有 take_damage()，也不存在被摧毁。将来加远程敌人时再接。

@export_group("标识")
@export var id: String = ""
@export var display_name: String = "防御塔"

@export_group("攻击")
@export var range: float = 160.0                                        ## 射程（像素）
@export var attack_speed: float = 1.2                                   ## 攻速：每秒攻击次数
@export var damage: float = 12.0                                        ## 单发伤害
@export var damage_type: DamageType.Kind = DamageType.Kind.PHYSICAL     ## 伤害类型
@export var target_priority: int = 0                                    ## 选敌优先级 0=最前 1=最近 2=血最多
@export var special_attack: String = ""                                 ## 特殊攻击（占位）值域: "" | "slow" | "splash"

@export_group("生存（本版仅字段，塔不会受伤）")
@export var max_health: float = 120.0                                   ## 血量
@export var physical_resist: float = 0.0                                ## 物理抗性 0.0~0.9
@export var magic_resist: float = 0.0                                   ## 法术抗性 0.0~0.9

@export_group("弹道与经济")
@export var projectile_speed: float = 520.0                             ## 弹道速度（像素/秒）
@export var instant_hit: bool = false                                   ## true = 瞬发直伤，不生成弹道
@export var cost: int = 50                                              ## 建造花费（LevelData.enforce_cost 为 false 时不生效）

## 攻击间隔（秒）。
## maxf 是除零守卫：attack_speed 为 0 时返回一个大而有限的值，不会得到 inf。
func get_attack_interval() -> float:
	return 1.0 / maxf(attack_speed, 0.001)

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("TowerData.id 为空")
	if range <= 0.0:
		errors.append("%s: range 必须 > 0" % id)
	if damage < 0.0:
		errors.append("%s: damage 不能为负" % id)
	if max_health < 0.0:
		errors.append("%s: max_health 不能为负" % id)
	if cost < 0:
		errors.append("%s: cost 不能为负" % id)
	if projectile_speed <= 0.0:
		errors.append("%s: projectile_speed 必须 > 0" % id)
	if target_priority < 0 or target_priority > 2:
		errors.append("%s: target_priority 必须为 0/1/2，当前 %d" % [id, target_priority])
	if not special_attack in ["", "slow", "splash"]:
		errors.append("%s: special_attack 取值非法 '%s'（值域: \"\" | \"slow\" | \"splash\"）" % [id, special_attack])
	return errors
