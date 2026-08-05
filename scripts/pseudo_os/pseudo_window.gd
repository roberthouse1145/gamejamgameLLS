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
@export var max_size: Vector2 = Vector2.ZERO
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
@onready var chrome_accent: ColorRect = %ChromeAccent
@onready var chrome_border: Panel = %ChromeBorder
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
	_hide_maximize_button_chrome()
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


func center_in_screen() -> void:
	var desktop_rect := _get_desktop_rect()
	var centered_position := desktop_rect.position + (desktop_rect.size - size) * 0.5
	position = _clamp_position_for_size(centered_position, size)


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


## 中间「最大化」按钮保留节点与 API 兼容，默认不出现在标题栏、不可点按
func _hide_maximize_button_chrome() -> void:
	if not maximize_button:
		return
	maximize_button.visible = false
	maximize_button.disabled = true
	maximize_button.mouse_filter = Control.MOUSE_FILTER_IGNORE


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
		
		# Apply size constraints
		# For edges that affect position (TOP, LEFT), we need to adjust position when clamping size
		var constrained_size := _clamp_size(new_rect.size)
		if not is_equal_approx(constrained_size.x, new_rect.size.x):
			var size_diff := constrained_size.x - new_rect.size.x
			new_rect.size.x = constrained_size.x
			if _resize_direction in [ResizeDirection.TOP_LEFT, ResizeDirection.LEFT, ResizeDirection.BOTTOM_LEFT]:
				new_rect.position.x -= size_diff

		if not is_equal_approx(constrained_size.y, new_rect.size.y):
			var size_diff := constrained_size.y - new_rect.size.y
			new_rect.size.y = constrained_size.y
			if _resize_direction in [ResizeDirection.TOP_LEFT, ResizeDirection.TOP, ResizeDirection.TOP_RIGHT]:
				new_rect.position.y -= size_diff
		
		# Apply the new rect
		position = _clamp_position_for_size(new_rect.position, new_rect.size)
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


func _clamp_size(value: Vector2) -> Vector2:
	var result := value
	result.x = maxf(result.x, min_size.x)
	result.y = maxf(result.y, min_size.y)
	if max_size.x > 0.0:
		result.x = minf(result.x, max_size.x)
	if max_size.y > 0.0:
		result.y = minf(result.y, max_size.y)
	return result


func _clamp_position_for_size(value: Vector2, target_size: Vector2) -> Vector2:
	var desktop_rect := _get_desktop_rect()
	if desktop_rect.size.x <= 0.0 or desktop_rect.size.y <= 0.0:
		return value

	var max_position := desktop_rect.position + desktop_rect.size - target_size
	return Vector2(
		clampf(value.x, desktop_rect.position.x, maxf(desktop_rect.position.x, max_position.x)),
		clampf(value.y, desktop_rect.position.y, maxf(desktop_rect.position.y, max_position.y))
	)


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
	var btn_radius: int = 15
	var empty := StyleBoxEmpty.new()
	var hover_neutral := _make_btn_circle(Color("#E2E4EA"), btn_radius)

	# Background panel — 带圆角+阴影，与 TitleBar 不同，必须 override
	var bg_panel: Panel = get_node_or_null("Background")
	if bg_panel:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#F7FAFF")
		s.corner_radius_top_left     = 24
		s.corner_radius_top_right    = 24
		s.corner_radius_bottom_left  = 0
		s.corner_radius_bottom_right = 0
		s.border_width_left   = 3
		s.border_width_top    = 3
		s.border_width_right  = 3
		s.border_width_bottom = 3
		s.border_color  = Color("#B8C7DB")
		s.shadow_color  = Color(0.05, 0.09, 0.16, 0.3)
		s.shadow_size   = 36
		s.shadow_offset = Vector2(0, 10)
		bg_panel.add_theme_stylebox_override("panel", s)

	# Title bar — 顶部圆角，底部边框，与 Background 不同，必须 override
	if title_bar:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#F8FAFE")
		s.corner_radius_top_left     = 24
		s.corner_radius_top_right    = 24
		s.corner_radius_bottom_left  = 0
		s.corner_radius_bottom_right = 0
		s.border_width_bottom = 2
		s.border_color = Color("#D3DDEA")
		s.shadow_color = Color(0.08, 0.13, 0.22, 0.12)
		s.shadow_size = 7
		s.shadow_offset = Vector2(0, 3)
		title_bar.add_theme_stylebox_override("panel", s)

	if chrome_border:
		var border_style := StyleBoxFlat.new()
		border_style.draw_center = false
		border_style.corner_radius_top_left = 24
		border_style.corner_radius_top_right = 24
		border_style.corner_radius_bottom_left = 0
		border_style.corner_radius_bottom_right = 0
		border_style.border_width_left = 2
		border_style.border_width_top = 2
		border_style.border_width_right = 2
		border_style.border_width_bottom = 2
		border_style.border_color = Color("#AEBFD5")
		chrome_border.add_theme_stylebox_override("panel", border_style)

	if chrome_accent:
		chrome_accent.color = Color("#8CB7F3")

	# 4K 窗口标题字号
	if title_label:
		title_label.add_theme_color_override("font_color", Color("#34435C"))
		title_label.add_theme_font_size_override("font_size", 26)

	# Minimize button — 专属黄色 hover，必须 override
	if minimize_button:
		minimize_button.text = ""
		minimize_button.icon = WindowIconRendererClass.create_minimize_icon(text_sec)
		_center_icon_only_button(minimize_button)
		var hs := _make_btn_circle(min_hover, btn_radius)
		minimize_button.add_theme_stylebox_override("normal",  empty)
		minimize_button.add_theme_stylebox_override("hover",   hs)
		minimize_button.add_theme_stylebox_override("pressed", hs)
		minimize_button.add_theme_stylebox_override("focus",   empty)
		minimize_button.add_theme_stylebox_override("disabled", empty)
		minimize_button.add_theme_stylebox_override("disabled_mirrored", empty)
		minimize_button.add_theme_color_override("font_color",       text_sec)
		minimize_button.add_theme_color_override("font_hover_color", Color.WHITE)
		minimize_button.add_theme_color_override("font_disabled_color", Color(text_sec, 0.38))
		minimize_button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.38))
		minimize_button.add_theme_font_size_override("font_size", 24)

	# Maximize button — 专属中性灰 hover，必须 override
	if maximize_button:
		maximize_button.text = ""
		maximize_button.icon = WindowIconRendererClass.create_maximize_icon(text_sec)
		_center_icon_only_button(maximize_button)
		maximize_button.add_theme_stylebox_override("normal",  empty)
		maximize_button.add_theme_stylebox_override("hover",   hover_neutral)
		maximize_button.add_theme_stylebox_override("pressed", hover_neutral)
		maximize_button.add_theme_stylebox_override("focus",   empty)
		maximize_button.add_theme_stylebox_override("disabled", empty)
		maximize_button.add_theme_stylebox_override("disabled_mirrored", empty)
		maximize_button.add_theme_color_override("font_color",       text_sec)
		maximize_button.add_theme_color_override("font_hover_color", Color("#1A1D27"))
		maximize_button.add_theme_color_override("font_disabled_color", Color(text_sec, 0.38))
		maximize_button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.38))
		maximize_button.add_theme_font_size_override("font_size", 24)

	# Close button — 专属红色 hover，必须 override
	if close_button:
		close_button.text = ""
		close_button.icon = WindowIconRendererClass.create_close_icon(text_sec)
		_center_icon_only_button(close_button)
		var hs := _make_btn_circle(close_hover, btn_radius)
		close_button.add_theme_stylebox_override("normal",  empty)
		close_button.add_theme_stylebox_override("hover",   hs)
		close_button.add_theme_stylebox_override("pressed", hs)
		close_button.add_theme_stylebox_override("focus",   empty)
		close_button.add_theme_stylebox_override("disabled", empty)
		close_button.add_theme_stylebox_override("disabled_mirrored", empty)
		close_button.add_theme_color_override("font_color",       text_sec)
		close_button.add_theme_color_override("font_hover_color", Color.WHITE)
		close_button.add_theme_color_override("font_disabled_color", Color(text_sec, 0.38))
		close_button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.38))
		close_button.add_theme_font_size_override("font_size", 27)


func _make_btn_circle(bg_color: Color, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg_color
	s.corner_radius_top_left     = r
	s.corner_radius_top_right    = r
	s.corner_radius_bottom_left  = r
	s.corner_radius_bottom_right = r
	return s


func _center_icon_only_button(btn: Button) -> void:
	## Button 默认 icon 水平左对齐，圆形 hover 会显得图标偏离中心
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_theme_constant_override("h_separation", 0)
