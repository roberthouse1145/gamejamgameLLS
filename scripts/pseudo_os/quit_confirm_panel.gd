class_name QuitConfirmPanel extends VBoxContainer
## 退出确认面板 - 作为 PseudoWindow 的内容显示

signal confirmed
signal cancelled

const TEXT_COLOR: Color = Color("#1A1D27")
const TEXT_DIM: Color = Color("#6B7086")
const ACCENT: Color = Color("#4A7CFF")
const DANGER: Color = Color("#E53E3E")
const BG_COLOR: Color = Color("#FFFFFF")
const FONT_SIZE: int = 22
const BTN_FONT_SIZE: int = 20


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var bg := StyleBoxFlat.new()
	bg.bg_color = BG_COLOR
	bg.content_margin_left = 40
	bg.content_margin_right = 40
	bg.content_margin_top = 40
	bg.content_margin_bottom = 40
	var panel_wrap := PanelContainer.new()
	panel_wrap.add_theme_stylebox_override("panel", bg)
	panel_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(panel_wrap)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 24)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_wrap.add_child(inner)

	# 图标
	var icon_label := Label.new()
	icon_label.text = "⏻"
	icon_label.add_theme_font_size_override("font_size", 48)
	icon_label.add_theme_color_override("font_color", DANGER)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(icon_label)

	# 提示文字
	var msg := Label.new()
	msg.text = "确定要关闭电源吗？"
	msg.add_theme_font_size_override("font_size", FONT_SIZE)
	msg.add_theme_color_override("font_color", TEXT_COLOR)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(msg)

	var sub_msg := Label.new()
	sub_msg.text = "所有未保存的进度将会丢失。"
	sub_msg.add_theme_font_size_override("font_size", 18)
	sub_msg.add_theme_color_override("font_color", TEXT_DIM)
	sub_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(sub_msg)

	# 按钮行
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 20)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(140, 48)
	_style_button(cancel_btn, Color("#EEF2F8"), TEXT_COLOR)
	cancel_btn.pressed.connect(func() -> void: cancelled.emit())
	btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "关闭电源"
	confirm_btn.custom_minimum_size = Vector2(140, 48)
	_style_button(confirm_btn, DANGER, Color.WHITE)
	confirm_btn.pressed.connect(func() -> void: confirmed.emit())
	btn_row.add_child(confirm_btn)


func _style_button(btn: Button, bg_color: Color, font_color: Color) -> void:
	btn.flat = false
	btn.add_theme_font_size_override("font_size", BTN_FONT_SIZE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg_color.darkened(0.1)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)
	btn.add_theme_color_override("font_pressed_color", font_color)
