class_name AVGStyleBox extends Resource
## AVG Style Box Resource
## 统一的样式盒资源，可根据配置生成 Godot StyleBox。
## 有 texture 时生成 StyleBoxTexture（九宫格），否则生成 StyleBoxFlat（纯色）。

## 九宫格图片（优先级高，有值时使用图片样式）
@export var texture: Texture2D
## 九宫格边距 (left, top, right, bottom)
@export var texture_margins: Vector4i = Vector4i(16, 16, 16, 16)
## 图片调色
@export var texture_modulate: Color = Color.WHITE

## 背景颜色（无 texture 时使用）
@export var bg_color: Color = Color(0.0, 0.0, 0.0, 0.8)
## 圆角半径
@export var corner_radius: int = 8
## 边框宽度
@export var border_width: int = 0
## 边框颜色
@export var border_color: Color = Color.WHITE
## 内容边距 (left, top, right, bottom)
@export var content_margins: Vector4i = Vector4i(0, 0, 0, 0)


## 生成 Godot StyleBox
func to_stylebox() -> StyleBox:
	if texture != null:
		return _create_texture_stylebox()
	else:
		return _create_flat_stylebox()


## 生成 StyleBoxTexture（九宫格）
func _create_texture_stylebox() -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture
	sb.texture_margin_left = texture_margins.x
	sb.texture_margin_top = texture_margins.y
	sb.texture_margin_right = texture_margins.z
	sb.texture_margin_bottom = texture_margins.w
	sb.modulate_color = texture_modulate
	if content_margins != Vector4i.ZERO:
		sb.content_margin_left = content_margins.x
		sb.content_margin_top = content_margins.y
		sb.content_margin_right = content_margins.z
		sb.content_margin_bottom = content_margins.w
	return sb


## 生成 StyleBoxFlat（纯色）
func _create_flat_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_corner_radius_all(corner_radius)
	sb.border_width_left = border_width
	sb.border_width_top = border_width
	sb.border_width_right = border_width
	sb.border_width_bottom = border_width
	sb.border_color = border_color
	if content_margins != Vector4i.ZERO:
		sb.content_margin_left = content_margins.x
		sb.content_margin_top = content_margins.y
		sb.content_margin_right = content_margins.z
		sb.content_margin_bottom = content_margins.w
	return sb


## 属性定义（供 PropertyEditor 使用）
static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "texture", "type": TYPE_OBJECT, "editable": true, "category": "图片样式"},
		{"name": "texture_margins", "type": TYPE_VECTOR4I, "editable": true, "category": "图片样式"},
		{"name": "texture_modulate", "type": TYPE_COLOR, "editable": true, "category": "图片样式"},
		{"name": "bg_color", "type": TYPE_COLOR, "editable": true, "category": "纯色样式"},
		{"name": "corner_radius", "type": TYPE_INT, "editable": true, "category": "纯色样式"},
		{"name": "border_width", "type": TYPE_INT, "editable": true, "category": "纯色样式"},
		{"name": "border_color", "type": TYPE_COLOR, "editable": true, "category": "纯色样式"},
		{"name": "content_margins", "type": TYPE_VECTOR4I, "editable": true, "category": "通用"},
	]
