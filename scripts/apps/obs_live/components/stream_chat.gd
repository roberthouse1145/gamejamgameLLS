class_name StreamChat extends Control
## 直播页右侧弹幕栏。与播放器并列，不遮挡直播内容。

signal screen_chat_toggled(enabled: bool)
signal donation_animation_toggled(enabled: bool)

const COLOR_PANEL: Color = Color("#FFFDFC")
const COLOR_BORDER: Color = Color("#C8D5E5")
const COLOR_HEADER: Color = Color("#F2F7FE")
const COLOR_FOOTER: Color = Color("#F8FAFD")
const COLOR_TEXT: Color = Color("#20283A")
const COLOR_SYSTEM: Color = Color("#8793A5")
const COLOR_FAMILY: Color = Color("#4A76B9")
const COLOR_LIVE: Color = Color("#E5486D")
const COLOR_TOGGLE_ACTIVE_BG: Color = Color("#E8F2FF")
const COLOR_TOGGLE_ACTIVE_BORDER: Color = Color("#7FA4D8")
const COLOR_TOGGLE_INACTIVE_BG: Color = Color("#FFFFFF")
const COLOR_TOGGLE_INACTIVE_BORDER: Color = Color("#D5E0EE")
const COLOR_TOGGLE_INACTIVE_TEXT: Color = Color("#768196")

const SC_COLORS: Array[Color] = [
	Color("#4A90D9"),
	Color("#E67E22"),
	Color("#C0392B"),
	Color("#8E44AD"),
]

const MAX_ENTRIES: int = 80

var _entries_box: VBoxContainer = null
var _scroll: ScrollContainer = null
var _empty_label: Label = null
var _screen_chat_button: Button = null
var _donation_animation_button: Button = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_theme_stylebox_override("panel", _make_style(COLOR_PANEL, COLOR_BORDER, 24))
	add_child(card)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	card.add_child(root)

	var header := PanelContainer.new()
	header.custom_minimum_size.y = 92
	header.add_theme_stylebox_override("panel", _make_header_style())
	root.add_child(header)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 26)
	header_margin.add_theme_constant_override("margin_right", 26)
	header.add_child(header_margin)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 16)
	header_margin.add_child(header_row)

	var header_label := Label.new()
	header_label.text = "直播弹幕"
	header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_label.add_theme_font_size_override("font_size", 34)
	header_label.add_theme_color_override("font_color", COLOR_FAMILY)
	header_row.add_child(header_label)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_spacer)

	var status_badge := PanelContainer.new()
	status_badge.custom_minimum_size = Vector2(112, 52)
	status_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_badge.add_theme_stylebox_override("panel", _make_live_badge_style())
	header_row.add_child(status_badge)
	var status_label := Label.new()
	status_label.text = "实时"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 26)
	status_label.add_theme_color_override("font_color", COLOR_LIVE)
	status_badge.add_child(status_label)

	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 22)
	body_margin.add_theme_constant_override("margin_top", 20)
	body_margin.add_theme_constant_override("margin_right", 22)
	body_margin.add_theme_constant_override("margin_bottom", 20)
	root.add_child(body_margin)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_margin.add_child(_scroll)

	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_box.add_theme_constant_override("separation", 14)
	_scroll.add_child(_entries_box)

	var empty_center := CenterContainer.new()
	empty_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_margin.add_child(empty_center)
	_empty_label = Label.new()
	_empty_label.text = "弹幕会显示在这里"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 28)
	_empty_label.add_theme_color_override("font_color", COLOR_SYSTEM)
	empty_center.add_child(_empty_label)

	var footer := PanelContainer.new()
	footer.custom_minimum_size.y = 84
	footer.add_theme_stylebox_override("panel", _make_footer_style())
	root.add_child(footer)
	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 26)
	footer_margin.add_theme_constant_override("margin_top", 14)
	footer_margin.add_theme_constant_override("margin_right", 26)
	footer_margin.add_theme_constant_override("margin_bottom", 14)
	footer.add_child(footer_margin)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 14)
	footer_margin.add_child(footer_row)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer_row.add_child(footer_spacer)
	_screen_chat_button = _make_toggle_button("视频弹幕")
	_screen_chat_button.toggled.connect(_on_screen_chat_toggled)
	footer_row.add_child(_screen_chat_button)
	_donation_animation_button = _make_toggle_button("打赏特效")
	_donation_animation_button.toggled.connect(_on_donation_animation_toggled)
	footer_row.add_child(_donation_animation_button)
	set_reaction_settings(true, true)


func set_reaction_settings(screen_chat_enabled: bool, donation_animation_enabled: bool) -> void:
	if _screen_chat_button != null:
		_screen_chat_button.set_pressed_no_signal(screen_chat_enabled)
		_refresh_toggle_button(_screen_chat_button)
	if _donation_animation_button != null:
		_donation_animation_button.set_pressed_no_signal(donation_animation_enabled)
		_refresh_toggle_button(_donation_animation_button)


func _on_screen_chat_toggled(enabled: bool) -> void:
	_refresh_toggle_button(_screen_chat_button)
	screen_chat_toggled.emit(enabled)


func _on_donation_animation_toggled(enabled: bool) -> void:
	_refresh_toggle_button(_donation_animation_button)
	donation_animation_toggled.emit(enabled)


func clear() -> void:
	if _entries_box == null:
		return
	for child: Node in _entries_box.get_children():
		_entries_box.remove_child(child)
		child.queue_free()
	if _empty_label != null:
		_empty_label.visible = true


func push_entries(entries: Array) -> void:
	for entry: Variant in entries:
		if entry is Dictionary:
			_add_entry(String(entry.get("text", "")))
	_scroll_to_bottom()


func push_system(text: String) -> void:
	_show_content()
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 27)
	label.add_theme_color_override("font_color", COLOR_SYSTEM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entries_box.add_child(label)
	_trim_entries()
	_scroll_to_bottom()


func push_sc(entry: Dictionary) -> void:
	var text: String = String(entry.get("text", "")).strip_edges()
	if text.is_empty():
		return
	_show_content()
	var color: Color = _read_superchat_color(entry.get("color", null))

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_sc_style(color))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 34)
	label.add_theme_font_size_override("bold_font_size", 34)
	label.add_theme_color_override("default_color", Color.WHITE)
	label.text = text
	margin.add_child(label)

	_entries_box.add_child(panel)
	_trim_entries()
	_scroll_to_bottom()


func handle_live_chat_event(event: Dictionary) -> void:
	match String(event.get("kind", "")):
		"send":
			push_entries(event.get("entries", []))
		"sc":
			push_sc(event)


func _read_superchat_color(value: Variant) -> Color:
	if value is Color:
		return value
	return SC_COLORS[_rng.randi_range(0, SC_COLORS.size() - 1)]

func _add_entry(text: String) -> void:
	if text.is_empty():
		return
	_show_content()
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 32)
	label.add_theme_font_size_override("bold_font_size", 32)
	label.add_theme_color_override("default_color", COLOR_TEXT)
	label.text = text
	_entries_box.add_child(label)
	_trim_entries()


func _show_content() -> void:
	if _empty_label != null:
		_empty_label.visible = false


func _trim_entries() -> void:
	while _entries_box.get_child_count() > MAX_ENTRIES:
		var oldest: Node = _entries_box.get_child(0)
		_entries_box.remove_child(oldest)
		oldest.queue_free()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _make_toggle_button(label_text: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(220.0, 56.0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta("label_text", label_text)
	button.add_theme_font_size_override("font_size", 24)
	return button


func _refresh_toggle_button(button: Button) -> void:
	if button == null:
		return
	var enabled: bool = button.button_pressed
	var label_text: String = str(button.get_meta("label_text", ""))
	button.text = "%s  %s" % [label_text, "开" if enabled else "关"]
	button.tooltip_text = "%s已%s，点击%s" % [
		label_text,
		"开启" if enabled else "关闭",
		"关闭" if enabled else "开启",
	]
	var text_color: Color = COLOR_FAMILY if enabled else COLOR_TOGGLE_INACTIVE_TEXT
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", COLOR_FAMILY)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_stylebox_override("normal", _make_toggle_style(enabled, false, false))
	button.add_theme_stylebox_override("hover", _make_toggle_style(enabled, true, false))
	button.add_theme_stylebox_override("pressed", _make_toggle_style(true, false, false))
	button.add_theme_stylebox_override("focus", _make_toggle_style(enabled, false, true))


func _make_toggle_style(enabled: bool, hovered: bool, focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_TOGGLE_ACTIVE_BG if enabled else COLOR_TOGGLE_INACTIVE_BG
	style.border_color = COLOR_TOGGLE_ACTIVE_BORDER if enabled else COLOR_TOGGLE_INACTIVE_BORDER
	if hovered:
		style.bg_color = style.bg_color.lightened(0.025) if enabled else Color("#F5F8FC")
	if focused:
		style.border_color = COLOR_FAMILY
	var border_width: int = 3 if focused else 2
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 28
	style.corner_radius_top_right = 28
	style.corner_radius_bottom_left = 28
	style.corner_radius_bottom_right = 28
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	return style


func _make_style(bg_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = border_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(0.10, 0.16, 0.26, 0.1)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 3)
	return style


func _make_header_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_HEADER
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.border_width_bottom = 2
	style.border_color = COLOR_BORDER
	return style


func _make_footer_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_FOOTER
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	style.border_width_top = 2
	style.border_color = COLOR_BORDER
	return style


func _make_live_badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFF0F4")
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#EAB7C4")
	style.corner_radius_top_left = 22
	style.corner_radius_top_right = 22
	style.corner_radius_bottom_left = 22
	style.corner_radius_bottom_right = 22
	return style


func _make_sc_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	return style
