class_name SettlementPanel extends Control
## 全屏直播结算。视觉沿用游戏桌面的浅色、圆角与蓝色描边体系。

signal finish_pressed()
signal crisis_choice_made(choice_id: String)

const FAN_CHART_SCENE: PackedScene = preload(
	"res://scenes/apps/obs_live/components/fan_composition_chart.tscn"
)
const AVATAR_SCENE: PackedScene = preload("res://scenes/ui/rounded_avatar.tscn")

## 3840×2160 设计画布字号：正文不低于 28，核心数字不低于 54。
const FONT_PAGE_TITLE: int = 64
const FONT_SECTION_TITLE: int = 40
const FONT_CARD_TITLE: int = 32
const FONT_BODY: int = 29
const FONT_CAPTION: int = 26
const FONT_METRIC: int = 58
const FONT_BUTTON: int = 34

const COLOR_BG: Color = Color("#F4F8FD")
const COLOR_BG_BAND: Color = Color("#E7F0FC")
const COLOR_SURFACE: Color = Color("#FFFDFC")
const COLOR_SURFACE_BLUE: Color = Color("#F2F7FE")
const COLOR_BORDER: Color = Color("#C8D5E5")
const COLOR_BORDER_STRONG: Color = Color("#AFC5E2")
const COLOR_TEXT: Color = Color("#20283A")
const COLOR_SECONDARY: Color = Color("#68738A")
const COLOR_MUTED: Color = Color("#8793A5")
const COLOR_PRIMARY: Color = Color("#5E91D9")
const COLOR_PRIMARY_HOVER: Color = Color("#76A9F0")
const COLOR_PRIMARY_PRESSED: Color = Color("#4B7FC8")
const COLOR_PINK: Color = Color("#E5486D")
const COLOR_PINK_SOFT: Color = Color("#FFF0F4")
const COLOR_AMBER: Color = Color("#B86E16")
const COLOR_GREEN: Color = Color("#3D9A76")
const COLOR_PURPLE: Color = Color("#7468C8")
const COLOR_DANGER: Color = Color("#C94C62")

## 与频道总览中的观众构成配色保持一致。
const FAN_GROUPS: Array[Dictionary] = [
	{"key": "r", "label": "路人", "color": Color("#909FBA")},
	{"key": "m", "label": "男粉", "color": Color("#5FA4EE")},
	{"key": "w", "label": "女粉", "color": Color("#ED739F")},
	{"key": "c", "label": "核心粉", "color": Color("#4FC3A5")},
	{"key": "b", "label": "黑粉", "color": Color("#404756")},
]

const CRISIS_OPTIONS: Array = [
	["respond", "发动态回应"],
	["cold", "冷处理"],
	["ignore", "装死"],
	["apologize", "公开道歉"],
]

var _avatar: Control = null
var _streamer_name: Label = null
var _stream_title: Label = null
var _revenue_value: Label = null
var _revenue_detail: Label = null
var _viewer_value: Label = null
var _viewer_detail: Label = null
var _fan_delta_value: Label = null
var _fan_delta_detail: Label = null
var _exp_value: Label = null
var _exp_detail: Label = null
var _support_revenue: Label = null
var _sponsor_revenue: Label = null
var _stress_change: Label = null
var _accident_status: Label = null
var _contract_status: Label = null
var _fan_chart: Control = null
var _fan_legend: VBoxContainer = null
var _fan_summary: Label = null
var _crisis_panel: PanelContainer = null
var _crisis_status: Label = null
var _crisis_buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_screen()


func _build_screen() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var header_band := ColorRect.new()
	header_band.color = COLOR_BG_BAND
	header_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header_band.offset_bottom = 310.0
	header_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header_band)

	var top_line := ColorRect.new()
	top_line.color = COLOR_PRIMARY
	top_line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_line.offset_bottom = 8.0
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_line)

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 72)
	outer_margin.add_theme_constant_override("margin_top", 56)
	outer_margin.add_theme_constant_override("margin_right", 72)
	outer_margin.add_theme_constant_override("margin_bottom", 54)
	add_child(outer_margin)

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 30)
	outer_margin.add_child(page)

	_build_header(page)
	_build_body(page)
	_build_footer(page)


func _build_header(parent: VBoxContainer) -> void:
	var header := PanelContainer.new()
	header.custom_minimum_size.y = 208.0
	header.add_theme_stylebox_override(
		"panel", _make_style(COLOR_SURFACE, COLOR_BORDER, 24, 2, 34, 10)
	)
	parent.add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	header.add_child(row)

	_avatar = AVATAR_SCENE.instantiate() as Control
	_avatar.custom_minimum_size = Vector2(134, 134)
	_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_avatar)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_theme_constant_override("separation", 8)
	row.add_child(heading)
	heading.add_child(_make_label("直播结算", FONT_PAGE_TITLE, COLOR_TEXT))
	_stream_title = _make_label("", FONT_CARD_TITLE, COLOR_SECONDARY)
	_stream_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_stream_title)
	_streamer_name = _make_label("", FONT_CAPTION, COLOR_PRIMARY)
	heading.add_child(_streamer_name)

	var ended_badge := PanelContainer.new()
	ended_badge.custom_minimum_size = Vector2(210, 72)
	ended_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ended_badge.add_theme_stylebox_override(
		"panel", _make_style(COLOR_PINK_SOFT, Color("#EAB7C4"), 24, 2, 18)
	)
	row.add_child(ended_badge)
	var ended_label := _make_label("已下播", FONT_BODY, COLOR_PINK)
	ended_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ended_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ended_badge.add_child(ended_label)


func _build_body(parent: VBoxContainer) -> void:
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 30)
	parent.add_child(body)
	_build_result_column(body)
	_build_fan_panel(body)


func _build_result_column(parent: HBoxContainer) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.45
	column.add_theme_constant_override("separation", 24)
	parent.add_child(column)

	var metrics_grid := GridContainer.new()
	metrics_grid.columns = 4
	metrics_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics_grid.add_theme_constant_override("h_separation", 20)
	column.add_child(metrics_grid)

	var revenue_card: Dictionary = _make_metric_card("本场收益", COLOR_AMBER)
	metrics_grid.add_child(revenue_card["panel"])
	_revenue_value = revenue_card["value"] as Label
	_revenue_detail = revenue_card["detail"] as Label

	var viewer_card: Dictionary = _make_metric_card("峰值观看", COLOR_PRIMARY)
	metrics_grid.add_child(viewer_card["panel"])
	_viewer_value = viewer_card["value"] as Label
	_viewer_detail = viewer_card["detail"] as Label

	var fan_card: Dictionary = _make_metric_card("新增粉丝", COLOR_GREEN)
	metrics_grid.add_child(fan_card["panel"])
	_fan_delta_value = fan_card["value"] as Label
	_fan_delta_detail = fan_card["detail"] as Label

	var exp_card: Dictionary = _make_metric_card("主播经验", COLOR_PURPLE)
	metrics_grid.add_child(exp_card["panel"])
	_exp_value = exp_card["value"] as Label
	_exp_detail = exp_card["detail"] as Label

	var details_card := PanelContainer.new()
	details_card.custom_minimum_size.y = 440.0
	details_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_card.add_theme_stylebox_override(
		"panel", _make_style(COLOR_SURFACE, COLOR_BORDER, 24, 2, 36, 8)
	)
	column.add_child(details_card)

	var details_column := VBoxContainer.new()
	details_column.add_theme_constant_override("separation", 26)
	details_card.add_child(details_column)
	details_column.add_child(_make_label("结算明细", FONT_SECTION_TITLE, COLOR_TEXT))

	var detail_groups := HBoxContainer.new()
	detail_groups.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_groups.add_theme_constant_override("separation", 42)
	details_column.add_child(detail_groups)

	var income_group := VBoxContainer.new()
	income_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	income_group.add_theme_constant_override("separation", 24)
	detail_groups.add_child(income_group)
	income_group.add_child(_make_label("收益构成", FONT_CARD_TITLE, COLOR_PRIMARY))
	_support_revenue = _make_value_row(income_group, "观众支持")
	_sponsor_revenue = _make_value_row(income_group, "商单收益")

	var divider := ColorRect.new()
	divider.custom_minimum_size.x = 2.0
	divider.color = Color("#D8E3F0")
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_groups.add_child(divider)

	var state_group := VBoxContainer.new()
	state_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_group.add_theme_constant_override("separation", 24)
	detail_groups.add_child(state_group)
	state_group.add_child(_make_label("状态变化", FONT_CARD_TITLE, COLOR_PRIMARY))
	_stress_change = _make_value_row(state_group, "压力变化")
	_accident_status = _make_value_row(state_group, "直播状态")
	_contract_status = _make_value_row(state_group, "剩余债务")

	_build_crisis_panel(column)


func _build_fan_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 1040.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.82
	panel.add_theme_stylebox_override(
		"panel", _make_style(COLOR_SURFACE, COLOR_BORDER, 24, 2, 38, 8)
	)
	parent.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(_make_label("粉丝构成", FONT_SECTION_TITLE, COLOR_TEXT))
	column.add_child(_make_label("本场结算后的粉丝占比", FONT_CAPTION, COLOR_SECONDARY))

	var chart_row := HBoxContainer.new()
	chart_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chart_row.add_theme_constant_override("separation", 44)
	column.add_child(chart_row)

	_fan_chart = FAN_CHART_SCENE.instantiate() as Control
	_fan_chart.custom_minimum_size = Vector2(470, 470)
	_fan_chart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fan_chart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chart_row.add_child(_fan_chart)

	_fan_legend = VBoxContainer.new()
	_fan_legend.custom_minimum_size.x = 310.0
	_fan_legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fan_legend.add_theme_constant_override("separation", 22)
	chart_row.add_child(_fan_legend)

	_add_horizontal_rule(column)
	_fan_summary = _make_label("", FONT_BODY, COLOR_SECONDARY)
	_fan_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fan_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_fan_summary)


func _build_crisis_panel(parent: VBoxContainer) -> void:
	_crisis_panel = PanelContainer.new()
	_crisis_panel.visible = false
	_crisis_panel.add_theme_stylebox_override(
		"panel", _make_style(COLOR_PINK_SOFT, Color("#EAB7C4"), 24, 2, 28, 5)
	)
	parent.add_child(_crisis_panel)

	var crisis_column := VBoxContainer.new()
	crisis_column.add_theme_constant_override("separation", 18)
	_crisis_panel.add_child(crisis_column)
	crisis_column.add_child(_make_label("舆情处理", FONT_CARD_TITLE, COLOR_DANGER))
	crisis_column.add_child(
		_make_label("负面讨论仍在发酵，选择本场直播后的处理方式。", FONT_CAPTION, COLOR_SECONDARY)
	)

	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	crisis_column.add_child(choices)
	for option: Array in CRISIS_OPTIONS:
		var choice_button := Button.new()
		choice_button.text = String(option[1])
		choice_button.custom_minimum_size = Vector2(230, 82)
		choice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice_button.add_theme_font_size_override("font_size", FONT_BODY)
		choice_button.add_theme_color_override("font_color", COLOR_TEXT)
		choice_button.add_theme_color_override("font_hover_color", COLOR_TEXT)
		choice_button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
		choice_button.add_theme_color_override("font_disabled_color", COLOR_MUTED)
		choice_button.add_theme_stylebox_override(
			"normal", _make_style(COLOR_SURFACE, Color("#D8A9B5"), 20, 2, 16)
		)
		choice_button.add_theme_stylebox_override(
			"hover", _make_style(Color("#FFE5EC"), COLOR_PINK, 20, 2, 16, 5)
		)
		choice_button.add_theme_stylebox_override(
			"pressed", _make_style(Color("#FBD5DF"), COLOR_PINK, 20, 2, 16)
		)
		choice_button.add_theme_stylebox_override(
			"disabled", _make_style(Color("#F2EEF0"), Color("#D8CFD2"), 20, 2, 16)
		)
		choice_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		choice_button.pressed.connect(_on_crisis_pressed.bind(String(option[0])))
		choices.add_child(choice_button)
		_crisis_buttons.append(choice_button)

	_crisis_status = _make_label("", FONT_CAPTION, COLOR_GREEN)
	_crisis_status.visible = false
	crisis_column.add_child(_crisis_status)


func _build_footer(parent: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 100.0
	footer.add_theme_constant_override("separation", 30)
	parent.add_child(footer)

	var hint := _make_label("确认后，本场结果将计入当前进度。", FONT_CAPTION, COLOR_SECONDARY)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(hint)

	var finish_button := Button.new()
	finish_button.custom_minimum_size = Vector2(430, 96)
	finish_button.text = "确认结算"
	finish_button.add_theme_font_size_override("font_size", FONT_BUTTON)
	finish_button.add_theme_color_override("font_color", Color.WHITE)
	finish_button.add_theme_color_override("font_hover_color", Color.WHITE)
	finish_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	finish_button.add_theme_stylebox_override(
		"normal", _make_style(COLOR_PRIMARY, COLOR_PRIMARY_PRESSED, 24, 2, 18, 7)
	)
	finish_button.add_theme_stylebox_override(
		"hover", _make_style(COLOR_PRIMARY_HOVER, COLOR_PRIMARY, 24, 2, 18, 10)
	)
	finish_button.add_theme_stylebox_override(
		"pressed", _make_style(COLOR_PRIMARY_PRESSED, COLOR_PRIMARY_PRESSED, 24, 2, 18, 3)
	)
	finish_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	finish_button.pressed.connect(func() -> void: finish_pressed.emit())
	footer.add_child(finish_button)


func show_result(plan: StreamPlanSnapshot, result: StreamSettlementResult) -> void:
	if result == null:
		visible = false
		return

	_apply_stream_identity(plan)
	_stream_title.text = "《%s》" % (plan.title if plan != null else "本场直播")
	_revenue_value.text = "¥%d" % result.revenue
	_revenue_detail.text = "含商单 ¥%d" % result.sponsor_payout if result.sponsor_payout > 0 else "来自观众支持"
	_viewer_value.text = "%d" % result.peak_viewers
	_viewer_detail.text = "人同时观看"
	_fan_delta_value.text = "%+d" % result.fan_delta
	_fan_delta_detail.text = "本场新增"
	_exp_value.text = "+%d" % result.streamer_exp_gain
	_exp_detail.text = "EXP"

	var support_revenue: int = maxi(result.revenue - result.sponsor_payout, 0)
	_support_revenue.text = "¥%d" % support_revenue
	_sponsor_revenue.text = (
		"¥%d · %s" % [
			result.sponsor_payout,
			"目标达成" if result.sponsor_satisfied else "目标未达成",
		]
		if result.sponsor_payout > 0
		else "无"
	)
	_stress_change.text = "%+d" % result.stress_delta
	_stress_change.add_theme_color_override(
		"font_color", COLOR_DANGER if result.stress_delta > 0 else COLOR_GREEN
	)
	_accident_status.text = "发生直播事故" if result.accident_occurred else "正常结束"
	_accident_status.add_theme_color_override(
		"font_color", COLOR_DANGER if result.accident_occurred else COLOR_GREEN
	)
	var game_state: Node = get_node_or_null("/root/GameState")
	var contract: Dictionary = game_state.get("contract") if game_state != null else {}
	_contract_status.text = "¥%d" % int(contract.get("debt", 0))

	var fan_segments: Array[Dictionary] = _make_fan_segments(result.resulting_fan_vector)
	_fan_chart.call("set_segments", fan_segments)
	_refresh_fan_legend(fan_segments)
	_fan_summary.text = "新增粉丝 %+d · 核心粉 %.0f%% · 黑粉 %.0f%%" % [
		result.fan_delta,
		_get_segment_value(fan_segments, "c"),
		_get_segment_value(fan_segments, "b"),
	]

	var black_fan_ratio: float = float(result.resulting_fan_vector.get("b", 0.0))
	var need_crisis: bool = result.accident_occurred or black_fan_ratio > 15.0
	_crisis_panel.visible = need_crisis
	_crisis_status.visible = false
	for button: Button in _crisis_buttons:
		button.disabled = false

	visible = true
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.26).set_trans(Tween.TRANS_SINE)


func _apply_stream_identity(plan: StreamPlanSnapshot) -> void:
	var display_name: String = "主播"
	var icon: Texture2D = null
	var manager: Node = get_node_or_null("/root/LiveStreamManager")
	if manager != null and plan != null and manager.has_method("get_persona"):
		var persona: Variant = manager.call("get_persona", plan.persona_id)
		if persona != null:
			display_name = str(persona.get("channel_name"))
			icon = persona.get("channel_avatar") as Texture2D
	_streamer_name.text = "主播 · %s" % display_name
	_avatar.call("set_avatar", icon, display_name)


func _make_fan_segments(vector: Dictionary) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var total: float = 0.0
	for group: Dictionary in FAN_GROUPS:
		total += maxf(float(vector.get(group["key"], 0.0)), 0.0)
	var use_default: bool = total <= 0.0
	if use_default:
		total = 100.0

	for group: Dictionary in FAN_GROUPS:
		var raw_value: float = maxf(float(vector.get(group["key"], 0.0)), 0.0)
		if use_default and String(group["key"]) == "r":
			raw_value = 100.0
		segments.append({
			"key": group["key"],
			"label": group["label"],
			"color": group["color"],
			"value": raw_value / total * 100.0,
		})
	return segments


func _refresh_fan_legend(segments: Array[Dictionary]) -> void:
	for child: Node in _fan_legend.get_children():
		_fan_legend.remove_child(child)
		child.queue_free()
	for segment: Dictionary in segments:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		_fan_legend.add_child(row)
		var swatch := ColorRect.new()
		var swatch_color: Color = segment["color"]
		swatch.color = swatch_color
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var name_label := _make_label(String(segment["label"]), FONT_BODY, COLOR_SECONDARY)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var value_label := _make_label("%.0f%%" % float(segment["value"]), FONT_BODY, COLOR_TEXT)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)


func _get_segment_value(segments: Array[Dictionary], key: String) -> float:
	for segment: Dictionary in segments:
		if String(segment.get("key", "")) == key:
			return float(segment.get("value", 0.0))
	return 0.0


func _on_crisis_pressed(choice_id: String) -> void:
	for button: Button in _crisis_buttons:
		button.disabled = true
	_crisis_status.text = "处理方式已选择"
	_crisis_status.visible = true
	crisis_choice_made.emit(choice_id)


func _make_metric_card(title_text: String, accent_color: Color) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 226)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel", _make_style(COLOR_SURFACE, COLOR_BORDER, 24, 2, 28, 7)
	)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var accent_bar := ColorRect.new()
	accent_bar.color = accent_color
	accent_bar.custom_minimum_size.y = 7.0
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(accent_bar)
	column.add_child(_make_label(title_text, FONT_BODY, COLOR_SECONDARY))
	var value := _make_label("--", FONT_METRIC, accent_color)
	column.add_child(value)
	var detail := _make_label("", FONT_CAPTION, COLOR_MUTED)
	column.add_child(detail)
	return {"panel": panel, "value": value, "detail": detail}


func _make_value_row(parent: VBoxContainer, title_text: String) -> Label:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 46.0
	row.add_theme_constant_override("separation", 24)
	parent.add_child(row)
	var title := _make_label(title_text, FONT_BODY, COLOR_SECONDARY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var value := _make_label("--", FONT_BODY, COLOR_TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value


func _add_horizontal_rule(parent: VBoxContainer) -> void:
	var separator := ColorRect.new()
	separator.custom_minimum_size.y = 2.0
	separator.color = Color("#D8E3F0")
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(separator)


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_style(
	bg_color: Color,
	border_color: Color,
	radius: int,
	border_width: int = 2,
	padding: int = 0,
	shadow_size: int = 0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	style.anti_aliasing = true
	if shadow_size > 0:
		style.shadow_color = Color(0.10, 0.16, 0.26, 0.13)
		style.shadow_size = shadow_size
		style.shadow_offset = Vector2(0, 4)
	return style
