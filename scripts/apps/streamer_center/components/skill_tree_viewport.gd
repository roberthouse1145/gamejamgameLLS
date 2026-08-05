class_name StreamerSkillTreeViewport extends Control
## 成长路线交互视口：左键拖动画布，滚轮围绕鼠标位置缩放。

@export_range(0.1, 1.0, 0.05) var min_zoom: float = 0.6
@export_range(1.0, 4.0, 0.05) var max_zoom: float = 1.8
@export_range(0.05, 0.5, 0.05) var zoom_step: float = 0.1
@export_range(0.0, 400.0, 1.0) var visible_edge: float = 120.0

@onready var skill_canvas: StreamerSkillTreeCanvas = %SkillCanvas

var _zoom: float = 1.0
var _dragging: bool = false
var _view_initialized: bool = false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	skill_canvas.zoom_requested.connect(_on_skill_zoom_requested)
	resized.connect(_on_resized)
	call_deferred("reset_view")


func rebuild() -> void:
	skill_canvas.rebuild()
	skill_canvas.size = skill_canvas.custom_minimum_size
	if _view_initialized:
		call_deferred("_clamp_canvas_position")
	else:
		call_deferred("reset_view")


func set_zoom(value: float, anchor: Vector2 = Vector2(-1.0, -1.0)) -> void:
	var next_zoom: float = clampf(value, min_zoom, max_zoom)
	if is_equal_approx(next_zoom, _zoom):
		return
	var resolved_anchor: Vector2 = anchor
	if resolved_anchor.x < 0.0 or resolved_anchor.y < 0.0:
		resolved_anchor = size * 0.5
	var canvas_anchor: Vector2 = (resolved_anchor - skill_canvas.position) / _zoom
	_zoom = next_zoom
	skill_canvas.scale = Vector2.ONE * _zoom
	skill_canvas.position = resolved_anchor - canvas_anchor * _zoom
	_clamp_canvas_position()


func get_zoom() -> float:
	return _zoom


func pan_by(delta: Vector2) -> void:
	skill_canvas.position += delta
	_clamp_canvas_position()


func reset_view() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	_zoom = clampf(1.0, min_zoom, max_zoom)
	skill_canvas.size = skill_canvas.custom_minimum_size
	skill_canvas.scale = Vector2.ONE * _zoom
	skill_canvas.position = (size - skill_canvas.size * _zoom) * 0.5
	_view_initialized = true
	_clamp_canvas_position()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse_button.pressed
			mouse_default_cursor_shape = Control.CURSOR_MOVE if _dragging else Control.CURSOR_ARROW
			accept_event()
			return
		if mouse_button.pressed and mouse_button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction: float = 1.0 if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			set_zoom(_zoom + zoom_step * direction, mouse_button.position)
			accept_event()
			return
	if event is InputEventMouseMotion and _dragging:
		var mouse_motion := event as InputEventMouseMotion
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_dragging = false
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			return
		pan_by(mouse_motion.relative)
		accept_event()


func _on_skill_zoom_requested(direction: float, canvas_anchor: Vector2) -> void:
	var viewport_anchor: Vector2 = skill_canvas.position + canvas_anchor * _zoom
	set_zoom(_zoom + zoom_step * direction, viewport_anchor)


func _on_resized() -> void:
	if _view_initialized:
		_clamp_canvas_position()


func _clamp_canvas_position() -> void:
	if not is_node_ready():
		return
	var scaled_size: Vector2 = skill_canvas.size * _zoom
	var minimum_position := Vector2(visible_edge, visible_edge) - scaled_size
	var maximum_position := size - Vector2(visible_edge, visible_edge)
	skill_canvas.position = Vector2(
		clampf(skill_canvas.position.x, minimum_position.x, maximum_position.x),
		clampf(skill_canvas.position.y, minimum_position.y, maximum_position.y)
	)
