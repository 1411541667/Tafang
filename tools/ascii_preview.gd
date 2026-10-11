extends SceneTree

## 把 output/ 里的每张截图降采样成 ASCII 字符画，打印到 stdout。
## 用途：断言只能证明「某个颜色的像素数够多」，看不到**版面**（谁在左、谁在上、
## 有没有互相遮挡）。字符画让「界面到底长什么样」变成可读的文字。
##
## 跑法：& $GODOT --headless --path $PROJ -s res://tools/ascii_preview.gd --quit-after 6000
## 注意：--headless 只影响渲染，读 PNG 不经过渲染后端，所以这里加 --headless 是安全的。

const PNG_DIR := "res://output/"
const COLS := 96
const ROWS := 54

# 色值 → 字符。'.' 是清屏底色，' ' 是没归类到的杂色（抗锯齿过渡）
const LEGEND := {
	"#0f151d": ".",  # 菜单底色 / 清屏色
	"#1b2430": ":",  # 地图底色 / 面板底色
	"#775f3c": "=",  # 路径
	"#9a7d50": "+",  # 路径描边
	"#33506e": "o",  # 塔位 / 面板边框
	"#4d78a8": "O",  # 塔位描边
	"#d8544f": "S",  # 出怪口
	"#57b06a": "G",  # 进怪口
	"#e04b4b": "g",  # 小兵
	"#f0952f": "r",  # 疾行
	"#a259d8": "k",  # 重甲
	"#3f6ea8": "T",  # 塔底座
	"#8fc4f5": "T",  # 塔底座描边
	"#ffd166": "*",  # 塔顶 / 弹道
	"#ffe066": "*",  # 弹道
	"#152030": "H",  # HUD 状态条
	"#243447": "B",  # 按钮底
	"#2f4a66": "B",  # 按钮悬停底
	"#e8eef6": "#",  # 文字
	"#95a6ba": "#",  # 次要文字
	"#4c4c4c": "!",  # 引擎默认灰（露底）
}


func _initialize() -> void:
	var names: PackedStringArray = DirAccess.get_files_at(PNG_DIR)
	var found := 0
	for file_name in names:
		if not file_name.ends_with(".png"):
			continue
		found += 1
		_preview(file_name)
	print("ASCII_PREVIEW_DONE 共 %d 张" % found)
	quit(0)


func _preview(file_name: String) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(PNG_DIR + file_name)
	if bytes.is_empty():
		printerr("[字符画] 读不到 ", PNG_DIR + file_name)
		return
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		printerr("[字符画] 解码失败 ", file_name)
		return

	var width := image.get_width()
	var height := image.get_height()
	print("")
	print("================ %s  %dx%d ================" % [file_name, width, height])

	for row in ROWS:
		var line := ""
		for col in COLS:
			var x: int = int(float(col) / float(COLS) * float(width))
			var y: int = int(float(row) / float(ROWS) * float(height))
			line += _char_for(image.get_pixel(clampi(x, 0, width - 1), clampi(y, 0, height - 1)))
		print(line)
	print("图例  底色.= %s  地图底.: %s  路径= 塔位o 塔T 出怪S 进怪G 怪g/r/k 弹* HUD_H 按钮B 文字# 露灰!" % [
		LEGEND["#0f151d"], LEGEND["#1b2430"],
	])


func _char_for(c: Color) -> String:
	var hex: String = "#" + c.to_html(false)
	if LEGEND.has(hex):
		return LEGEND[hex]
	# 半覆盖的抗锯齿文字像素：亮到一定程度就算文字
	if c.r > 0.5 and c.g > 0.5 and c.b > 0.5:
		return "#"
	return " "
