class_name PseudoCursor extends Control
## 代码绘制的桌面虚拟光标。

signal clicked(position: Vector2)

# ==================== 配色 ====================
@export_group("Colors")
## 光标本体（干净白色）
@export var color_body: Color = Color.WHITE
## 描边（柔和深色，不要纯黑）
@export var color_border: Color = Color("3a3d4a")
## 点击反馈色
@export var color_accent: Color = Color("4a7cff")
## 投影色
@export var color_shadow: Color = Color(0.0, 0.0, 0.0, 0.12)

@export_group("Size")
## 光标高度（px，4K 视口）
@export var cursor_height: float = 56.0
## 描边粗细
@export var border_width: float = 3.2

@export_group("Feel")
## 跟随灵敏度（越高越跟手）
@export var follow_speed: float = 50.0
## 点击缩放
@export var click_scale: float = 0.88

# ==================== 内部 ====================
var _current_scale: float = 1.0
var _target_scale: float = 1.0
var _current_color: Color
var _target_color: Color

# 预计算的几何数据
var _arrow_points: PackedVector2Array
var _border_points: PackedVector2Array
var _shadow_points: PackedVector2Array


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	z_index = 4096
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_TOP_LEFT)
	size = Vector2.ZERO

	_current_color = color_body
	_target_color = color_body
	_rebuild_geometry()
	global_position = get_global_mouse_position()


func _rebuild_geometry() -> void:
	var h: float = cursor_height
	# 经典 Windows 箭头：尖端在左上 (0,0)
	#   左边缘直下 → 缺口内折 → 尾巴向右下 → 尾巴右侧 → 回到缺口外侧 → 右翼
	var raw: Array[Vector2] = [
		Vector2(0.0,   0.0),    # 0  尖端
		Vector2(0.0,   0.74),   # 1  左下
		Vector2(0.22,  0.58),   # 2  缺口内 (notch)
		Vector2(0.36,  0.88),   # 3  尾巴左下
		Vector2(0.48,  0.82),   # 4  尾巴右下
		Vector2(0.32,  0.52),   # 5  缺口外
		Vector2(0.52,  0.52),   # 6  右翼
	]
	# 缩放到实际像素
	_arrow_points = PackedVector2Array()
	for p in raw:
		_arrow_points.append(p * h)

	# 描边：沿法线向外扩展
	_border_points = _offset_polygon(_arrow_points, border_width)

	# 投影：整体偏移 + 稍微放大
	_shadow_points = _offset_polygon(_arrow_points, border_width + 3.0)


func _offset_polygon(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	## 对多边形做简单的向外偏移（基于重心扩张）
	var center := Vector2.ZERO
	for p in poly:
		center += p
	center /= float(poly.size())

	var result: PackedVector2Array = PackedVector2Array()
	for p in poly:
		var dir: Vector2 = (p - center).normalized()
		result.append(p + dir * amount)
	return result


func _process(delta: float) -> void:
	var follow_weight: float = clampf(follow_speed * delta, 0.0, 1.0)
	global_position = global_position.lerp(get_global_mouse_position(), follow_weight)

	# 平滑插值缩放和颜色
	_current_scale = lerpf(_current_scale, _target_scale, clampf(18.0 * delta, 0.0, 1.0))
	_current_color = _current_color.lerp(_target_color, clampf(14.0 * delta, 0.0, 1.0))

	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_target_scale = click_scale
				_target_color = color_accent
				var audio_manager: Node = get_node_or_null("/root/AudioManager")
				if audio_manager != null and audio_manager.has_method("play_sfx_key"):
					audio_manager.play_sfx_key("ui_click")
				clicked.emit(global_position)
			else:
				_target_scale = 1.0
				_target_color = color_body


func _draw() -> void:
	var sc: float = _current_scale
	var sm := Transform2D().scaled(Vector2(sc, sc))

	# 1. 投影（偏移 3px，半透明）
	var shadow_offset := Transform2D(0.0, Vector2(3.0, 4.0)) * sm
	draw_set_transform_matrix(shadow_offset)
	draw_colored_polygon(_shadow_points, color_shadow)

	# 2. 描边（柔和深色轮廓）
	draw_set_transform_matrix(sm)
	draw_colored_polygon(_border_points, color_border)

	# 3. 本体（白色，点击时渐变为粉色）
	draw_colored_polygon(_arrow_points, _current_color)

	draw_set_transform_matrix(Transform2D.IDENTITY)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		visible = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER:
		visible = true


func restore_system_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
