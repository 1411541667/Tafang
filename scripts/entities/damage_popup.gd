class_name DamagePopup
extends Node2D
## 伤害飘字：从命中点向上飘并淡出。纯表现，不影响任何战斗数值。
##
## 【为什么用 _physics_process】整个游戏的逻辑都跑在固定物理帧上（配合 --fixed-fps
## 才能做确定性测试）。飘字虽然是表现，但走同一条时间轴可以让截图测试算出「第 N 帧
## 应该飘到哪里」，不必依赖显示器刷新率。
##
## 【中文字体】伤害数字是阿拉伯数字，内置字体就有；但如果换成中文标签就会变方框。
## 所以这里优先加载项目自带的 NotoSansSC，加载失败才退回内置字体（至少数字还能显示）。

const FONT_PATH := "res://assets/fonts/NotoSansSC-VF.ttf"
const FONT_SIZE := 22
const LIFETIME := 0.75
const RISE_DISTANCE := 38.0
const COLOR_PHYSICAL := Color("#ffd166")
const COLOR_MAGIC := Color("#8fd3ff")
const COLOR_OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
const OUTLINE_SIZE := 3

var text: String = ""
var text_color: Color = Color.WHITE

var _age: float = 0.0
var _origin: Vector2 = Vector2.ZERO

static var _font: Font = null

static func get_font() -> Font:
	if _font == null:
		var resource: Resource = load(FONT_PATH)
		_font = resource as Font
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font

static func create(at: Vector2, amount: float, kind: DamageType.Kind) -> DamagePopup:
	var popup := DamagePopup.new()
	popup._origin = at
	popup.position = at
	# 向上取整：抗性把 12 点伤害减到 6 时显示 6，不会出现 5.999 这种数字
	popup.text = str(int(round(maxf(amount, 0.0))))
	popup.text_color = COLOR_PHYSICAL if kind == DamageType.Kind.PHYSICAL else COLOR_MAGIC
	# 浮在敌人和弹道之上；不随暂停冻结会更好看，但保持可暂停以免测试里被漏掉
	popup.z_index = 60
	return popup

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var ratio := _age / LIFETIME
	position = _origin + Vector2(0.0, -RISE_DISTANCE * ratio)
	modulate.a = 1.0 - ratio

func _draw() -> void:
	var font := get_font()
	if font == null or text.is_empty():
		return
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var origin := Vector2(-size.x * 0.5, size.y * 0.35)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
		OUTLINE_SIZE, COLOR_OUTLINE)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, text_color)
