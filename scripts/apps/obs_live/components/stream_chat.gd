class_name StreamChat extends Control
## 直播界面右侧 chat 区：浅色弹幕卡片，自底向上滚动。

const COLOR_PAGE: Color = Color("#F0F4F8")
const COLOR_CARD: Color = Color("#FFFFFF")
const COLOR_BORDER: Color = Color("#C8D6EA")
const COLOR_HEADER: Color = Color("#EAF1FA")
const COLOR_TEXT: Color = Color("#1A2238")
const COLOR_SYSTEM: Color = Color("#8793A5")
const COLOR_FAMILY: Color = Color("#3A5FA8")

const SC_COLORS: Array[Color] = [
	Color("#4A90D9"),
	Color("#E67E22"),
	Color("#C0392B"),
	Color("#8E44AD"),
]

const MAX_ENTRIES: int = 80
const AMBIENT_INTERVAL: float = 1.6

var _entries_box: VBoxContainer = null
var _scroll: ScrollContainer = null
var _ambient_hint: String = DanmakuPool.HINT_NEUTRAL
var _ambient_elapsed: float = 0.0
var _ambient_running: bool = false
var _rng := RandomNumberGenerator.new()
var _sc_color_index: int = 0


func _ready() -> void:
	var page_bg := ColorRect.new()
	page_bg.color = COLOR_PAGE
	page_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_bg)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_theme_stylebox_override("panel", _make_style(COLOR_CARD, COLOR_BORDER, 12))
	add_child(card)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	card.add_child(root)

	var header := PanelContainer.new()
	header.custom_minimum_size.y = 48
	header.add_theme_stylebox_override("panel", _make_header_style())
	root.add_child(header)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 14)
	header_margin.add_theme_constant_override("margin_right", 14)
	header.add_child(header_margin)

	var header_label := Label.new()
	header_label.text = "直播弹幕"
	header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_label.add_theme_font_size_override("font_size", 28)
	header_label.add_theme_color_override("font_color", COLOR_FAMILY)
	header_margin.add_child(header_label)

	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 12)
	body_margin.add_theme_constant_override("margin_top", 10)
	body_margin.add_theme_constant_override("margin_right", 12)
	body_margin.add_theme_constant_override("margin_bottom", 12)
	root.add_child(body_margin)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_margin.add_child(_scroll)

	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_box.add_theme_constant_override("separation", 8)
	_scroll.add_child(_entries_box)


func start_ambient(axis_hint: String, seed_value: int) -> void:
	_ambient_hint = axis_hint
	_rng.seed = seed_value
	_ambient_running = true
	_ambient_elapsed = 0.0


func stop_ambient() -> void:
	_ambient_running = false


func push_entries(entries: Array) -> void:
	for entry: Variant in entries:
		if entry is Dictionary:
			_add_entry(String(entry.get("text", "")))
	_scroll_to_bottom()


func push_system(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 26)
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
	var color: Color = SC_COLORS[_sc_color_index % SC_COLORS.size()]
	_sc_color_index += 1

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


func _process(delta: float) -> void:
	if not _ambient_running:
		return
	_ambient_elapsed += delta
	if _ambient_elapsed < AMBIENT_INTERVAL:
		return
	_ambient_elapsed = 0.0
	push_entries(DanmakuPool.roll(_rng, _ambient_hint, 1))


func _add_entry(text: String) -> void:
	if text.is_empty():
		return
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


func _trim_entries() -> void:
	while _entries_box.get_child_count() > MAX_ENTRIES:
		var oldest: Node = _entries_box.get_child(0)
		_entries_box.remove_child(oldest)
		oldest.queue_free()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


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
	style.shadow_color = Color(0.18, 0.22, 0.32, 0.08)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	return style


func _make_header_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_HEADER
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.border_width_bottom = 2
	style.border_color = COLOR_BORDER
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
