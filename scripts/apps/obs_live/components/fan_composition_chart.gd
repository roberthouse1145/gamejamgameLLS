extends Control
## 直播结算中的粉丝构成圆饼图。图例与精确百分比由结算界面直接展示。

const CIRCLE_STEPS: int = 120
const EMPTY_COLOR: Color = Color("#EAF1FA")
const OUTLINE_COLOR: Color = Color("#AFC5E2")

var _segments: Array[Dictionary] = []


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


func set_segments(segments: Array[Dictionary]) -> void:
	_segments.clear()
	for segment: Dictionary in segments:
		_segments.append(segment.duplicate(true))
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = maxf(minf(size.x, size.y) * 0.5 - 6.0, 0.0)
	if radius <= 0.0:
		return

	var total: float = 0.0
	for segment: Dictionary in _segments:
		total += maxf(float(segment.get("value", 0.0)), 0.0)
	if total <= 0.0:
		draw_circle(center, radius, EMPTY_COLOR)
		draw_arc(center, radius, 0.0, TAU, CIRCLE_STEPS, OUTLINE_COLOR, 2.0, true)
		return

	var start_angle: float = -PI * 0.5
	for segment: Dictionary in _segments:
		var value: float = maxf(float(segment.get("value", 0.0)), 0.0)
		if value <= 0.0:
			continue
		var ratio: float = value / total
		var angle_span: float = TAU * ratio
		var step_count: int = maxi(int(ceil(float(CIRCLE_STEPS) * ratio)), 2)
		var polygon := PackedVector2Array([center])
		for step: int in range(step_count + 1):
			var angle: float = start_angle + angle_span * float(step) / float(step_count)
			polygon.append(center + Vector2(cos(angle), sin(angle)) * radius)
		var segment_color: Color = segment.get("color", EMPTY_COLOR)
		draw_colored_polygon(polygon, segment_color)
		start_angle += angle_span
	draw_arc(center, radius, 0.0, TAU, CIRCLE_STEPS, OUTLINE_COLOR, 2.0, true)
