class_name ContentCard extends Button
## 人设卡/素材卡：与事件卡共用拼图卡框，仅内容分区不同（无左右接口）。

const COLOR_TITLE: Color = Color("#201F3A")
const COLOR_FAMILY: Color = Color("#496BB9")
const COLOR_INFO: Color = Color("#404B62")
const COLOR_STAT: Color = Color("#201F3A")

var payload: Dictionary = {}
var drag_enabled: bool = false:
	set(value):
		drag_enabled = value
		if _interaction != null:
			_interaction.drag_enabled = value

var _slot_edges: CardSlotEdges = null
var _interaction: CardInteraction = null
var _title_label: Label = null
var _badge_label: Label = null
var _icon_rect: TextureRect = null
var _info_label: Label = null
var _left_stat_value: Label = null
var _right_stat_value: Label = null
var _stats_row: HBoxContainer = null
var _selected: bool = false
var _hovered: bool = false


func _init() -> void:
	custom_minimum_size = CardDisplayMetrics.FULL_SIZE
	size = CardDisplayMetrics.FULL_SIZE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	focus_mode = Control.FOCUS_NONE
	_build_chrome()
	_apply_empty_button_styles()


func _ready() -> void:
	_ensure_interaction()
	_refresh_interaction()


func get_card_payload() -> Dictionary:
	return payload


func set_card_shadow_strength(strength: float) -> void:
	if _slot_edges != null:
		_slot_edges.set_glow_strength(strength)


## badge 例："人设卡" / "素材 · 连续型"；info_lines 为说明行；stat_left/right 为底部小统计。
func configure(
	title: String,
	badge: String,
	icon: Texture2D,
	info_lines: Array[String],
	card_payload: Dictionary,
	selected: bool,
	stat_left: String = "",
	stat_right: String = ""
) -> void:
	payload = card_payload
	_selected = selected
	_title_label.text = title
	_badge_label.text = badge
	_icon_rect.texture = icon
	_info_label.text = "\n".join(info_lines)
	_left_stat_value.text = stat_left
	_right_stat_value.text = stat_right
	_stats_row.visible = not stat_left.is_empty() or not stat_right.is_empty()
	_slot_edges.configure([], [], false)
	_refresh_interaction()


func set_selected(selected: bool) -> void:
	_selected = selected
	_refresh_interaction()


func _ensure_interaction() -> void:
	if _interaction != null:
		return
	_interaction = CardInteraction.new()
	_interaction.name = "CardInteraction"
	_interaction.drag_enabled = drag_enabled
	add_child(_interaction)
	_interaction.clicked.connect(_on_interaction_clicked)
	_interaction.visual_state_changed.connect(_on_visual_state_changed)


func _on_interaction_clicked() -> void:
	pressed.emit()


func _on_visual_state_changed(is_hovered: bool, is_dragging: bool) -> void:
	_hovered = is_hovered or is_dragging
	_refresh_interaction()


func _build_chrome() -> void:
	_slot_edges = CardSlotEdges.new()
	_slot_edges.name = "SlotEdges"
	_slot_edges.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_edges)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 62.0
	margin.offset_top = 30.0
	margin.offset_right = -62.0
	margin.offset_bottom = -30.0
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	_title_label = Label.new()
	_title_label.custom_minimum_size = Vector2(0, 46)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", COLOR_TITLE)
	_title_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	_title_label.add_theme_constant_override("outline_size", 3)
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title_label)

	var title_divider := ColorRect.new()
	title_divider.custom_minimum_size = Vector2(0, 2)
	title_divider.color = Color(0.78, 0.835, 0.91, 0.85)
	title_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_divider)

	_badge_label = Label.new()
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.add_theme_font_size_override("font_size", 20)
	_badge_label.add_theme_color_override("font_color", COLOR_FAMILY)
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_badge_label)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(0, 150)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_icon_rect)

	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(0, 130)
	_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 23)
	_info_label.add_theme_color_override("font_color", COLOR_INFO)
	_info_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))
	_info_label.add_theme_constant_override("outline_size", 2)
	_info_label.add_theme_constant_override("line_spacing", 5)
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_info_label)

	var footer_divider := ColorRect.new()
	footer_divider.custom_minimum_size = Vector2(0, 2)
	footer_divider.color = Color(0.78, 0.835, 0.91, 0.85)
	footer_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer_divider)

	_stats_row = HBoxContainer.new()
	_stats_row.custom_minimum_size = Vector2(0, 54)
	_stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_stats_row)

	_left_stat_value = _make_stat_label()
	_stats_row.add_child(_wrap_stat(_left_stat_value))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_row.add_child(spacer)
	_right_stat_value = _make_stat_label()
	_stats_row.add_child(_wrap_stat(_right_stat_value))

	_slot_edges.configure([], [], false)


func _make_stat_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", COLOR_STAT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _wrap_stat(value_label: Label) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.82)
	style.border_color = Color(0.804, 0.855, 0.918, 0.9)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.content_margin_left = 13
	style.content_margin_top = 8
	style.content_margin_right = 13
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(value_label)
	return panel


func _apply_empty_button_styles() -> void:
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("hover", empty)
	add_theme_stylebox_override("pressed", empty)
	add_theme_stylebox_override("disabled", empty)
	add_theme_stylebox_override("focus", empty)


func _refresh_interaction() -> void:
	if _slot_edges == null:
		return
	_slot_edges.set_interaction_state(_selected, _hovered, false)
	if _interaction != null:
		_interaction.drag_enabled = drag_enabled and not payload.is_empty()
