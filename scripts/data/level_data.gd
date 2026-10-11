class_name LevelData
extends Resource
## 关卡数据：关卡血量 / 地图 / 防御塔 / 敌人
##
## 【依赖方向】level_data.gd 不认识 DataRegistry —— 跨资源引用完整性检查放在
## DataRegistry.validate_all() 里。如果在这里反向调用 DataRegistry，
## 就会形成 LevelData <-> DataRegistry 的 class_name 循环依赖（报 Could not resolve class）。

@export_group("标识")
@export var id: String = ""
@export var display_name: String = "关卡"

@export_group("关卡血量")
## 关卡血量 = 允许漏怪总数。每漏 1 只怪扣 GameRules.LEAK_DAMAGE 点，归零即判负。
@export var base_health: int = 10

@export_group("经济")
@export var starting_gold: int = 150        ## 初始金币（本版仅统计与显示，不限制放置）
## 是否把 TowerData.cost 作为放置门槛。
## 本版 false：塔可以自由放置（需求「暂时不做限制」）。
## 将来勾上 true 即恢复「金币不足则拒绝放置」，**不需要改任何代码**。
@export var enforce_cost: bool = false

@export_group("内容")
## 地图用 **id** 引用，不持有 MapData 对象。
##
## 【为什么】整个 data 层统一「按 id 引用」这一条规则（防御塔用 allowed_tower_ids、
## 敌人用 enemy_id 也都是 id）。好处有三个：
##   1. 不依赖资源对象的序列化行为 —— 持有 MapData 对象时，Godot 会把整份地图
##      内嵌成 SubResource 副本写进每个关卡文件（即使加了 FLAG_CHANGE_PATH 也一样），
##      于是改地图文件不会影响任何关卡，数据静默分叉。
##   2. 关卡文件小、diff 干净，一眼能看出这一关用了哪张图。
##   3. LevelData.validate() 保持完全自包含，不反向依赖 DataRegistry
##      （否则 LevelData <-> DataRegistry 会形成 class_name 循环依赖）。
## 运行时由 LevelRunner 调 DataRegistry.get_map(level.map_id) 拿真实地图。
@export var map_id: String = ""
@export var allowed_tower_ids: PackedStringArray = PackedStringArray(["arrow_tower"])
@export var waves: Array[WaveData] = []

@export_group("节奏")
@export var prep_time: float = 8.0          ## 开局准备时间（秒）
@export var wave_interval: float = 12.0     ## 波与波之间的倒计时（秒）
@export var auto_next_wave: bool = true     ## 倒计时归零是否自动开始下一波（玩家也可点「立即开始」）

## 本关全部波次的敌人总数。
func total_enemy_count() -> int:
	var total := 0
	for wave in waves:
		if wave != null:
			total += wave.total_count()
	return total

## 只做「自包含」的结构校验，不解析任何 id（那是 DataRegistry.validate_all() 的活）。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("LevelData.id 为空")
	if base_health <= 0:
		errors.append("%s: base_health 必须 > 0，当前 %d" % [id, base_health])
	if starting_gold < 0:
		errors.append("%s: starting_gold 不能为负" % id)
	if prep_time < 0.0:
		errors.append("%s: prep_time 不能为负" % id)
	if wave_interval < 0.0:
		errors.append("%s: wave_interval 不能为负" % id)

	if map_id.is_empty():
		errors.append("%s: map_id 为空（关卡必须指定一张地图）" % id)

	if allowed_tower_ids.is_empty():
		errors.append("%s: allowed_tower_ids 为空" % id)

	if waves.is_empty():
		errors.append("%s: waves 为空（关卡至少要有一个波次）" % id)
	for i in waves.size():
		var wave: WaveData = waves[i]
		if wave == null:
			errors.append("%s: waves[%d] 为 null" % [id, i])
			continue
		for e in wave.validate():
			errors.append("%s: waves[%d] %s" % [id, i, e])

	return errors
