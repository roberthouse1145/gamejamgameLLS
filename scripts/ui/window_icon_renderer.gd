class_name WindowIconRenderer
extends RefCounted
## 代码绘制窗口控制按钮图标（Win11 风格细线）
## 不依赖外部素材，纯代码生成 ImageTexture

const ICON_SIZE: int = 48
const COLOR_DEFAULT: Color = Color("#6B7086")


## 生成最小化图标（横线）
static func create_minimize_icon(color: Color = COLOR_DEFAULT) -> ImageTexture:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy: int = int(ICON_SIZE * 0.5)
	var x0: int = int(ICON_SIZE * 0.25)
	var x1: int = int(ICON_SIZE * 0.75)
	for x: int in range(x0, x1 + 1):
		img.set_pixel(x, cy, color)
		img.set_pixel(x, cy + 1, color)
	return ImageTexture.create_from_image(img)


## 生成最大化图标（方框）
static func create_maximize_icon(color: Color = COLOR_DEFAULT) -> ImageTexture:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var s: int = int(ICON_SIZE * 0.25)
	var e: int = int(ICON_SIZE * 0.75)
	_draw_rect_outline(img, s, s, e, e, color)
	return ImageTexture.create_from_image(img)


## 生成关闭图标（X）
static func create_close_icon(color: Color = COLOR_DEFAULT) -> ImageTexture:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var s: int = int(ICON_SIZE * 0.25)
	var e: int = int(ICON_SIZE * 0.75)
	var length: int = e - s
	for i: int in range(length + 1):
		# 左上→右下
		img.set_pixel(s + i, s + i, color)
		if s + i + 1 < ICON_SIZE:
			img.set_pixel(s + i, s + i + 1, color)
		# 右上→左下
		img.set_pixel(e - i, s + i, color)
		if s + i + 1 < ICON_SIZE:
			img.set_pixel(e - i, s + i + 1, color)
	return ImageTexture.create_from_image(img)


## 生成还原图标（两个重叠方框，最大化状态下使用）
static func create_restore_icon(color: Color = COLOR_DEFAULT) -> ImageTexture:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 后方小方框（右上偏移）
	_draw_rect_outline(img, int(ICON_SIZE * 0.35), int(ICON_SIZE * 0.2), int(ICON_SIZE * 0.75), int(ICON_SIZE * 0.6), color)
	# 前方小方框区域先清透明再画框
	var fx0: int = int(ICON_SIZE * 0.2)
	var fy0: int = int(ICON_SIZE * 0.35)
	var fx1: int = int(ICON_SIZE * 0.6)
	var fy1: int = int(ICON_SIZE * 0.75)
	for x: int in range(fx0, fx1 + 1):
		for y: int in range(fy0, fy1 + 1):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	_draw_rect_outline(img, fx0, fy0, fx1, fy1, color)
	return ImageTexture.create_from_image(img)


## 生成汉堡菜单图标（三条横线）
static func create_hamburger_icon(color: Color = COLOR_DEFAULT) -> ImageTexture:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var x0: int = int(ICON_SIZE * 0.2)
	var x1: int = int(ICON_SIZE * 0.8)
	var rows: Array[int] = [int(ICON_SIZE * 0.3), int(ICON_SIZE * 0.5), int(ICON_SIZE * 0.7)]
	for cy: int in rows:
		for x: int in range(x0, x1 + 1):
			img.set_pixel(x, cy, color)
			img.set_pixel(x, cy + 1, color)
	return ImageTexture.create_from_image(img)


static func _draw_rect_outline(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	for x: int in range(x0, x1 + 1):
		img.set_pixel(x, y0, color)
		img.set_pixel(x, y1, color)
	for y: int in range(y0, y1 + 1):
		img.set_pixel(x0, y, color)
		img.set_pixel(x1, y, color)
