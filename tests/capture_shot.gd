extends Node
##
## 视觉截图测试：真渲染 + 像素分析，不靠肉眼。
##
## 运行（**绝对不能加 --headless**，dummy 渲染后端截出来是纯色）：
##   & $GODOT --path <proj> --resolution 1280x720 --fixed-fps 60 --quit-after 2000 res://tests/capture_shot.tscn
##
## 输出：res://output/*.png （已被 .gitignore 排除）
##
## 像素分析思路（来自学习记忆）：
##   - 颜色即断言锚点：所有视觉元素都用 _draw() 画纯色，采样时按精确色值查表即可。
##   - 容差 + 采样步长 + 包围盒：能查出「画面空白」「元素根本没画出来」「画在荒唐的位置」。
##   - 文字是抗锯齿的，按精确色值查不到，改用「高亮像素计数」这个启发式。
##   - 暂停遮罩是半透明叠加，叠加后原色必须消失 —— 用它反证遮罩真的盖上了。
##

const OUT_DIR := "res://output"

## 精确色锚点：色值 → 语义名。全部是 _draw() 画的纯色填充，采样像素应精确等于它。
const EXACT_TARGETS := {
	"菜单底色": "#0f151d",
	"地图底色": "#1b2430",
	"路径": "#775f3c",
	"路径描边": "#9a7d50",
	"塔位": "#33506e",
	"塔位描边": "#4d78a8",
	"出怪口": "#d8544f",
	"进怪口": "#57b06a",
	"小兵": "#e04b4b",
	"疾行": "#f0952f",
	"重甲": "#a259d8",
	"塔底座": "#3f6ea8",
	"塔顶": "#ffd166",
	"弹道": "#ffe066",
	"HUD状态条": "#152030",
	"按钮底": "#243447",
	"文字": "#e8eef6",
	"次要文字": "#95a6ba",
	"引擎默认灰": "#4c4c4c",
}

const SAMPLE_STEP := 2

var _passed := 0
var _failed := 0
var _failures: Array[String] = []


func _ready() -> void:
	# 测试自身永不暂停：后面要截「暂停面板」，get_tree().paused = true 不能把自己冻住
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("========== 塔防截图测试 ==========")
	await _run_all()
	_report()


# ---------------------------------------------------------------------------
# 断言
# ---------------------------------------------------------------------------

func _check(label: String, condition: bool, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
		return true
	_failed += 1
	var text := "  [FAIL] %s" % label
	if not detail.is_empty():
		text += "  —— %s" % detail
	_failures.append(text)
	print(text)
	return false


func _wait_physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


# ---------------------------------------------------------------------------
# 截图 + 像素分析
# ---------------------------------------------------------------------------

func _capture(name: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		_check("截到画面：%s" % name, false, "get_texture().get_image() 返回 null")
		return {}
	var absolute := ProjectSettings.globalize_path(OUT_DIR) + "/" + name + ".png"
	var err := image.save_png(absolute)
	_check("保存截图：%s" % name, err == OK, "save_png 错误码 = %d" % err)
	print("      %s  (%d x %d)  ->  %s" % [name, image.get_width(), image.get_height(), absolute])
	return _analyze(image, name)


func _analyze(image: Image, name: String) -> Dictionary:
	var hits := {}
	var bounds := {}
	for key in EXACT_TARGETS.keys():
		hits[key] = 0
		bounds[key] = [image.get_width(), image.get_height(), -1, -1]

	# 锚点表是「语义名 → 色值」，采样时拿到的是色值，所以要一张反向索引：色值 → 语义名。
	# （之前这里直接写 EXACT_TARGETS.has(hex) —— 拿色值去查以语义名为键的表，恒为 false，
	#   于是所有精确色命中数永远是 0，而直方图又证明颜色明明画对了。）
	var reverse := {}
	for label in EXACT_TARGETS.keys():
		reverse[EXACT_TARGETS[label]] = label

	var distinct := {}
	var bright := 0
	var text_px := 0
	var width := image.get_width()
	var height := image.get_height()

	for y in range(0, height, SAMPLE_STEP):
		for x in range(0, width, SAMPLE_STEP):
			var c := image.get_pixel(x, y)
			# Color.to_html(false) 返回的十六进制**不带 # 前缀**，这里补上以对齐锚点表
			var hex := "#" + c.to_html(false)
			distinct[hex] = true
			if reverse.has(hex):
				var key: String = reverse[hex]
				hits[key] = int(hits[key]) + 1
				var box: Array = bounds[key]
				box[0] = mini(int(box[0]), x)
				box[1] = mini(int(box[1]), y)
				box[2] = maxi(int(box[2]), x)
				box[3] = maxi(int(box[3]), y)
			# 文字是抗锯齿的，精确色查不到，用「接近纯白」计数
			if c.r > 0.85 and c.g > 0.88 and c.b > 0.92:
				bright += 1
			# 更宽松的「浅色像素」计数：字号小的时候笔画几乎全是半覆盖像素，
			# 上面的近白阈值只剩个位数，完全量不出「有没有文字」。0.5 这条线能覆盖
			# 文字(#e8eef6 / #95a6ba)与它们的抗锯齿过渡，同时排除所有背景/路径/塔位色。
			if c.r > 0.5 and c.g > 0.5 and c.b > 0.5:
				text_px += 1

	var report := {
		"name": name,
		"hits": hits,
		"bounds": bounds,
		"colors": distinct.size(),
		"bright": bright,
		"text_px": text_px,
		"size": Vector2i(width, height),
	}
	var summary := ""
	for key in EXACT_TARGETS.keys():
		if int(hits[key]) > 0:
			summary += "%s=%d " % [key, int(hits[key])]
	print("      颜色种类 %d，高亮像素 %d，浅色像素 %d" % [report["colors"], bright, text_px])
	print("      命中：%s" % summary)
	return report


func _hits(report: Dictionary, key: String) -> int:
	if report.is_empty():
		return 0
	var table: Dictionary = report["hits"]
	return int(table.get(key, 0))


## 空白检测：全黑/全白只有 1~2 种颜色。
func _check_not_blank(report: Dictionary) -> void:
	if report.is_empty():
		_check("画面非空白", false, "没有截到图")
		return
	_check("画面不是空白（颜色种类 %d）" % int(report["colors"]), int(report["colors"]) >= 8,
		"只有 %d 种颜色，大概是渲染后端没画东西（加了 --headless？）" % int(report["colors"]))
	_check("画面尺寸 = 1280 x 720", report["size"] == Vector2i(1280, 720),
		"实际 = %s" % str(report["size"]))
	# 地图 20x11x64 = 1280x704，比窗口矮 16px；没设默认清屏色时那条缝会露出引擎灰
	_check("没有露出引擎默认灰底（#4c4c4c）", _hits(report, "引擎默认灰") == 0,
		"露出 %d 个灰像素 —— default_clear_color 没生效或地图没铺满" % _hits(report, "引擎默认灰"))


## 文字检测：抗锯齿让纯色像素变少，所以既看精确色也看「接近纯白」的启发式。
func _check_has_text(report: Dictionary, label: String, minimum: int) -> void:
	var exact := _hits(report, "文字") + _hits(report, "次要文字")
	var bright := int(report.get("bright", 0))
	# 主判据用「浅色像素」：小字号的中文几乎全是半覆盖的抗锯齿像素，
	# 精确色与近白阈值都只剩个位数（结算面板 14 + 12），量不出内容多少。
	var text_px := int(report.get("text_px", 0))
	_check("有可读文字：%s（精确色 %d / 近白 %d / 浅色 %d）" % [label, exact, bright, text_px],
		text_px >= minimum,
		"少于 %d 个浅色像素 —— 可能是中文变方框或界面没搭起来" % minimum)


# ---------------------------------------------------------------------------
# 各场景截图
# ---------------------------------------------------------------------------

func _shot_simple(scene_path: String, name: String, min_text: int) -> Dictionary:
	var packed: PackedScene = load(scene_path)
	var node: Node = packed.instantiate()
	add_child(node)
	await _wait_physics(6)
	var report := await _capture(name)
	_check_not_blank(report)
	_check_has_text(report, name, min_text)
	node.queue_free()
	await _wait_physics(3)
	return report


func _spawn_battle() -> LevelRunner:
	GameState.update_settings(func() -> void:
		GameState.show_damage_popup = true
		GameState.show_enemy_health_bar = true
	)
	var packed: PackedScene = load("res://scenes/level.tscn")
	var runner: LevelRunner = packed.instantiate()
	runner.setup(DataRegistry.get_level("level_test"))
	add_child(runner)
	await _wait_physics(4)

	# 直线地图，塔摆在路径上下两侧，射程覆盖住一段路
	var map := runner.map_data
	var row_above := map.path[0] + Vector2i(0, -1)
	var row_below := map.path[0] + Vector2i(0, 1)
	var columns := [2, 6, 10, 14]
	for i in columns.size():
		var column: int = columns[i]
		var cell := Vector2i(column, row_above.y) if i % 2 == 0 else Vector2i(column, row_below.y)
		runner.build_manager.try_place(cell, runner.gold)

	runner.start_next_wave_now()
	await _wait_physics(96)
	return runner


func _run_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	print("")
	print("--- 界面截图 ---")
	var menu := await _shot_simple("res://scenes/main_menu.tscn", "01_主菜单", 60)
	_check("主菜单有按钮底色", _hits(menu, "按钮底") > 200,
		"按钮底像素 = %d" % _hits(menu, "按钮底"))
	_check("主菜单有背景色", _hits(menu, "菜单底色") > 5000,
		"背景像素 = %d" % _hits(menu, "菜单底色"))

	var select := await _shot_simple("res://scenes/level_select.tscn", "02_关卡选择", 100)
	_check("关卡选择页有按钮（6 个关卡）", _hits(select, "按钮底") > 800,
		"按钮底像素 = %d" % _hits(select, "按钮底"))

	var settings := await _shot_simple("res://scenes/settings_menu.tscn", "03_设置", 60)
	_check("设置页有背景色", _hits(settings, "菜单底色") > 5000)

	print("")
	print("--- 战场截图（真渲染 + 像素校验）---")
	var runner := await _spawn_battle()
	var battle := await _capture("04_战斗")
	_check_not_blank(battle)

	_check("画出了行进路线", _hits(battle, "路径") > 200, "路径像素 = %d" % _hits(battle, "路径"))
	_check("画出了可建造塔位", _hits(battle, "塔位") > 100, "塔位像素 = %d" % _hits(battle, "塔位"))
	_check("画出了出怪口", _hits(battle, "出怪口") > 20, "出怪口像素 = %d" % _hits(battle, "出怪口"))
	_check("画出了进怪口", _hits(battle, "进怪口") > 20, "进怪口像素 = %d" % _hits(battle, "进怪口"))
	_check("画出了防御塔底座", _hits(battle, "塔底座") > 20, "塔底座像素 = %d" % _hits(battle, "塔底座"))
	_check("画出了防御塔炮口", _hits(battle, "塔顶") > 2, "炮口像素 = %d" % _hits(battle, "塔顶"))
	_check("画出了敌人（小兵）", _hits(battle, "小兵") > 5, "小兵像素 = %d" % _hits(battle, "小兵"))
	_check("画出了 HUD 状态条", _hits(battle, "HUD状态条") > 500,
		"HUD 像素 = %d" % _hits(battle, "HUD状态条"))
	_check_has_text(battle, "战斗 HUD", 60)

	# 路径包围盒必须落在地图区域内（不是画到屏幕外或挤在角落）
	var path_box: Array = battle["bounds"]["路径"]
	var box_width := int(path_box[2]) - int(path_box[0])
	var box_height := int(path_box[3]) - int(path_box[1])
	_check("路径横向铺开（包围盒宽 %d px）" % box_width, box_width > 1000,
		"直线地图的路径应该几乎横穿整屏")
	_check("路径高度合理（包围盒高 %d px）" % box_height, box_height <= 128,
		"单格高的路径不该有几格高")
	_check("路径起点靠左（min_x = %d）" % int(path_box[0]), int(path_box[0]) < 96,
		"出怪口在网格 (0,5)，应该贴着左边")
	_check("路径终点靠右（max_x = %d）" % int(path_box[2]), int(path_box[2]) > 1100)

	print("")
	print("--- 暂停面板 ---")
	runner.set_paused(true)
	_check("已进入暂停", runner.paused and get_tree().paused)
	await _wait_physics(6)
	var paused := await _capture("05_暂停面板")
	_check_not_blank(paused)
	_check("暂停后遮罩盖住了战场（路径像素 %d → %d）"
		% [_hits(battle, "路径"), _hits(paused, "路径")],
		_hits(paused, "路径") < _hits(battle, "路径") / 10,
		"半透明遮罩叠加后原色必须基本消失")
	_check("暂停面板有按钮", _hits(paused, "按钮底") > 200,
		"按钮底像素 = %d" % _hits(paused, "按钮底"))
	_check_has_text(paused, "暂停面板", 60)

	print("")
	print("--- 结算面板 ---")
	runner.set_paused(false)
	await _wait_physics(4)
	runner.level_won.emit()
	await _wait_physics(6)
	var result := await _capture("06_结算面板")
	_check_not_blank(result)
	_check("结算面板盖住了战场", _hits(result, "HUD状态条") < _hits(battle, "HUD状态条") / 4,
		"HUD 像素 %d → %d" % [_hits(battle, "HUD状态条"), _hits(result, "HUD状态条")])
	_check("结算面板有按钮", _hits(result, "按钮底") > 200,
		"按钮底像素 = %d" % _hits(result, "按钮底"))
	_check_has_text(result, "结算面板", 60)

	runner.queue_free()
	await _wait_physics(3)

	print("")
	print("--- 画面对比基准 ---")
	print("      战斗画面颜色种类 = %d（空白画面会是 1~2）" % int(battle["colors"]))
	_check("战斗画面颜色丰富（%d 种）" % int(battle["colors"]), int(battle["colors"]) > 20,
		"元素太少，可能有一半没画出来")


# ---------------------------------------------------------------------------

func _report() -> void:
	get_tree().paused = false
	print("")
	print("========== 结果 ==========")
	print("通过 %d ，失败 %d" % [_passed, _failed])
	if _failed > 0:
		print("失败项：")
		for line in _failures:
			print(line)
		print("CAPTURE_RESULT=FAIL")
	else:
		print("CAPTURE_RESULT=OK")
	get_tree().quit(1 if _failed > 0 else 0)
