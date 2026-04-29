class_name StructuredFormMinigame extends MinigameBase
## 通用结构化表单 minigame。
## 静态 schema 由 task_data.form_config 提供；LLM 辅助/审核统一使用行导向 DSL。

const ActivityOptionLLMServiceClass = preload("res://scripts/activity/activity_option_llm_service.gd")

const ASSIST_SYSTEM_PROMPT_KEY: String = "minigame/structured_form_assist_system"
const REVIEW_SYSTEM_PROMPT_KEY: String = "minigame/structured_form_review_system"

const COLOR_BG := Color("#e9dfcf")
const COLOR_BG_STRIP := Color("#d8c5a9")
const COLOR_PAPER := Color("#fffdf6")
const COLOR_PAPER_EDGE := Color("#d9c9a5")
const COLOR_INK := Color("#17120c")
const COLOR_INK_SOFT := Color("#4f4436")
const COLOR_INK_MUTED := Color("#766852")
const COLOR_ACCENT := Color("#b85c38")
const COLOR_ACCENT_HOVER := Color("#9f4829")
const COLOR_GREEN := Color("#2f6b4f")
const COLOR_GREEN_HOVER := Color("#24563f")
const COLOR_ERROR := Color("#b42318")
const COLOR_BORDER := Color("#cdbb97")
const COLOR_FIELD_BG := Color("#fffaf0")
const COLOR_FIELD_BG_HOVER := Color("#fff4dc")
const COLOR_SELECTION := Color(0.72, 0.36, 0.22, 0.22)

var _form_config: Dictionary = {}
var _fields: Array[Dictionary] = []
var _field_controls: Dictionary = {}
var _assist_actions: Array[Dictionary] = []
var _llm_service: ActivityOptionLLMService = null
var _pending_request_id: String = ""
var _pending_action: Dictionary = {}
var _pending_submit_values: Dictionary = {}
var _submitting: bool = false

var _root_box: VBoxContainer = null
var _fields_box: VBoxContainer = null
var _assist_box: HBoxContainer = null
var _status_label: Label = null
var _submit_button: Button = null


func _on_minigame_start() -> void:
	_parse_config()
	_setup_llm()
	_build_ui()
	_refresh_submit_state()


func _on_minigame_cleanup() -> void:
	if _llm_service != null:
		_llm_service.clear_pending_requests()


func _parse_config() -> void:
	_form_config = task_data.get("form_config", {})
	if _form_config.is_empty():
		_form_config = _build_fallback_form_config()

	_fields.clear()
	var raw_fields: Variant = _form_config.get("fields", [])
	if raw_fields is Array:
		for raw_field in raw_fields:
			if raw_field is Dictionary:
				var normalized := _normalize_field(raw_field as Dictionary)
				if not normalized.is_empty():
					_fields.append(normalized)

	_assist_actions.clear()
	var raw_actions: Variant = _form_config.get("assist_actions", [])
	if (not raw_actions is Array or (raw_actions as Array).is_empty()) and _form_config.get("llm_assist", {}) is Dictionary:
		raw_actions = (_form_config.get("llm_assist", {}) as Dictionary).get("actions", [])
	if raw_actions is Array:
		for raw_action in raw_actions:
			if raw_action is Dictionary:
				var action := (raw_action as Dictionary).duplicate(true)
				if not str(action.get("id", "")).strip_edges().is_empty():
					_assist_actions.append(action)


func _build_fallback_form_config() -> Dictionary:
	return {
		"form_id": "generic_form",
		"title": str(task_data.get("title", "结构化表单")),
		"description": str(task_data.get("description", "")),
		"submit_label": "提交",
		"fields": [
			{
				"id": "content",
				"type": "textarea",
				"label": "内容",
				"required": true,
				"max_length": 400,
			},
		],
	}


func _normalize_field(raw_field: Dictionary) -> Dictionary:
	var field_id := str(raw_field.get("id", "")).strip_edges()
	var field_type := str(raw_field.get("type", "text")).strip_edges().to_lower()
	if field_id.is_empty():
		return {}
	if field_type not in ["text", "textarea", "single_select", "multi_select"]:
		field_type = "text"
	var field := raw_field.duplicate(true)
	field["id"] = field_id
	field["type"] = field_type
	field["label"] = str(field.get("label", field_id)).strip_edges()
	return field


func _setup_llm() -> void:
	_llm_service = ActivityOptionLLMServiceClass.new()
	_llm_service.name = "StructuredFormLLM"
	add_child(_llm_service)
	_llm_service.request_completed.connect(_on_llm_completed)
	_llm_service.request_failed.connect(_on_llm_failed)
	_llm_service.configure(
		"StructuredFormLLM",
		str(_form_config.get("llm_role", "structured_form")),
		["creative_brief_outline", "chat_default"],
		{},
		{"temperature": 0.5}
	)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_add_workbench_decoration(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 34)
	outer_margin.add_theme_constant_override("margin_top", 28)
	outer_margin.add_theme_constant_override("margin_right", 34)
	outer_margin.add_theme_constant_override("margin_bottom", 28)
	center.add_child(outer_margin)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(820, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_PAPER
	card_style.set_corner_radius_all(8)
	card_style.border_color = COLOR_PAPER_EDGE
	card_style.set_border_width_all(1)
	card_style.shadow_color = Color(0.16, 0.11, 0.06, 0.2)
	card_style.shadow_size = 16
	card_style.shadow_offset = Vector2(0, 8)
	card_style.content_margin_left = 42
	card_style.content_margin_right = 42
	card_style.content_margin_top = 34
	card_style.content_margin_bottom = 34
	card.add_theme_stylebox_override("panel", card_style)
	outer_margin.add_child(card)

	_root_box = VBoxContainer.new()
	_root_box.add_theme_constant_override("separation", 16)
	card.add_child(_root_box)

	_root_box.add_child(_build_header_band())

	var title := Label.new()
	title.text = str(_form_config.get("title", task_data.get("title", "结构化表单")))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", COLOR_INK)
	_root_box.add_child(title)

	var desc_text := str(_form_config.get("description", task_data.get("description", ""))).strip_edges()
	if not desc_text.is_empty():
		var desc := Label.new()
		desc.text = desc_text
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 17)
		desc.add_theme_color_override("font_color", COLOR_INK_SOFT)
		_root_box.add_child(desc)

	_root_box.add_child(_build_rule_line())

	_fields_box = VBoxContainer.new()
	_fields_box.add_theme_constant_override("separation", 18)
	_root_box.add_child(_fields_box)

	for field in _fields:
		_fields_box.add_child(_build_field(field))

	_assist_box = HBoxContainer.new()
	_assist_box.add_theme_constant_override("separation", 10)
	_assist_box.alignment = BoxContainer.ALIGNMENT_END
	_assist_box.visible = not _assist_actions.is_empty()
	_root_box.add_child(_assist_box)
	for action in _assist_actions:
		var btn := Button.new()
		btn.text = str(action.get("label", "辅助生成"))
		btn.custom_minimum_size = Vector2(150, 44)
		btn.add_theme_font_size_override("font_size", 16)
		_style_button(btn, COLOR_ACCENT, COLOR_ACCENT_HOVER)
		btn.pressed.connect(_on_assist_pressed.bind(action))
		_assist_box.add_child(btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	_root_box.add_child(_status_label)

	var submit_row := HBoxContainer.new()
	submit_row.alignment = BoxContainer.ALIGNMENT_END
	_root_box.add_child(submit_row)

	_submit_button = Button.new()
	_submit_button.text = str(_form_config.get("submit_label", "提交"))
	_submit_button.custom_minimum_size = Vector2(170, 50)
	_submit_button.add_theme_font_size_override("font_size", 18)
	_style_button(_submit_button, COLOR_GREEN, COLOR_GREEN_HOVER)
	_submit_button.pressed.connect(_on_submit_pressed)
	submit_row.add_child(_submit_button)


func _add_workbench_decoration(bg: ColorRect) -> void:
	var strip := ColorRect.new()
	strip.color = COLOR_BG_STRIP
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = 110.0
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(strip)

	var side := ColorRect.new()
	side.color = Color(0.45, 0.27, 0.15, 0.08)
	side.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side.offset_right = 72.0
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(side)


func _build_header_band() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var badge := Label.new()
	badge.text = "CREATIVE BRIEF"
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", COLOR_ACCENT)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.72, 0.36, 0.22, 0.12)
	badge_style.border_color = Color(0.72, 0.36, 0.22, 0.28)
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(4)
	badge_style.content_margin_left = 10
	badge_style.content_margin_right = 10
	badge_style.content_margin_top = 5
	badge_style.content_margin_bottom = 5
	badge.add_theme_stylebox_override("normal", badge_style)
	row.add_child(badge)

	var note := Label.new()
	note.text = "和林夏一起把灵感落到纸上"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", COLOR_INK_MUTED)
	row.add_child(note)
	return row


func _build_rule_line() -> Control:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = Color(COLOR_PAPER_EDGE.r, COLOR_PAPER_EDGE.g, COLOR_PAPER_EDGE.b, 0.75)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _build_field(field: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	var label := Label.new()
	label.text = _field_label_text(field)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COLOR_INK)
	box.add_child(label)

	match str(field.get("type", "text")):
		"textarea":
			box.add_child(_build_textarea_field(field))
		"single_select":
			box.add_child(_build_single_select_field(field))
		"multi_select":
			box.add_child(_build_multi_select_field(field))
		_:
			box.add_child(_build_text_field(field))

	var hint := str(field.get("hint", "")).strip_edges()
	if not hint.is_empty():
		var hint_label := Label.new()
		hint_label.text = hint
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_label.add_theme_font_size_override("font_size", 14)
		hint_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
		box.add_child(hint_label)
	return box


func _field_label_text(field: Dictionary) -> String:
	var text := str(field.get("label", field.get("id", "")))
	if bool(field.get("required", false)):
		text += " *"
	return text


func _build_text_field(field: Dictionary) -> Control:
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(0, 44)
	edit.placeholder_text = str(field.get("placeholder", ""))
	edit.text = str(field.get("default", ""))
	edit.add_theme_font_size_override("font_size", 18)
	_apply_field_style(edit)
	edit.text_changed.connect(func(_value: String) -> void: _refresh_submit_state())
	_field_controls[str(field.get("id", ""))] = {"kind": "text", "node": edit}
	return edit


func _build_textarea_field(field: Dictionary) -> Control:
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(0, float(field.get("height", 150)))
	edit.placeholder_text = str(field.get("placeholder", ""))
	edit.text = str(field.get("default", ""))
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.add_theme_font_size_override("font_size", 17)
	_apply_field_style(edit)
	edit.text_changed.connect(func() -> void: _refresh_submit_state())
	_field_controls[str(field.get("id", ""))] = {"kind": "textarea", "node": edit}
	return edit


func _build_single_select_field(field: Dictionary) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var select := OptionButton.new()
	select.custom_minimum_size = Vector2(0, 44)
	select.add_theme_font_size_override("font_size", 17)
	_apply_option_style(select)
	select.add_item("请选择", 0)
	for option_text in _as_string_array(field.get("options", [])):
		select.add_item(option_text)
	var allow_custom := bool(field.get("allow_custom", false))
	if allow_custom:
		select.add_item("自定义...")
	_style_option_popup(select)
	root.add_child(select)

	var custom_edit := LineEdit.new()
	custom_edit.visible = false
	custom_edit.custom_minimum_size = Vector2(0, 42)
	custom_edit.placeholder_text = str(field.get("custom_placeholder", "输入自定义类型"))
	custom_edit.add_theme_font_size_override("font_size", 17)
	_apply_field_style(custom_edit)
	root.add_child(custom_edit)

	select.item_selected.connect(func(_index: int) -> void:
		if allow_custom:
			custom_edit.visible = select.get_item_text(select.selected) == "自定义..."
		_refresh_submit_state()
	)
	custom_edit.text_changed.connect(func(_value: String) -> void: _refresh_submit_state())

	_field_controls[str(field.get("id", ""))] = {
		"kind": "single_select",
		"select": select,
		"custom": custom_edit,
		"allow_custom": allow_custom,
	}
	return root


func _build_multi_select_field(field: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.columns = int(field.get("columns", 2))
	var checks: Array[CheckBox] = []
	for option_text in _as_string_array(field.get("options", [])):
		var cb := CheckBox.new()
		cb.text = option_text
		cb.add_theme_font_size_override("font_size", 17)
		cb.add_theme_color_override("font_color", COLOR_INK_SOFT)
		cb.add_theme_color_override("font_hover_color", COLOR_INK)
		cb.add_theme_color_override("font_pressed_color", COLOR_INK)
		cb.toggled.connect(func(_pressed: bool) -> void: _refresh_submit_state())
		grid.add_child(cb)
		checks.append(cb)
	_field_controls[str(field.get("id", ""))] = {"kind": "multi_select", "checks": checks}
	return grid


func _apply_field_style(control: Control) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_FIELD_BG
	normal.border_color = COLOR_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 13
	normal.content_margin_right = 13
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	control.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = COLOR_FIELD_BG_HOVER
	control.add_theme_stylebox_override("hover", hover)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = COLOR_ACCENT
	focus.set_border_width_all(2)
	control.add_theme_stylebox_override("focus", focus)
	control.add_theme_color_override("font_color", COLOR_INK)
	control.add_theme_color_override("font_placeholder_color", COLOR_INK_MUTED)
	control.add_theme_color_override("caret_color", COLOR_ACCENT)
	control.add_theme_color_override("selection_color", COLOR_SELECTION)


func _apply_option_style(select: OptionButton) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_FIELD_BG
	normal.border_color = COLOR_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 13
	normal.content_margin_right = 13
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = COLOR_FIELD_BG_HOVER
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = COLOR_ACCENT
	focus.set_border_width_all(2)
	select.add_theme_stylebox_override("normal", normal)
	select.add_theme_stylebox_override("hover", hover)
	select.add_theme_stylebox_override("pressed", hover)
	select.add_theme_stylebox_override("focus", focus)
	select.add_theme_color_override("font_color", COLOR_INK)
	select.add_theme_color_override("font_hover_color", COLOR_INK)
	select.add_theme_color_override("font_pressed_color", COLOR_INK)
	select.add_theme_color_override("font_focus_color", COLOR_INK)
	select.add_theme_color_override("font_disabled_color", COLOR_INK_MUTED)


func _style_option_popup(select: OptionButton) -> void:
	var popup := select.get_popup()
	if popup == null:
		return
	var panel := StyleBoxFlat.new()
	panel.bg_color = COLOR_PAPER
	panel.border_color = COLOR_BORDER
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.content_margin_left = 8
	panel.content_margin_right = 8
	panel.content_margin_top = 6
	panel.content_margin_bottom = 6
	popup.add_theme_stylebox_override("panel", panel)
	popup.add_theme_color_override("font_color", COLOR_INK)
	popup.add_theme_color_override("font_hover_color", COLOR_INK)
	popup.add_theme_color_override("font_accelerator_color", COLOR_INK_MUTED)
	popup.add_theme_color_override("font_disabled_color", COLOR_INK_MUTED)
	popup.add_theme_font_size_override("font_size", 17)


func _style_button(btn: Button, base: Color, hover: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = base
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	normal.shadow_color = Color(base.r, base.g, base.b, 0.28)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 2)
	var hover_style := normal.duplicate() as StyleBoxFlat
	hover_style.bg_color = hover
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("#c8bca5")
	disabled.shadow_color = Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", Color("#ffffff"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	btn.add_theme_color_override("font_disabled_color", Color("#756b59"))


func _on_assist_pressed(action: Dictionary) -> void:
	if _submitting or not _pending_request_id.is_empty():
		return
	var target_field := str(action.get("target_field", "")).strip_edges()
	if target_field.is_empty() or not _field_controls.has(target_field):
		_set_status("找不到要辅助生成的字段。", true)
		return
	_pending_action = action.duplicate(true)
	_set_busy(true, str(action.get("running_label", "林夏正在帮你整理...")))

	if _llm_service == null or not _llm_service.is_enabled():
		_apply_assist_value(_build_fallback_assist_value(action))
		return

	var prompt := _build_assist_prompt(action)
	var system_prompt := _build_assist_system_prompt(action)
	_pending_request_id = _llm_service.request_text(prompt, system_prompt, {
		"mode": "assist",
		"action_id": str(action.get("id", "")),
	}, {"temperature": float(action.get("temperature", 0.7))})
	if _pending_request_id.is_empty():
		_apply_assist_value(_build_fallback_assist_value(action))


func _build_assist_system_prompt(action: Dictionary) -> String:
	var custom := str(action.get("system_prompt", "")).strip_edges()
	if not custom.is_empty():
		return custom
	return _resolve_prompt(ASSIST_SYSTEM_PROMPT_KEY, "协助玩家填写结构化表单。只输出 DSL：value: <文本>")


func _build_assist_prompt(action: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("表单：%s" % str(_form_config.get("title", "")))
	lines.append("目标字段：%s" % str(action.get("target_field", "")))
	var prompt_text := str(action.get("prompt", "")).strip_edges()
	if not prompt_text.is_empty():
		lines.append("要求：%s" % prompt_text)
	lines.append("")
	lines.append("当前表单内容：")
	var values := _collect_values()
	for key in values.keys():
		lines.append("- %s: %s" % [str(key), _format_value_for_prompt(values[key])])
	return "\n".join(lines)


func _build_fallback_assist_value(action: Dictionary) -> String:
	var fallback := str(action.get("fallback_value", "")).strip_edges()
	if not fallback.is_empty():
		return fallback
	var values := _collect_values()
	var title := str(values.get("game_title", values.get("title", "这个作品"))).strip_edges()
	var genre := str(values.get("game_genre", "AVG")).strip_edges()
	var tags := _format_value_for_prompt(values.get("game_tags", []))
	if title.is_empty():
		title = "这个作品"
	if tags.is_empty():
		tags = "日常"
	return "在一所以魔法闻名的学院中，主角意外卷入一场与异世界秘密有关的事件。作品以「%s」为核心印象，在%s的氛围下推进一段%s故事。" % [title, tags, genre]


func _on_submit_pressed() -> void:
	if _submitting or not _pending_request_id.is_empty():
		return
	var validation := _validate_form()
	if not bool(validation.get("ok", false)):
		_set_status(str(validation.get("message", "请检查表单。")), true)
		return
	_pending_submit_values = _collect_values()
	_start_review_or_finish(_pending_submit_values)


func _start_review_or_finish(values: Dictionary) -> void:
	var review: Dictionary = _form_config.get("review", {})
	if review.is_empty() or str(review.get("mode", "none")).strip_edges().to_lower() == "none":
		_finish_with_values(values)
		return
	_submitting = true
	_set_busy(true, str(review.get("running_label", "正在审核表单...")))

	if _llm_service == null or not _llm_service.is_enabled():
		_finish_with_values(values)
		return

	var prompt := _build_review_prompt(values, review)
	var system_prompt := _build_review_system_prompt(review)
	_pending_request_id = _llm_service.request_text(prompt, system_prompt, {
		"mode": "review",
	}, {"temperature": float(review.get("temperature", 0.3))})
	if _pending_request_id.is_empty():
		_finish_with_values(values)


func _build_review_system_prompt(review: Dictionary) -> String:
	var custom := str(review.get("system_prompt", "")).strip_edges()
	if not custom.is_empty():
		return custom
	return _resolve_prompt(REVIEW_SYSTEM_PROMPT_KEY, "审核结构化表单，默认通过。只输出 DSL：approved: true\nreason:")


func _build_review_prompt(values: Dictionary, review: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("表单：%s" % str(_form_config.get("title", "")))
	var rule := str(review.get("rule", "")).strip_edges()
	if not rule.is_empty():
		lines.append("审核规则：%s" % rule)
	lines.append("")
	lines.append("提交内容：")
	for key in values.keys():
		lines.append("- %s: %s" % [str(key), _format_value_for_prompt(values[key])])
	return "\n".join(lines)


func _on_llm_completed(request_id: String, context: Dictionary, raw_text: String, _response: Dictionary) -> void:
	if request_id != _pending_request_id:
		return
	_pending_request_id = ""
	var mode := str(context.get("mode", ""))
	if mode == "assist":
		var value := _parse_value_dsl(raw_text)
		if value.is_empty():
			value = _build_fallback_assist_value(_pending_action)
		_apply_assist_value(value)
		return
	if mode == "review":
		var result := _parse_review_dsl(raw_text)
		if bool(result.get("approved", true)):
			_finish_with_values(_pending_submit_values)
		else:
			_submitting = false
			_set_busy(false)
			_set_status("审核未通过：%s" % str(result.get("reason", "内容不符合要求")), true)


func _on_llm_failed(request_id: String, context: Dictionary, _error_message: String, _error_code: int) -> void:
	if request_id != _pending_request_id:
		return
	_pending_request_id = ""
	var mode := str(context.get("mode", ""))
	if mode == "assist":
		_apply_assist_value(_build_fallback_assist_value(_pending_action))
		return
	if mode == "review":
		_finish_with_values(_pending_submit_values)


func _apply_assist_value(value: String) -> void:
	var target_field := str(_pending_action.get("target_field", "")).strip_edges()
	_set_field_value(target_field, value.strip_edges())
	_pending_action = {}
	_set_busy(false)
	_set_status("内容已填入，你可以继续修改。", false)
	_refresh_submit_state()


func _finish_with_values(values: Dictionary) -> void:
	_submitting = false
	_set_busy(false)
	var result := {
		"score": 1.0,
		"result_kind": "structured_form",
		"form_id": str(_form_config.get("form_id", "generic_form")),
		"form_values": values.duplicate(true),
		"creative_prompt": _build_creative_prompt(values),
		"review_type_desc": str(_form_config.get("review_type_desc", "搭档刚提交了一份结构化方案")),
		"review_performance_desc": str(_form_config.get("review_performance_desc", "这份表单已经收束成可以继续推进的明确输入。")),
	}
	present_summary_and_finish({
		"title": str(_form_config.get("summary_title", "表单已提交")),
		"subtitle": str(_form_config.get("summary_subtitle", "这份内容会作为后续开发的输入。")),
		"stats": _build_summary_stats(values),
		"button_text": str(_form_config.get("summary_button", "完成")),
		"result": result,
	})


func _build_summary_stats(values: Dictionary) -> Array[String]:
	var stats: Array[String] = []
	for field in _fields:
		var field_id := str(field.get("id", ""))
		var label := str(field.get("label", field_id))
		if not values.has(field_id):
			continue
		var value_text := _format_value_for_prompt(values[field_id])
		if value_text.length() > 60:
			value_text = value_text.left(57) + "..."
		stats.append("%s：%s" % [label, value_text])
		if stats.size() >= 4:
			break
	return stats


func _build_creative_prompt(values: Dictionary) -> String:
	var lines: PackedStringArray = []
	for field in _fields:
		var field_id := str(field.get("id", ""))
		if values.has(field_id):
			lines.append("%s：%s" % [
				str(field.get("label", field_id)),
				_format_value_for_prompt(values[field_id]),
			])
	return "\n".join(lines)


func _collect_values() -> Dictionary:
	var values: Dictionary = {}
	for field in _fields:
		var field_id := str(field.get("id", ""))
		if field_id.is_empty():
			continue
		values[field_id] = _get_field_value(field_id)
	return values


func _get_field_value(field_id: String) -> Variant:
	var info: Dictionary = _field_controls.get(field_id, {})
	var kind := str(info.get("kind", ""))
	match kind:
		"text":
			var edit: LineEdit = info.get("node")
			return edit.text.strip_edges() if edit != null else ""
		"textarea":
			var edit: TextEdit = info.get("node")
			return edit.text.strip_edges() if edit != null else ""
		"single_select":
			var select: OptionButton = info.get("select")
			var custom: LineEdit = info.get("custom")
			if select == null or select.selected <= 0:
				return ""
			if bool(info.get("allow_custom", false)) and select.get_item_text(select.selected) == "自定义...":
				return custom.text.strip_edges() if custom != null else ""
			return select.get_item_text(select.selected)
		"multi_select":
			var result: Array[String] = []
			var checks: Array = info.get("checks", [])
			for item in checks:
				var cb: CheckBox = item
				if cb != null and cb.button_pressed:
					result.append(cb.text)
			return result
	return ""


func _set_field_value(field_id: String, value: Variant) -> void:
	var info: Dictionary = _field_controls.get(field_id, {})
	var kind := str(info.get("kind", ""))
	match kind:
		"text":
			var edit: LineEdit = info.get("node")
			if edit != null:
				edit.text = str(value)
		"textarea":
			var edit: TextEdit = info.get("node")
			if edit != null:
				edit.text = str(value)
		"single_select":
			_set_single_select_value(info, str(value))
		"multi_select":
			var values := _as_string_array(value)
			for item in info.get("checks", []):
				var cb: CheckBox = item
				if cb != null:
					cb.button_pressed = cb.text in values


func _set_single_select_value(info: Dictionary, value: String) -> void:
	var select: OptionButton = info.get("select")
	var custom: LineEdit = info.get("custom")
	if select == null:
		return
	for i in range(1, select.item_count):
		if select.get_item_text(i) == value:
			select.selected = i
			if custom != null:
				custom.visible = false
			return
	if bool(info.get("allow_custom", false)):
		select.selected = select.item_count - 1
		if custom != null:
			custom.visible = true
			custom.text = value


func _validate_form() -> Dictionary:
	for field in _fields:
		var field_id := str(field.get("id", ""))
		var label := str(field.get("label", field_id))
		var value: Variant = _get_field_value(field_id)
		if bool(field.get("required", false)) and _is_empty_value(value):
			return {"ok": false, "message": "请填写%s。" % label}
		var max_length := int(field.get("max_length", 0))
		if max_length > 0 and str(value).length() > max_length:
			return {"ok": false, "message": "%s不能超过 %d 字。" % [label, max_length]}
		if str(field.get("type", "")) == "multi_select":
			var selected_count := (value as Array).size() if value is Array else 0
			var min_selected := int(field.get("min_selected", 0))
			var max_selected := int(field.get("max_selected", 0))
			if min_selected > 0 and selected_count < min_selected:
				return {"ok": false, "message": "%s至少选择 %d 项。" % [label, min_selected]}
			if max_selected > 0 and selected_count > max_selected:
				return {"ok": false, "message": "%s最多选择 %d 项。" % [label, max_selected]}
	return {"ok": true}


func _is_empty_value(value: Variant) -> bool:
	if value is Array:
		return (value as Array).is_empty()
	return str(value).strip_edges().is_empty()


func _refresh_submit_state() -> void:
	if _submit_button == null:
		return
	_submit_button.disabled = _submitting or not _pending_request_id.is_empty()


func _set_busy(busy: bool, message: String = "") -> void:
	_submitting = busy and _pending_action.is_empty()
	if _submit_button != null:
		_submit_button.disabled = busy
	if _assist_box != null:
		for action_button in _assist_box.get_children():
			if action_button is Button:
				(action_button as Button).disabled = busy
	if not message.is_empty():
		_set_status(message, false)


func _set_status(message: String, is_error: bool) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.add_theme_color_override("font_color", COLOR_ERROR if is_error else COLOR_INK_MUTED)


func _format_value_for_prompt(value: Variant) -> String:
	if value is Array:
		var parts: PackedStringArray = []
		for item in value:
			parts.append(str(item))
		return ", ".join(parts)
	return str(value)


func _as_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			var text := str(item).strip_edges()
			if not text.is_empty():
				result.append(text)
	elif value is PackedStringArray:
		for item in value:
			var text := str(item).strip_edges()
			if not text.is_empty():
				result.append(text)
	else:
		var text := str(value).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _parse_value_dsl(raw_text: String) -> String:
	var text := raw_text.strip_edges()
	if text.is_empty():
		return ""
	var lines := text.split("\n")
	var collecting := false
	var collected: PackedStringArray = []
	for raw_line in lines:
		var line := str(raw_line).strip_edges()
		if line.to_lower().begins_with("value:") or line.begins_with("value："):
			var colon := line.find(":")
			if colon < 0:
				colon = line.find("：")
			var rest := line.substr(colon + 1).strip_edges()
			if not rest.is_empty():
				return rest
			collecting = true
			continue
		if collecting:
			collected.append(str(raw_line).strip_edges())
	if not collected.is_empty():
		return "\n".join(collected).strip_edges()
	return text


func _parse_review_dsl(raw_text: String) -> Dictionary:
	var result := {"approved": true, "reason": ""}
	for raw_line in raw_text.strip_edges().split("\n"):
		var line := str(raw_line).strip_edges()
		var lower := line.to_lower()
		if lower.begins_with("approved:") or lower.begins_with("approved："):
			var value := _strip_dsl_label(line)
			result["approved"] = value.to_lower() not in ["false", "no", "0", "拒绝", "不通过"]
		elif lower.begins_with("reason:") or lower.begins_with("reason："):
			result["reason"] = _strip_dsl_label(line)
	return result


func _strip_dsl_label(line: String) -> String:
	var colon := line.find(":")
	if colon < 0:
		colon = line.find("：")
	if colon < 0:
		return line.strip_edges()
	return line.substr(colon + 1).strip_edges()


func _resolve_prompt(prompt_key: String, fallback: String) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("has_prompt") and pm.has_method("resolve"):
		if pm.has_prompt(prompt_key):
			var resolved := str(pm.resolve(prompt_key)).strip_edges()
			if not resolved.is_empty():
				return resolved
	return fallback
