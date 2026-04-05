class_name CommunityApp
extends Control

const LOADING_HINTS: PackedStringArray = [
	"评论区还在往上冒，先刷两眼新帖子。",
	"大家正在转发、围观、补刀，页面马上成形。",
	"新的讨论还在刷新，像在手机里往上滑一样。",
]
const LOADING_CARD_HEIGHTS: PackedFloat32Array = [310.0, 260.0, 290.0, 240.0, 320.0]

const C_CARD_BG := Color("#FFFFFF")
const C_CARD_BORDER := Color("#E4E0DB")
const C_HISTORY_BG := Color("#F7F5F2")
const C_HISTORY_BORDER := Color("#E8E4DF")
const C_TITLE := Color("#1A1A1A")
const C_BODY := Color("#5A5A5A")
const C_META := Color("#9A9A9A")
const C_ACCENT_FORUM := Color("#5B8DEF")
const C_ACCENT_PROMO := Color("#E8854C")
const C_ACCENT_EVENT := Color("#5EAD6E")
const C_BTN_ENABLED := Color("#2D4263")
const C_BTN_DISABLED := Color("#D6D2CD")
const C_BTN_TEXT := Color("#FFFFFF")
const C_BTN_TEXT_OFF := Color("#9A9590")
const C_LINK := Color("#4A78C9")

@onready var feed_scroll: ScrollContainer = %FeedScroll
@onready var actions_container: VBoxContainer = %ActionsContainer
@onready var history_container: VBoxContainer = %HistoryContainer
@onready var status_label: Label = %StatusLabel
@onready var loading_view: Control = %LoadingView
@onready var loading_content: HBoxContainer = %LoadingContent
@onready var loading_scroll: ScrollContainer = %LoadingScroll
@onready var left_col: VBoxContainer = %LeftCol
@onready var right_col: VBoxContainer = %RightCol

var _action_buttons: Dictionary = {}
var _is_loading: bool = false
var _loading_action_id: String = ""
var _loading_tween: Tween = null


func _ready() -> void:
	_connect_signals()
	_set_loading_visible(false)
	_refresh_view()


func _connect_signals() -> void:
	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager != null:
		var started := Callable(self, "_on_action_started")
		if not manager.is_connected("community_action_started", started):
			manager.connect("community_action_started", started)

		var completed := Callable(self, "_on_action_completed")
		if not manager.is_connected("community_action_completed", completed):
			manager.connect("community_action_completed", completed)

		var failed := Callable(self, "_on_action_failed")
		if not manager.is_connected("community_action_failed", failed):
			manager.connect("community_action_failed", failed)

	var browser: Node = get_node_or_null("/root/BrowserManager")
	if browser != null:
		var history_updated := Callable(self, "_on_browser_history_updated")
		if not browser.is_connected("browser_history_updated", history_updated):
			browser.connect("browser_history_updated", history_updated)


func _refresh_view() -> void:
	if _is_loading:
		return
	_render_actions()
	_render_history()


func _render_actions() -> void:
	_clear_container(actions_container)
	_action_buttons.clear()

	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null or not manager.has_method("get_available_actions"):
		_add_empty_state(actions_container, "社区服务暂时连不上，稍后再刷。")
		return

	var actions: Array = manager.get_available_actions()
	if actions.is_empty():
		_add_empty_state(actions_container, "今天暂时没有可以执行的社区行动。")
		return

	for action_data in actions:
		if action_data is Dictionary:
			actions_container.add_child(_build_action_card(action_data))


func _build_action_card(action_data: Dictionary) -> Control:
	var action_id: String = str(action_data.get("action_id", "")).strip_edges()
	var accent: Color = _get_action_accent(action_id)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_card_style(C_CARD_BG, C_CARD_BORDER, 12))

	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	panel.add_child(outer)

	# Left accent bar
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(4, 0)
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = accent
	bar_style.corner_radius_top_left = 12
	bar_style.corner_radius_bottom_left = 12
	bar.add_theme_stylebox_override("panel", bar_style)
	outer.add_child(bar)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	outer.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 6)
	row.add_child(text_box)

	var title := Label.new()
	title.text = str(action_data.get("title", "社区行动"))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", C_TITLE)
	text_box.add_child(title)

	var desc := Label.new()
	desc.text = str(action_data.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", C_BODY)
	text_box.add_child(desc)

	var meta := Label.new()
	meta.text = _build_action_meta_text(action_data)
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override("font_color", C_META)
	text_box.add_child(meta)

	var button_box := VBoxContainer.new()
	button_box.custom_minimum_size = Vector2(110, 0)
	button_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(button_box)

	var action_button := Button.new()
	var enabled: bool = bool(action_data.get("enabled", true)) and not _is_loading
	action_button.name = "ActionButton_%s" % action_id
	action_button.text = "开始"
	action_button.disabled = not enabled
	action_button.custom_minimum_size = Vector2(0, 38)
	action_button.pressed.connect(_on_action_button_pressed.bind(action_id))
	_style_action_button(action_button, enabled)
	button_box.add_child(action_button)

	if not enabled:
		var reason := Label.new()
		reason.text = str(action_data.get("blocked_reason", "暂时无法执行"))
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reason.add_theme_font_size_override("font_size", 12)
		reason.add_theme_color_override("font_color", Color("#B07A6A") if not _is_loading else C_META)
		button_box.add_child(reason)

	_action_buttons[action_id] = action_button
	return panel


func _get_action_accent(action_id: String) -> Color:
	match action_id:
		"browse_forum":
			return C_ACCENT_FORUM
		"post_promo":
			return C_ACCENT_PROMO
		"watch_event":
			return C_ACCENT_EVENT
		_:
			return C_ACCENT_FORUM


func _build_action_meta_text(action_data: Dictionary) -> String:
	var tags: Array = action_data.get("tags", [])
	var tag_text := " / ".join(PackedStringArray(tags))
	var ap_cost: int = int(action_data.get("ap_cost", 1))
	if tag_text.is_empty():
		return "消耗 %d 行动力" % ap_cost
	return "消耗 %d 行动力 · %s" % [ap_cost, tag_text]


func _style_action_button(button: Button, enabled: bool) -> void:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	style.bg_color = C_BTN_ENABLED if enabled else C_BTN_DISABLED
	var hover_style := style.duplicate()
	if enabled:
		hover_style.bg_color = C_BTN_ENABLED.lightened(0.1)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", C_BTN_TEXT if enabled else C_BTN_TEXT_OFF)
	button.add_theme_color_override("font_hover_color", C_BTN_TEXT if enabled else C_BTN_TEXT_OFF)
	button.add_theme_color_override("font_pressed_color", C_BTN_TEXT if enabled else C_BTN_TEXT_OFF)
	button.add_theme_font_size_override("font_size", 15)


func _render_history() -> void:
	_clear_container(history_container)

	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null or not manager.has_method("get_recent_entries"):
		_add_empty_state(history_container, "还没有记录，先去刷点什么吧。")
		return

	var entries: Array = manager.get_recent_entries(6)
	if entries.is_empty():
		_add_empty_state(history_container, "还没有社区行动记录。")
		return

	for entry in entries:
		if entry is Dictionary:
			history_container.add_child(_build_history_item(entry))


func _build_history_item(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_card_style(C_HISTORY_BG, C_HISTORY_BORDER, 10))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 11)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 11)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var action_id: String = str(entry.get("action_id", "")).strip_edges()
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(6, 6)
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = _get_action_accent(action_id)
	dot_style.corner_radius_top_left = 3
	dot_style.corner_radius_top_right = 3
	dot_style.corner_radius_bottom_left = 3
	dot_style.corner_radius_bottom_right = 3
	dot.add_theme_stylebox_override("panel", dot_style)
	var dot_wrapper := VBoxContainer.new()
	dot_wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	dot_wrapper.add_child(dot)
	row.add_child(dot_wrapper)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 3)
	row.add_child(text_box)

	var title := Label.new()
	title.text = str(entry.get("title", "未命名记录"))
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", C_TITLE)
	text_box.add_child(title)

	var summary := Label.new()
	summary.text = _build_history_summary(entry)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 13)
	summary.add_theme_color_override("font_color", C_META)
	text_box.add_child(summary)

	var open_button := Button.new()
	open_button.text = "查看"
	open_button.flat = true
	open_button.add_theme_font_size_override("font_size", 14)
	open_button.add_theme_color_override("font_color", C_LINK)
	open_button.add_theme_color_override("font_hover_color", C_LINK.lightened(0.15))
	open_button.add_theme_color_override("font_pressed_color", C_LINK)
	open_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	open_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	open_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	open_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	open_button.pressed.connect(_open_entry_in_browser.bind(str(entry.get("url", ""))))
	row.add_child(open_button)

	return panel


func _build_history_summary(entry: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append("第%s天" % str(entry.get("day", "?")))

	var phase: String = str(entry.get("phase", "")).strip_edges()
	if not phase.is_empty():
		parts.append(phase)

	var summary: String = str(entry.get("summary", "")).strip_edges()
	if not summary.is_empty():
		parts.append(summary)
	return " · ".join(parts)


func _on_action_button_pressed(action_id: String) -> void:
	if _is_loading:
		return

	var manager: Node = get_node_or_null("/root/CommunityActionManager")
	if manager == null or not manager.has_method("perform_action"):
		_set_status("社区连接中断，请稍后再试。")
		return

	var result: Dictionary = manager.perform_action(action_id)
	if not bool(result.get("success", false)):
		_set_status(str(result.get("error", "行动失败")))
		_refresh_view()
		return

	if bool(result.get("async", false)):
		_begin_loading_state(action_id)
	else:
		_set_status("已经加载好了，页面正在打开。")
		_refresh_view()


func _on_action_started(action_id: String, _request_id: String) -> void:
	_begin_loading_state(action_id)


func _on_action_completed(action_id: String, entry: Dictionary) -> void:
	if action_id == _loading_action_id or _is_loading:
		_end_loading_state()
	_open_entry_in_browser(str(entry.get("url", "")))
	_set_status("页面已经打开了。")
	_refresh_view()


func _on_action_failed(action_id: String, error: String) -> void:
	if action_id == _loading_action_id and _is_loading:
		_set_status("加载中遇到了点问题，先用备用内容””")
	else:
		_set_status("连接中断了，试试刷新。")
	if not error.strip_edges().is_empty():
		push_warning("CommunityApp action failed: %s" % error)


func _on_browser_history_updated() -> void:
	if not _is_loading:
		_render_history()


func _open_entry_in_browser(url: String) -> void:
	var browser: Node = get_node_or_null("/root/BrowserManager")
	if browser == null or not browser.has_method("request_open_url"):
		return
	var target_url: String = url.strip_edges()
	if target_url.is_empty():
		return
	browser.request_open_url(target_url)


func _begin_loading_state(action_id: String) -> void:
	_is_loading = true
	_loading_action_id = action_id
	_set_loading_visible(true)
	_render_loading_feed()
	_set_status("正在刷新……")
	call_deferred("_restart_loading_animation")


func _end_loading_state() -> void:
	_is_loading = false
	_loading_action_id = ""
	_stop_loading_animation()
	_set_loading_visible(false)


func _set_loading_visible(visible_state: bool) -> void:
	if feed_scroll != null:
		feed_scroll.visible = not visible_state
	if loading_view != null:
		loading_view.visible = visible_state


func _render_loading_feed() -> void:
	_clear_container(left_col)
	_clear_container(right_col)

	var left_height: float = 0.0
	var right_height: float = 0.0

	for cycle in range(3):
		for index in range(LOADING_CARD_HEIGHTS.size()):
			var card_height: float = LOADING_CARD_HEIGHTS[index % LOADING_CARD_HEIGHTS.size()]
			var card: Control = _build_loading_card(index)
			if left_height <= right_height:
				left_col.add_child(card)
				left_height += card_height + 10.0
			else:
				right_col.add_child(card)
				right_height += card_height + 10.0


func _build_loading_card(index: int) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, LOADING_CARD_HEIGHTS[index % LOADING_CARD_HEIGHTS.size()])
	panel.add_theme_stylebox_override("panel", _make_card_style(Color("#FFFFFF"), Color("#E2E8F4"), 14))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)

	# Avatar row: circle + name + timestamp
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	body.add_child(top_row)
	top_row.add_child(_make_skeleton_circle(28, Color("#DDE4EF")))
	top_row.add_child(_make_skeleton_block(72, 14, Color("#D5DDE9"), 4))
	var pill_spacer := Control.new()
	pill_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(pill_spacer)
	top_row.add_child(_make_skeleton_block(48, 12, Color("#E8EDF3"), 4))

	# Image placeholder (portrait-ish for Xiaohongshu feel)
	var poster_height: float = [120.0, 90.0, 140.0, 100.0, 110.0][index % 5]
	body.add_child(_make_skeleton_block(0, poster_height, Color("#EDF1F7"), 10, true))

	# Text lines
	body.add_child(_make_skeleton_block(0, 16, Color("#E0E6EF"), 5, true, 0.78))
	body.add_child(_make_skeleton_block(0, 14, Color("#E8EDF3"), 5, true, 0.92))
	if index % 2 == 0:
		body.add_child(_make_skeleton_block(0, 14, Color("#F0F4F8"), 5, true, 0.55))

	# Reaction row
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	body.add_child(footer)
	footer.add_child(_make_skeleton_block(40, 12, Color("#E5EBF3"), 6))
	footer.add_child(_make_skeleton_block(40, 12, Color("#ECF0F6"), 6))
	footer.add_child(_make_skeleton_block(52, 12, Color("#E5EBF3"), 6))

	return panel


func _make_skeleton_circle(diameter: float, color_value: Color) -> Control:
	var block := PanelContainer.new()
	block.custom_minimum_size = Vector2(diameter, diameter)
	var style := StyleBoxFlat.new()
	style.bg_color = color_value
	var r := int(diameter / 2.0)
	style.corner_radius_top_left = r
	style.corner_radius_top_right = r
	style.corner_radius_bottom_left = r
	style.corner_radius_bottom_right = r
	block.add_theme_stylebox_override("panel", style)
	return block


func _make_skeleton_block(
	width_value: float,
	height_value: float,
	color_value: Color,
	radius: int,
	expand_width: bool = false,
	width_ratio: float = 1.0
) -> Control:
	var wrapper := HBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var block := PanelContainer.new()
	block.custom_minimum_size = Vector2(width_value, height_value)
	if expand_width:
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var right_spacer := Control.new()
		right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if width_ratio < 0.999:
			right_spacer.size_flags_stretch_ratio = maxf(0.01, 1.0 - width_ratio)
			block.size_flags_stretch_ratio = maxf(0.01, width_ratio)
		wrapper.add_child(block)
		wrapper.add_child(right_spacer)
	else:
		wrapper.add_child(block)

	var style := StyleBoxFlat.new()
	style.bg_color = color_value
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	block.add_theme_stylebox_override("panel", style)
	return wrapper


func _restart_loading_animation() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not _is_loading:
		return

	_stop_loading_animation()
	loading_scroll.scroll_vertical = 0
	var one_set_height: float = loading_content.size.y / 3.0
	if one_set_height <= 4.0:
		return
	_start_scroll_cycle(one_set_height)


func _start_scroll_cycle(set_height: float) -> void:
	if not _is_loading:
		return
	_stop_loading_animation()
	loading_scroll.scroll_vertical = 0
	var duration: float = set_height / 55.0
	_loading_tween = create_tween()
	_loading_tween.tween_property(loading_scroll, "scroll_vertical", int(set_height), duration)
	_loading_tween.tween_callback(_start_scroll_cycle.bind(set_height))


func _stop_loading_animation() -> void:
	if _loading_tween != null and is_instance_valid(_loading_tween):
		_loading_tween.kill()
	_loading_tween = null
	if loading_scroll != null:
		loading_scroll.scroll_vertical = 0


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _clear_container(container: Container) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


func _add_empty_state(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#77859E"))
	container.add_child(label)


func _make_card_style(bg_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
