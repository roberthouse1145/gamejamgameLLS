class_name WebPageRenderer
extends RefCounted

const FIELD_ERROR_TEXT_COLOR := "#B42318"


static func render(page_json: Dictionary, on_action: Callable = Callable(), page_state: Dictionary = {}) -> Control:
	var state: Dictionary = page_state.duplicate(true)
	if not state.has("inputs"):
		state["inputs"] = {}
	if not state.has("fields"):
		state["fields"] = {}
	if not state.has("field_order"):
		state["field_order"] = []
	var root: Control = _build_node(page_json, on_action, state)
	if root == null:
		var fallback := Label.new()
		fallback.text = "Page render failed"
		fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return fallback
	return root


static func collect_form_data(page_state: Dictionary) -> Dictionary:
	return _collect_form_data(page_state)


static func validate_form(page_state: Dictionary, form_data: Dictionary = {}) -> Dictionary:
	var effective_form_data: Dictionary = form_data.duplicate(true)
	if effective_form_data.is_empty():
		effective_form_data = _collect_form_data(page_state)
	return _validate_form(page_state, effective_form_data)


static func _build_node(node_data: Variant, on_action: Callable, page_state: Dictionary) -> Control:
	if not node_data is Dictionary:
		var invalid := Label.new()
		invalid.text = "Invalid node"
		return invalid

	var data: Dictionary = node_data
	var node_type: String = str(data.get("type", "")).to_lower()

	match node_type:
		"margin", "margincontainer":
			return _apply_container_flags(_build_margin(data, on_action, page_state))
		"vbox":
			return _build_box_node(data, true, on_action, page_state)
		"hbox":
			return _build_box_node(data, false, on_action, page_state)
		"label":
			return _apply_content_flags(_build_label(data))
		"rich_text":
			return _apply_content_flags(_build_rich_text(data))
		"panel":
			var panel_node := _build_panel(data, on_action, page_state)
			_apply_size_attrs(panel_node, data)
			return panel_node
		"panelcontainer":
			var panel_container_node := _build_panel_container(data, on_action, page_state)
			_apply_panel_container_size_attrs(panel_container_node, data)
			return panel_container_node
		"separator":
			return _apply_content_flags(_build_separator(data))
		"spacer":
			return _build_spacer(data)
		"button":
			return _apply_content_flags(_build_button(data, on_action, page_state))
		"link":
			return _apply_content_flags(_build_link(data, on_action))
		"input":
			return _apply_content_flags(_build_input(data, page_state))
		"textarea":
			return _apply_content_flags(_build_text_area(data, page_state))
		"checkbox":
			return _apply_content_flags(_build_checkbox(data, page_state))
		"select":
			return _apply_content_flags(_build_select(data, page_state))
		"scroll":
			return _apply_container_flags(_build_scroll(data, on_action, page_state))
		_:
			var unknown := Label.new()
			unknown.text = "[Unsupported node type] %s" % node_type
			unknown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			unknown.add_theme_color_override("font_color", Color("#ffb86c"))
			return _apply_content_flags(unknown)


static func _apply_container_flags(ctrl: Control) -> Control:
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return ctrl


static func _apply_content_flags(ctrl: Control) -> Control:
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return ctrl


static func _apply_size_attrs(ctrl: Control, data: Dictionary) -> void:
	var has_width := data.has("width")
	var has_height := data.has("height")
	var has_fill: bool = _as_bool(data.get("fill", false))
	var has_shrink: bool = _as_bool(data.get("shrink", false))
	if has_width:
		ctrl.custom_minimum_size.x = int(data["width"])
	if has_height:
		ctrl.custom_minimum_size.y = int(data["height"])
	if has_shrink:
		ctrl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		ctrl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	elif has_fill:
		ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	elif has_width and not has_height:
		ctrl.custom_minimum_size.x = int(data["width"])
		ctrl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	elif has_height and not has_width:
		ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func _build_box_node(data: Dictionary, is_vbox: bool, on_action: Callable, page_state: Dictionary) -> Control:
	var box := _build_box(data, is_vbox, on_action, page_state)
	var result: Control = box
	if data.has("bg_color"):
		result = _wrap_with_bg(box, data)
	_apply_size_attrs(result, data)
	return result


static func _wrap_with_bg(inner: Control, data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _parse_color(data.get("bg_color", "#ffffff"), Color("#ffffff"))
	panel.add_theme_stylebox_override("panel", style)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(inner)
	return panel


static func _build_margin(data: Dictionary, on_action: Callable, page_state: Dictionary) -> Control:
	var margin := MarginContainer.new()
	var all_margin: int = int(data.get("margin", 0))
	margin.add_theme_constant_override("margin_left", int(data.get("margin_left", all_margin)))
	margin.add_theme_constant_override("margin_top", int(data.get("margin_top", all_margin)))
	margin.add_theme_constant_override("margin_right", int(data.get("margin_right", all_margin)))
	margin.add_theme_constant_override("margin_bottom", int(data.get("margin_bottom", all_margin)))

	var child: Variant = data.get("child", {})
	var child_node: Control = _build_node(child, on_action, page_state)
	margin.add_child(child_node)
	return margin


static func _build_box(data: Dictionary, is_vbox: bool, on_action: Callable, page_state: Dictionary) -> Control:
	var box: BoxContainer
	if is_vbox:
		box = VBoxContainer.new()
	else:
		box = HBoxContainer.new()
	box.add_theme_constant_override("separation", int(data.get("separation", 8)))

	var children: Array = data.get("children", [])
	for item in children:
		var child_node: Control = _build_node(item, on_action, page_state)
		box.add_child(child_node)

	return box


static func _build_label(data: Dictionary) -> Control:
	var label := Label.new()
	label.text = str(data.get("text", ""))
	if _as_bool(data.get("nowrap", false)):
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(data.get("font_size", 22)))
	label.add_theme_color_override("font_color", _parse_color(data.get("color", "#1A1D27"), Color("#1A1D27")))

	if data.has("align"):
		match str(data["align"]):
			"center":
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			"right":
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	return label


static func _build_rich_text(data: Dictionary) -> Control:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.text = str(data.get("bbcode", ""))
	rich.add_theme_font_size_override("normal_font_size", int(data.get("font_size", 22)))
	rich.add_theme_color_override("default_color", _parse_color(data.get("color", "#333333"), Color("#333333")))
	return rich


static func _build_panel(data: Dictionary, on_action: Callable, page_state: Dictionary) -> Control:
	var panel := PanelContainer.new()
	_apply_panel_style(panel, data)
	var margin := _build_panel_margin(data, on_action, page_state)
	panel.add_child(margin)
	return panel


static func _build_panel_container(data: Dictionary, on_action: Callable, page_state: Dictionary) -> Control:
	var panel := PanelContainer.new()
	_apply_panel_style(panel, data)
	var margin := _build_panel_margin(data, on_action, page_state)
	panel.add_child(margin)
	return panel


static func _apply_panel_style(panel: Control, data: Dictionary) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = _parse_color(data.get("bg_color", "#ffffff"), Color("#ffffff"))
	var radius: int = int(data.get("corner_radius", 8))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = _parse_color(data.get("border_color", "#E2E4EA"), Color("#E2E4EA"))
	panel.add_theme_stylebox_override("panel", style)


static func _build_panel_margin(data: Dictionary, on_action: Callable, page_state: Dictionary) -> MarginContainer:
	var margin := MarginContainer.new()
	var padding: int = int(data.get("padding", 12))
	margin.add_theme_constant_override("margin_left", padding)
	margin.add_theme_constant_override("margin_top", padding)
	margin.add_theme_constant_override("margin_right", padding)
	margin.add_theme_constant_override("margin_bottom", padding)
	var child: Variant = data.get("child", {})
	var child_node: Control = _build_node(child, on_action, page_state)
	margin.add_child(child_node)
	return margin


static func _apply_panel_container_size_attrs(ctrl: Control, data: Dictionary) -> void:
	var has_width := data.has("width")
	var has_height := data.has("height")
	var has_fill: bool = _as_bool(data.get("fill", false))
	var has_shrink: bool = _as_bool(data.get("shrink", false))

	if has_width:
		ctrl.custom_minimum_size.x = int(data["width"])
	if has_height:
		ctrl.custom_minimum_size.y = int(data["height"])

	if has_shrink:
		ctrl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		ctrl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return

	if has_fill:
		ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		return

	ctrl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ctrl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


static func _build_separator(data: Dictionary) -> Control:
	var sep := HSeparator.new()
	if data.has("color"):
		var style := StyleBoxLine.new()
		style.color = _parse_color(data.get("color", "#5a5a5a"), Color("#5a5a5a"))
		style.thickness = 1
		sep.add_theme_stylebox_override("separator", style)
	return sep


static func _build_spacer(data: Dictionary) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(int(data.get("width", 0)), int(data.get("height", 0)))
	return spacer


static func _build_button(data: Dictionary, on_action: Callable, page_state: Dictionary) -> Control:
	var button := Button.new()
	button.text = str(data.get("text", "Open"))
	button.clip_text = true
	button.add_theme_font_size_override("font_size", int(data.get("font_size", 18)))
	var btn_color: Color = _parse_color(data.get("color", "#333333"), Color("#333333"))
	button.add_theme_color_override("font_color", btn_color)
	button.add_theme_color_override("font_hover_color", btn_color)
	button.add_theme_color_override("font_pressed_color", btn_color)
	button.add_theme_color_override("font_focus_color", btn_color)
	button.add_theme_color_override("font_hover_pressed_color", btn_color)

	if data.has("bg_color"):
		var bg: Color = _parse_color(data.get("bg_color", "#4A7CFF"), Color("#4A7CFF"))
		var hover_bg: Color = bg.darkened(0.12)
		var pressed_bg: Color = bg.darkened(0.2)
		var disabled_bg: Color = Color("#E2E4EA")
		var radius: int = 6
		button.add_theme_stylebox_override("normal", _make_btn_style(bg, radius))
		button.add_theme_stylebox_override("hover", _make_btn_style(hover_bg, radius))
		button.add_theme_stylebox_override("pressed", _make_btn_style(pressed_bg, radius))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("disabled", _make_btn_style(disabled_bg, radius))
		button.add_theme_color_override("font_disabled_color", Color("#9EA2B5"))

	button.disabled = _as_bool(data.get("disabled", false))
	if data.has("action") and on_action.is_valid():
		button.pressed.connect(func():
			var action_data := data.duplicate(true)
			if _should_collect_form_data(action_data):
				var form_data := _collect_form_data(page_state)
				action_data["__form_data"] = form_data
				if _should_validate_form(action_data):
					action_data["__form_validation"] = _validate_form(page_state, form_data)
			on_action.call(action_data)
		)
	return button


static func _make_btn_style(bg: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


static func _build_link(data: Dictionary, on_action: Callable) -> Control:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	if _as_bool(data.get("nowrap", false)):
		rich.autowrap_mode = TextServer.AUTOWRAP_OFF
	else:
		rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var link_text: String = str(data.get("text", ""))
	var link_color: String = str(data.get("color", "#4A90D9"))
	var link_font_size: int = int(data.get("font_size", 20))
	rich.add_theme_font_size_override("normal_font_size", link_font_size)
	if data.has("action") and on_action.is_valid():
		var url_val: String = str(data.get("url", ""))
		rich.text = "[color=%s][url=%s]%s[/url][/color]" % [link_color, url_val, link_text]
		var action_data := data.duplicate(true)
		rich.meta_clicked.connect(func(_meta: Variant): on_action.call(action_data))
	else:
		rich.text = "[color=%s]%s[/color]" % [link_color, link_text]
	return rich


static func _build_input(data: Dictionary, page_state: Dictionary) -> Control:
	var line_edit := LineEdit.new()
	line_edit.placeholder_text = str(data.get("placeholder", ""))
	line_edit.text = str(data.get("value", ""))
	line_edit.editable = not _as_bool(data.get("disabled", false))
	line_edit.custom_minimum_size.y = 42
	line_edit.add_theme_font_size_override("font_size", int(data.get("font_size", 20)))
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if data.has("secret"):
		line_edit.secret = _as_bool(data.get("secret", false))
	var max_length: int = int(str(data.get("max_length", 0)))
	if max_length > 0:
		line_edit.max_length = max_length
	var field_name: String = str(data.get("field", "")).strip_edges()
	if not field_name.is_empty():
		page_state["inputs"][field_name] = line_edit
	return _wrap_field_control(line_edit, data, page_state, "input")


static func _build_text_area(data: Dictionary, page_state: Dictionary) -> Control:
	var text_edit := TextEdit.new()
	text_edit.text = str(data.get("text", data.get("value", "")))
	text_edit.editable = not _as_bool(data.get("disabled", false))
	text_edit.custom_minimum_size.y = int(data.get("height", 120))
	text_edit.add_theme_font_size_override("font_size", int(data.get("font_size", 20)))
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	return _wrap_field_control(text_edit, data, page_state, "textarea")


static func _build_checkbox(data: Dictionary, page_state: Dictionary) -> Control:
	var checkbox := CheckBox.new()
	checkbox.text = str(data.get("text", data.get("label", "")))
	checkbox.button_pressed = _as_bool(data.get("checked", false))
	checkbox.disabled = _as_bool(data.get("disabled", false))
	checkbox.add_theme_font_size_override("font_size", int(data.get("font_size", 18)))
	return _wrap_field_control(checkbox, data, page_state, "checkbox")


static func _build_select(data: Dictionary, page_state: Dictionary) -> Control:
	var select := OptionButton.new()
	select.disabled = _as_bool(data.get("disabled", false))
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.add_theme_font_size_override("font_size", int(data.get("font_size", 18)))
	var option_values := PackedStringArray()

	var options: Array = _parse_select_options(data.get("options", []))
	var placeholder: String = str(data.get("placeholder", "")).strip_edges()
	if not placeholder.is_empty():
		select.add_item(placeholder)
		option_values.append("")

	for option in options:
		if not option is Dictionary:
			continue
		var option_dict: Dictionary = option
		select.add_item(str(option_dict.get("label", "")))
		option_values.append(str(option_dict.get("value", "")))

	var selected_value: String = str(data.get("value", data.get("selected", ""))).strip_edges()
	if selected_value.is_empty():
		select.selected = 0 if select.item_count > 0 else -1
	else:
		var found_index := -1
		for index in range(option_values.size()):
			if option_values[index] == selected_value:
				found_index = index
				break
		select.selected = found_index if found_index >= 0 else 0
	select.set_meta("option_values", option_values)
	return _wrap_field_control(select, data, page_state, "select")


static func _wrap_field_control(control: Control, data: Dictionary, page_state: Dictionary, field_type: String) -> Control:
	var field_name: String = str(data.get("field", "")).strip_edges()
	if field_name.is_empty():
		return control

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 4)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(control)

	var error_label := Label.new()
	error_label.visible = false
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_size_override("font_size", 14)
	error_label.add_theme_color_override("font_color", Color(FIELD_ERROR_TEXT_COLOR))
	error_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(error_label)

	_register_field(page_state, field_name, control, field_type, data, error_label)
	_connect_field_interaction(control, page_state, field_name)
	return wrapper


static func _register_field(
	page_state: Dictionary,
	field_name: String,
	control: Control,
	field_type: String,
	config: Dictionary,
	error_label: Label
) -> void:
	var fields: Dictionary = page_state.get("fields", {})
	fields[field_name] = {
		"control": control,
		"field_type": field_type,
		"config": config.duplicate(true),
		"error_label": error_label,
		"option_values": _extract_option_values(config),
	}
	page_state["fields"] = fields
	var field_order: Array = page_state.get("field_order", [])
	if not field_order.has(field_name):
		field_order.append(field_name)
	page_state["field_order"] = field_order


static func _connect_field_interaction(control: Control, page_state: Dictionary, field_name: String) -> void:
	if control is LineEdit:
		var line_edit := control as LineEdit
		line_edit.text_changed.connect(func(_new_text: String) -> void:
			_clear_field_error(page_state, field_name)
		)
	elif control is TextEdit:
		var text_edit := control as TextEdit
		text_edit.text_changed.connect(func() -> void:
			_clear_field_error(page_state, field_name)
		)
	elif control is CheckBox:
		var checkbox := control as CheckBox
		checkbox.toggled.connect(func(_pressed: bool) -> void:
			_clear_field_error(page_state, field_name)
		)
	elif control is OptionButton:
		var select := control as OptionButton
		select.item_selected.connect(func(_index: int) -> void:
			_clear_field_error(page_state, field_name)
		)


static func _build_scroll(data: Dictionary, on_action: Callable, page_state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var child: Variant = data.get("child", {})
	var child_node: Control = _build_node(child, on_action, page_state)
	scroll.add_child(child_node)
	return scroll


static func _should_collect_form_data(action_data: Dictionary) -> bool:
	if _should_validate_form(action_data):
		return true
	return _as_bool(action_data.get("collect_form", false))


static func _should_validate_form(action_data: Dictionary) -> bool:
	if _as_bool(action_data.get("validate_form", false)):
		return true
	return str(action_data.get("action", "")) == "submit_story_form"


static func _collect_form_data(page_state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var fields: Dictionary = page_state.get("fields", {})
	if not fields.is_empty():
		for field_name in fields.keys():
			var entry_variant: Variant = fields[field_name]
			if not entry_variant is Dictionary:
				continue
			var entry: Dictionary = entry_variant
			result[str(field_name)] = _extract_field_value(entry)
		return result

	var inputs: Dictionary = page_state.get("inputs", {})
	for field_name in inputs.keys():
		var input_node: LineEdit = inputs[field_name]
		if input_node != null and is_instance_valid(input_node):
			result[str(field_name)] = input_node.text
	return result


static func _validate_form(page_state: Dictionary, form_data: Dictionary) -> Dictionary:
	var errors: Dictionary = {}
	var fields: Dictionary = page_state.get("fields", {})
	var ordered_fields: Array = page_state.get("field_order", [])

	for field_name_variant in ordered_fields:
		var field_name: String = str(field_name_variant)
		if not fields.has(field_name):
			continue
		var entry_variant: Variant = fields[field_name]
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var error_text: String = _validate_field(field_name, entry, form_data.get(field_name, null))
		if not error_text.is_empty():
			errors[field_name] = error_text

	for field_name_variant in fields.keys():
		var field_name: String = str(field_name_variant)
		if errors.has(field_name) or ordered_fields.has(field_name):
			continue
		var entry_variant: Variant = fields[field_name]
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var error_text: String = _validate_field(field_name, entry, form_data.get(field_name, null))
		if not error_text.is_empty():
			errors[field_name] = error_text

	_apply_validation_state(page_state, errors)

	var first_error := ""
	for field_name_variant in ordered_fields:
		var field_name: String = str(field_name_variant)
		if errors.has(field_name):
			first_error = str(errors[field_name])
			break
	if first_error.is_empty():
		for field_name_variant in errors.keys():
			first_error = str(errors[field_name_variant])
			break

	return {
		"is_valid": errors.is_empty(),
		"errors": errors,
		"first_error": first_error,
	}


static func _validate_field(field_name: String, entry: Dictionary, value: Variant) -> String:
	var config: Dictionary = entry.get("config", {})
	var field_type: String = str(entry.get("field_type", "input"))
	var label: String = str(config.get("label", config.get("placeholder", field_name))).strip_edges()
	if label.is_empty():
		label = field_name

	if _as_bool(config.get("required", false)) and _is_empty_field_value(value, field_type):
		return str(config.get("required_message", "%s cannot be empty" % label))

	if _is_empty_field_value(value, field_type):
		return ""

	var text_value: String = ""
	match field_type:
		"checkbox":
			text_value = "true" if bool(value) else "false"
		_:
			text_value = str(value)

	var min_length: int = int(str(config.get("min_length", 0)))
	if min_length > 0 and text_value.length() < min_length:
		return str(config.get("min_length_message", "%s must be at least %d characters" % [label, min_length]))

	var max_length: int = int(str(config.get("max_length", 0)))
	if max_length > 0 and text_value.length() > max_length:
		return str(config.get("max_length_message", "%s must be at most %d characters" % [label, max_length]))

	var pattern: String = str(config.get("pattern", "")).strip_edges()
	if not pattern.is_empty():
		var regex := RegEx.new()
		if regex.compile(pattern) == OK and regex.search(text_value) == null:
			return str(config.get("pattern_message", "%s format is invalid" % label))

	if field_type == "select":
		var option_values: PackedStringArray = entry.get("option_values", PackedStringArray())
		if not option_values.is_empty() and not option_values.has(text_value):
			return str(config.get("option_message", "%s option is invalid" % label))

	return ""


static func _apply_validation_state(page_state: Dictionary, errors: Dictionary) -> void:
	var fields: Dictionary = page_state.get("fields", {})
	for field_name_variant in fields.keys():
		var field_name: String = str(field_name_variant)
		var entry_variant: Variant = fields[field_name]
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var error_label: Label = entry.get("error_label", null)
		var control: Control = entry.get("control", null)
		var error_text: String = str(errors.get(field_name, "")).strip_edges()

		if control != null and is_instance_valid(control):
			control.tooltip_text = error_text
		if error_label == null or not is_instance_valid(error_label):
			continue
		error_label.text = error_text
		error_label.visible = not error_text.is_empty()


static func _clear_field_error(page_state: Dictionary, field_name: String) -> void:
	var fields: Dictionary = page_state.get("fields", {})
	if not fields.has(field_name):
		return
	var entry_variant: Variant = fields[field_name]
	if not entry_variant is Dictionary:
		return
	var entry: Dictionary = entry_variant
	var error_label: Label = entry.get("error_label", null)
	var control: Control = entry.get("control", null)
	if control != null and is_instance_valid(control):
		control.tooltip_text = ""
	if error_label != null and is_instance_valid(error_label):
		error_label.text = ""
		error_label.visible = false


static func _extract_field_value(entry: Dictionary) -> Variant:
	var control: Control = entry.get("control", null)
	if control == null or not is_instance_valid(control):
		return null
	var field_type: String = str(entry.get("field_type", "input"))
	match field_type:
		"textarea":
			var text_edit := control as TextEdit
			return text_edit.text if text_edit != null else ""
		"checkbox":
			var checkbox := control as CheckBox
			return checkbox.button_pressed if checkbox != null else false
		"select":
			var select := control as OptionButton
			if select == null or select.item_count == 0 or select.selected < 0:
				return ""
			var option_values: PackedStringArray = select.get_meta("option_values", PackedStringArray())
			if select.selected < option_values.size():
				return option_values[select.selected]
			return select.get_item_text(select.selected)
		_:
			var line_edit := control as LineEdit
			return line_edit.text if line_edit != null else ""


static func _is_empty_field_value(value: Variant, field_type: String) -> bool:
	match field_type:
		"checkbox":
			return not bool(value)
		_:
			return str(value).strip_edges().is_empty()


static func _extract_option_values(config: Dictionary) -> PackedStringArray:
	var values := PackedStringArray()
	for option in _parse_select_options(config.get("options", [])):
		if option is Dictionary:
			values.append(str(option.get("value", "")).strip_edges())
	return values


static func _parse_select_options(raw_options: Variant) -> Array:
	var result: Array = []
	if raw_options is Array:
		for item in raw_options:
			if item is Dictionary:
				var option_dict: Dictionary = item
				result.append({
					"value": str(option_dict.get("value", option_dict.get("label", ""))).strip_edges(),
					"label": str(option_dict.get("label", option_dict.get("value", ""))).strip_edges(),
				})
			else:
				var text := str(item).strip_edges()
				if not text.is_empty():
					result.append({"value": text, "label": text})
		return result

	var raw_text: String = str(raw_options).strip_edges()
	if raw_text.is_empty():
		return result
	for token in raw_text.split("|", false):
		var cleaned: String = str(token).strip_edges()
		if cleaned.is_empty():
			continue
		var separator_index := cleaned.find(":")
		if separator_index > 0:
			result.append({
				"value": cleaned.substr(0, separator_index).strip_edges(),
				"label": cleaned.substr(separator_index + 1).strip_edges(),
			})
		else:
			result.append({"value": cleaned, "label": cleaned})
	return result


static func _as_bool(value: Variant) -> bool:
	if value is bool:
		return value
	var text := str(value).strip_edges().to_lower()
	return text in ["1", "true", "yes", "on"]


static func _parse_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		var as_string: String = str(value)
		if as_string.length() == 4 and as_string.begins_with("#"):
			as_string = "#" + as_string[1] + as_string[1] + as_string[2] + as_string[2] + as_string[3] + as_string[3]
		if Color.html_is_valid(as_string):
			return Color(as_string)
	return fallback
