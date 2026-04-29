class_name AVGDSLSerializer extends RefCounted
## AVG DSL 序列化器
## 将 Array[AVGCommand] 或 Array[Dictionary] 序列化为 DSL 文本
## 输出 AVG DSL V2 方言，保证结果可被 AVGDSLParserV2 重新解析

const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")

var _variable_lookup: Dictionary = {}

## 指令类型 → 位置参数名列表（generic fallback 使用）
const POSITIONAL_PARAMS: Dictionary = {
	"SHOW_CHARACTER": ["character_id"],
	"HIDE_CHARACTER": ["character_id"],
	"CHANGE_EXPRESSION": ["character_id", "expression"],
	"MOVE_CHARACTER": ["character_id"],
	"MOVE_CHARACTER_BY": ["character_id"],
	"FLIP_CHARACTER": ["character_id"],
	"CHARACTER_EFFECT": ["character_id", "effect"],
	"SET_CHARACTER_PROPERTY": ["character_id"],
	"WAIT_TIME": ["duration"],
	"LABEL": ["name"],
	"JUMP_LABEL": ["target"],
	"JUMP_SCENE": ["scene_id"],
	"CALL_EVENT": ["event_id"],
	"PLAY_BGM": ["audio_path"],
	"PLAY_SFX": ["audio_path"],
	"CHANGE_BACKGROUND": ["texture_path"],
	"SHOW_IMAGE": ["image_id", "image_path"],
	"HIDE_IMAGE": ["image_id"],
	"SCREEN_FADE": ["direction"],
	"SET_TIME_OF_DAY": ["preset"],
	"SCREEN_FLASH": [],
	"SCREEN_SHAKE": [],
	"CAMERA_ZOOM": ["zoom"],
	"CAMERA_PAN": [],
	"CAMERA_RESET": [],
	"SPAWN_NODE": ["shared_node_id"],
	"SHOW_NODE": ["node_id"],
	"HIDE_NODE": ["node_id"],
	"REMOVE_NODE": ["node_id"],
	"SET_TEXT": ["node_id", "text"],
	"SET_STYLE": ["node_id"],
	"MOVE_NODE": ["node_id"],
	"RESIZE_NODE": ["node_id"],
	"SHOW_NOTIFICATION": [],
	"SET_HUD_VISIBLE": [],
	"SET_TEXT_SPEED": ["speed"],
	"CLEAR_DIALOGUE": [],
	"WAIT_CLICK": [],
	"STOP_BGM": [],
}

const OP_TO_SYMBOL: Dictionary = {
	"set": "=",
	"add": "+=",
	"subtract": "-=",
	"multiply": "*=",
	"divide": "/=",
	"modulo": "%=",
}

const STAGE_PARAM_ORDER: Array[String] = [
	"emotions",
	"outfits",
	"duration",
	"enter_effect",
	"exit_effect",
	"enter_distance",
	"exit_distance",
	"move_easing",
	"enter_easing",
	"exit_easing",
]


func serialize(commands: Array, indent_level: int = 0, variable_lookup: Dictionary = {}) -> String:
	var previous_lookup: Dictionary = _variable_lookup
	_variable_lookup = previous_lookup if variable_lookup.is_empty() else variable_lookup
	var lines: Array[String] = []
	for cmd in commands:
		var cmd_type: String = _get_command_type(cmd)
		var params: Dictionary = _get_params(cmd)
		var line: String = _serialize_command(cmd_type, params, indent_level)
		if not line.is_empty():
			lines.append(line)
	_variable_lookup = previous_lookup
	return "\n".join(lines)


func _serialize_command(cmd_type: String, params: Dictionary, indent_level: int) -> String:
	match cmd_type:
		"DIALOGUE":
			return _serialize_dialogue(params, indent_level)
		"JUMP_SCENE":
			return _indent(indent_level) + _serialize_call("scene", "jump", [_serialize_call_literal(params.get("scene_id", ""))], {})
		"JUMP_TO_NODE", "JUMP_LABEL":
			return _indent(indent_level) + _serialize_jump(cmd_type, params)
		"SET_VARIABLE":
			return _indent(indent_level) + _serialize_set_variable(params)
		"IF":
			return _serialize_if(params, indent_level)
		"CHOICE":
			return _serialize_choice(params, indent_level)
		"STAGE_SET", "STAGE_ENTER", "STAGE_EXIT":
			return _indent(indent_level) + _serialize_stage_command(cmd_type, params)
		"SHOW_CHARACTER":
			return _indent(indent_level) + _serialize_character_call(params, "show", ["character_id"])
		"HIDE_CHARACTER":
			return _indent(indent_level) + _serialize_character_call(params, "hide", ["character_id"])
		"CHANGE_EXPRESSION":
			return _indent(indent_level) + _serialize_character_assignment(params, "character_id", "expression", "expression")
		"CHANGE_OUTFIT":
			return _indent(indent_level) + _serialize_character_assignment(params, "character_id", "outfit", "outfit")
		"MOVE_CHARACTER":
			return _indent(indent_level) + _serialize_character_call(params, "move", ["character_id"])
		"FLIP_CHARACTER":
			return _indent(indent_level) + _serialize_character_call(params, "flip", ["character_id"])
		"CHARACTER_EFFECT":
			return _indent(indent_level) + _serialize_character_call(params, "effect", ["character_id", "effect"])
		"PLAY_BGM":
			return _indent(indent_level) + _serialize_call("bgm", "play", [_serialize_call_literal(params.get("audio_path", ""))], _filter_params(params, ["audio_path"]))
		"STOP_BGM":
			return _indent(indent_level) + "bgm.stop()"
		"PLAY_SFX":
			return _indent(indent_level) + _serialize_call("sfx", "play", [_serialize_call_literal(params.get("audio_path", ""))], _filter_params(params, ["audio_path"]))
		"CHANGE_BACKGROUND":
			return _indent(indent_level) + _serialize_call("bg", "show", [_serialize_call_literal(params.get("texture_path", ""))], _filter_params(params, ["texture_path"]))
		"SHOW_IMAGE":
			return _indent(indent_level) + _serialize_image_command(params, false)
		"HIDE_IMAGE":
			return _indent(indent_level) + _serialize_image_command(params, true)
		"SCREEN_FADE":
			return _indent(indent_level) + _serialize_call("screen", "fade", [], params)
		"SET_TIME_OF_DAY":
			return _indent(indent_level) + _serialize_call("screen", "time_of_day", [_serialize_call_literal(params.get("preset", ""))], _filter_params(params, ["preset"]))
		"SCREEN_FLASH":
			return _indent(indent_level) + _serialize_call("screen", "flash", [], params)
		"SCREEN_SHAKE":
			return _indent(indent_level) + _serialize_call("camera", "shake", [], params)
		"CAMERA_ZOOM":
			return _indent(indent_level) + _serialize_call("camera", "zoom", [_serialize_call_literal(params.get("zoom", 1.0))], _filter_params(params, ["zoom"]))
		"CAMERA_PAN":
			return _indent(indent_level) + _serialize_call("camera", "pan", [], params)
		"CAMERA_RESET":
			return _indent(indent_level) + _serialize_call("camera", "reset", [], params)
		"WAIT_TIME":
			return _indent(indent_level) + _serialize_call("time", "wait", [_serialize_call_literal(params.get("duration", 0.0))], _filter_params(params, ["duration"]))
		"WAIT_CLICK":
			return _indent(indent_level) + "wait.click()"
		"CALL_EVENT":
			return _indent(indent_level) + _serialize_call("event", "call", [_serialize_call_literal(params.get("event_id", ""))], _filter_params(params, ["event_id"]))
		_:
			return _indent(indent_level) + _serialize_bracket_command(cmd_type, params)


func _serialize_dialogue(params: Dictionary, indent_level: int) -> String:
	var text: String = str(params.get("text", ""))
	var speaker: String = str(params.get("speaker", params.get("speaker_name", ""))).strip_edges()
	var emotion: String = str(params.get("emotion", params.get("expression", ""))).strip_edges()
	var text_line: String = "%s> %s" % [_indent(indent_level), text]
	var text_block_args: Array[String] = []

	if not speaker.is_empty():
		text_block_args.append("speaker=%s" % _serialize_call_literal(speaker))
	if not emotion.is_empty():
		text_block_args.append("expression=%s" % _serialize_call_literal(emotion))

	if text_block_args.is_empty():
		return text_line
	return "%s# => TextBlock(%s)\n%s" % [
		_indent(indent_level),
		", ".join(text_block_args),
		text_line
	]


func _serialize_jump(cmd_type: String, params: Dictionary) -> String:
	match cmd_type:
		"JUMP_TO_NODE":
			return "-> #%s" % str(params.get("node_id", ""))
		"JUMP_LABEL":
			return "-> @%s" % str(params.get("target", ""))
	return ""


func _serialize_set_variable(params: Dictionary) -> String:
	var variable_ref: String = _resolve_variable_ref(params)
	var value_source: String = str(params.get("value_source", "constant"))
	var operation: String = str(params.get("operation", "set"))

	if value_source == "constant" and OP_TO_SYMBOL.has(operation):
		return "var[%s] %s %s" % [
			variable_ref,
			OP_TO_SYMBOL[operation],
			_serialize_variable_literal(params.get("value", ""))
		]

	return _serialize_bracket_command("SET_VARIABLE", params)


func _serialize_if(params: Dictionary, indent_level: int) -> String:
	var condition_expr: String = _serialize_condition_expression(params.get("condition_commands", []))
	var if_commands: Array = params.get("if_commands", [])
	var else_commands: Array = params.get("else_commands", [])
	var has_else: bool = params.get("has_else", false)
	var lines: Array[String] = []
	var indent: String = _indent(indent_level)
	lines.append("%sif %s:" % [indent, condition_expr if not condition_expr.is_empty() else "true"])

	if not if_commands.is_empty():
		var body: String = serialize(if_commands, indent_level + 1, _variable_lookup)
		if not body.is_empty():
			lines.append(body)

	if has_else:
		lines.append("%selse:" % indent)
		if not else_commands.is_empty():
			var else_body: String = serialize(else_commands, indent_level + 1, _variable_lookup)
			if not else_body.is_empty():
				lines.append(else_body)

	return "\n".join(lines)


func _serialize_choice(params: Dictionary, indent_level: int) -> String:
	var choices: Array = params.get("choices", [])
	var lines: Array[String] = ["%s# => ChoiceBlock()" % _indent(indent_level)]

	for choice in choices:
		var choice_dict: Dictionary = choice if choice is Dictionary else {}
		var option_line: String = "%s- %s" % [
			_indent(indent_level),
			str(choice_dict.get("text", ""))
		]
		var condition_expr: String = _serialize_condition_expression(choice_dict.get("condition_commands", []))
		if not condition_expr.is_empty():
			option_line += " [if %s]" % condition_expr
		lines.append(option_line)

		var sub_commands: Array = choice_dict.get("commands", [])
		if not sub_commands.is_empty():
			var body: String = serialize(sub_commands, indent_level + 1, _variable_lookup)
			if not body.is_empty():
				lines.append(body)

	return "\n".join(lines)


func _serialize_condition_expression(commands: Array) -> String:
	if commands.is_empty():
		return ""
	var parts: Array[String] = []
	for cmd in commands:
		var expr: String = _serialize_condition_node(cmd, "and")
		if expr.is_empty():
			continue
		parts.append(expr)
	return " and ".join(parts)


func _serialize_condition_node(cmd: Variant, parent_logic: String = "") -> String:
	var cond_type: String = _get_command_type(cmd)
	var cond_params: Dictionary = _get_params(cmd)
	match cond_type:
		"CHECK_VAR":
			var rhs_text: String = ""
			if str(cond_params.get("value_source", "constant")) == "variable":
				rhs_text = "var[%s]" % _resolve_variable_ref({
					"variable_id": cond_params.get("source_variable_id", ""),
					"variable_key": cond_params.get("source_variable_key", ""),
					"variable_name": cond_params.get("source_variable_name", ""),
				})
			else:
				rhs_text = _serialize_variable_literal(cond_params.get("value", ""))
			return "var[%s] %s %s" % [
				_resolve_variable_ref(cond_params),
				str(cond_params.get("operator", "==")),
				rhs_text
			]
		"CHECK_HOVER":
			var node_id: String = str(cond_params.get("node_id", "")).strip_edges()
			return "hover(%s)" % (node_id if not node_id.is_empty() else "self")
		"CHECK_CLICK":
			var click_node_id: String = str(cond_params.get("node_id", "")).strip_edges()
			return "click(%s)" % (click_node_id if not click_node_id.is_empty() else "self")
		"IF":
			return _serialize_condition_if_node(cond_params, parent_logic)
		_:
			return ""


func _serialize_condition_if_node(params: Dictionary, parent_logic: String = "") -> String:
	var primary_expr: String = _serialize_condition_expression(params.get("condition_commands", []))
	var if_expr: String = _serialize_condition_expression(params.get("if_condition_commands", []))
	var else_expr: String = _serialize_condition_expression(params.get("else_condition_commands", []))
	var has_else: bool = params.get("has_else", false)

	if if_expr.is_empty() and has_else and not else_expr.is_empty():
		return _wrap_condition_expr("%s or %s" % [primary_expr, else_expr], "or", parent_logic)
	if not if_expr.is_empty() and not has_else:
		return _wrap_condition_expr("%s and %s" % [primary_expr, if_expr], "and", parent_logic)
	if not primary_expr.is_empty():
		return _wrap_condition_expr(primary_expr, "and", parent_logic)
	return "true"


func _wrap_condition_expr(expr: String, expr_logic: String, parent_logic: String) -> String:
	if expr.is_empty():
		return expr
	if parent_logic == "and" and expr_logic == "or":
		return "(%s)" % expr
	return expr


func _serialize_stage_command(cmd_type: String, params: Dictionary) -> String:
	var characters: Array[String] = _extract_stage_characters(params)
	var method_name: String = "set"
	match cmd_type:
		"STAGE_ENTER":
			method_name = "enter"
		"STAGE_EXIT":
			method_name = "exit"
		_:
			if characters.is_empty():
				return "stage.clear()"

	var positional: Array[String] = []
	for character_ref in characters:
		positional.append(_serialize_call_literal(character_ref))

	var kwargs: Dictionary = {}
	for key in STAGE_PARAM_ORDER:
		if not params.has(key):
			continue
		var value: Variant = params.get(key)
		if value is String and str(value).strip_edges().is_empty():
			continue
		kwargs[key] = _normalize_literal_value(value)
	return _serialize_call("stage", method_name, positional, kwargs)


func _serialize_character_call(params: Dictionary, method_name: String, excluded_keys: Array[String]) -> String:
	var character_id: String = str(params.get("character_id", "")).strip_edges()
	var positional: Array[String] = []
	if params.has("effect"):
		positional.append(_serialize_call_literal(params.get("effect", "")))
	var kwargs: Dictionary = _filter_params(params, excluded_keys)
	return _serialize_call(character_id, method_name, positional, kwargs)


func _serialize_character_assignment(params: Dictionary, id_key: String, property_name: String, value_key: String) -> String:
	var object_name: String = str(params.get(id_key, "")).strip_edges()
	return "%s.%s = %s" % [
		object_name,
		property_name,
		_serialize_literal(params.get(value_key, ""))
	]


func _serialize_image_command(params: Dictionary, is_hide: bool) -> String:
	var image_id: String = str(params.get("image_id", "")).strip_edges()
	var is_cg: bool = image_id == "cg"
	if is_hide:
		var hide_kwargs: Dictionary = _filter_params(params, ["image_id"])
		if is_cg or image_id.is_empty():
			return _serialize_call("cg", "hide", [], hide_kwargs)
		return _serialize_call("image", "hide", [_serialize_call_literal(image_id)], hide_kwargs)

	var image_path: String = str(params.get("image_path", "")).strip_edges()
	var object_name: String = "cg" if is_cg else "image"
	var kwargs: Dictionary = _filter_params(params, ["image_id", "image_path"])
	_expand_image_layout_kwargs(kwargs)
	return _serialize_call(object_name, "show", [_serialize_call_literal(image_path)], kwargs)


func _expand_image_layout_kwargs(kwargs: Dictionary) -> void:
	if kwargs.has("position") and kwargs.get("position") is Vector2:
		var position: Vector2 = kwargs.get("position")
		kwargs.erase("position")
		kwargs["x"] = position.x
		kwargs["y"] = position.y
	if kwargs.has("size") and kwargs.get("size") is Vector2:
		var size_value: Vector2 = kwargs.get("size")
		kwargs.erase("size")
		kwargs["width"] = size_value.x
		kwargs["height"] = size_value.y


func _serialize_call(object_name: String, method_name: String, positional_parts: Array[String], kwargs: Dictionary) -> String:
	var args: Array[String] = []
	args.append_array(positional_parts)
	args.append_array(_serialize_call_kwargs(kwargs))
	return "%s.%s(%s)" % [object_name, method_name, ", ".join(args)]


func _serialize_call_kwargs(kwargs: Dictionary) -> Array[String]:
	var items: Array[String] = []
	var sorted_keys: Array = kwargs.keys()
	sorted_keys.sort()
	for key in sorted_keys:
		if str(key).begins_with("_"):
			continue
		var value: Variant = kwargs.get(key)
		if value is String and str(value).strip_edges().is_empty():
			continue
		items.append("%s=%s" % [str(key), _serialize_call_literal(_normalize_literal_value(value))])
	return items


func _normalize_literal_value(value: Variant) -> Variant:
	if value is Color:
		return (value as Color).to_html(true)
	return value


func _serialize_bracket_command(cmd_type: String, params: Dictionary) -> String:
	var parts: Array[String] = [cmd_type]
	var positional_names: Array = POSITIONAL_PARAMS.get(cmd_type, [])
	var used_keys: Dictionary = {}

	for param_name in positional_names:
		if not params.has(param_name):
			continue
		parts.append(_serialize_literal(params.get(param_name)))
		used_keys[param_name] = true

	var sorted_keys: Array = params.keys()
	sorted_keys.sort()
	for key in sorted_keys:
		if used_keys.has(key):
			continue
		if str(key).begins_with("_"):
			continue
		parts.append("%s=%s" % [str(key), _serialize_literal(_normalize_literal_value(params.get(key)))])

	return "[%s]" % " ".join(parts)


func _filter_params(params: Dictionary, excluded_keys: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for key in params.keys():
		var key_text: String = str(key)
		if excluded_keys.has(key_text):
			continue
		if key_text.begins_with("_"):
			continue
		result[key_text] = params.get(key)
	return result


func _extract_stage_characters(params: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var raw_characters: Variant = params.get("characters", [])
	if raw_characters is Array:
		for entry in raw_characters:
			var trimmed: String = str(entry).strip_edges()
			if trimmed.is_empty():
				continue
			result.append(trimmed)
		if not result.is_empty():
			return result

	var raw_csv: String = str(params.get("characters_csv", "")).strip_edges()
	if raw_csv.is_empty():
		return result
	for entry in raw_csv.split(","):
		var trimmed_csv: String = entry.strip_edges()
		if trimmed_csv.is_empty():
			continue
		result.append(trimmed_csv)
	return result


func _serialize_literal(value: Variant) -> String:
	if value is bool:
		return "true" if value else "false"
	if value is int or value is float:
		return str(value)
	if value is String:
		var text: String = value
		if text.is_empty() or _should_quote_string(text):
			return "\"%s\"" % text.replace("\\", "\\\\").replace("\"", "\\\"")
		return text
	return str(value)


func _serialize_call_literal(value: Variant) -> String:
	if value is String:
		var text: String = value
		return "\"%s\"" % text.replace("\\", "\\\\").replace("\"", "\\\"")
	return _serialize_literal(value)


func _serialize_variable_literal(value: Variant) -> String:
	var normalized: Variant = value
	if value is bool or value is float:
		normalized = AVGVariableClass.normalize_script_literal(value)
	if normalized is int:
		return str(normalized)
	if normalized is String:
		var text: String = normalized
		var looks_like_non_string_literal: bool = AVGVariableClass.normalize_script_literal(text) is int
		if text.is_empty() or _should_quote_string(text) or looks_like_non_string_literal:
			return "\"%s\"" % text.replace("\\", "\\\\").replace("\"", "\\\"")
		return text
	return _serialize_literal(normalized)


func _should_quote_string(text: String) -> bool:
	var rx := RegEx.new()
	rx.compile("^[A-Za-z0-9_./#-]+$")
	return rx.search(text) == null


func _resolve_variable_ref(params: Dictionary) -> String:
	var variable_key: String = str(params.get("variable_key", params.get("variable_name", ""))).strip_edges()
	if not variable_key.is_empty():
		return variable_key

	var variable_id: String = str(params.get("variable_id", "")).strip_edges()
	if not variable_id.is_empty():
		if _variable_lookup.has(variable_id):
			return str(_variable_lookup[variable_id])
		return variable_id

	return ""


func _indent(level: int) -> String:
	return "    ".repeat(level)


func _get_command_type(cmd: Variant) -> String:
	if cmd is AVGCommand:
		return cmd.command_type
	if cmd is Dictionary:
		return str(cmd.get("command_type", ""))
	return ""


func _get_params(cmd: Variant) -> Dictionary:
	if cmd is AVGCommand:
		return cmd.params
	if cmd is Dictionary:
		return cmd.get("params", {})
	return {}
