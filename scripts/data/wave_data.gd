class_name WaveData
extends Resource
## 一个波次：由若干出怪组构成，各组按自己的 delay / interval 并行出怪。

@export var groups: Array[SpawnGroup] = []

## 本波从开始到「最后一支出怪」的时长（秒）。决定 SPAWNING 阶段持续多久。
func duration() -> float:
	var total := 0.0
	for group in groups:
		if group != null:
			total = maxf(total, group.last_spawn_time())
	return total

## 本波敌人总数。
func total_count() -> int:
	var total := 0
	for group in groups:
		if group != null:
			total += group.count
	return total

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if groups.is_empty():
		errors.append("WaveData.groups 为空（空波次会让流程直接跳过）")
	for i in groups.size():
		var group: SpawnGroup = groups[i]
		if group == null:
			errors.append("WaveData.groups[%d] 为 null" % i)
		else:
			errors.append_array(group.validate())
	return errors
