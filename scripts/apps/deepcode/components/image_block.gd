extends MarginContainer
## 图片预览块 — 在聊天流中显示 AI 生成的图片
## 显示缩略图 + image_id + 保存路径标签

@onready var texture_rect: TextureRect = %TextureRect
@onready var info_label: Label = %InfoLabel
@onready var panel: PanelContainer = %Panel

const MAX_PREVIEW_WIDTH: float = 400.0
const MAX_PREVIEW_HEIGHT: float = 300.0


func _ready() -> void:
	if panel:
		panel.add_theme_stylebox_override("panel", _get_panel_style())
	if info_label:
		info_label.add_theme_color_override("font_color", DeepCodeTheme.COLOR_TEXT_SECONDARY)
		info_label.add_theme_font_size_override("font_size", 12)


## 从本地路径加载图片并显示
func load_image(local_path: String, image_id: String = "", prompt_hint: String = "") -> void:
	if texture_rect == null:
		return

	var tex: Texture2D = _load_texture_from_path(local_path)
	if tex == null:
		_show_error("无法加载图片: " + local_path)
		return

	texture_rect.texture = tex
	# 限制预览尺寸
	texture_rect.custom_minimum_size = _calc_preview_size(tex.get_size())
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# 信息标签
	var info_parts: Array = []
	if not image_id.is_empty():
		info_parts.append(image_id)
	info_parts.append("%dx%d" % [int(tex.get_width()), int(tex.get_height())])
	if not prompt_hint.is_empty():
		info_parts.append(prompt_hint.left(60))
	if info_label:
		info_label.text = " | ".join(info_parts)


func _show_error(msg: String) -> void:
	if info_label:
		info_label.text = msg
		info_label.add_theme_color_override("font_color", DeepCodeTheme.COLOR_ERROR)


func _load_texture_from_path(path: String) -> Texture2D:
	# user:// 路径不能用 load()，需要手动加载
	if not FileAccess.file_exists(path):
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()

	var image: Image = Image.new()
	var err: Error = image.load_png_from_buffer(bytes)
	if err != OK:
		# 尝试 jpg
		err = image.load_jpg_from_buffer(bytes)
	if err != OK:
		return null

	return ImageTexture.create_from_image(image)


func _calc_preview_size(original: Vector2) -> Vector2:
	if original.x <= 0 or original.y <= 0:
		return Vector2(MAX_PREVIEW_WIDTH, MAX_PREVIEW_HEIGHT)

	var ratio: float = min(MAX_PREVIEW_WIDTH / original.x, MAX_PREVIEW_HEIGHT / original.y)
	if ratio >= 1.0:
		return original
	return Vector2(original.x * ratio, original.y * ratio)


static func _get_panel_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = DeepCodeTheme.rounded_flat(
		DeepCodeTheme.COLOR_SURFACE, DeepCodeTheme.RADIUS_MD,
		DeepCodeTheme.COLOR_BORDER, 1
	)
	s.content_margin_left = 8
	s.content_margin_top = 8
	s.content_margin_right = 8
	s.content_margin_bottom = 8
	return s
