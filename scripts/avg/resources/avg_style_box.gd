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


## 生成 Godot StyleBox（normal 状态）
func to_stylebox() -> StyleBox:
	if texture != null:
		return _create_texture_stylebox()
	else:
		return _create_flat_stylebox()


## 生成 hover 状态样式（基于 normal 变亮）
func to_hover_stylebox() -> StyleBox:
	if texture != null:
		var sb := _create_texture_stylebox()
		sb.modulate_color = texture_modulate.lightened(0.15)
		return sb
	else:
		var sb := _create_flat_stylebox()
		sb.bg_color = bg_color.lightened(0.15)
		if border_width > 0:
			sb.border_color = border_color.lightened(0.15)
		return sb


## 生成 pressed 状态样式（基于 normal 变暗）
func to_pressed_stylebox() -> StyleBox:
	if texture != null:
		var sb := _create_texture_stylebox()
		sb.modulate_color = texture_modulate.darkened(0.15)
		return sb
	else:
		var sb := _create_flat_stylebox()
		sb.bg_color = bg_color.darkened(0.15)
		if border_width > 0:
			sb.border_color = border_color.darkened(0.15)
		return sb


## 生成 disabled 状态样式（基于 normal 变灰/去饱和）
func to_disabled_stylebox() -> StyleBox:
	if texture != null:
		var sb := _create_texture_stylebox()
		var c := texture_modulate
		var grey := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
		sb.modulate_color = Color(
			lerpf(c.r, grey, 0.6),
			lerpf(c.g, grey, 0.6),
			lerpf(c.b, grey, 0.6),
			c.a * 0.6
		)
		return sb
	else:
		var sb := _create_flat_stylebox()
		var c := bg_color
		var grey := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
		sb.bg_color = Color(
			lerpf(c.r, grey, 0.6),
			lerpf(c.g, grey, 0.6),
			lerpf(c.b, grey, 0.6),
			c.a * 0.6
		)
		if border_width > 0:
			var bc := border_color
			var bg := bc.r * 0.3 + bc.g * 0.59 + bc.b * 0.11
			sb.border_color = Color(
				lerpf(bc.r, bg, 0.6),
				lerpf(bc.g, bg, 0.6),
				lerpf(bc.b, bg, 0.6),
				bc.a * 0.6
			)
		return sb


## 将全部 4 个状态（normal / hover / pressed / disabled）应用到按钮
func apply_to_button(button: BaseButton) -> void:
	button.add_theme_stylebox_override("normal", to_stylebox())
	button.add_theme_stylebox_override("hover", to_hover_stylebox())
	button.add_theme_stylebox_override("pressed", to_pressed_stylebox())
	button.add_theme_stylebox_override("disabled", to_disabled_stylebox())


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
