class_name Combat
## 战斗数值的唯一计算入口。
##
## 刻意做成 static 纯函数、不碰任何节点：冒烟测试可以直接断言数值，
## 不需要实例化场景。公式里没有任何除法，因此不可能产出 inf / nan。

## 抗性上限。超过按 0.9 计，保证任何伤害都不会被完全免疫（不会出现 0 伤害）。
const MAX_RESIST := 0.9

## 取某个伤害类型对应的抗性值，并夹到 [0.0, MAX_RESIST]。
static func resist_for(kind: DamageType.Kind, physical_resist: float, magic_resist: float) -> float:
	var raw := physical_resist
	if kind == DamageType.Kind.MAGIC:
		raw = magic_resist
	return clampf(raw, 0.0, MAX_RESIST)

## 伤害公式：最终伤害 = 攻击力 × (1 - 抗性)。
static func compute_damage(amount: float, kind: DamageType.Kind, physical_resist: float, magic_resist: float) -> float:
	if amount <= 0.0:
		return 0.0
	var reduction := resist_for(kind, physical_resist, magic_resist)
	return amount * (1.0 - reduction)
