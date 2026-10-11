extends SceneTree
##
## 开发辅助：把 output/ 里的截图做成颜色直方图，用来核对像素锚点表。
##
##   & $GODOT --headless --path <proj> -s res://tools/inspect_png.gd --quit-after 3000
##
## 它不是测试，只是排查「截图里到底有什么颜色」的工具。
##

const DIR := "res://output"


func _initialize() -> void:
	var files := DirAccess.get_files_at(DIR)
	if files.is_empty():
		print("output/ 里没有文件")
		quit(1)
		return
	for file_name in files:
		if not file_name.ends_with(".png"):
			continue
		_inspect(DIR + "/" + file_name, file_name)
	quit(0)


func _inspect(path: String, label: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		print("== %s ：读不到文件" % label)
		return
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		print("== %s ：不是合法 PNG" % label)
		return

	var counts := {}
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var hex := "#" + image.get_pixel(x, y).to_html(false)
			counts[hex] = int(counts.get(hex, 0)) + 1

	var keys := counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(counts[a]) > int(counts[b]))

	print("")
	print("== %s  (%d x %d)  颜色种类 %d" % [label, image.get_width(), image.get_height(), keys.size()])
	var limit := mini(14, keys.size())
	for i in limit:
		var key: String = keys[i]
		var swatch := Color(key)
		print("     %s  采样 %5d  （%.3f, %.3f, %.3f）"
			% [key, int(counts[key]), swatch.r, swatch.g, swatch.b])
