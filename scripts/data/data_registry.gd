class_name DataRegistry
## 关卡 / 防御塔 / 敌人 数据的统一入口（按 id 取资源）+ 跨资源完整性校验。
##
## 【依赖方向】DataRegistry -> data 资源类（单向）。
## 资源类之间绝不互相引用，避免 class_name 循环依赖。
##
## 【重要】Dictionary.get() / load() 返回 Variant。
## 对它用 `:=` 推断类型会被 Godot 4.7 当成错误（inference_on_variant 警告升级为 error），
## 脚本解析失败后没人调 quit()，进程会永久挂起。
## 所以本文件里所有取值一律**显式标注类型**，绝不使用 `:=`。

const LEVEL_ORDER: Array[String] = [
	"level_01", "level_02", "level_03", "level_04", "level_05", "level_test"
]

const LEVEL_PATHS := {
	"level_01": "res://data/levels/level_01.tres",
	"level_02": "res://data/levels/level_02.tres",
	"level_03": "res://data/levels/level_03.tres",
	"level_04": "res://data/levels/level_04.tres",
	"level_05": "res://data/levels/level_05.tres",
	"level_test": "res://data/levels/level_test.tres",
}

const TOWER_PATHS := {
	"arrow_tower": "res://data/towers/arrow_tower.tres",
}

const ENEMY_PATHS := {
	"grunt": "res://data/enemies/grunt.tres",
	"runner": "res://data/enemies/runner.tres",
	"tank": "res://data/enemies/tank.tres",
}

const MAP_PATHS := {
	"map_01": "res://data/maps/map_01.tres",
	"map_02": "res://data/maps/map_02.tres",
	"map_03": "res://data/maps/map_03.tres",
	"map_04": "res://data/maps/map_04.tres",
	"map_05": "res://data/maps/map_05.tres",
	"map_test": "res://data/maps/map_test.tres",
}

# ---------------------------------------------------------------------------
# 按 id 取资源
# ---------------------------------------------------------------------------

static func get_level(id: String) -> LevelData:
	var path: String = LEVEL_PATHS.get(id, "")
	if path.is_empty():
		push_error("DataRegistry: 未知关卡 id '%s'" % id)
		return null
	if not ResourceLoader.exists(path):
		push_error("DataRegistry: 关卡资源不存在 '%s'（先跑 tools/generate_data.gd）" % path)
		return null
	var res: Resource = load(path)
	return res as LevelData

static func get_tower(id: String) -> TowerData:
	var path: String = TOWER_PATHS.get(id, "")
	if path.is_empty():
		push_error("DataRegistry: 未知防御塔 id '%s'" % id)
		return null
	if not ResourceLoader.exists(path):
		push_error("DataRegistry: 防御塔资源不存在 '%s'（先跑 tools/generate_data.gd）" % path)
		return null
	var res: Resource = load(path)
	return res as TowerData

static func get_enemy(id: String) -> EnemyData:
	var path: String = ENEMY_PATHS.get(id, "")
	if path.is_empty():
		push_error("DataRegistry: 未知敌人 id '%s'" % id)
		return null
	if not ResourceLoader.exists(path):
		push_error("DataRegistry: 敌人资源不存在 '%s'（先跑 tools/generate_data.gd）" % path)
		return null
	var res: Resource = load(path)
	return res as EnemyData

static func get_map(id: String) -> MapData:
	var path: String = MAP_PATHS.get(id, "")
	if path.is_empty():
		push_error("DataRegistry: 未知地图 id '%s'" % id)
		return null
	if not ResourceLoader.exists(path):
		push_error("DataRegistry: 地图资源不存在 '%s'（先跑 tools/generate_data.gd）" % path)
		return null
	var res: Resource = load(path)
	return res as MapData

## 关卡选择页用的顺序列表（固定顺序，不依赖字典遍历顺序）。
static func all_level_ids() -> Array[String]:
	return LEVEL_ORDER.duplicate()

static func all_map_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in MAP_PATHS.keys():
		ids.append(key)
	ids.sort()
	return ids

static func all_tower_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in TOWER_PATHS.keys():
		ids.append(key)
	ids.sort()
	return ids

static func all_enemy_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in ENEMY_PATHS.keys():
		ids.append(key)
	ids.sort()
	return ids

# ---------------------------------------------------------------------------
# 跨资源完整性校验
# ---------------------------------------------------------------------------

## 校验所有资源：自身字段合法性 + id 引用完整性 + 近战不可达不变式。
## 生成器与冒烟测试共用这一个入口。
static func validate_all() -> PackedStringArray:
	var errors := PackedStringArray()

	# --- 防御塔 ---
	for tower_id: String in TOWER_PATHS.keys():
		var tower := get_tower(tower_id)
		if tower == null:
			errors.append("防御塔 '%s' 无法加载" % tower_id)
			continue
		if tower.id != tower_id:
			errors.append("防御塔 '%s': 文件内 id 为 '%s'，与注册表不一致" % [tower_id, tower.id])
		errors.append_array(tower.validate())

	# --- 敌人 ---
	for enemy_id: String in ENEMY_PATHS.keys():
		var enemy := get_enemy(enemy_id)
		if enemy == null:
			errors.append("敌人 '%s' 无法加载" % enemy_id)
			continue
		if enemy.id != enemy_id:
			errors.append("敌人 '%s': 文件内 id 为 '%s'，与注册表不一致" % [enemy_id, enemy.id])
		errors.append_array(enemy.validate())

	# --- 地图 ---
	for map_id: String in MAP_PATHS.keys():
		var map := get_map(map_id)
		if map == null:
			errors.append("地图 '%s' 无法加载" % map_id)
			continue
		if map.id != map_id:
			errors.append("地图 '%s': 文件内 id 为 '%s'，与注册表不一致" % [map_id, map.id])
		errors.append_array(map.validate())

	# --- 近战不可达不变式（结构上锁死「敌人打不到塔」）---
	for enemy_id: String in ENEMY_PATHS.keys():
		var enemy := get_enemy(enemy_id)
		if enemy == null:
			continue
		if enemy.attack_range >= float(GameRules.TILE_SIZE):
			errors.append("%s: attack_range=%.1f >= TILE_SIZE=%d —— 近战敌人将够得着防御塔，破坏核心不变式" % [enemy_id, enemy.attack_range, GameRules.TILE_SIZE])

	# --- 关卡（含跨资源引用）---
	for level_id: String in LEVEL_ORDER:
		var level := get_level(level_id)
		if level == null:
			errors.append("关卡 '%s' 无法加载" % level_id)
			continue
		if level.id != level_id:
			errors.append("关卡 '%s': 文件内 id 为 '%s'，与注册表不一致" % [level_id, level.id])
		errors.append_array(level.validate())

		if get_map(level.map_id) == null:
			errors.append("%s: map_id 含未知地图 id '%s'" % [level_id, level.map_id])

		for tower_id in level.allowed_tower_ids:
			if get_tower(tower_id) == null:
				errors.append("%s: allowed_tower_ids 含未知防御塔 id '%s'" % [level_id, tower_id])

		for wi in level.waves.size():
			var wave: WaveData = level.waves[wi]
			if wave == null:
				continue
			for gi in wave.groups.size():
				var group: SpawnGroup = wave.groups[gi]
				if group == null:
					continue
				if get_enemy(group.enemy_id) == null:
					errors.append("%s: waves[%d].groups[%d] 含未知敌人 id '%s'" % [level_id, wi, gi, group.enemy_id])

	return errors

## 所有关卡的资源路径（测试直接 instantiate 时用）。
static func level_resource_path(id: String) -> String:
	var path: String = LEVEL_PATHS.get(id, "")
	return path
