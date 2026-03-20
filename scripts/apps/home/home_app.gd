class_name HomeApp
extends Control

const COLOR_BG := Color("#F4EFE6")
const COLOR_PANEL := Color("#FFF9F1")
const COLOR_PANEL_ALT := Color("#F7F1E8")
const COLOR_BORDER := Color("#D8C8B7")
const COLOR_TITLE := Color("#3D2C24")
const COLOR_TEXT := Color("#5A473C")
const COLOR_MUTED := Color("#8D7767")
const COLOR_ACTION := Color("#C46B4A")
const COLOR_ACTION_HOVER := Color("#D77B57")
const COLOR_DISABLED := Color("#B8AA9C")
const COLOR_OK := Color("#6F8F5B")

var _home_manager: Node = null
var _game_loop: Node = null
var _game_manager: Node = null

var _header_label: Label = null
var _stats_label: Label = null
var _hint_label: Label = null
var _activity_list: VBoxContainer = null
var _detail_title: Label = null
var _detail_body: Label = null
var _option_list: VBoxContainer = null
var _result_label: RichTextLabel = null

var _selected_activity_id: String = ""
var _last_payload: Dictionary = {}


func _ready() -> void:
	_home_manager = get_node_or_null("/root/HomeActivityManager")
	_game_loop = get_node_or_null("/root/GameLoopManager")
	_game_manager = get_node_or_null("/root/GameManager")

	_build_ui()
	_connect_signals()
	_refresh_all()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var hero := _build_panel(COLOR_PANEL, 20)
	root.add_child(hero)

	var hero_box := VBoxContainer.new()
	hero_box.add_theme_constant_override("separation", 8)
	hero.add_child(hero_box)

	var title := Label.new()
	title.text = "Home"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	hero_box.add_child(title)

	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 16)
	_header_label.add_theme_color_override("font_color", COLOR_TEXT)
	hero_box.add_child(_header_label)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 15)
	_stats_label.add_theme_color_override("font_color", COLOR_MUTED)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_box.add_child(_stats_label)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", COLOR_OK)
	hero_box.add_child(_hint_label)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	root.add_child(content)

	var left_panel := _build_panel(COLOR_PANEL_ALT, 18)
	left_panel.custom_minimum_size = Vector2(420, 0)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(left_panel)

	var left_box := VBoxContainer.new()
	left_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_theme_constant_override("separation", 14)
	left_panel.add_child(left_box)

	var left_title := Label.new()
	left_title.text = "今天在家做什么"
	left_title.add_theme_font_size_override("font_size", 20)
	left_title.add_theme_color_override("font_color", COLOR_TITLE)
	left_box.add_child(left_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_box.add_child(scroll)

	_activity_list = VBoxContainer.new()
	_activity_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_activity_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_activity_list)

	var right_panel := _build_panel(COLOR_PANEL, 18)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(right_panel)

	var right_box := VBoxContainer.new()
	right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 14)
	right_panel.add_child(right_box)

	_detail_title = Label.new()
	_detail_title.text = "选择一个活动"
	_detail_title.add_theme_font_size_override("font_size", 22)
	_detail_title.add_theme_color_override("font_color", COLOR_TITLE)
	right_box.add_child(_detail_title)

	_detail_body = Label.new()
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.add_theme_font_size_override("font_size", 15)
	_detail_body.add_theme_color_override("font_color", COLOR_TEXT)
	right_box.add_child(_detail_body)

	var option_title := Label.new()
	option_title.text = "可选项"
	option_title.add_theme_font_size_override("font_size", 16)
	option_title.add_theme_color_override("font_color", COLOR_MUTED)
	right_box.add_child(option_title)

	var option_scroll := ScrollContainer.new()
	option_scroll.custom_minimum_size = Vector2(0, 220)
	option_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	option_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_box.add_child(option_scroll)

	_option_list = VBoxContainer.new()
	_option_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_list.add_theme_constant_override("separation", 10)
	option_scroll.add_child(_option_list)

	var result_title := Label.new()
	result_title.text = "最近结果"
	result_title.add_theme_font_size_override("font_size", 16)
	result_title.add_theme_color_override("font_color", COLOR_MUTED)
	right_box.add_child(result_title)

	_result_label = RichTextLabel.new()
	_result_label.custom_minimum_size = Vector2(0, 180)
	_result_label.fit_content = true
	_result_label.bbcode_enabled = true
	_result_label.scroll_active = true
	_result_label.add_theme_color_override("default_color", COLOR_TEXT)
	_result_label.add_theme_font_size_override("normal_font_size", 15)
	right_box.add_child(_result_label)


func _connect_signals() -> void:
	if _game_loop != null:
		if _game_loop.has_signal("ap_changed"):
			_game_loop.ap_changed.connect(_on_state_changed)
		if _game_loop.has_signal("phase_changed"):
			_game_loop.phase_changed.connect(_on_state_changed)
		if _game_loop.has_signal("day_changed"):
			_game_loop.day_changed.connect(_on_state_changed)

	if _game_manager != null and _game_manager.has_signal("stats_changed"):
		_game_manager.stats_changed.connect(_on_state_changed)

	if _home_manager != null:
		if _home_manager.has_signal("activity_started"):
			_home_manager.activity_started.connect(_on_activity_started)
		if _home_manager.has_signal("activity_completed"):
			_home_manager.activity_completed.connect(_on_activity_completed)
		if _home_manager.has_signal("session_failed"):
			_home_manager.session_failed.connect(_on_session_failed)


func _refresh_all() -> void:
	_refresh_header()
	_refresh_activities()
	_refresh_detail()


func _refresh_header() -> void:
	if _game_loop == null or _game_manager == null:
		_header_label.text = "HomeActivityManager 未就绪"
		_stats_label.text = ""
		return

	var phase_name: String = _format_phase()
	_header_label.text = "Day %d  ·  %s  ·  AP %d/%d" % [
		int(_game_loop.get("current_day")),
		phase_name,
		int(_game_loop.get("current_ap")),
		int(_game_loop.get("max_ap_per_day")),
	]
	_stats_label.text = "好感 %d    压力 %d    激情 %d    零花钱 %d" % [
		int(_game_manager.get("affection")),
		int(_game_manager.get("stress")),
		int(_game_manager.get("passion")),
		int(_game_manager.get("money")),
	]

	if _home_manager != null and _home_manager.has_method("has_any_pending_sessions") and _home_manager.has_any_pending_sessions():
		_hint_label.text = "当前有居家活动正在进行，等她说完这一句。"
	else:
		_hint_label.text = "外出是事件，在家更像是把关系慢慢养出来。"


func _refresh_activities() -> void:
	if _activity_list == null:
		return

	for child in _activity_list.get_children():
		child.queue_free()

	if _home_manager == null or not _home_manager.has_method("get_available_activities"):
		return

	var activities: Array[Dictionary] = _home_manager.get_available_activities()
	for activity in activities:
		_activity_list.add_child(_build_activity_card(activity))

	if not _selected_activity_id.is_empty():
		var still_exists: bool = false
		for activity in activities:
			if str(activity.get("activity_id", "")) == _selected_activity_id:
				still_exists = true
				break
		if not still_exists:
			_selected_activity_id = ""


func _build_activity_card(activity: Dictionary) -> Control:
	var card := _build_panel(Color.WHITE, 14)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var title := Label.new()
	title.text = str(activity.get("title", "未命名活动"))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	box.add_child(title)

	var desc := Label.new()
	desc.text = str(activity.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(desc)

	var meta := Label.new()
	meta.text = _build_activity_meta(activity)
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(meta)

	var has_choice: bool = bool(activity.get("requires_choice", false))
	var button := Button.new()
	button.text = "查看选项" if has_choice else "开始"
	button.disabled = not bool(activity.get("enabled", false))
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button_style(button, not button.disabled)
	if button.disabled:
		button.text = str(activity.get("disabled_reason", "暂不可用"))
	else:
		button.pressed.connect(_on_activity_pressed.bind(str(activity.get("activity_id", "")), has_choice))
	box.add_child(button)

	return card


func _refresh_detail() -> void:
	if _detail_title == null or _detail_body == null or _option_list == null:
		return

	for child in _option_list.get_children():
		child.queue_free()

	if _selected_activity_id.is_empty():
		_detail_title.text = "选择一个活动"
		_detail_body.text = "左侧会根据当前时段、AP 和数值条件刷新可用的在家活动。"
		return

	var activity: Dictionary = _find_activity(_selected_activity_id)
	if activity.is_empty():
		_detail_title.text = "选择一个活动"
		_detail_body.text = "当前时段没有找到这个活动。"
		return

	_detail_title.text = str(activity.get("title", "在家活动"))
	_detail_body.text = str(activity.get("description", ""))

	if not bool(activity.get("requires_choice", false)):
		var tip := Label.new()
		tip.text = "这个活动不需要额外选择，直接点左侧按钮就会开始。"
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.add_theme_font_size_override("font_size", 14)
		tip.add_theme_color_override("font_color", COLOR_MUTED)
		_option_list.add_child(tip)
		return

	if _home_manager == null or not _home_manager.has_method("get_activity_options"):
		return

	var options: Array[Dictionary] = _home_manager.get_activity_options(_selected_activity_id)
	if options.is_empty():
		var empty_label := Label.new()
		empty_label.text = "这个时段没有可用选项。"
		empty_label.add_theme_color_override("font_color", COLOR_MUTED)
		_option_list.add_child(empty_label)
		return

	for option in options:
		_option_list.add_child(_build_option_card(_selected_activity_id, option))


func _build_option_card(activity_id: String, option: Dictionary) -> Control:
	var card := _build_panel(Color.WHITE, 12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var title := Label.new()
	title.text = str(option.get("title", "未命名选项"))
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	box.add_child(title)

	var meta := Label.new()
	meta.text = _build_option_meta(option)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(meta)

	var button := Button.new()
	button.text = "选这个"
	button.disabled = not bool(option.get("enabled", true))
	button.focus_mode = Control.FOCUS_NONE
	_apply_button_style(button, not button.disabled)
	if button.disabled:
		button.text = str(option.get("disabled_reason", "当前不可选"))
	else:
		button.pressed.connect(_on_option_pressed.bind(activity_id, "content_id", str(option.get("content_id", ""))))
	box.add_child(button)

	return card


func _build_activity_meta(activity: Dictionary) -> String:
	var ap_cost: int = int(activity.get("ap_cost", 0))
	var phase_text: String = "/".join(PackedStringArray(activity.get("available_phases", [])))
	var parts: Array[String] = []
	parts.append("AP %d" % ap_cost)
	if not phase_text.is_empty():
		parts.append("时段 %s" % phase_text)
	return " · ".join(parts)


func _build_option_meta(option: Dictionary) -> String:
	var parts: Array[String] = []
	if option.has("money_cost") and int(option.get("money_cost", 0)) > 0:
		parts.append("花费 %d" % int(option.get("money_cost", 0)))
	if option.has("min_affection"):
		parts.append("需要好感 %d" % int(option.get("min_affection", 0)))
	if option.has("tone"):
		parts.append("氛围 %s" % str(option.get("tone", "")))
	if option.has("type"):
		parts.append("类型 %s" % str(option.get("type", "")))
	return " · ".join(parts)


func _build_panel(bg_color: Color, padding: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _apply_button_style(button: Button, enabled: bool) -> void:
	var base_color: Color = COLOR_ACTION if enabled else COLOR_DISABLED
	var hover_color: Color = COLOR_ACTION_HOVER if enabled else COLOR_DISABLED
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _make_button_style(base_color))
	button.add_theme_stylebox_override("hover", _make_button_style(hover_color))
	button.add_theme_stylebox_override("pressed", _make_button_style(hover_color.darkened(0.08)))
	button.add_theme_stylebox_override("disabled", _make_button_style(COLOR_DISABLED))


func _make_button_style(bg_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _find_activity(activity_id: String) -> Dictionary:
	if _home_manager == null or not _home_manager.has_method("get_available_activities"):
		return {}
	var activities: Array[Dictionary] = _home_manager.get_available_activities()
	for activity in activities:
		if str(activity.get("activity_id", "")) == activity_id:
			return activity
	return {}


func _format_phase() -> String:
	if _game_loop == null:
		return "UNKNOWN"
	match str(_game_loop.get_phase_name(_game_loop.time_phase)):
		"MORNING":
			return "早上"
		"AFTERNOON":
			return "下午"
		"NIGHT":
			return "晚上"
	return "未知"


func _append_result(message: String) -> void:
	if _result_label == null:
		return
	var history: String = _result_label.text
	var next_entry: String = "[color=#5A473C]%s[/color]" % message
	if history.is_empty():
		_result_label.text = next_entry
	else:
		_result_label.text = "%s\n\n%s" % [history, next_entry]


func _on_activity_pressed(activity_id: String, requires_choice: bool) -> void:
	_selected_activity_id = activity_id
	_refresh_detail()
	if not requires_choice:
		_execute_activity(activity_id)


func _on_option_pressed(activity_id: String, key_name: String, option_id: String) -> void:
	_execute_activity(activity_id, {key_name: option_id})


func _execute_activity(activity_id: String, context: Dictionary = {}) -> void:
	if _home_manager == null or not _home_manager.has_method("begin_activity"):
		return

	var result: Dictionary = _home_manager.begin_activity(activity_id, context)
	if bool(result.get("success", false)):
		_append_result("开始了「%s」。" % str(result.get("activity_id", activity_id)))
	else:
		_append_result("无法开始活动: %s" % str(result.get("error", "未知错误")))
	_refresh_all()


func _on_state_changed(_arg1 = null, _arg2 = null) -> void:
	_refresh_all()


func _on_activity_started(_activity_id: String, _payload: Dictionary) -> void:
	_refresh_all()


func _on_activity_completed(activity_id: String, payload: Dictionary) -> void:
	_last_payload = payload.duplicate(true)
	var message: String = "「%s」结束。" % activity_id
	if payload.has("context"):
		var context: Dictionary = payload.get("context", {})
		var option: Dictionary = context.get("option", {})
		var option_title: String = str(option.get("title", "")).strip_edges()
		if not option_title.is_empty():
			message = "「%s」结束: %s" % [activity_id, option_title]
	if not str(payload.get("reply", "")).strip_edges().is_empty():
		message += "\n%s" % str(payload.get("reply", ""))
	var moment: Dictionary = payload.get("moment", {})
	var moment_text: String = str(moment.get("content", "")).strip_edges()
	if not moment_text.is_empty():
		message += "\n朋友圈: %s" % moment_text
	_append_result(message)
	_refresh_all()


func _on_session_failed(error_message: String) -> void:
	_append_result("活动失败: %s" % error_message)
	_refresh_all()
