class_name Taskbar extends Panel
## Taskbar component showing running application window buttons.

const WindowIconRendererClass = preload("res://scripts/ui/window_icon_renderer.gd")

const T_SURFACE: Color = Color("#FFFFFF")
const T_SURFACE_ALT: Color = Color("#EEF2F8")
const T_TEXT: Color = Color("#1A1D27")
const T_TEXT_DIM: Color = Color("#6B7086")
const T_ACCENT: Color = Color("#4A7CFF")
const T_TOP_EDGE: Color = Color("#B8C4D8")

const TASKBAR_HEIGHT: float = 76.0
const START_BUTTON_MIN_WIDTH: float = 72.0
const PHASE_FONT_SIZE: int = 24
const CLOCK_MIN_WIDTH: float = 240.0

signal window_button_clicked(window: Control)
signal start_button_clicked

@onready var button_container: HBoxContainer = %ButtonContainer

var _window_buttons: Dictionary = {}
var _game_loop: Node = null

@export var button_min_width: float = 160.0
@export var button_max_width: float = 240.0


func _ready() -> void:
	if button_container == null:
		push_error("Taskbar: ButtonContainer not found")
		return
	_apply_theme()
	_bind_game_loop()
	_update_phase_label()
	_bind_start_button()


func _bind_start_button() -> void:
	var start_btn := get_node_or_null("HBoxContainer/StartButton") as Button
	if start_btn and not start_btn.pressed.is_connected(_on_start_button_pressed):
		start_btn.pressed.connect(_on_start_button_pressed)


func _on_start_button_pressed() -> void:
	start_button_clicked.emit()


## 获取 StartButton 的全局位置（供开始菜单定位）
func get_start_button_global_position() -> Vector2:
	var start_btn := get_node_or_null("HBoxContainer/StartButton") as Button
	if start_btn:
		return start_btn.global_position
	return global_position


func _apply_theme() -> void:
	custom_minimum_size.y = TASKBAR_HEIGHT

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = T_SURFACE_ALT
	panel_style.border_width_top = 2
	panel_style.border_color = T_TOP_EDGE
	panel_style.shadow_color = Color(0.44, 0.49, 0.58, 0.16)
	panel_style.shadow_size = 10
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	add_theme_stylebox_override("panel", panel_style)

	var root := get_node_or_null("HBoxContainer") as HBoxContainer
	if root != null:
		root.add_theme_constant_override("separation", 10)

	var start_btn := get_node_or_null("HBoxContainer/StartButton") as Button
	if start_btn != null:
		start_btn.custom_minimum_size.x = START_BUTTON_MIN_WIDTH
		start_btn.flat = false
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color.TRANSPARENT
		normal.corner_radius_top_left = 10
		normal.corner_radius_top_right = 10
		normal.corner_radius_bottom_left = 10
		normal.corner_radius_bottom_right = 10
		normal.content_margin_left = 14
		normal.content_margin_right = 14
		normal.content_margin_top = 8
		normal.content_margin_bottom = 8
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color("#DFE6F1")
		start_btn.add_theme_stylebox_override("normal", normal)
		start_btn.add_theme_stylebox_override("hover", hover)
		start_btn.add_theme_stylebox_override("pressed", hover)
		start_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		start_btn.add_theme_color_override("font_color", T_TEXT)
		start_btn.add_theme_color_override("font_hover_color", T_ACCENT)
		start_btn.add_theme_color_override("font_pressed_color", T_ACCENT)
		start_btn.add_theme_color_override("font_focus_color", T_TEXT)
		start_btn.add_theme_color_override("font_hover_pressed_color", T_ACCENT)
		start_btn.add_theme_font_size_override("font_size", 26)
		# 用代码绘制的汉堡图标替换 ☰ 文字
		start_btn.text = ""
		start_btn.icon = WindowIconRendererClass.create_hamburger_icon(T_TEXT)
		start_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var phase_label := get_node_or_null("HBoxContainer/Clock") as Label
	if phase_label != null:
		phase_label.add_theme_color_override("font_color", T_TEXT_DIM)
		phase_label.add_theme_font_size_override("font_size", PHASE_FONT_SIZE)
		phase_label.custom_minimum_size.x = CLOCK_MIN_WIDTH

	button_container.add_theme_constant_override("separation", 8)


func _style_window_button(button: Button) -> void:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color.TRANSPARENT
	normal_style.corner_radius_top_left = 6
	normal_style.corner_radius_top_right = 6
	normal_style.corner_radius_bottom_left = 6
	normal_style.corner_radius_bottom_right = 6
	normal_style.content_margin_left = 12
	normal_style.content_margin_right = 12
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color("#DFE6F1")

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
	button.add_theme_font_size_override("font_size", 24)
	button.toggle_mode = true


func add_window_button(window: Control, title: String, icon: Texture2D = null) -> void:
	if window == null or not is_instance_valid(window):
		push_warning("Taskbar: Cannot add button for invalid window")
		return
	if _window_buttons.has(window):
		push_warning("Taskbar: Button for window already exists")
		return

	var button := Button.new()
	button.text = title
	button.custom_minimum_size.x = button_min_width
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_style_window_button(button)

	if icon != null:
		button.icon = icon

	button.pressed.connect(_on_window_button_pressed.bind(window))

	button_container.add_child(button)
	_window_buttons[window] = button
	_update_button_widths()


func remove_window_button(window: Control) -> void:
	if not _window_buttons.has(window):
		return

	var button: Button = _window_buttons[window]
	if is_instance_valid(button):
		button.queue_free()

	_window_buttons.erase(window)
	_update_button_widths()


func update_window_button_title(window: Control, title: String) -> void:
	if not _window_buttons.has(window):
		return

	var button: Button = _window_buttons[window]
	if is_instance_valid(button):
		button.text = title


func update_window_button_icon(window: Control, icon: Texture2D) -> void:
	if not _window_buttons.has(window):
		return

	var button: Button = _window_buttons[window]
	if is_instance_valid(button):
		button.icon = icon


func set_window_button_focused(window: Control, focused: bool) -> void:
	if not _window_buttons.has(window):
		return

	var button: Button = _window_buttons[window]
	if is_instance_valid(button):
		button.button_pressed = focused


func set_window_button_minimized(window: Control, minimized: bool) -> void:
	if not _window_buttons.has(window):
		return

	var button: Button = _window_buttons[window]
	if is_instance_valid(button):
		button.modulate.a = 0.7 if minimized else 1.0


func has_window_button(window: Control) -> bool:
	return _window_buttons.has(window)


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


func get_tracked_windows() -> Array:
	return _window_buttons.keys()


func clear_all_buttons() -> void:
	for window in _window_buttons.keys():
		remove_window_button(window)


func _update_button_widths() -> void:
	if button_container == null:
		return

	var button_count := _window_buttons.size()
	if button_count == 0:
		return

	var available_width := button_container.size.x
	var ideal_width := available_width / button_count
	var button_width := clampf(ideal_width, button_min_width, button_max_width)

	for button in _window_buttons.values():
		if is_instance_valid(button):
			button.custom_minimum_size.x = button_width


func _on_window_button_pressed(window: Control) -> void:
	window_button_clicked.emit(window)


func _bind_game_loop() -> void:
	_game_loop = get_node_or_null("/root/GameLoopManager")
	if _game_loop != null and _game_loop.has_signal("phase_changed"):
		if not _game_loop.phase_changed.is_connected(_on_phase_changed):
			_game_loop.phase_changed.connect(_on_phase_changed)
	if _game_loop != null and _game_loop.has_signal("day_changed"):
		if not _game_loop.day_changed.is_connected(_on_day_changed):
			_game_loop.day_changed.connect(_on_day_changed)


func _update_phase_label() -> void:
	var phase_label := get_node_or_null("HBoxContainer/Clock") as Label
	if phase_label == null:
		return
	var day_text := "第1天"
	var phase_text := "上午"
	if _game_loop != null:
		day_text = "第%d天" % int(_game_loop.get("current_day"))
		if _game_loop.has_method("get_phase_display_name"):
			phase_text = str(_game_loop.call("get_phase_display_name", _game_loop.get("time_phase")))
	phase_label.text = "%s · %s" % [day_text, phase_text]


func _on_phase_changed(_phase: int) -> void:
	_update_phase_label()


func _on_day_changed(_day: int) -> void:
	_update_phase_label()
