@tool
class_name CardMoodEdges extends Control
## 卡牌唯一外轮廓：四种情绪分别占据四条纵向接口轨道。

const BODY_COLOR: Color = Color("#F9FCFF")
const BODY_LOCKED_COLOR: Color = Color("#EDF2F8")
const OUTLINE_COLOR: Color = Color("#20283A")
const HOVER_OUTLINE_COLOR: Color = Color("#6B9FEA")
const SELECTED_OUTLINE_COLOR: Color = Color("#E5486D")
const LOCKED_OUTLINE_COLOR: Color = Color("#8793A5")
const PATTERN_COLOR: Color = Color(0.72, 0.82, 0.93, 0.28)
const MOOD_COLORS: Dictionary = {
	BehaviorCardResource.MOOD_HOT: Color("#EE5A78"),
	BehaviorCardResource.MOOD_CALM: Color("#5F86D9"),
	BehaviorCardResource.MOOD_WARM: Color("#DDB84F"),
	BehaviorCardResource.MOOD_GLOOM: Color("#9169C9"),
}
const MOOD_LANES: Dictionary = {
	BehaviorCardResource.MOOD_HOT: 0,
	BehaviorCardResource.MOOD_CALM: 1,
	BehaviorCardResource.MOOD_WARM: 2,
	BehaviorCardResource.MOOD_GLOOM: 3,
}
const LANE_COUNT: int = 4

var mood_inputs: Array[StringName] = []
var mood_outputs: Array[StringName] = []
var show_connectors: bool = true
var selected: bool = false
var hovered: bool = false
var locked: bool = false


func configure(input_moods: Array[StringName], output_moods: Array[StringName], enabled: bool = true) -> void:
	mood_inputs.assign(input_moods)
	mood_outputs.assign(output_moods)
	show_connectors = enabled
	queue_redraw()


func set_interaction_state(is_selected: bool, is_hovered: bool, is_locked: bool) -> void:
	selected = is_selected
	hovered = is_hovered
	locked = is_locked
	queue_redraw()


func has_input_notches() -> bool:
	return show_connectors and not mood_inputs.is_empty()


func has_output_tabs() -> bool:
	return show_connectors and not mood_outputs.is_empty()


func get_input_lanes() -> Array[int]:
	return _get_lanes(mood_inputs)


func get_output_lanes() -> Array[int]:
	return _get_lanes(mood_outputs)


func get_lane_y(mood: StringName) -> float:
	var lane: int = _get_lane(mood)
	if lane < 0:
		return -1.0
	return size.y * (float(lane) + 0.5) / float(LANE_COUNT)


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
	if has_output_tabs():
		for mood: StringName in _ordered_moods(mood_outputs):
			var output_y: float = get_lane_y(mood)
			points.append(Vector2(right, output_y - connector_radius))
			points.append_array(_arc_points(Vector2(right, output_y), connector_radius, -PI * 0.5, PI * 0.5, 12))
	points.append(Vector2(right, bottom - corner_radius))
	points.append_array(_arc_points(Vector2(right - corner_radius, bottom - corner_radius), corner_radius, 0.0, PI * 0.5, 6))
	points.append(Vector2(left + corner_radius, bottom))
	points.append_array(_arc_points(Vector2(left + corner_radius, bottom - corner_radius), corner_radius, PI * 0.5, PI, 6))
	if has_input_notches():
		var ordered_inputs: Array[StringName] = _ordered_moods(mood_inputs)
		ordered_inputs.reverse()
		for mood: StringName in ordered_inputs:
			var input_y: float = get_lane_y(mood)
			points.append(Vector2(left, input_y + connector_radius))
			points.append_array(_arc_points(Vector2(left, input_y), connector_radius, PI * 0.5, -PI * 0.5, 12))
	points.append(Vector2(left, top + corner_radius))

	draw_colored_polygon(points, BODY_LOCKED_COLOR if locked else BODY_COLOR)
	_draw_inner_pattern(left, right, top, bottom)
	if has_output_tabs():
		for mood: StringName in mood_outputs:
			draw_circle(Vector2(right, get_lane_y(mood)), connector_radius - 5.0, _mood_color(mood))
	if has_input_notches():
		for mood: StringName in mood_inputs:
			draw_arc(Vector2(left, get_lane_y(mood)), connector_radius - 3.0, -PI * 0.5, PI * 0.5, 24, _mood_color(mood), 12.0, true)

	var closed_outline: PackedVector2Array = points.duplicate()
	closed_outline.append(points[0])
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


func _get_lane(mood: StringName) -> int:
	return int(MOOD_LANES.get(mood, -1))


func _get_lanes(moods: Array[StringName]) -> Array[int]:
	var result: Array[int] = []
	for mood: StringName in _ordered_moods(moods):
		result.append(_get_lane(mood))
	return result


func _ordered_moods(moods: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for lane: int in range(LANE_COUNT):
		for mood: StringName in moods:
			if _get_lane(mood) == lane:
				result.append(mood)
	return result


func _arc_points(center: Vector2, radius: float, from_angle: float, to_angle: float, steps: int) -> PackedVector2Array:
	var result: PackedVector2Array = []
	for index: int in range(steps + 1):
		var weight: float = float(index) / float(steps)
		var angle: float = lerpf(from_angle, to_angle, weight)
		result.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return result


func _mood_color(mood: StringName) -> Color:
	return MOOD_COLORS.get(mood, Color("#AEB8C8"))
