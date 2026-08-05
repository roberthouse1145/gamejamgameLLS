class_name ImageViewerApp extends Control
## 虚拟桌面图片查看器。默认适应窗口，也可按原始像素比例查看大图。

const MIN_ZOOM: float = 0.05
const MAX_ZOOM: float = 4.0
const ZOOM_STEP: float = 0.25

@onready var title_label: Label = %ImageTitle
@onready var status_label: Label = %ImageStatus
@onready var image_scroll: ScrollContainer = %ImageScroll
@onready var image_center: CenterContainer = %ImageCenter
@onready var image_texture: TextureRect = %ImageTexture
@onready var empty_label: Label = %EmptyLabel
@onready var fit_button: Button = %FitButton
@onready var actual_size_button: Button = %ActualSizeButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var zoom_in_button: Button = %ZoomInButton

var _texture: Texture2D = null
var _zoom: float = 1.0
var _fit_to_window: bool = true


func _ready() -> void:
	_apply_styles()
	fit_button.pressed.connect(_show_fitted)
	actual_size_button.pressed.connect(_show_actual_size)
	zoom_out_button.pressed.connect(_zoom_out)
	zoom_in_button.pressed.connect(_zoom_in)
	image_scroll.resized.connect(_refresh_image_size)
	_refresh_controls()


func open_image(image_path: String, image_title: String = "") -> bool:
	if image_path.is_empty() or not ResourceLoader.exists(image_path):
		_show_load_error("图片资源不存在")
		return false
	var loaded_texture := ResourceLoader.load(image_path) as Texture2D
	if loaded_texture == null:
		_show_load_error("图片资源无法读取")
		return false
	_texture = loaded_texture
	image_texture.texture = _texture
	image_texture.visible = true
	empty_label.visible = false
	title_label.text = image_title if not image_title.strip_edges().is_empty() else image_path.get_file().get_basename()
	_fit_to_window = true
	_zoom = 1.0
	_refresh_image_size.call_deferred()
	return true


func _show_load_error(message: String) -> void:
	_texture = null
	image_texture.texture = null
	image_texture.visible = false
	empty_label.visible = true
	empty_label.text = message
	title_label.text = "图片查看器"
	status_label.text = "未载入图片"
	_refresh_controls()


func _show_fitted() -> void:
	_fit_to_window = true
	_refresh_image_size()


func _show_actual_size() -> void:
	_fit_to_window = false
	_zoom = 1.0
	_refresh_image_size()


func _zoom_out() -> void:
	_fit_to_window = false
	_zoom = clampf(_effective_zoom() - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
	_refresh_image_size()


func _zoom_in() -> void:
	_fit_to_window = false
	_zoom = clampf(_effective_zoom() + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
	_refresh_image_size()


func _effective_zoom() -> float:
	if not _fit_to_window or _texture == null:
		return _zoom
	var texture_size := _texture.get_size()
	var available := Vector2(maxf(image_scroll.size.x - 48.0, 1.0), maxf(image_scroll.size.y - 48.0, 1.0))
	return minf(available.x / texture_size.x, available.y / texture_size.y)


func _refresh_image_size() -> void:
	if _texture == null or not is_instance_valid(image_scroll):
		_refresh_controls()
		return
	var scale := clampf(_effective_zoom(), MIN_ZOOM, MAX_ZOOM)
	if _fit_to_window:
		_zoom = scale
	var display_size := _texture.get_size() * scale
	image_texture.custom_minimum_size = display_size
	image_center.custom_minimum_size = Vector2(
		maxf(display_size.x, image_scroll.size.x - 6.0),
		maxf(display_size.y, image_scroll.size.y - 6.0)
	)
	_refresh_controls()


func _refresh_controls() -> void:
	var has_image := _texture != null
	fit_button.disabled = not has_image
	actual_size_button.disabled = not has_image
	zoom_out_button.disabled = not has_image
	zoom_in_button.disabled = not has_image
	if has_image:
		status_label.text = "%d × %d  ·  %d%%" % [
			_texture.get_width(),
			_texture.get_height(),
			roundi(_effective_zoom() * 100.0),
		]


func _apply_styles() -> void:
	var toolbar_style := StyleBoxFlat.new()
	toolbar_style.bg_color = Color("#F8FAFD")
	toolbar_style.border_width_bottom = 2
	toolbar_style.border_color = Color("#D7E0EC")
	%Toolbar.add_theme_stylebox_override("panel", toolbar_style)

	var canvas_style := StyleBoxFlat.new()
	canvas_style.bg_color = Color("#202738")
	canvas_style.corner_radius_top_left = 18
	canvas_style.corner_radius_top_right = 18
	canvas_style.corner_radius_bottom_left = 18
	canvas_style.corner_radius_bottom_right = 18
	%CanvasPanel.add_theme_stylebox_override("panel", canvas_style)

	for button: Button in [fit_button, actual_size_button, zoom_out_button, zoom_in_button]:
		button.add_theme_font_size_override("font_size", 24)
		button.add_theme_color_override("font_color", Color("#33405A"))
		button.add_theme_stylebox_override("normal", _button_style(Color("#FFFFFF"), Color("#CCD7E6")))
		button.add_theme_stylebox_override("hover", _button_style(Color("#EDF5FF"), Color("#82AEE8")))
		button.add_theme_stylebox_override("pressed", _button_style(Color("#DDEBFF"), Color("#6795D2")))
		button.add_theme_stylebox_override("disabled", _button_style(Color("#EEF1F5"), Color("#DCE2EA")))


func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = border
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
