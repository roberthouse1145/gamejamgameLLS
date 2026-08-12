class_name LinkPostaPostLoader extends Control
## 新帖等待期间使用的轻量伪圆环；只表达页面更新，不代表网络进度。

const TRACK_COLOR := Color("#E4E7EC")
const ACTIVE_COLOR := Color("#C73550")
const LINE_WIDTH: float = 8.0
const ARC_LENGTH: float = PI * 0.72

var _angle: float = -PI * 0.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_angle = fmod(_angle + delta * 4.4, TAU)
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = maxf(minf(size.x, size.y) * 0.5 - LINE_WIDTH, 4.0)
	draw_arc(center, radius, 0.0, TAU, 48, TRACK_COLOR, LINE_WIDTH, true)
	draw_arc(center, radius, _angle, _angle + ARC_LENGTH, 18, ACTIVE_COLOR, LINE_WIDTH, true)
