class_name CardInteraction extends Node
## 卡牌交互状态机。scale 仅用于短时反馈，任何结束路径都精确回到 Vector2.ONE。

signal clicked
signal drag_begun
signal visual_state_changed(is_hovered: bool, is_dragging: bool)

enum VisualState { IDLE, HOVER, DRAG, SETTLING }

const HOVER_SCALE: Vector2 = Vector2(1.08, 1.08)
const DRAG_SCALE: Vector2 = Vector2(1.14, 1.14)
const DRAG_THRESHOLD_PX: float = 10.0
const TWEEN_SEC: float = 0.12

@export var drag_enabled: bool = true

var _card: Control = null
var _controller: Node = null
var _visual_state: int = VisualState.IDLE
var _pressed: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _hovering: bool = false
var _input_locked: bool = false
var _shadow_strength: float = 0.0
var _home_position: Vector2 = Vector2.ZERO
var _settle_serial: int = 0
var _tween: Tween = null


func _ready() -> void:
	_card = get_parent() as Control
	assert(_card != null, "CardInteraction must be a child of a Control card")
	_card.mouse_entered.connect(_on_mouse_entered)
	_card.mouse_exited.connect(_on_mouse_exited)
	_card.gui_input.connect(_on_gui_input)
	_card.pivot_offset = _card.size * 0.5
	_card.resized.connect(_on_card_resized)
	snap_idle()


func bind_controller(controller: Node) -> void:
	_controller = controller


func get_card() -> Control:
	return _card


func get_card_payload() -> Dictionary:
	if _card == null:
		return {}
	if _card.has_method("get_card_payload"):
		var method_payload: Variant = _card.call("get_card_payload")
		return method_payload if method_payload is Dictionary else {}
	if "drag_payload" in _card:
		var drag_payload: Variant = _card.get("drag_payload")
		return drag_payload if drag_payload is Dictionary else {}
	if "payload" in _card:
		var property_payload: Variant = _card.get("payload")
		return property_payload if property_payload is Dictionary else {}
	return {}


func get_visual_state() -> int:
	return _visual_state


func is_idle() -> bool:
	return _visual_state == VisualState.IDLE


func is_dragging() -> bool:
	return _visual_state == VisualState.DRAG


func is_motion_locked() -> bool:
	return _visual_state == VisualState.DRAG or _visual_state == VisualState.SETTLING


func get_shadow_strength() -> float:
	return _shadow_strength


func set_home_position(pos: Vector2) -> void:
	_home_position = pos


func get_home_position() -> Vector2:
	return _home_position


func begin_drag_visual() -> void:
	_pressed = true
	_hovering = false
	_input_locked = false
	_set_visual_state(VisualState.DRAG)


func settle_to(global_pos: Vector2, on_done: Callable = Callable()) -> void:
	_pressed = false
	_hovering = false
	_input_locked = true
	_settle_serial += 1
	var serial: int = _settle_serial
	_visual_state = VisualState.SETTLING
	visual_state_changed.emit(false, false)
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_card, "global_position", global_pos, TWEEN_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_card, "scale", Vector2.ONE, TWEEN_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_shadow, _shadow_strength, 0.0, TWEEN_SEC)
	_tween.chain().tween_callback(_finish_settle.bind(serial, global_pos, on_done))


func cancel_press() -> void:
	_pressed = false
	_hovering = false
	_input_locked = false
	if _visual_state != VisualState.SETTLING:
		_set_visual_state(VisualState.IDLE)


func snap_idle() -> void:
	if _card == null:
		return
	_settle_serial += 1
	_pressed = false
	_hovering = false
	_input_locked = false
	_kill_tween()
	_visual_state = VisualState.IDLE
	_card.scale = Vector2.ONE
	_set_shadow(0.0)
	visual_state_changed.emit(false, false)


func _on_card_resized() -> void:
	_card.pivot_offset = _card.size * 0.5


func _on_mouse_entered() -> void:
	if _input_locked or _visual_state != VisualState.IDLE:
		return
	_hovering = true
	_set_visual_state(VisualState.HOVER)


func _on_mouse_exited() -> void:
	_hovering = false
	if not _input_locked and _visual_state == VisualState.HOVER and not _pressed:
		_set_visual_state(VisualState.IDLE)


func _on_gui_input(event: InputEvent) -> void:
	if _card == null or _input_locked:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			if _visual_state == VisualState.DRAG or _visual_state == VisualState.SETTLING:
				return
			_pressed = true
			_press_pos = mouse_button.global_position
			_card.accept_event()
			return
		if _visual_state == VisualState.DRAG:
			_pressed = false
			_card.accept_event()
			return
		if _pressed:
			_pressed = false
			_set_visual_state(VisualState.HOVER if _hovering else VisualState.IDLE)
			clicked.emit()
			_card.accept_event()
	elif event is InputEventMouseMotion and _pressed and drag_enabled:
		var mouse_motion := event as InputEventMouseMotion
		if mouse_motion.global_position.distance_to(_press_pos) >= DRAG_THRESHOLD_PX:
			_start_drag()
			_card.accept_event()


func _start_drag() -> void:
	if _controller == null or not drag_enabled:
		return
	var grab_offset: Vector2 = _press_pos - _card.global_position
	_controller.call("begin_drag", self, grab_offset)
	if _visual_state == VisualState.DRAG:
		drag_begun.emit()


func _set_visual_state(state: int) -> void:
	if _input_locked and state != VisualState.SETTLING:
		return
	_visual_state = state
	match state:
		VisualState.IDLE:
			_animate_to(Vector2.ONE, 0.0)
			visual_state_changed.emit(false, false)
		VisualState.HOVER:
			_animate_to(HOVER_SCALE, 0.22)
			visual_state_changed.emit(true, false)
		VisualState.DRAG:
			_animate_to(DRAG_SCALE, 0.38)
			visual_state_changed.emit(true, true)
		VisualState.SETTLING:
			visual_state_changed.emit(false, false)


func _finish_settle(serial: int, global_pos: Vector2, on_done: Callable) -> void:
	if serial != _settle_serial or _card == null:
		return
	_card.global_position = global_pos
	_card.scale = Vector2.ONE
	_shadow_strength = 0.0
	_visual_state = VisualState.IDLE
	_pressed = false
	_hovering = false
	_input_locked = false
	_tween = null
	visual_state_changed.emit(false, false)
	if on_done.is_valid():
		on_done.call()


func _animate_to(target_scale: Vector2, target_shadow: float) -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_card, "scale", target_scale, TWEEN_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_shadow, _shadow_strength, target_shadow, TWEEN_SEC)


func _set_shadow(value: float) -> void:
	_shadow_strength = value
	if _card != null and _card.has_method("set_card_shadow_strength"):
		_card.call("set_card_shadow_strength", value)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
