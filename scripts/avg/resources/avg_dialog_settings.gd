class_name AVGDialogSettings extends Resource
## AVG Dialog Settings Resource
## 对话框全局默认样式配置，包含对话框和名字框的样式、位置、字体等设置。

## 对话框默认位置: 0=bottom, 1=center, 2=top
@export var default_position: int = 0
## 默认打字速度（字/秒）
@export var default_text_speed: float = 30.0

## 对话框归一化尺寸（相对于项目分辨率）
@export var box_norm_size: Vector2 = Vector2(0.83, 0.28)
## 对话框距边缘间距（像素，基于项目分辨率）
@export var box_margin: int = 40
## 对话框背景样式
@export var box_style: Resource  # AVGStyleBox
## 文本内边距 (left, top, right, bottom)
@export var text_padding: Vector4i = Vector4i(20, 15, 20, 15)

## 正文字号
@export var text_font_size: int = 24
## 正文颜色
@export var text_color: Color = Color.WHITE
@export var text_outline_size: int = 2
@export var text_outline_color: Color = Color(0, 0, 0, 0.85)
@export var cursor_texture: Texture2D
@export var cursor_norm_size: Vector2 = Vector2(0.026, 0.022)
@export var cursor_norm_offset: Vector2 = Vector2(-0.045, -0.08)

## 名字框背景样式（null 时跟随 box_style）
@export var name_box_style: Resource  # AVGStyleBox
## 名字框相对于对话框左上角的归一化偏移
@export var name_norm_offset: Vector2 = Vector2(0.02, -0.06)
## 名字框归一化尺寸
@export var name_norm_size: Vector2 = Vector2(0.15, 0.05)
## 名字框内边距
@export var name_padding: Vector4i = Vector4i(10, 5, 10, 5)
## 名字字号
@export var name_font_size: int = 28
## 名字颜色
@export var name_color: Color = Color.WHITE
@export var name_outline_size: int = 2
@export var name_outline_color: Color = Color(0, 0, 0, 0.85)

## 选项按钮样式
@export var choice_style: Resource  # AVGStyleBox
## 选项按钮归一化最小尺寸
@export var choice_min_norm_size: Vector2 = Vector2(0.2, 0.05)
## 选项按钮字号
@export var choice_font_size: int = 22
## 选项按钮字色
@export var choice_font_color: Color = Color.WHITE
## 选项按钮间距（像素，基于项目分辨率）
@export var choice_spacing: int = 10

## 默认表情切换方式: 0=crossfade, 1=instant, 2=fade_through_black
@export var default_expression_transition: int = 0
## 默认表情切换时长（秒）
@export var default_expression_duration: float = 0.2


## 获取有效的对话框样式（确保不为 null）
func get_box_stylebox() -> StyleBox:
	if box_style != null and box_style.has_method("to_stylebox"):
		return box_style.to_stylebox()
	# 默认样式
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	sb.set_corner_radius_all(8)
	return sb


## 获取有效的名字框样式（null 时跟随对话框样式）
func get_name_stylebox() -> StyleBox:
	if name_box_style != null and name_box_style.has_method("to_stylebox"):
		return name_box_style.to_stylebox()
	return get_box_stylebox()


## 获取有效的选项按钮样式
func get_choice_stylebox() -> StyleBox:
	if choice_style != null and choice_style.has_method("to_stylebox"):
		return choice_style.to_stylebox()
	if box_style != null and box_style.has_method("to_stylebox"):
		return box_style.to_stylebox()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## 属性定义（供 PropertyEditor 使用）
static func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "default_position", "type": TYPE_INT, "editable": true, "category": "基本",
		 "hint": "choices", "options": ["bottom", "center", "top"]},
		{"name": "default_text_speed", "type": TYPE_FLOAT, "editable": true, "category": "基本"},
		{"name": "box_norm_size", "type": TYPE_VECTOR2, "editable": true, "category": "对话框"},
		{"name": "box_margin", "type": TYPE_INT, "editable": true, "category": "对话框"},
		{"name": "box_style", "type": "sub_resource", "editable": true, "category": "对话框",
		 "resource_script": "res://scripts/avg/resources/avg_style_box.gd"},
		{"name": "text_padding", "type": TYPE_VECTOR4I, "editable": true, "category": "对话框"},
		{"name": "text_font_size", "type": TYPE_INT, "editable": true, "category": "文本"},
		{"name": "text_color", "type": TYPE_COLOR, "editable": true, "category": "文本"},
		{"name": "text_outline_size", "type": TYPE_INT, "editable": true, "category": "文本"},
		{"name": "text_outline_color", "type": TYPE_COLOR, "editable": true, "category": "文本"},
		{"name": "cursor_texture", "type": TYPE_OBJECT, "class_hint": "Texture2D", "editable": true, "category": "文本"},
		{"name": "cursor_norm_size", "type": TYPE_VECTOR2, "editable": true, "category": "文本"},
		{"name": "cursor_norm_offset", "type": TYPE_VECTOR2, "editable": true, "category": "文本"},
		{"name": "name_norm_offset", "type": TYPE_VECTOR2, "editable": true, "category": "名字框"},
		{"name": "name_norm_size", "type": TYPE_VECTOR2, "editable": true, "category": "名字框"},
		{"name": "name_box_style", "type": "sub_resource", "editable": true, "category": "名字框",
		 "resource_script": "res://scripts/avg/resources/avg_style_box.gd"},
		{"name": "name_padding", "type": TYPE_VECTOR4I, "editable": true, "category": "名字框"},
		{"name": "name_font_size", "type": TYPE_INT, "editable": true, "category": "名字框"},
		{"name": "name_color", "type": TYPE_COLOR, "editable": true, "category": "名字框"},
		{"name": "name_outline_size", "type": TYPE_INT, "editable": true, "category": "名字框"},
		{"name": "name_outline_color", "type": TYPE_COLOR, "editable": true, "category": "名字框"},
		{"name": "choice_style", "type": "sub_resource", "editable": true, "category": "选项",
		 "resource_script": "res://scripts/avg/resources/avg_style_box.gd"},
		{"name": "choice_min_norm_size", "type": TYPE_VECTOR2, "editable": true, "category": "选项"},
		{"name": "choice_font_size", "type": TYPE_INT, "editable": true, "category": "选项"},
		{"name": "choice_font_color", "type": TYPE_COLOR, "editable": true, "category": "选项"},
		{"name": "choice_spacing", "type": TYPE_INT, "editable": true, "category": "选项"},
		{"name": "default_expression_transition", "type": TYPE_INT, "editable": true, "category": "角色",
		 "hint": "choices", "options": ["crossfade", "instant", "fade_through_black"]},
		{"name": "default_expression_duration", "type": TYPE_FLOAT, "editable": true, "category": "角色"},
	]
