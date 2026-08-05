class_name StreamerAbilityRadar extends Control
## 主播五维能力图；精确数值同时由旁侧文本呈现。

const ABILITY_LABELS: PackedStringArray = ["游戏力", "杂谈力", "歌唱力", "演出力", "杂项力"]
const GRID_LEVELS: int = 5
const MAX_VALUE: float = 5.0
const GRID_COLOR: Color = Color("#CFDDF0")
const AXIS_COLOR: Color = Color("#B7C9E2")
const FILL_COLOR: Color = Color(0.286, 0.788, 0.737, 0.24)
const LINE_COLOR: Color = Color("#4E70D2")
const POINT_COLOR: Color = Color("#E45B7A")
const LABEL_COLOR: Color = Color("#20283A")

var _values: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_values(values: Dictionary) -> void:
	_values = PackedFloat32Array([
		clampf(float(values.get("game", 1)), 0.0, MAX_VALUE),
		clampf(float(values.get("talk", 1)), 0.0, MAX_VALUE),
		clampf(float(values.get("song", 1)), 0.0, MAX_VALUE),
		clampf(float(values.get("act", 1)), 0.0, MAX_VALUE),
		clampf(float(values.get("tech", 1)), 0.0, MAX_VALUE),
	])
	tooltip_text = "游戏力 Lv.%d，杂谈力 Lv.%d，歌唱力 Lv.%d，演出力 Lv.%d，杂项力 Lv.%d" % [
		int(_values[0]), int(_values[1]), int(_values[2]), int(_values[3]), int(_values[4])
	]
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * Vector2(0.5, 0.51)
	var radius: float = minf(size.x, size.y) * 0.31
	if radius <= 0.0:
		return

	for level: int in range(1, GRID_LEVELS + 1):
		var level_radius: float = radius * float(level) / float(GRID_LEVELS)
		var grid_points: PackedVector2Array = _polygon_points(center, level_radius)
		grid_points.append(grid_points[0])
		draw_polyline(grid_points, GRID_COLOR, 2.0, true)

	for index: int in range(ABILITY_LABELS.size()):
		var direction: Vector2 = _axis_direction(index)
		draw_line(center, center + direction * radius, AXIS_COLOR, 2.0, true)

	var value_points: PackedVector2Array = []
	for index: int in range(_values.size()):
		value_points.append(center + _axis_direction(index) * radius * (_values[index] / MAX_VALUE))
	if value_points.size() == ABILITY_LABELS.size():
		draw_colored_polygon(value_points, FILL_COLOR)
		var closed_points: PackedVector2Array = value_points.duplicate()
		closed_points.append(value_points[0])
		draw_polyline(closed_points, LINE_COLOR, 5.0, true)
		for point: Vector2 in value_points:
			draw_circle(point, 7.0, POINT_COLOR)

	var font: Font = get_theme_default_font()
	var font_size: int = 23
	for index: int in range(ABILITY_LABELS.size()):
		var label_text: String = ABILITY_LABELS[index]
		var label_size: Vector2 = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var label_center: Vector2 = center + _axis_direction(index) * (radius + 45.0)
		var label_position := Vector2(label_center.x - label_size.x * 0.5, label_center.y + label_size.y * 0.35)
		draw_string(font, label_position, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)


func _polygon_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for index: int in range(ABILITY_LABELS.size()):
		points.append(center + _axis_direction(index) * radius)
	return points


func _axis_direction(index: int) -> Vector2:
	var angle: float = -PI * 0.5 + TAU * float(index) / float(ABILITY_LABELS.size())
	return Vector2(cos(angle), sin(angle))
