class_name BalanceDebugPanel
extends PanelContainer

const STAT_ROWS: Array[Dictionary] = [
	{"label": "压力", "key": "stress", "step": 5, "min": 0, "max": 100},
	{"label": "热情", "key": "passion", "step": 5, "min": 0, "max": 100},
	{"label": "金钱", "key": "money", "step": 100, "min": 0, "max": 9999},
]

var _status_label: Label = null
var _value_labels: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4096
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -360.0
	offset_right = -16.0
	offset_top = 90.0
	offset_bottom = 430.0
	_build_ui()
	_connect_runtime_signals()
	_refresh()


func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.92)
	style.border_color = Color(0.3, 0.4, 0.65, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	var title := Label.new()
	title.text = "Balance Debug"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color("#C9D4F2"))
	col.add_child(_status_label)

	for row_data in STAT_ROWS:
		col.add_child(_make_stat_row(row_data))

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 6)
	col.add_child(preset_row)
	preset_row.add_child(_make_preset_button("默认", 5, 70, 500))
	preset_row.add_child(_make_preset_button("强制睡", 85, 70, 500))
	preset_row.add_child(_make_preset_button("低热情", 40, 20, 500))

	var hint := RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	hint.scroll_active = false
	hint.text = "[b]使用方式[/b]\n这里只改数值，不触发任何行动。\n请从桌面 APP 图标真实点击验证：Dev Work / Part Time / Community / Sleep / Map / SBEAM。"
	hint.add_theme_font_size_override("normal_font_size", 12)
	hint.add_theme_color_override("default_color", Color("#DDE6FF"))
	col.add_child(hint)


func _make_stat_row(row_data: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var key := str(row_data.get("key", ""))
	var step := int(row_data.get("step", 1))

	var label := Label.new()
	label.text = str(row_data.get("label", key))
	label.custom_minimum_size.x = 42
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#DDE6FF"))
	row.add_child(label)

	var minus := Button.new()
	minus.text = "-%d" % step
	minus.custom_minimum_size = Vector2(56, 30)
	minus.pressed.connect(func() -> void: _adjust_stat(key, -step))
	row.add_child(minus)

	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.custom_minimum_size.x = 54
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", Color.WHITE)
	_value_labels[key] = value
	row.add_child(value)

	var plus := Button.new()
	plus.text = "+%d" % step
	plus.custom_minimum_size = Vector2(56, 30)
	plus.pressed.connect(func() -> void: _adjust_stat(key, step))
	row.add_child(plus)

	return row


func _make_preset_button(text: String, stress: int, passion: int, money: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(70, 30)
	button.pressed.connect(func() -> void: _set_stats(stress, passion, money))
	return button


func _connect_runtime_signals() -> void:
	var gm := _gm()
	if gm != null and gm.has_signal("stats_changed"):
		gm.stats_changed.connect(_refresh)
	var glm := _glm()
	if glm != null:
		if glm.has_signal("ap_changed"):
			glm.ap_changed.connect(func(_current: int, _max_ap: int) -> void: _refresh())
		if glm.has_signal("phase_changed"):
			glm.phase_changed.connect(func(_phase: int) -> void: _refresh())
		if glm.has_signal("day_changed"):
			glm.day_changed.connect(func(_day: int) -> void: _refresh())


func _adjust_stat(stat_key: String, delta: int) -> void:
	var gm := _gm()
	if gm == null or not gm.has_method("modify_stat"):
		return
	gm.modify_stat(stat_key, delta)
	_refresh()


func _set_stats(stress: int, passion: int, money: int) -> void:
	var gm := _gm()
	if gm == null:
		return
	gm.set("stress", stress)
	gm.set("passion", passion)
	gm.set("money", money)
	_refresh()


func _refresh() -> void:
	var gm := _gm()
	var glm := _glm()
	if gm == null or glm == null:
		if _status_label != null:
			_status_label.text = "Autoload 未就绪"
		return

	if _status_label != null:
		_status_label.text = "Day %d · %s · AP %d/%d" % [
			int(glm.get("current_day")),
			str(glm.get_phase_name(glm.get("time_phase"))),
			int(glm.get("current_ap")),
			int(glm.get("max_ap_per_day")),
		]

	for row_data in STAT_ROWS:
		var key := str(row_data.get("key", ""))
		var label: Label = _value_labels.get(key, null)
		if label != null:
			label.text = str(int(gm.get(key)))


func _gm() -> Node:
	return get_node_or_null("/root/GameManager")


func _glm() -> Node:
	return get_node_or_null("/root/GameLoopManager")
