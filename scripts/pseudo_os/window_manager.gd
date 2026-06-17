class_name WindowManager extends Node
## 窗口管理器，负责窗口的创建、销毁、拖拽、缩放、层级管理
## Window manager responsible for window creation, destruction, drag, resize, and z-order management

# Preload PseudoWindow class
const PseudoWindowClass = preload("res://scripts/pseudo_os/pseudo_window.gd")

# Signals
signal window_created(window: Control)
signal window_closed(window: Control)
signal window_focused(window: Control)
signal window_minimized(window: Control)

# Window scene reference
const WINDOW_SCENE_PATH := "res://scenes/pseudo_os/window.tscn"
const OPEN_ANIM_DURATION: float = 0.18
const MINIMIZE_ANIM_DURATION: float = 0.14
const CLOSE_ANIM_DURATION: float = 0.12
const OPEN_ANIM_OFFSET_Y: float = 14.0
const OPEN_ANIM_START_SCALE: Vector2 = Vector2(0.97, 0.97)
const WINDOW_EDGE_MARGIN: float = 24.0
var _window_scene: PackedScene

# Window management
var windows: Array = []  # Array of PseudoWindow
var focused_window: Control = null

# Container for windows (set by Desktop)
var window_container: Control = null
var taskbar: Control = null


func _ready() -> void:
	# Preload window scene
	_window_scene = load(WINDOW_SCENE_PATH) as PackedScene


## Create a new window with the given title and content
## @param title: Window title text
## @param content: Control node to display inside the window
## @param constraints: Optional WindowConstraints resource (Task 4.2)
## @return: The created PseudoWindow instance
func create_window(title: String, content: Control, constraints = null) -> Control:
	# Implementation will be completed in Task 3.6
	# This is the basic structure
	if not _window_scene:
		push_error("WindowManager: Window scene not loaded")
		return null
	
	var window: Control = _window_scene.instantiate()
	if not window:
		push_error("WindowManager: Failed to instantiate window")
		return null
	
	# Set window properties
	window.window_title = title
	
	# Apply constraints if provided
	if constraints:
		_apply_constraints(window, constraints)
	
	# Add to container
	if window_container:
		window_container.add_child(window)
	else:
		push_warning("WindowManager: No window container set, adding to self")
		add_child(window)
	
	# Set content
	if content:
		window.set_content(content)

	_apply_relative_default_size(window, constraints)
	fit_window_to_container(window)
	
	# Connect window signals
	_connect_window_signals(window)
	
	# Track window
	windows.append(window)
	
	# 开窗过渡：避免“瞬间弹出”的生硬感
	_animate_window_open(window)

	# Focus the new window
	focus_window(window)
	
	# Emit signal
	window_created.emit(window)
	
	return window


func _animate_window_open(window: Control) -> void:
	if window == null or not is_instance_valid(window):
		return
	_kill_window_tween(window)

	# 先设置初始状态，再 tween 到目标状态。
	var target_position: Vector2 = window.position
	window.pivot_offset = window.size * 0.5
	window.position = target_position + Vector2(0.0, OPEN_ANIM_OFFSET_Y)
	window.scale = OPEN_ANIM_START_SCALE
	window.modulate.a = 0.0

	var tween := window.create_tween()
	window.set_meta("motion_tween", tween)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(window, "position", target_position, OPEN_ANIM_DURATION)
	tween.parallel().tween_property(window, "scale", Vector2.ONE, OPEN_ANIM_DURATION)
	tween.parallel().tween_property(window, "modulate:a", 1.0, OPEN_ANIM_DURATION)
	tween.finished.connect(func() -> void:
		if is_instance_valid(window):
			window.remove_meta("motion_tween")
	)


func _animate_window_minimize(window: Control) -> void:
	if window == null or not is_instance_valid(window):
		return
	if window.has_meta("minimizing") and bool(window.get_meta("minimizing")):
		return

	window.set_meta("minimizing", true)
	_kill_window_tween(window)

	var origin_position: Vector2 = window.position
	var target_position: Vector2 = _get_minimize_target_position(window, origin_position)
	window.pivot_offset = window.size * 0.5
	var tween := window.create_tween()
	window.set_meta("motion_tween", tween)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(window, "position", target_position, MINIMIZE_ANIM_DURATION)
	tween.parallel().tween_property(window, "scale", Vector2(0.18, 0.18), MINIMIZE_ANIM_DURATION)
	tween.parallel().tween_property(window, "modulate:a", 0.12, MINIMIZE_ANIM_DURATION)
	tween.finished.connect(func() -> void:
		if not is_instance_valid(window):
			return
		window.position = origin_position
		window.scale = Vector2.ONE
		window.modulate.a = 1.0
		window.minimize()
		window_minimized.emit(window)
		if taskbar != null and is_instance_valid(taskbar):
			if taskbar.has_method("set_window_button_minimized"):
				taskbar.set_window_button_minimized(window, true)
			if taskbar.has_method("pulse_window_button"):
				taskbar.pulse_window_button(window)
		window.remove_meta("motion_tween")
		window.remove_meta("minimizing")
		_focus_topmost_window()
	)


func _get_minimize_target_position(window: Control, fallback_position: Vector2) -> Vector2:
	var fallback := fallback_position + Vector2(0.0, OPEN_ANIM_OFFSET_Y)
	if taskbar == null or not is_instance_valid(taskbar):
		return fallback
	if not taskbar.has_method("get_window_button"):
		return fallback

	var button_variant: Variant = taskbar.get_window_button(window)
	if not (button_variant is Control):
		return fallback

	var button := button_variant as Control
	if not is_instance_valid(button) or window.get_parent() == null:
		return fallback

	var parent := window.get_parent() as Control
	if parent == null:
		return fallback

	var target_center: Vector2 = button.get_global_rect().get_center() - parent.get_global_rect().position
	# pivot_offset 设为窗口中心，视觉中心始终在 position + size * 0.5，与 scale 无关
	# 因此要让视觉中心对齐任务栏按钮中心，position = target_center - size * 0.5
	return target_center - window.size * 0.5


func _animate_window_close(window: Control) -> void:
	if window == null or not is_instance_valid(window):
		return
	_kill_window_tween(window)

	window.pivot_offset = window.size * 0.5
	var tween := window.create_tween()
	window.set_meta("motion_tween", tween)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(window, "scale", Vector2(0.94, 0.94), CLOSE_ANIM_DURATION)
	tween.parallel().tween_property(window, "modulate:a", 0.0, CLOSE_ANIM_DURATION)
	tween.finished.connect(func() -> void:
		if not is_instance_valid(window):
			return
		window.hide()
		window_closed.emit(window)
		_focus_topmost_window()
		window.queue_free()
	)


func _kill_window_tween(window: Control) -> void:
	if window == null or not is_instance_valid(window):
		return
	if not window.has_meta("motion_tween"):
		return
	var tween_meta: Variant = window.get_meta("motion_tween")
	if tween_meta is Tween:
		var tween := tween_meta as Tween
		if is_instance_valid(tween):
			tween.kill()
	if window.has_meta("motion_tween"):
		window.remove_meta("motion_tween")


## Close and destroy a window
## @param window: The window to close
func close_window(window: Control) -> void:
	# Implementation will be completed in Task 3.6
	if not window or not is_instance_valid(window):
		return
	if window.has_meta("closing") and bool(window.get_meta("closing")):
		return

	window.set_meta("closing", true)
	
	# Remove from tracking
	var index := windows.find(window)
	if index >= 0:
		windows.remove_at(index)
	
	# Clear focus if this was the focused window
	if focused_window == window:
		focused_window = null

	_animate_window_close(window)


## Focus a window, bringing it to the front
## @param window: The window to focus
func focus_window(window: Control) -> void:
	# Implementation will be completed in Task 3.7
	if not window or not is_instance_valid(window):
		return

	# If window is minimized, restore it first
	if "is_minimized" in window and window.is_minimized:
		restore_window(window)
		return

	if window == focused_window and _is_window_frontmost(window):
		return

	_bring_window_to_front(window)

	if window == focused_window:
		return
	
	# Update focused window reference
	focused_window = window
	
	# Emit signal
	window_focused.emit(window)


## Minimize a window
## @param window: The window to minimize
func minimize_window(window: Control) -> void:
	if not window or not is_instance_valid(window):
		return
	if window.is_minimized:
		return

	if focused_window == window:
		focused_window = null

	_animate_window_minimize(window)


func minimize_window_with_callback(window: Control, on_finished: Callable = Callable()) -> bool:
	if not window or not is_instance_valid(window):
		return false
	if window.is_minimized:
		if on_finished.is_valid():
			on_finished.call_deferred()
		return true

	if on_finished.is_valid():
		var callable_ref: Array = []  # 用数组包装，让 lambda 能引用自身
		var finished_callable: Callable = func(minimized_window: Control) -> void:
			if minimized_window != window:
				return
			if callable_ref.size() > 0 and window_minimized.is_connected(callable_ref[0]):
				window_minimized.disconnect(callable_ref[0])
			on_finished.call()
		callable_ref.append(finished_callable)
		window_minimized.connect(finished_callable)

	minimize_window(window)
	return true


## Maximize a window to fill the desktop area
## @param window: The window to maximize
func maximize_window(window: Control) -> void:
	if not window or not is_instance_valid(window):
		return
	
	window.maximize()


## Restore a window from minimized or maximized state
## @param window: The window to restore
func restore_window(window: Control) -> void:
	if not window or not is_instance_valid(window):
		return
	
	if window.is_minimized:
		window.restore()
		if taskbar != null and is_instance_valid(taskbar) and taskbar.has_method("set_window_button_minimized"):
			taskbar.set_window_button_minimized(window, false)
		_animate_window_open(window)
		focus_window(window)
	elif window.is_maximized:
		window.unmaximize()


func fit_window_to_container(window: Control, center_window: bool = true) -> void:
	if window == null or not is_instance_valid(window):
		return

	var available_size := _get_available_window_size(window)
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		return

	var target_size := _clamp_window_size_to_available(window.size, window, available_size)
	window.size = target_size

	if center_window:
		_center_window_in_container(window, available_size)
	else:
		_clamp_window_position_to_container(window, available_size)


## Get all currently open windows
## @return: Array of PseudoWindow instances
func get_windows() -> Array:
	return windows


## Get the currently focused window
## @return: The focused PseudoWindow or null
func get_focused_window() -> Control:
	return focused_window


## Check if a window is currently open
## @param window: The window to check
## @return: True if the window is open
func is_window_open(window: Control) -> bool:
	return window in windows and is_instance_valid(window)


## Set the container where windows will be added
## @param container: The Control node to use as window container
func set_window_container(container: Control) -> void:
	window_container = container


func set_taskbar(taskbar_control: Control) -> void:
	taskbar = taskbar_control


# Private methods

## Apply WindowConstraints to a window
func _apply_constraints(window: Control, constraints) -> void:
	# WindowConstraints will be created in Task 4.2
	# For now, check if constraints has expected properties
	if constraints.has_method("get") or constraints is Resource:
		if "min_size" in constraints:
			window.min_size = constraints.min_size
			window.custom_minimum_size = constraints.min_size
		if "max_size" in constraints and "max_size" in window:
			window.max_size = constraints.max_size
		if "resizable" in constraints:
			window.resizable = constraints.resizable
		if "default_size" in constraints:
			window.size = constraints.default_size


func _apply_relative_default_size(window: Control, constraints) -> void:
	if window == null or not is_instance_valid(window) or constraints == null:
		return
	if not ("default_size_ratio" in constraints):
		return

	var ratio: float = clampf(float(constraints.default_size_ratio), 0.0, 1.0)
	if ratio <= 0.0:
		return

	var available_size := _get_available_window_size(window)
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		return

	var target_window_size := available_size * ratio
	if "default_content_aspect_ratio" in constraints:
		target_window_size = _fit_window_size_for_content_aspect(
			window,
			target_window_size,
			float(constraints.default_content_aspect_ratio)
		)
	window.size = target_window_size


func _fit_window_size_for_content_aspect(window: Control, max_window_size: Vector2, aspect_ratio: float) -> Vector2:
	if aspect_ratio <= 0.0 or max_window_size.x <= 0.0 or max_window_size.y <= 0.0:
		return max_window_size

	var chrome_padding := _get_window_chrome_padding(window)
	var max_content_size := Vector2(
		maxf(max_window_size.x - chrome_padding.x, 1.0),
		maxf(max_window_size.y - chrome_padding.y, 1.0)
	)

	var content_size := max_content_size
	var content_aspect := content_size.x / content_size.y
	if content_aspect > aspect_ratio:
		content_size.x = content_size.y * aspect_ratio
	else:
		content_size.y = content_size.x / aspect_ratio

	return content_size + chrome_padding


func _get_window_chrome_padding(window: Control) -> Vector2:
	var content_container := window.get_node_or_null("ContentContainer") as Control
	if content_container == null:
		return Vector2.ZERO

	var padding := window.size - content_container.size
	if padding.x < 0.0 or padding.y < 0.0:
		return Vector2.ZERO
	return padding


func _get_available_window_size(window: Control) -> Vector2:
	var parent := window.get_parent() as Control
	if parent != null and parent.size.x > 0.0 and parent.size.y > 0.0:
		return parent.size
	var viewport := window.get_viewport()
	if viewport != null:
		return viewport.get_visible_rect().size
	return Vector2.ZERO


func _clamp_window_size_to_available(value: Vector2, window: Control, available_size: Vector2) -> Vector2:
	var padded_available := Vector2(
		maxf(available_size.x - WINDOW_EDGE_MARGIN * 2.0, 160.0),
		maxf(available_size.y - WINDOW_EDGE_MARGIN * 2.0, 120.0)
	)
	var min_size: Vector2 = window.min_size if "min_size" in window else Vector2(200, 150)
	var max_size: Vector2 = window.max_size if "max_size" in window else Vector2.ZERO

	var result := value
	if max_size.x > 0.0:
		result.x = minf(result.x, max_size.x)
	if max_size.y > 0.0:
		result.y = minf(result.y, max_size.y)

	result.x = minf(result.x, padded_available.x)
	result.y = minf(result.y, padded_available.y)

	if min_size.x <= padded_available.x:
		result.x = maxf(result.x, min_size.x)
	if min_size.y <= padded_available.y:
		result.y = maxf(result.y, min_size.y)

	return result


func _center_window_in_container(window: Control, available_size: Vector2) -> void:
	window.position = Vector2(
		maxf((available_size.x - window.size.x) * 0.5, WINDOW_EDGE_MARGIN),
		maxf((available_size.y - window.size.y) * 0.5, WINDOW_EDGE_MARGIN)
	)


func _clamp_window_position_to_container(window: Control, available_size: Vector2) -> void:
	var max_position := available_size - window.size - Vector2(WINDOW_EDGE_MARGIN, WINDOW_EDGE_MARGIN)
	window.position = Vector2(
		clampf(window.position.x, WINDOW_EDGE_MARGIN, maxf(WINDOW_EDGE_MARGIN, max_position.x)),
		clampf(window.position.y, WINDOW_EDGE_MARGIN, maxf(WINDOW_EDGE_MARGIN, max_position.y))
	)


## Connect window signals to manager handlers
func _connect_window_signals(window: Control) -> void:
	window.close_requested.connect(_on_window_close_requested.bind(window))
	window.minimize_requested.connect(_on_window_minimize_requested.bind(window))
	window.maximize_requested.connect(_on_window_maximize_requested.bind(window))
	window.focus_requested.connect(_on_window_focus_requested.bind(window))


## Focus the topmost visible window
func _focus_topmost_window() -> void:
	var topmost: Control = null
	var highest_idx: int = -1
	
	for window in windows:
		if is_instance_valid(window) and window.visible and not window.is_minimized:
			var idx: int = window.get_index()
			if idx > highest_idx:
				highest_idx = idx
				topmost = window
	
	if topmost:
		focus_window(topmost)


func _bring_window_to_front(window: Control) -> void:
	var parent := window.get_parent()
	if parent == null:
		return

	var top_index := parent.get_child_count() - 1
	if window.get_index() != top_index:
		parent.move_child(window, top_index)


func _is_window_frontmost(window: Control) -> bool:
	var parent := window.get_parent()
	if parent == null:
		return true
	return window.get_index() == parent.get_child_count() - 1


# Signal handlers

func _on_window_close_requested(window: Control) -> void:
	close_window(window)


func _on_window_minimize_requested(window: Control) -> void:
	minimize_window(window)


func _on_window_maximize_requested(window: Control) -> void:
	if window.is_maximized:
		restore_window(window)
	else:
		maximize_window(window)


func _on_window_focus_requested(window: Control) -> void:
	focus_window(window)
