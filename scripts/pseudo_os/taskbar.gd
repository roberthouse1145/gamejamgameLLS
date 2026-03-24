class_name Taskbar extends Panel
## 任务栏组件，显示运行中的应用窗口按钮

# Theme colors (与 PseudoWindow 统一的现代浅色调色板)
const T_SURFACE: Color    = Color("#FFFFFF")
const T_SURFACE_ALT: Color = Color("#F7F8FA")
const T_BORDER: Color     = Color("#E2E4EA")
const T_TEXT: Color       = Color("#1A1D27")
const T_TEXT_DIM: Color   = Color("#6B7086")
const T_TEXT_MUTED: Color = Color("#9EA2B5")
const T_ACCENT: Color     = Color("#4A7CFF")

# Signals
signal window_button_clicked(window: Control)

# Node references
@onready var button_container: HBoxContainer = %ButtonContainer

# Window to button mapping
var _window_buttons: Dictionary = {}  # window -> Button

# Button settings
@export var button_min_width: float = 160.0
@export var button_max_width: float = 240.0


func _ready() -> void:
	if not button_container:
		push_error("Taskbar: ButtonContainer not found")
	_apply_theme()


func _apply_theme() -> void:
	# Panel panel style — 由 pseudo_os_light.tres Theme 提供，无需 override

	# StartButton — 专属颜色（hover 变 accent），与普通 window button 不同，保留
	var start_btn: Button = get_node_or_null("HBoxContainer/StartButton")
	if start_btn:
		start_btn.flat = false
		var sn := StyleBoxFlat.new()
		sn.bg_color = Color.TRANSPARENT
		sn.content_margin_left = 12
		sn.content_margin_right = 12
		sn.content_margin_top = 4
		sn.content_margin_bottom = 4
		var sh := sn.duplicate() as StyleBoxFlat
		sh.bg_color = Color("#E8E9ED")
		start_btn.add_theme_stylebox_override("normal", sn)
		start_btn.add_theme_stylebox_override("hover", sh)
		start_btn.add_theme_stylebox_override("pressed", sh)
		start_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		start_btn.add_theme_color_override("font_color", T_TEXT)
		start_btn.add_theme_color_override("font_hover_color", T_ACCENT)
		start_btn.add_theme_color_override("font_pressed_color", T_ACCENT)
		start_btn.add_theme_color_override("font_focus_color", T_TEXT)
		start_btn.add_theme_color_override("font_hover_pressed_color", T_ACCENT)
		start_btn.add_theme_font_size_override("font_size", 24)

	# Separator — 由 Theme VSeparator/styles/separator 提供，无需 override

	# Clock — font_color 是特殊 dim 色，保留；font_size 由 Theme Label 提供，删除
	var clock: Label = get_node_or_null("HBoxContainer/Clock")
	if clock:
		clock.add_theme_color_override("font_color", T_TEXT_DIM)

	# ButtonContainer spacing — HBoxContainer constant，Theme 未定义，保留
	if button_container:
		button_container.add_theme_constant_override("separation", 6)


func _style_window_button(button: Button) -> void:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color.TRANSPARENT
	normal_style.corner_radius_top_left = 6
	normal_style.corner_radius_top_right = 6
	normal_style.corner_radius_bottom_left = 6
	normal_style.corner_radius_bottom_right = 6
	normal_style.content_margin_left = 10
	normal_style.content_margin_right = 10
	normal_style.content_margin_top = 4
	normal_style.content_margin_bottom = 4

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color("#E8E9ED")

	# pressed = focused 状态（toggle_mode），用底部 accent 条表示激活
	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = T_SURFACE
	pressed_style.border_width_bottom = 2
	pressed_style.border_color = T_ACCENT

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", T_TEXT_DIM)
	button.add_theme_color_override("font_hover_color", T_TEXT)
	button.add_theme_color_override("font_pressed_color", T_TEXT)
	button.add_theme_color_override("font_focus_color", T_TEXT)
	button.add_theme_color_override("font_hover_pressed_color", T_TEXT)
	button.add_theme_font_size_override("font_size", 22)
	button.toggle_mode = true


## Add a button for a window
## @param window: The PseudoWindow to add a button for
## @param title: The title to display on the button
## @param icon: Optional icon texture for the button
func add_window_button(window: Control, title: String, icon: Texture2D = null) -> void:
	if not window or not is_instance_valid(window):
		push_warning("Taskbar: Cannot add button for invalid window")
		return
	
	# Check if button already exists
	if _window_buttons.has(window):
		push_warning("Taskbar: Button for window already exists")
		return
	
	# Create button
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.x = button_min_width
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_style_window_button(button)

	# Set icon if provided
	if icon:
		button.icon = icon

	# Connect button press signal
	button.pressed.connect(_on_window_button_pressed.bind(window))

	# Add to container
	if button_container:
		button_container.add_child(button)
	
	# Track mapping
	_window_buttons[window] = button
	
	# Update button widths
	_update_button_widths()


## Remove a button for a window
## @param window: The PseudoWindow whose button to remove
func remove_window_button(window: Control) -> void:
	if not _window_buttons.has(window):
		return
	
	var button: Button = _window_buttons[window]
	if is_instance_valid(button):
		button.queue_free()
	
	_window_buttons.erase(window)
	
	# Update button widths
	_update_button_widths()


## Update a window button's title
## @param window: The PseudoWindow whose button to update
## @param title: The new title
func update_window_button_title(window: Control, title: String) -> void:
	if not _window_buttons.has(window):
		return
	
	var button: Button = _window_buttons[window]
	if is_instance_valid(button):
		button.text = title


## Update a window button's icon
## @param window: The PseudoWindow whose button to update
## @param icon: The new icon texture
func update_window_button_icon(window: Control, icon: Texture2D) -> void:
	if not _window_buttons.has(window):
		return
	
	var button: Button = _window_buttons[window]
	if is_instance_valid(button):
		button.icon = icon


## Set the visual state of a window button (focused/unfocused)
## @param window: The PseudoWindow whose button to update
## @param focused: Whether the window is focused
func set_window_button_focused(window: Control, focused: bool) -> void:
	if not _window_buttons.has(window):
		return
	
	var button: Button = _window_buttons[window]
	if is_instance_valid(button):
		# Use button_pressed to indicate focused state
		button.button_pressed = focused


## Set the visual state of a window button (minimized)
## @param window: The PseudoWindow whose button to update
## @param minimized: Whether the window is minimized
func set_window_button_minimized(window: Control, minimized: bool) -> void:
	if not _window_buttons.has(window):
		return
	
	var button: Button = _window_buttons[window]
	if is_instance_valid(button):
		# Dim the button when minimized
		button.modulate.a = 0.7 if minimized else 1.0


## Check if a window has a button
## @param window: The window to check
## @return: True if the window has a button
func has_window_button(window: Control) -> bool:
	return _window_buttons.has(window)


## Get the button for a window
## @param window: The window to get the button for
## @return: The Button or null
func get_window_button(window: Control) -> Button:
	if _window_buttons.has(window):
		return _window_buttons[window]
	return null


func pulse_window_button(window: Control) -> void:
	var button := get_window_button(window)
	if button == null or not is_instance_valid(button):
		return
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(1.04, 1.04), 0.07)
	tween.tween_property(button, "scale", Vector2.ONE, 0.1)


## Get all tracked windows
## @return: Array of windows
func get_tracked_windows() -> Array:
	return _window_buttons.keys()


## Clear all window buttons
func clear_all_buttons() -> void:
	for window in _window_buttons.keys():
		remove_window_button(window)


## Update button widths based on available space
func _update_button_widths() -> void:
	if not button_container:
		return
	
	var button_count := _window_buttons.size()
	if button_count == 0:
		return
	
	# Calculate available width
	var available_width := button_container.size.x
	var ideal_width := available_width / button_count
	
	# Clamp to min/max
	var button_width := clampf(ideal_width, button_min_width, button_max_width)
	
	# Apply to all buttons
	for button in _window_buttons.values():
		if is_instance_valid(button):
			button.custom_minimum_size.x = button_width


## Handle window button press
func _on_window_button_pressed(window: Control) -> void:
	window_button_clicked.emit(window)
