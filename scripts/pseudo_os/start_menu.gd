class_name StartMenu extends PanelContainer
## 开始菜单弹出面板 - 点击任务栏开始按钮后显示

signal settings_requested
signal power_off_requested

const MENU_WIDTH: float = 260.0
const MENU_ITEM_HEIGHT: float = 56.0
const MENU_PADDING: float = 8.0

const BG_COLOR: Color = Color("#F0F3F8")
const HOVER_COLOR: Color = Color("#DFE6F1")
const TEXT_COLOR: Color = Color("#1A1D27")
const TEXT_DIM_COLOR: Color = Color("#6B7086")
const BORDER_COLOR: Color = Color("#B8C4D8")
const ICON_SIZE: float = 28.0
const FONT_SIZE: int = 22

var _settings_btn: Button
var _power_btn: Button
var _motion_tween: Tween = null


func _ready() -> void:
	visible = false
	_build_ui()
	_apply_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build_ui() -> void:
	custom_minimum_size.x = MENU_WIDTH

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_settings_btn = _create_menu_item("⚙  设置", vbox)
	_settings_btn.pressed.connect(func() -> void:
		close_menu()
		settings_requested.emit()
	)

	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep)

	_power_btn = _create_menu_item("⏻  关闭电源", vbox)
	_power_btn.pressed.connect(func() -> void:
		close_menu()
		power_off_requested.emit()
	)


func _create_menu_item(label_text: String, parent: Control) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size.y = MENU_ITEM_HEIGHT
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	parent.add_child(btn)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.TRANSPARENT
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = HOVER_COLOR
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", TEXT_COLOR)
	btn.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	btn.add_theme_font_size_override("font_size", FONT_SIZE)
	return btn


func _apply_theme() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = BG_COLOR
	panel.corner_radius_top_left = 12
	panel.corner_radius_top_right = 12
	panel.corner_radius_bottom_left = 0
	panel.corner_radius_bottom_right = 0
	panel.border_width_top = 1
	panel.border_width_left = 1
	panel.border_width_right = 1
	panel.border_color = BORDER_COLOR
	panel.shadow_color = Color(0.0, 0.0, 0.0, 0.12)
	panel.shadow_size = 16
	panel.content_margin_left = MENU_PADDING
	panel.content_margin_right = MENU_PADDING
	panel.content_margin_top = MENU_PADDING
	panel.content_margin_bottom = MENU_PADDING
	add_theme_stylebox_override("panel", panel)


func toggle_menu(anchor_global_pos: Vector2) -> void:
	if visible:
		close_menu()
	else:
		open_menu(anchor_global_pos)


func open_menu(anchor_global_pos: Vector2) -> void:
	_kill_motion_tween()
	visible = true
	scale = Vector2.ONE
	modulate.a = 1.0
	reset_size()
	var menu_size := get_combined_minimum_size()
	menu_size.x = maxf(menu_size.x, MENU_WIDTH)
	size = menu_size
	global_position = Vector2(
		anchor_global_pos.x,
		anchor_global_pos.y - menu_size.y
	)
	# 打开动画
	pivot_offset = Vector2(0, menu_size.y)
	scale = Vector2(1.0, 0.0)
	modulate.a = 0.0
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_CUBIC)
	_motion_tween.set_ease(Tween.EASE_OUT)
	_motion_tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.14)
	_motion_tween.parallel().tween_property(self, "modulate:a", 1.0, 0.10)
	_motion_tween.finished.connect(func() -> void:
		_motion_tween = null
	)


func close_menu() -> void:
	if not visible:
		return
	_kill_motion_tween()
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_CUBIC)
	_motion_tween.set_ease(Tween.EASE_IN)
	_motion_tween.parallel().tween_property(self, "scale", Vector2(1.0, 0.0), 0.10)
	_motion_tween.parallel().tween_property(self, "modulate:a", 0.0, 0.08)
	_motion_tween.finished.connect(func() -> void:
		visible = false
		scale = Vector2.ONE
		modulate.a = 1.0
		_motion_tween = null
	)


func _kill_motion_tween() -> void:
	if _motion_tween != null and is_instance_valid(_motion_tween):
		_motion_tween.kill()
		_motion_tween = null


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not get_global_rect().has_point(get_global_mouse_position()):
				close_menu()
				get_viewport().set_input_as_handled()
