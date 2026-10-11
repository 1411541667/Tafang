class_name UiKit
extends RefCounted
## UI 构件工厂：所有界面都用代码搭，.tscn 里只留「根节点 + 脚本」。
##
## 【为什么不手写 .tscn】手写场景文件要手算 anchors/offsets/theme override，
## 一处数字错位就是一屏错版，而且很难 review。用代码搭 UI 让版式可以复用、
## 可以加注释、可以抽公共构件 —— 代价只是少了一点编辑器可视化。
##
## 【字体】项目自带的 NotoSansSC 是唯一含中文字形的字体。
## 每个控件都显式 add_theme_font_override，不依赖 project.godot 的全局 theme，
## 这样即使某个控件被移到别的分支也还是中文正常。
## 加载失败时退回内置字体（中文会变方框，但至少数字和英文还在，不会整屏空白）。

const FONT_PATH := "res://assets/fonts/NotoSansSC-VF.ttf"

# 调色板：与地图绘制用的颜色同源，保证 UI 和战场是同一套色系
const BG_DARK := Color("#0f151d")
const PANEL_BG := Color("#1b2430")
const PANEL_BORDER := Color("#33506e")
const TEXT := Color("#e8eef6")
const TEXT_DIM := Color("#95a6ba")
const ACCENT := Color("#4d78a8")
const ACCENT_HOVER := Color("#5f92cc")
const DANGER := Color("#d8544f")
const OK := Color("#57b06a")
const GOLD := Color("#ffd166")

const BUTTON_BG := Color("#243447")
const BUTTON_BG_HOVER := Color("#2f4a66")
const BUTTON_BG_PRESSED := Color("#1b2a3a")
const BUTTON_BG_DISABLED := Color("#1a222c")

static var _font: Font = null
static var _font_resolved: bool = false

static func font() -> Font:
	if not _font_resolved:
		_font_resolved = true
		var resource: Resource = load(FONT_PATH)
		_font = resource as Font
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font

# ---------------------------------------------------------------------------
# 样式盒
# ---------------------------------------------------------------------------

static func flat_box(background: Color, border: Color, border_width: int = 2,
		radius: int = 6, padding: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	if padding > 0:
		box.content_margin_left = padding
		box.content_margin_right = padding
		box.content_margin_top = padding
		box.content_margin_bottom = padding
	return box

# ---------------------------------------------------------------------------
# 基础构件
# ---------------------------------------------------------------------------

static func make_label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func make_button(text: String, min_size: Vector2 = Vector2(240, 52)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_override("font", font())
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", TEXT_DIM)
	button.add_theme_stylebox_override("normal",
		flat_box(BUTTON_BG, PANEL_BORDER, 2, 6, 10))
	button.add_theme_stylebox_override("hover",
		flat_box(BUTTON_BG_HOVER, ACCENT_HOVER, 2, 6, 10))
	button.add_theme_stylebox_override("pressed",
		flat_box(BUTTON_BG_PRESSED, ACCENT_HOVER, 2, 6, 10))
	button.add_theme_stylebox_override("focus",
		flat_box(Color(0, 0, 0, 0), ACCENT_HOVER, 2, 6, 10))
	button.add_theme_stylebox_override("disabled",
		flat_box(BUTTON_BG_DISABLED, PANEL_BORDER, 2, 6, 10))
	return button

static func make_check(text: String, pressed: bool) -> CheckButton:
	var button := CheckButton.new()
	button.text = text
	button.button_pressed = pressed
	button.add_theme_font_override("font", font())
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", ACCENT_HOVER)
	return button

static func make_panel(background: Color = PANEL_BG, border: Color = PANEL_BORDER,
		padding: int = 14) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", flat_box(background, border, 2, 8, padding))
	return panel

static func make_spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

static func make_background(color: Color = BG_DARK) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 不吞鼠标事件：战场上的点击必须能穿透到 _unhandled_input
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

static func make_vbox(separation: int = 14) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box

static func make_hbox(separation: int = 14) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box

## 居中容器，铺满父节点并把内容摆在中间
static func make_center() -> CenterContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return center

## 标题 + 副标题 + 内容，菜单页共用的版式
static func make_page(title_text: String, subtitle_text: String = "") -> VBoxContainer:
	var box := make_vbox(16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := make_label(title_text, 48, TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	if not subtitle_text.is_empty():
		var subtitle := make_label(subtitle_text, 17, TEXT_DIM)
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(subtitle)
	return box
