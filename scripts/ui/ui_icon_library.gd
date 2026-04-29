class_name UIIconLibrary
extends RefCounted

const ICON_WARNING: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_warning.png")
const ICON_INFO: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_info.png")
const ICON_MORNING: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_morning.png")
const ICON_AFTERNOON: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_afternoon.png")
const ICON_NIGHT: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_night.png")
const ICON_SETTINGS: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_settings.png")
const ICON_POWER: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_power.png")
const ICON_IMAGE: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_image.png")
const ICON_METRO: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_metro.png")
const ICON_BUS: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_bus.png")

## 延迟生成的代码绘制图标缓存
static var _generated_cache: Dictionary = {}

const _ICON_MAP := {
	"warning": ICON_WARNING,
	"info": ICON_INFO,
	"morning": ICON_MORNING,
	"afternoon": ICON_AFTERNOON,
	"night": ICON_NIGHT,
	"settings": ICON_SETTINGS,
	"power": ICON_POWER,
	"image": ICON_IMAGE,
	"metro": ICON_METRO,
	"bus": ICON_BUS,
	# emoji 兼容映射
	"⚠": ICON_WARNING,
	"💡": ICON_INFO,
	"☀": ICON_MORNING,
	"🌤": ICON_AFTERNOON,
	"🌙": ICON_NIGHT,
	"⚙": ICON_SETTINGS,
	"⏻": ICON_POWER,
	"🖼": ICON_IMAGE,
	"🚇": ICON_METRO,
	"🚌": ICON_BUS,
}

## 代码绘制图标的 token 列表（按需生成，避免启动时全部创建）
const _GENERATED_TOKENS := {
	"document": "_gen_document",
	"book": "_gen_book",
	"download": "_gen_download",
	"rest": "_gen_rest",
	"hamburger": "_gen_hamburger",
	# emoji 兼容
	"📝": "_gen_document",
	"📚": "_gen_book",
	"⬇": "_gen_download",
	"☾": "_gen_rest",
	"☰": "_gen_hamburger",
}


static func get_icon(token: String) -> Texture2D:
	var normalized := token.strip_edges().to_lower()
	if normalized.is_empty():
		return null
	# 先查预加载贴图
	if _ICON_MAP.has(normalized):
		return _ICON_MAP[normalized]
	# 原始 token 查（emoji 不会被 to_lower 改变）
	if _ICON_MAP.has(token.strip_edges()):
		return _ICON_MAP[token.strip_edges()]
	# 查代码绘制图标
	var gen_key := ""
	if _GENERATED_TOKENS.has(normalized):
		gen_key = normalized
	elif _GENERATED_TOKENS.has(token.strip_edges()):
		gen_key = token.strip_edges()
	if not gen_key.is_empty():
		if _generated_cache.has(gen_key):
			return _generated_cache[gen_key]
		var method_name: String = _GENERATED_TOKENS[gen_key]
		var tex: Texture2D = _call_generator(method_name)
		if tex != null:
			_generated_cache[gen_key] = tex
		return tex
	return null


static func _call_generator(method_name: String) -> Texture2D:
	var size: int = 32
	var color := Color("#4569C7")
	match method_name:
		"_gen_document":
			return _gen_document(size, color)
		"_gen_book":
			return _gen_book(size, color)
		"_gen_download":
			return _gen_download(size, color)
		"_gen_rest":
			return _gen_rest(size, color)
		"_gen_hamburger":
			var WindowIconRendererClass := preload("res://scripts/ui/window_icon_renderer.gd")
			return WindowIconRendererClass.create_hamburger_icon(color)
	return null


## 文档图标（纸张 + 横线）
static func _gen_document(sz: int, color: Color) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 纸张轮廓
	var left: int = int(sz * 0.25)
	var right: int = int(sz * 0.75)
	var top: int = int(sz * 0.15)
	var bottom: int = int(sz * 0.85)
	for x: int in range(left, right + 1):
		img.set_pixel(x, top, color)
		img.set_pixel(x, bottom, color)
	for y: int in range(top, bottom + 1):
		img.set_pixel(left, y, color)
		img.set_pixel(right, y, color)
	# 内部横线
	for row_i: int in range(3):
		var ly: int = top + int(sz * 0.2) + row_i * int(sz * 0.15)
		if ly < bottom:
			for x: int in range(left + 3, right - 2):
				img.set_pixel(x, ly, color)
	return ImageTexture.create_from_image(img)


## 书本图标（打开的书）
static func _gen_book(sz: int, color: Color) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = sz / 2
	var top: int = int(sz * 0.2)
	var bottom: int = int(sz * 0.8)
	# 书脊
	for y: int in range(top, bottom + 1):
		img.set_pixel(cx, y, color)
	# 左页
	for x: int in range(int(sz * 0.15), cx):
		img.set_pixel(x, top, color)
		img.set_pixel(x, bottom, color)
	for y: int in range(top, bottom + 1):
		img.set_pixel(int(sz * 0.15), y, color)
	# 右页
	for x: int in range(cx, int(sz * 0.85) + 1):
		img.set_pixel(x, top, color)
		img.set_pixel(x, bottom, color)
	for y: int in range(top, bottom + 1):
		img.set_pixel(int(sz * 0.85), y, color)
	return ImageTexture.create_from_image(img)


## 下载图标（向下箭头 + 底线）
static func _gen_download(sz: int, color: Color) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = sz / 2
	# 竖线
	for y: int in range(int(sz * 0.2), int(sz * 0.6) + 1):
		img.set_pixel(cx, y, color)
		img.set_pixel(cx + 1, y, color)
	# 箭头
	for i: int in range(5):
		var ay: int = int(sz * 0.55) + i
		if ay < sz and cx - i >= 0 and cx + i + 1 < sz:
			img.set_pixel(cx - i, ay, color)
			img.set_pixel(cx + i + 1, ay, color)
	# 底线
	for x: int in range(int(sz * 0.25), int(sz * 0.75) + 1):
		img.set_pixel(x, int(sz * 0.8), color)
		img.set_pixel(x, int(sz * 0.8) + 1, color)
	return ImageTexture.create_from_image(img)


## 休息/月亮图标
static func _gen_rest(sz: int, color: Color) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: float = sz * 0.45
	var cy: float = sz * 0.45
	var r_outer: float = sz * 0.3
	var r_inner: float = sz * 0.25
	var offset_x: float = sz * 0.12
	# 画月牙：外圆内减去偏移内圆
	for x: int in range(sz):
		for y: int in range(sz):
			var dx_o: float = x - cx
			var dy_o: float = y - cy
			var in_outer: bool = (dx_o * dx_o + dy_o * dy_o) <= (r_outer * r_outer)
			var dx_i: float = x - (cx + offset_x)
			var dy_i: float = y - (cy - offset_x * 0.5)
			var in_inner: bool = (dx_i * dx_i + dy_i * dy_i) <= (r_inner * r_inner)
			if in_outer and not in_inner:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
