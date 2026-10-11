class_name SpawnGroup
extends Resource
## 一个波次内的一组出怪。同一组出同一种敌人，可以有自己的延迟与强度倍率。

@export var enemy_id: String = ""
@export var count: int = 1              ## 本组出怪数量
@export var interval: float = 1.0       ## 组内相邻两只怪的间隔（秒）
@export var delay: float = 0.0          ## 本组相对「本波开始时刻」的延迟（秒）
@export var hp_scale: float = 1.0       ## 血量倍率
@export var speed_scale: float = 1.0    ## 移速倍率

## 本组最后一支出现在「本波开始后」的第几秒。
func last_spawn_time() -> float:
	return delay + interval * float(maxi(count - 1, 0))

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if enemy_id.is_empty():
		errors.append("SpawnGroup.enemy_id 为空")
	if count <= 0:
		errors.append("%s: count 必须 > 0，当前 %d" % [enemy_id, count])
	# interval 必须 > 0：否则 while (timer <= 0) 会在同一帧把本组怪全部吐完
	if interval <= 0.0:
		errors.append("%s: interval 必须 > 0（0 会导致一帧内出完本组全部敌人）" % enemy_id)
	if delay < 0.0:
		errors.append("%s: delay 不能为负" % enemy_id)
	if hp_scale <= 0.0:
		errors.append("%s: hp_scale 必须 > 0" % enemy_id)
	if speed_scale <= 0.0:
		errors.append("%s: speed_scale 必须 > 0" % enemy_id)
	return errors
