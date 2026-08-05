class_name CardMoodEdges extends Control
## 按 Resource 的情绪槽绘制真实拼图轮廓：左凹为入口，右凸为出口。

const BODY_COLOR: Color = Color("#F9FCFF")
const OUTLINE_COLOR: Color = Color("#20283A")
const MOOD_COLORS: Dictionary = {
	BehaviorCardResource.MOOD_HOT: Color("#EE5A78"),
	BehaviorCardResource.MOOD_CALM: Color("#5F86D9"),
	BehaviorCardResource.MOOD_WARM: Color("#DDB84F"),
	BehaviorCardResource.MOOD_GLOOM: Color("#9169C9"),
}

var mood_in: StringName = BehaviorCardResource.MOOD_OPEN
var mood_out: StringName = BehaviorCardResource.MOOD_OPEN
var show_connectors: bool = true


func configure(input_mood: StringName, output_mood: StringName, enabled: bool = true) -> void:
	mood_in = input_mood
	mood_out = output_mood
	show_connectors = enabled
	queue_redraw()


func has_input_notch() -> bool:
	return show_connectors and mood_in != BehaviorCardResource.MOOD_OPEN


func has_output_tab() -> bool:
	return show_connectors and mood_out != BehaviorCardResource.MOOD_OPEN


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var left: float = 34.0
	var right: float = size.x - 34.0
	var top: float = 8.0
	var bottom: float = size.y - 8.0
	var center_y: float = size.y * 0.5
	var radius: float = 31.0
	var points: PackedVector2Array = []
	points.append_array(_arc_points(Vector2(left + 28.0, top + 28.0), 28.0, PI, PI * 1.5, 6))
	points.append(Vector2(right - 28.0, top))
	points.append_array(_arc_points(Vector2(right - 28.0, top + 28.0), 28.0, PI * 1.5, TAU, 6))
	if show_connectors and mood_out != BehaviorCardResource.MOOD_OPEN:
		points.append(Vector2(right, center_y - radius))
		points.append_array(_arc_points(Vector2(right, center_y), radius, -PI * 0.5, PI * 0.5, 12))
	points.append(Vector2(right, bottom - 28.0))
	points.append_array(_arc_points(Vector2(right - 28.0, bottom - 28.0), 28.0, 0.0, PI * 0.5, 6))
	points.append(Vector2(left + 28.0, bottom))
	points.append_array(_arc_points(Vector2(left + 28.0, bottom - 28.0), 28.0, PI * 0.5, PI, 6))
	if show_connectors and mood_in != BehaviorCardResource.MOOD_OPEN:
		points.append(Vector2(left, center_y + radius))
		points.append_array(_arc_points(Vector2(left, center_y), radius, PI * 0.5, -PI * 0.5, 12))
	points.append(Vector2(left, top + 28.0))
	draw_colored_polygon(points, BODY_COLOR)
	if show_connectors and mood_out != BehaviorCardResource.MOOD_OPEN:
		draw_circle(Vector2(right, center_y), radius - 4.0, _mood_color(mood_out))
	if show_connectors and mood_in != BehaviorCardResource.MOOD_OPEN:
		draw_arc(Vector2(left, center_y), radius - 3.0, -PI * 0.5, PI * 0.5, 24, _mood_color(mood_in), 13.0, true)
	var closed_outline: PackedVector2Array = points.duplicate()
	closed_outline.append(points[0])
	draw_polyline(closed_outline, OUTLINE_COLOR, 5.0, true)


func _arc_points(center: Vector2, radius: float, from_angle: float, to_angle: float, steps: int) -> PackedVector2Array:
	var result: PackedVector2Array = []
	for index: int in range(steps + 1):
		var weight: float = float(index) / float(steps)
		var angle: float = lerpf(from_angle, to_angle, weight)
		result.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return result


func _mood_color(mood: StringName) -> Color:
	return MOOD_COLORS.get(mood, Color("#AEB8C8"))
