class_name DamageType
## 伤害类型。决定用目标的哪一个抗性字段来减伤。
##
## PHYSICAL -> 用 physical_resist
## MAGIC    -> 用 magic_resist

enum Kind {
	PHYSICAL,   ## 物理
	MAGIC,      ## 法术
}

const NAMES := {
	Kind.PHYSICAL: "物理",
	Kind.MAGIC: "法术",
}

## 取伤害类型的中文名（给 HUD / 报错信息用）。
static func display_name(kind: Kind) -> String:
	var result: String = NAMES.get(kind, "未知")
	return result
