class_name AVGDSLSerializer extends RefCounted
## AVG DSL 序列化器
## 将 Array[AVGCommand] 或 Array[Dictionary] 序列化为 DSL 文本
## 纯 RefCounted 类，不依赖场景树或 Autoload

## 指令类型 → 位置参数名列表（与 AVGDSLParser.POSITIONAL_PARAMS 保持一致）
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

## SET_VARIABLE operation → 操作符映射
const OP_TO_SYMBOL: Dictionary = {
	"set": "=",
	"add": "+=",
	"subtract": "-=",
	"multiply": "*=",
	"divide": "/=",
	"modulo": "%=",
}


## 将命令数组序列化为 DSL 文本
## commands 可以是 Array[AVGCommand] 或 Array[Dictionary]
func serialize(commands: Array, indent_level: int = 0) -> String:
	var lines: Array[String] = []
	for cmd in commands:
		var cmd_type: String = _get_command_type(cmd)
		var params: Dictionary = _get_params(cmd)
		var line: String = _serialize_command(cmd_type, params, indent_level)
		if not line.is_empty():
			lines.append(line)
	return "\n".join(lines)


## 序列化单条命令
func _serialize_command(cmd_type: String, params: Dictionary, indent_level: int) -> String:
	match cmd_type:
		"DIALOGUE":
			return _indent(indent_level) + _serialize_dialogue(params)
		"JUMP_SCENE", "JUMP_TO_NODE", "JUMP_LABEL":
			return _indent(indent_level) + _serialize_jump(cmd_type, params)
		"SET_VARIABLE":
			return _indent(indent_level) + _serialize_set_variable(params)
		"IF":
			return _serialize_if(params, indent_level)
		"CHOICE":
			return _serialize_choice(params, indent_level)
		_:
			return _indent(indent_level) + _serialize_bracket_command(cmd_type, params)


## 序列化对话命令
## 含表情: "角色名(表情): 文本"
## 无表情: "角色名: 文本"
## 旁白: ": 文本"
func _serialize_dialogue(params: Dictionary) -> String:
	var speaker: String = str(params.get("speaker", ""))
	var text: String = str(params.get("text", ""))
	var expression: String = str(params.get("expression", ""))

	if speaker.is_empty():
		return ": %s" % text
	elif not expression.is_empty():
		return "%s(%s): %s" % [speaker, expression, text]
	else:
		return "%s: %s" % [speaker, text]


## 序列化跳转命令
## JUMP_SCENE → "-> scene_id"
## JUMP_TO_NODE → "-> #node_id"
## JUMP_LABEL → "-> @target"
func _serialize_jump(cmd_type: String, params: Dictionary) -> String:
	match cmd_type:
		"JUMP_SCENE":
			return "-> %s" % str(params.get("scene_id", ""))
		"JUMP_TO_NODE":
			return "-> #%s" % str(params.get("node_id", ""))
		"JUMP_LABEL":
			return "-> @%s" % str(params.get("target", ""))
	return ""


## 序列化方括号指令（通用）
## 格式: [COMMAND_TYPE 位置参数 key=value...]
func _serialize_bracket_command(cmd_type: String, params: Dictionary) -> String:
	var parts: Array[String] = [cmd_type]
	var positional_names: Array = POSITIONAL_PARAMS.get(cmd_type, [])
	var used_keys: Dictionary = {}

	# 先输出位置参数（按定义顺序）
	for param_name in positional_names:
		if params.has(param_name):
			parts.append(_serialize_value(params[param_name]))
			used_keys[param_name] = true

	# 再输出剩余的 key=value 参数（跳过已输出的位置参数和内部键）
	var sorted_keys: Array = params.keys()
	sorted_keys.sort()
	for key in sorted_keys:
		if used_keys.has(key):
			continue
		if key.begins_with("_"):
			continue
		parts.append("%s=%s" % [key, _serialize_value(params[key])])

	return "[%s]" % " ".join(parts)


## 序列化 SET_VARIABLE 命令
## 简写 (value_source=constant): [SET_VARIABLE var_id op= 值]
## 高级 (其他 value_source): [SET_VARIABLE var_id key=value...]
func _serialize_set_variable(params: Dictionary) -> String:
	var var_id: String = str(params.get("variable_id", ""))
	var value_source: String = str(params.get("value_source", ""))
	var operation: String = str(params.get("operation", "set"))

	# 简写格式: value_source 为 constant 且有 operation
	if value_source == "constant" and OP_TO_SYMBOL.has(operation):
		var op_symbol: String = OP_TO_SYMBOL[operation]
		var value: Variant = params.get("value", "")
		return "[SET_VARIABLE %s %s %s]" % [var_id, op_symbol, _serialize_value(value)]

	# 高级格式: [SET_VARIABLE var_id key=value...]
	var parts: Array[String] = ["SET_VARIABLE", var_id]
	var skip_keys: Dictionary = {"variable_id": true}
	var sorted_keys: Array = params.keys()
	sorted_keys.sort()
	for key in sorted_keys:
		if skip_keys.has(key):
			continue
		if key.begins_with("_"):
			continue
		parts.append("%s=%s" % [key, _serialize_value(params[key])])
	return "[%s]" % " ".join(parts)


## 序列化 IF 块（递归）
## 简写 (单条件 CHECK_VAR): [IF var_id op value] ... [END]
## 多条件: [IF] [? ...] [THEN] ... [END]
func _serialize_if(params: Dictionary, indent_level: int) -> String:
	var condition_commands: Array = params.get("condition_commands", [])
	var if_commands: Array = params.get("if_commands", [])
	var has_else: bool = params.get("has_else", false)
	var else_commands: Array = params.get("else_commands", [])
	var lines: Array[String] = []
	var indent: String = _indent(indent_level)
	var inner_indent_level: int = indent_level + 1

	# 判断是否使用简写格式
	var use_simple: bool = _is_simple_if(condition_commands)

	if use_simple:
		# 简写: [IF var_id op value]
		var cond: Dictionary = _get_params(condition_commands[0])
		var var_id: String = str(cond.get("variable_id", ""))
		var op: String = str(cond.get("operator", "=="))
		var value: Variant = cond.get("value", "")
		lines.append("%s[IF %s %s %s]" % [indent, var_id, op, _serialize_value(value)])
	else:
		# 多条件: [IF] + [? ...] 行
		lines.append("%s[IF]" % indent)
		for cond_cmd in condition_commands:
			var cond_type: String = _get_command_type(cond_cmd)
			var cond_params: Dictionary = _get_params(cond_cmd)
			lines.append("%s%s" % [_indent(inner_indent_level), _serialize_condition(cond_type, cond_params)])
		lines.append("%s[THEN]" % indent)

	# if_commands
	if not if_commands.is_empty():
		var body: String = serialize(if_commands, inner_indent_level)
		if not body.is_empty():
			lines.append(body)

	# else
	if has_else:
		lines.append("%s[ELSE]" % indent)
		if not else_commands.is_empty():
			var else_body: String = serialize(else_commands, inner_indent_level)
			if not else_body.is_empty():
				lines.append(else_body)

	lines.append("%s[END]" % indent)
	return "\n".join(lines)


## 序列化 CHOICE 块（递归）
func _serialize_choice(params: Dictionary, indent_level: int) -> String:
	var choices: Array = params.get("choices", [])
	var lines: Array[String] = []
	var indent: String = _indent(indent_level)
	var option_indent: String = _indent(indent_level + 1)
	var cmd_indent_level: int = indent_level + 2

	lines.append("%s[CHOICE]" % indent)

	for choice in choices:
		var choice_dict: Dictionary = choice as Dictionary
		var text: String = str(choice_dict.get("text", ""))
		var condition_commands: Array = choice_dict.get("condition_commands", [])
		var hidden_when_unmet: bool = choice_dict.get("hidden_when_unmet", false)
		var sub_commands: Array = choice_dict.get("commands", [])

		# 构建选项行
		var option_line: String = "- "

		# 条件
		if not condition_commands.is_empty():
			var cond_cmd: Variant = condition_commands[0]
			var cond_type: String = _get_command_type(cond_cmd)
			var cond_params: Dictionary = _get_params(cond_cmd)
			option_line += _serialize_condition(cond_type, cond_params) + " "

		# HIDDEN 标记
		if hidden_when_unmet:
			option_line += "[HIDDEN] "

		option_line += text
		lines.append("%s%s" % [option_indent, option_line])

		# 子命令
		if not sub_commands.is_empty():
			var body: String = serialize(sub_commands, cmd_indent_level)
			if not body.is_empty():
				lines.append(body)

	lines.append("%s[END]" % indent)
	return "\n".join(lines)


## 序列化条件行: [? CHECK_VAR var_id op value] 或 [? CHECK_HOVER node_id] 等
func _serialize_condition(cond_type: String, cond_params: Dictionary) -> String:
	match cond_type:
		"CHECK_VAR":
			var var_id: String = str(cond_params.get("variable_id", ""))
			var op: String = str(cond_params.get("operator", "=="))
			var value: Variant = cond_params.get("value", "")
			return "[? CHECK_VAR %s %s %s]" % [var_id, op, _serialize_value(value)]
		"CHECK_HOVER":
			var node_id: String = str(cond_params.get("node_id", ""))
			return "[? CHECK_HOVER %s]" % node_id
		"CHECK_CLICK":
			var node_id: String = str(cond_params.get("node_id", ""))
			return "[? CHECK_CLICK %s]" % node_id
		_:
			# 通用条件序列化
			var parts: Array[String] = [cond_type]
			var sorted_keys: Array = cond_params.keys()
			sorted_keys.sort()
			for key in sorted_keys:
				if key.begins_with("_"):
					continue
				parts.append("%s=%s" % [key, _serialize_value(cond_params[key])])
			return "[? %s]" % " ".join(parts)


## 判断 IF 是否可以使用简写格式
## 条件: 恰好 1 个条件且为 CHECK_VAR
func _is_simple_if(condition_commands: Array) -> bool:
	if condition_commands.size() != 1:
		return false
	var cond_type: String = _get_command_type(condition_commands[0])
	return cond_type == "CHECK_VAR"


## 序列化值为字符串
## String 含空格 → 加引号; bool → true/false; int/float → 原样
func _serialize_value(value: Variant) -> String:
	if value is bool:
		return "true" if value else "false"
	if value is int or value is float:
		return str(value)
	# String
	var s: String = str(value)
	if " " in s or "\t" in s:
		return '"%s"' % s
	return s


## 生成缩进字符串（每级 2 个空格）
func _indent(level: int) -> String:
	return "  ".repeat(level)


## 从 AVGCommand 或 Dictionary 中提取 command_type
func _get_command_type(cmd: Variant) -> String:
	if cmd is AVGCommand:
		return cmd.command_type
	if cmd is Dictionary:
		return str(cmd.get("command_type", ""))
	return ""


## 从 AVGCommand 或 Dictionary 中提取 params
func _get_params(cmd: Variant) -> Dictionary:
	if cmd is AVGCommand:
		return cmd.params
	if cmd is Dictionary:
		return cmd.get("params", {})
	return {}
