class_name RoundedAvatar extends Control
## 统一头像组件：对任意纹理应用圆角裁切与黑色描边。

@export var texture: Texture2D = null:
	set(value):
		texture = value
		_apply_content()
@export var fallback_text: String = "?":
	set(value):
		fallback_text = value
		_apply_content()
@export_range(0.0, 0.5, 0.01) var corner_radius: float = 0.5:
	set(value):
		corner_radius = value
		_apply_shader_parameters()
@export_range(0.0, 0.2, 0.005) var outline_width: float = 0.035:
	set(value):
		outline_width = value
		_apply_shader_parameters()
@export var outline_color: Color = Color("#0A0A0D"):
	set(value):
		outline_color = value
		_apply_shader_parameters()

@onready var texture_rect: TextureRect = %TextureRect
@onready var fallback_label: Label = %FallbackLabel

var _fallback_texture: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if texture_rect.material != null:
		texture_rect.material = texture_rect.material.duplicate()
	_apply_shader_parameters()
	_apply_content()


func set_avatar(value: Texture2D, display_name: String = "?") -> void:
	texture = value
	fallback_text = display_name.substr(0, 1) if not display_name.is_empty() else "?"
	_apply_content()


func _apply_content() -> void:
	if not is_node_ready():
		return
	var has_texture: bool = texture != null
	texture_rect.texture = texture if has_texture else _get_fallback_texture()
	fallback_label.visible = not has_texture
	fallback_label.text = fallback_text


func _apply_shader_parameters() -> void:
	if not is_node_ready() or texture_rect.material == null:
		return
	var shader_material := texture_rect.material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter("corner_radius", corner_radius)
	shader_material.set_shader_parameter("outline_width", outline_width)
	shader_material.set_shader_parameter("outline_color", outline_color)


func _get_fallback_texture() -> Texture2D:
	if _fallback_texture != null:
		return _fallback_texture
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color("#7C8798"))
	_fallback_texture = ImageTexture.create_from_image(image)
	return _fallback_texture
