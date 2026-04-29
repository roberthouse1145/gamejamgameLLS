class_name PseudoWindow extends Control
## 伪窗口组件，支持拖拽、缩放、最小化、最大化、关闭
## Pseudo window component with drag, resize, minimize, maximize, close support

const WindowIconRendererClass = preload("res://scripts/ui/window_icon_renderer.gd")

# Signals
@warning_ignore("unused_signal")
signal close_requested
signal minimize_requested
signal maximize_requested
signal focus_requested

# Exports
@export var window_title: String = "Window":
	set(value):
		window_title = value
		if title_label:
			title_label.text = value

@export var min_size: Vector2 = Vector2(200, 150)
@export var resizable: bool = true

# State variables
var content: Control
var is_maximized: bool = false
var is_minimized: bool = false
var pre_maximize_rect: Rect2
var close_locked: bool = false
var minimize_locked: bool = false

# Drag state
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

# Resize state
enum ResizeDirection {
	NONE,
	TOP_LEFT, TOP, TOP_RIGHT,
	LEFT, RIGHT,
	BOTTOM_LEFT, BOTTOM, BOTTOM_RIGHT
}
var _is_resizing: bool = false
var _resize_direction: ResizeDirection = ResizeDirection.NONE
var _resize_start_rect: Rect2
var _resize_start_mouse: Vector2

# Node references
@onready var title_bar: Panel = %TitleBar
@onready var title_label: Label = %TitleLabel
@onready var minimize_button: Button = %MinimizeButton
@onready var maximize_button: Button = %MaximizeButton
@onready var close_button: Button = %CloseButton
@onready var content_container: Control = %ContentContainer
@onready var resize_handles: Control = %ResizeHandles


func _ready() -> void:
	# Set initial title
	if title_label:
		title_label.text = window_title

	# Connect button signals
	if minimize_button:
		minimize_button.pressed.connect(_on_minimize_pressed)
	if maximize_button:
		maximize_button.pressed.connect(_on_maximize_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Connect title bar input for dragging
	if title_bar:
		title_bar.gui_input.connect(_on_title_bar_gui_input)

	# Setup resize handles
	_setup_resize_handles()

	# Request focus when clicked anywhere on window
	gui_input.connect(_on_window_gui_input)

	# Apply modern theme by default
	_apply_default_theme()
	_refresh_chrome_state()


func _setup_resize_handles() -> void:
	"""Setup resize handle input connections"""
	if not resize_handles:
		return
	
	var handle_names := [
		"TopLeft", "Top", "TopRight",
		"Left", "Right",
		"BottomLeft", "Bottom", "BottomRight"
	]
	var directions := [
		ResizeDirection.TOP_LEFT, ResizeDirection.TOP, ResizeDirection.TOP_RIGHT,
		ResizeDirection.LEFT, ResizeDirection.RIGHT,
		ResizeDirection.BOTTOM_LEFT, ResizeDirection.BOTTOM, ResizeDirection.BOTTOM_RIGHT
	]
	
	for i in range(handle_names.size()):
		var handle := resize_handles.get_node_or_null(handle_names[i]) as Control
		if handle:
			handle.gui_input.connect(_on_resize_handle_gui_input.bind(directions[i]))


## Set the content control to display inside the window
func set_content(p_content: Control) -> void:
	if content and content.get_parent() == content_container:
		content_container.remove_child(content)
	
	content = p_content
	if content and content_container:
		content_container.add_child(content)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_close_locked(value: bool) -> void:
	close_locked = value
	_refresh_chrome_state()


func set_minimize_locked(value: bool) -> void:
	minimize_locked = value
	_refresh_chrome_state()


func _refresh_chrome_state() -> void:
	if close_button:
		close_button.disabled = close_locked
	if minimize_button:
		minimize_button.disabled = minimize_locked


## Handle title bar input for dragging
func _on_title_bar_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton and not event is InputEventMouseMotion:
		return
	
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
				focus_requested.emit()
			else:
				_is_dragging = false
	
	elif event is InputEventMouseMotion and _is_dragging:
		# Don't allow dragging when maximized
		if is_maximized:
			return
		# Update window position to follow mouse cursor while maintaining offset
		global_position = get_global_mouse_position() - _drag_offset


## Handle resize handle input for resizing
func _on_resize_handle_gui_input(event: InputEvent, direction: ResizeDirection) -> void:
	if not resizable or is_maximized:
		return
	
	if not event is InputEventMouseButton and not event is InputEventMouseMotion:
		return
	
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_is_resizing = true
				_resize_direction = direction
				_resize_start_rect = Rect2(position, size)
				_resize_start_mouse = get_global_mouse_position()
				focus_requested.emit()
			else:
				_is_resizing = false
				_resize_direction = ResizeDirection.NONE
	
	elif event is InputEventMouseMotion and _is_resizing:
		# Calculate mouse delta from resize start position
		var delta := get_global_mouse_position() - _resize_start_mouse
		
		# Calculate new rect based on resize direction
		var new_rect := _resize_start_rect
		
		match _resize_direction:
			ResizeDirection.TOP_LEFT:
				new_rect.position.x += delta.x
				new_rect.position.y += delta.y
				new_rect.size.x -= delta.x
				new_rect.size.y -= delta.y
			ResizeDirection.TOP:
				new_rect.position.y += delta.y
				new_rect.size.y -= delta.y
			ResizeDirection.TOP_RIGHT:
				new_rect.position.y += delta.y
				new_rect.size.x += delta.x
				new_rect.size.y -= delta.y
			ResizeDirection.LEFT:
				new_rect.position.x += delta.x
				new_rect.size.x -= delta.x
			ResizeDirection.RIGHT:
				new_rect.size.x += delta.x
			ResizeDirection.BOTTOM_LEFT:
				new_rect.position.x += delta.x
				new_rect.size.x -= delta.x
				new_rect.size.y += delta.y
			ResizeDirection.BOTTOM:
				new_rect.size.y += delta.y
			ResizeDirection.BOTTOM_RIGHT:
				new_rect.size.x += delta.x
				new_rect.size.y += delta.y
		
		# Apply min_size constraint
		# For edges that affect position (TOP, LEFT), we need to adjust position when clamping size
		if new_rect.size.x < min_size.x:
			var size_diff := min_size.x - new_rect.size.x
			new_rect.size.x = min_size.x
			# If resizing from left edge, adjust position to compensate
			if _resize_direction in [ResizeDirection.TOP_LEFT, ResizeDirection.LEFT, ResizeDirection.BOTTOM_LEFT]:
				new_rect.position.x -= size_diff
		
		if new_rect.size.y < min_size.y:
			var size_diff := min_size.y - new_rect.size.y
			new_rect.size.y = min_size.y
			# If resizing from top edge, adjust position to compensate
			if _resize_direction in [ResizeDirection.TOP_LEFT, ResizeDirection.TOP, ResizeDirection.TOP_RIGHT]:
				new_rect.position.y -= size_diff
		
		# Apply the new rect
		position = new_rect.position
		size = new_rect.size


## Handle window click for focus
func _on_window_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			focus_requested.emit()


func _input(event: InputEvent) -> void:
	if not visible or is_minimized:
		return
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	if not get_global_rect().has_point(mouse_event.global_position):
		return

	if not _is_topmost_window_at_point(mouse_event.global_position):
		return

	focus_requested.emit()


func _is_topmost_window_at_point(point: Vector2) -> bool:
	var parent := get_parent()
	if parent == null:
		return true

	var my_index := get_index()
	for i in range(my_index + 1, parent.get_child_count()):
		var sibling := parent.get_child(i)
		if not sibling is Control:
			continue

		var sibling_control := sibling as Control
		if not sibling_control.visible:
			continue
		if "is_minimized" in sibling_control and sibling_control.is_minimized:
			continue
		if sibling_control.get_global_rect().has_point(point):
			return false

	return true


## Button handlers
func _on_minimize_pressed() -> void:
	if minimize_locked:
		return
	minimize_requested.emit()


func _on_maximize_pressed() -> void:
	maximize_requested.emit()


func _on_close_pressed() -> void:
	if close_locked:
		return
	close_requested.emit()


## Minimize the window
func minimize() -> void:
	if is_minimized:
		return
	is_minimized = true
	hide()


## Restore from minimized state
func restore() -> void:
	if not is_minimized:
		return
	is_minimized = false
	show()


## Get the available desktop area (parent container rect)
func _get_desktop_rect() -> Rect2:
	var parent := get_parent_control()
	if parent:
		return Rect2(Vector2.ZERO, parent.size)
	# Fallback to viewport size if no parent control
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


## Maximize the window to fill the parent container (desktop area)
func maximize() -> void:
	if is_maximized:
		return
	
	# Store current rect for restore
	pre_maximize_rect = Rect2(position, size)
	is_maximized = true
	
	# Get the desktop area and expand window to fill it
	var desktop_rect := _get_desktop_rect()
	position = desktop_rect.position
	size = desktop_rect.size
	
	# Update maximize button to show restore icon
	_update_maximize_button_icon()
	
	# Disable resize handles when maximized
	_set_resize_handles_enabled(false)


## Restore from maximized state
func unmaximize() -> void:
	if not is_maximized:
		return
	
	is_maximized = false
	
	# Restore previous rect
	position = pre_maximize_rect.position
	size = pre_maximize_rect.size
	
	# Update maximize button to show maximize icon
	_update_maximize_button_icon()
	
	# Re-enable resize handles
	_set_resize_handles_enabled(true)


## Toggle maximize state
func toggle_maximize() -> void:
	if is_maximized:
		unmaximize()
	else:
		maximize()


## Update the maximize button icon based on current state
func _update_maximize_button_icon() -> void:
	if not maximize_button:
		return

	var icon_color := Color("#6B7086")
	if is_maximized:
		maximize_button.text = ""
		maximize_button.icon = WindowIconRendererClass.create_restore_icon(icon_color)
	else:
		maximize_button.text = ""
		maximize_button.icon = WindowIconRendererClass.create_maximize_icon(icon_color)


## Enable or disable resize handles
func _set_resize_handles_enabled(enabled: bool) -> void:
	if not resize_handles:
		return

	# Set mouse filter to ignore input when disabled
	var filter := Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE

	for child in resize_handles.get_children():
		if child is Control:
			child.mouse_filter = filter


## Apply modern light theme to the window chrome
func _apply_default_theme() -> void:
	var text_sec     := Color("#6B7086")
	var close_hover  := Color("#FF5F57")
	var min_hover    := Color("#F5A623")
	var btn_radius: int = 6
	var empty := StyleBoxEmpty.new()
	var hover_neutral := _make_btn_circle(Color("#E2E4EA"), btn_radius)

	# Background panel — 带圆角+阴影，与 TitleBar 不同，必须 override
	var bg_panel: Panel = get_node_or_null("Background")
	if bg_panel:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#FFFFFF")
		s.corner_radius_top_left     = 8
		s.corner_radius_top_right    = 8
		s.corner_radius_bottom_left  = 8
		s.corner_radius_bottom_right = 8
		s.border_width_left   = 1
		s.border_width_top    = 1
		s.border_width_right  = 1
		s.border_width_bottom = 1
		s.border_color  = Color("#E2E4EA")
		s.shadow_color  = Color(0.1, 0.11, 0.15, 0.12)
		s.shadow_size   = 16
		s.shadow_offset = Vector2(0, 4)
		bg_panel.add_theme_stylebox_override("panel", s)

	# Title bar — 顶部圆角，底部边框，与 Background 不同，必须 override
	if title_bar:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#FFFFFF")
		s.corner_radius_top_left     = 8
		s.corner_radius_top_right    = 8
		s.corner_radius_bottom_left  = 0
		s.corner_radius_bottom_right = 0
		s.border_width_bottom = 1
		s.border_color = Color("#EFF0F4")
		title_bar.add_theme_stylebox_override("panel", s)

	# Title label — font_color 由 Theme Label 提供；font_size=16 与 Theme(22) 不同，保留
	if title_label:
		title_label.add_theme_font_size_override("font_size", 16)

	# Minimize button — 专属黄色 hover，必须 override
	if minimize_button:
		minimize_button.text = ""
		minimize_button.icon = WindowIconRendererClass.create_minimize_icon(text_sec)
		var hs := _make_btn_circle(min_hover, btn_radius)
		minimize_button.add_theme_stylebox_override("normal",  empty)
		minimize_button.add_theme_stylebox_override("hover",   hs)
		minimize_button.add_theme_stylebox_override("pressed", hs)
		minimize_button.add_theme_stylebox_override("focus",   empty)
		minimize_button.add_theme_color_override("font_color",       text_sec)
		minimize_button.add_theme_color_override("font_hover_color", Color.WHITE)
		minimize_button.add_theme_font_size_override("font_size", 16)

	# Maximize button — 专属中性灰 hover，必须 override
	if maximize_button:
		maximize_button.text = ""
		maximize_button.icon = WindowIconRendererClass.create_maximize_icon(text_sec)
		maximize_button.add_theme_stylebox_override("normal",  empty)
		maximize_button.add_theme_stylebox_override("hover",   hover_neutral)
		maximize_button.add_theme_stylebox_override("pressed", hover_neutral)
		maximize_button.add_theme_stylebox_override("focus",   empty)
		maximize_button.add_theme_color_override("font_color",       text_sec)
		maximize_button.add_theme_color_override("font_hover_color", Color("#1A1D27"))
		maximize_button.add_theme_font_size_override("font_size", 16)

	# Close button — 专属红色 hover，必须 override
	if close_button:
		close_button.text = ""
		close_button.icon = WindowIconRendererClass.create_close_icon(text_sec)
		var hs := _make_btn_circle(close_hover, btn_radius)
		close_button.add_theme_stylebox_override("normal",  empty)
		close_button.add_theme_stylebox_override("hover",   hs)
		close_button.add_theme_stylebox_override("pressed", hs)
		close_button.add_theme_stylebox_override("focus",   empty)
		close_button.add_theme_color_override("font_color",       text_sec)
		close_button.add_theme_color_override("font_hover_color", Color.WHITE)
		close_button.add_theme_font_size_override("font_size", 18)


func _make_btn_circle(bg_color: Color, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg_color
	s.corner_radius_top_left     = r
	s.corner_radius_top_right    = r
	s.corner_radius_bottom_left  = r
	s.corner_radius_bottom_right = r
	return s
