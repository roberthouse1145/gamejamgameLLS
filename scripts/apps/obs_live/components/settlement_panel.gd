class_name SettlementPanel extends Control
## 下播结算面板：展示预结算结果，玩家确认后落账。

signal finish_pressed()

const COLOR_BG: Color = Color(0.94, 0.96, 0.98, 0.92)
const COLOR_CARD: Color = Color("#FFFFFF")
const COLOR_BORDER: Color = Color("#C8D6EA")
const COLOR_TEXT: Color = Color("#1A2238")
const COLOR_SECONDARY: Color = Color("#5A6885")
const COLOR_ACCENT: Color = Color("#E5486D")

var _rows_box: VBoxContainer = null


func _ready() -> void:
	visible = false
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(1100, 0)
	card.add_theme_stylebox_override("panel", _make_style(COLOR_CARD, COLOR_BORDER, 24))
	center.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_bottom", 50)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 26)
	margin.add_child(column)
	var title := _make_label("直播结算", 44, COLOR_TEXT)
	column.add_child(title)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 18)
	column.add_child(_rows_box)
	var finish_button := Button.new()
	finish_button.custom_minimum_size = Vector2(420, 92)
	finish_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	finish_button.text = "下播"
	finish_button.add_theme_font_size_override("font_size", 30)
	finish_button.add_theme_color_override("font_color", Color.WHITE)
	finish_button.add_theme_stylebox_override("normal", _make_style(COLOR_ACCENT, COLOR_ACCENT, 18))
	finish_button.add_theme_stylebox_override("hover", _make_style(Color("#F05D7E"), COLOR_ACCENT, 18))
	finish_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	finish_button.pressed.connect(func() -> void: finish_pressed.emit())
	column.add_child(finish_button)


func show_result(plan: StreamPlanSnapshot, result: StreamSettlementResult) -> void:
	for child: Node in _rows_box.get_children():
		child.queue_free()
	if result == null:
		return
	_add_row("《%s》" % (plan.title if plan != null else ""), COLOR_SECONDARY, 26)
	_add_row("峰值在线　%d 人" % result.peak_viewers, COLOR_TEXT, 32)
	_add_row("新增粉丝　%+d" % result.fan_delta, COLOR_TEXT, 32)
	_add_row("打赏收益　¥%d" % result.revenue, COLOR_TEXT, 32)
	_add_row("事故　%s" % ("发生了直播事故" if result.accident_occurred else "无"), COLOR_ACCENT if result.accident_occurred else COLOR_TEXT, 32)
	if result.sponsor_payout > 0:
		_add_row("商单结算　¥%d（%s）" % [result.sponsor_payout, "满意度达标" if result.sponsor_satisfied else "满意度未达标"], COLOR_SECONDARY, 26)
	_add_row("压力　%+d　·　主播 EXP +%d" % [result.stress_delta, result.streamer_exp_gain], COLOR_SECONDARY, 26)
	visible = true
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.35)


func _add_row(text_value: String, color: Color, font_size: int) -> void:
	_rows_box.add_child(_make_label(text_value, font_size, color))


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_style(bg_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
