@tool
class_name CardSlotEdges extends Control
## 卡牌唯一外轮廓：只在激活的 1~4 号位置绘制接口，并显示逐槽连接状态。

const BODY_COLOR: Color = Color("#F9FCFF")
const BODY_LOCKED_COLOR: Color = Color("#EDF2F8")
const OUTLINE_COLOR: Color = Color("#20283A")
const HOVER_OUTLINE_COLOR: Color = Color("#6B9FEA")
const SELECTED_OUTLINE_COLOR: Color = Color("#7568CB")
const LOCKED_OUTLINE_COLOR: Color = Color("#8793A5")
const PATTERN_COLOR: Color = Color(0.72, 0.82, 0.93, 0.28)
const DISCONNECTED_COLOR: Color = Color("#E65B72")
const CONNECTED_COLOR: Color = Color("#42BFA0")
const SLOT_COUNT: int = 4

var left_slots: Array[int] = []
var right_slots: Array[int] = []
var connected_left_slots: Array[int] = []
var connected_right_slots: Array[int] = []
var show_connection_state: bool = false
var show_connectors: bool = true
var selected: bool = false
var hovered: bool = false
var locked: bool = false
var glow_strength: float = 0.0


func set_glow_strength(strength: float) -> void:
	glow_strength = clampf(strength, 0.0, 1.0)
	queue_redraw()


func configure(input_slots: Array[int], output_slots: Array[int], enabled: bool = true) -> void:
	left_slots.assign(input_slots)
	right_slots.assign(output_slots)
	connected_left_slots.clear()
	connected_right_slots.clear()
	show_connection_state = false
	show_connectors = enabled
	queue_redraw()


func set_connected_slots(left_connected: Array[int], right_connected: Array[int]) -> void:
	connected_left_slots.assign(left_connected)
	connected_right_slots.assign(right_connected)
	show_connection_state = true
	queue_redraw()


func set_interaction_state(is_selected: bool, is_hovered: bool, is_locked: bool) -> void:
	selected = is_selected
	hovered = is_hovered
	locked = is_locked
	queue_redraw()


func has_left_notches() -> bool:
	return show_connectors and not left_slots.is_empty()


func has_right_tabs() -> bool:
	return show_connectors and not right_slots.is_empty()


func get_slot_y(slot: int) -> float:
	if slot < BehaviorCardResource.SLOT_MIN or slot > BehaviorCardResource.SLOT_MAX:
		return -1.0
	return size.y * (float(slot) - 0.5) / float(SLOT_COUNT)


func is_left_slot_connected(slot: int) -> bool:
	return slot in connected_left_slots


func is_right_slot_connected(slot: int) -> bool:
	return slot in connected_right_slots


func is_connection_state_visible() -> bool:
	return show_connection_state


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var left: float = 34.0
	var right: float = size.x - 34.0
	var top: float = 8.0
	var bottom: float = size.y - 8.0
	var corner_radius: float = 28.0
	var connector_radius: float = 29.0
	var points: PackedVector2Array = []

	points.append_array(_arc_points(Vector2(left + corner_radius, top + corner_radius), corner_radius, PI, PI * 1.5, 6))
	points.append(Vector2(right - corner_radius, top))
	points.append_array(_arc_points(Vector2(right - corner_radius, top + corner_radius), corner_radius, PI * 1.5, TAU, 6))
	if has_right_tabs():
		for slot: int in _ordered_slots(right_slots):
			var output_y: float = get_slot_y(slot)
			points.append(Vector2(right, output_y - connector_radius))
			points.append_array(_arc_points(Vector2(right, output_y), connector_radius, -PI * 0.5, PI * 0.5, 12))
	points.append(Vector2(right, bottom - corner_radius))
	points.append_array(_arc_points(Vector2(right - corner_radius, bottom - corner_radius), corner_radius, 0.0, PI * 0.5, 6))
	points.append(Vector2(left + corner_radius, bottom))
	points.append_array(_arc_points(Vector2(left + corner_radius, bottom - corner_radius), corner_radius, PI * 0.5, PI, 6))
	if has_left_notches():
		var ordered_inputs: Array[int] = _ordered_slots(left_slots)
		ordered_inputs.reverse()
		for slot: int in ordered_inputs:
			var input_y: float = get_slot_y(slot)
			points.append(Vector2(left, input_y + connector_radius))
			points.append_array(_arc_points(Vector2(left, input_y), connector_radius, PI * 0.5, -PI * 0.5, 12))
	points.append(Vector2(left, top + corner_radius))

	draw_colored_polygon(points, BODY_LOCKED_COLOR if locked else BODY_COLOR)
	_draw_inner_pattern(left, right, top, bottom)
	if show_connection_state and has_right_tabs():
		for slot: int in right_slots:
			draw_circle(
				Vector2(right, get_slot_y(slot)),
				connector_radius - 5.0,
				_get_connection_color(is_right_slot_connected(slot))
			)
	if show_connection_state and has_left_notches():
		for slot: int in left_slots:
			draw_arc(
				Vector2(left, get_slot_y(slot)),
				connector_radius - 3.0,
				-PI * 0.5,
				PI * 0.5,
				24,
				_get_connection_color(is_left_slot_connected(slot)),
				12.0,
				true
			)

	var closed_outline: PackedVector2Array = points.duplicate()
	closed_outline.append(points[0])
	if glow_strength > 0.02:
		var glow_color := Color(HOVER_OUTLINE_COLOR, 0.22 + glow_strength * 0.45)
		draw_polyline(closed_outline, glow_color, _get_outline_width() + 10.0 + glow_strength * 8.0, true)
	draw_polyline(closed_outline, _get_outline_color(), _get_outline_width(), true)


func _draw_inner_pattern(left: float, right: float, top: float, bottom: float) -> void:
	var pattern_left: float = left + 20.0
	var pattern_right: float = right - 20.0
	var pattern_top: float = top + 20.0
	var pattern_bottom: float = bottom - 20.0
	var cell_size: float = 48.0
	var x: float = pattern_left
	while x <= pattern_right:
		draw_line(Vector2(x, pattern_top), Vector2(x, pattern_bottom), PATTERN_COLOR, 1.0)
		x += cell_size
	var y: float = pattern_top
	while y <= pattern_bottom:
		draw_line(Vector2(pattern_left, y), Vector2(pattern_right, y), PATTERN_COLOR, 1.0)
		y += cell_size


func _get_outline_color() -> Color:
	if locked:
		return LOCKED_OUTLINE_COLOR
	if selected:
		return SELECTED_OUTLINE_COLOR
	if hovered:
		return HOVER_OUTLINE_COLOR
	return OUTLINE_COLOR


func _get_outline_width() -> float:
	if selected:
		return 7.0
	if hovered:
		return 5.0
	return 4.0


func _ordered_slots(slots: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for slot: int in range(BehaviorCardResource.SLOT_MIN, BehaviorCardResource.SLOT_MAX + 1):
		if slot in slots:
			result.append(slot)
	return result


func _arc_points(center: Vector2, radius: float, from_angle: float, to_angle: float, steps: int) -> PackedVector2Array:
	var result: PackedVector2Array = []
	for index: int in range(steps + 1):
		var weight: float = float(index) / float(steps)
		var angle: float = lerpf(from_angle, to_angle, weight)
		result.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return result


func _get_connection_color(is_connected: bool) -> Color:
	return CONNECTED_COLOR if is_connected else DISCONNECTED_COLOR
