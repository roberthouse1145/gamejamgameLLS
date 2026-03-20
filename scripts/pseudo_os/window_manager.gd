class_name WindowManager extends Node
## 窗口管理器，负责窗口的创建、销毁、拖拽、缩放、层级管理
## Window manager responsible for window creation, destruction, drag, resize, and z-order management

# Preload PseudoWindow class
const PseudoWindowClass = preload("res://scripts/pseudo_os/pseudo_window.gd")

# Signals
signal window_created(window: Control)
signal window_closed(window: Control)
signal window_focused(window: Control)

# Window scene reference
const WINDOW_SCENE_PATH := "res://scenes/pseudo_os/window.tscn"
var _window_scene: PackedScene

# Window management
var windows: Array = []  # Array of PseudoWindow
var focused_window: Control = null
var next_z_index: int = 0

# Container for windows (set by Desktop)
var window_container: Control = null


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
	
	# Setup z-order
	window.z_index = next_z_index
	next_z_index += 1
	
	# Connect window signals
	_connect_window_signals(window)
	
	# Track window
	windows.append(window)
	
	# Focus the new window
	focus_window(window)
	
	# Emit signal
	window_created.emit(window)
	
	return window


## Close and destroy a window
## @param window: The window to close
func close_window(window: Control) -> void:
	# Implementation will be completed in Task 3.6
	if not window or not is_instance_valid(window):
		return
	
	# Remove from tracking
	var index := windows.find(window)
	if index >= 0:
		windows.remove_at(index)
	
	# Clear focus if this was the focused window
	if focused_window == window:
		focused_window = null
		# Focus the next topmost window
		_focus_topmost_window()
	
	# Emit signal before destruction
	window_closed.emit(window)
	
	# Destroy the window
	window.queue_free()


## Focus a window, bringing it to the front
## @param window: The window to focus
func focus_window(window: Control) -> void:
	# Implementation will be completed in Task 3.7
	if not window or not is_instance_valid(window):
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
	
	window.minimize()
	
	# If this was the focused window, focus another
	if focused_window == window:
		focused_window = null
		_focus_topmost_window()


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
		focus_window(window)
	elif window.is_maximized:
		window.unmaximize()


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


# Private methods

## Apply WindowConstraints to a window
func _apply_constraints(window: Control, constraints) -> void:
	# WindowConstraints will be created in Task 4.2
	# For now, check if constraints has expected properties
	if constraints.has_method("get") or constraints is Resource:
		if "min_size" in constraints:
			window.min_size = constraints.min_size
		if "resizable" in constraints:
			window.resizable = constraints.resizable
		if "default_size" in constraints:
			window.size = constraints.default_size


## Connect window signals to manager handlers
func _connect_window_signals(window: Control) -> void:
	window.close_requested.connect(_on_window_close_requested.bind(window))
	window.minimize_requested.connect(_on_window_minimize_requested.bind(window))
	window.maximize_requested.connect(_on_window_maximize_requested.bind(window))
	window.focus_requested.connect(_on_window_focus_requested.bind(window))


## Focus the topmost visible window
func _focus_topmost_window() -> void:
	var topmost: Control = null
	var highest_z: int = -1
	
	for window in windows:
		if is_instance_valid(window) and window.visible and not window.is_minimized:
			if window.z_index > highest_z:
				highest_z = window.z_index
				topmost = window
	
	if topmost:
		focus_window(topmost)


func _bring_window_to_front(window: Control) -> void:
	# Keep visual stacking and mouse hit order in sync.
	# Relying on z_index alone can still leave older siblings receiving input first.
	window.z_index = next_z_index
	next_z_index += 1

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
