class_name AVGDSLParser extends RefCounted
## AVG DSL 解析器
## 将 DSL 文本解析为 Array[AVGCommand]
## 纯 RefCounted 类，不依赖场景树或 Autoload

## 指令类型 → 位置参数名列表
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
	"SHOW_IMAGE": ["image_id", "texture_path"],
	"HIDE_IMAGE": ["image_id"],
	"SCREEN_FADE": ["direction"],
	"SCREEN_FLASH": [],
	"SCREEN_SHAKE": [],
	"CAMERA_ZOOM": ["zoom_level"],
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

## 所有已知的指令类型（用于验证）
var _known_command_types: Dictionary = {}


func _init() -> void:
	# 从 POSITIONAL_PARAMS 构建已知类型集合
	for key in POSITIONAL_PARAMS:
		_known_command_types[key] = true
	# 额外的已知类型（使用专用解析或块解析）
	_known_command_types["SET_VARIABLE"] = true
	_known_command_types["CHECK_VAR"] = true
	_known_command_types["IF"] = true
	_known_command_types["CHOICE"] = true
	_known_command_types["DIALOGUE"] = true
	_known_command_types["JUMP_TO_NODE"] = true
	_known_command_types["CHECK_HOVER"] = true
	_known_command_types["CHECK_CLICK"] = true


## 解析 DSL 文本为 AVGCommand 数组
## 返回: {success: bool, commands: Array[AVGCommand], errors: Array[Dictionary]}
func parse(dsl_text: String) -> Dictionary:
	var lines: Array[String] = []
	for l in dsl_text.split("\n"):
		lines.append(l)

	var commands: Array[AVGCommand] = []
	var errors: Array[Dictionary] = []
	var i: int = 0

	while i < lines.size():
		var raw_line: String = lines[i]
		var stripped: String = raw_line.strip_edges()

		# 空行或注释行 → 跳过
		if stripped.is_empty() or stripped.begins_with("#"):
			i += 1
			continue

		# [IF 开头 → IF 块解析（Task 1.3 实现，当前返回 stub）
		if stripped.begins_with("[IF"):
			var result: Dictionary = _parse_if_block(lines, i, 0)
			if result.has("error"):
				errors.append({"line": i + 1, "message": result["error"]})
			elif result.has("command"):
				commands.append(result["command"])
			errors.append_array(result.get("errors", []))
			i = result.get("next_index", i + 1)
			continue

		# [CHOICE] → CHOICE 块解析（Task 1.3 实现，当前返回 stub）
		if stripped == "[CHOICE]":
			var result: Dictionary = _parse_choice_block(lines, i, 0)
			if result.has("error"):
				errors.append({"line": i + 1, "message": result["error"]})
			elif result.has("command"):
				commands.append(result["command"])
			errors.append_array(result.get("errors", []))
			i = result.get("next_index", i + 1)
			continue

		# [ 开头 → 方括号指令
		if stripped.begins_with("["):
			var cmd: AVGCommand = _parse_bracket_command(stripped)
			if cmd != null:
				commands.append(cmd)
			else:
				var err_msg: String = _get_bracket_error(stripped)
				errors.append({"line": i + 1, "message": err_msg})
			i += 1
			continue

		# -> 开头 → 跳转命令
		if stripped.begins_with("->"):
			var cmd: AVGCommand = _parse_jump_line(stripped)
			if cmd != null:
				commands.append(cmd)
			else:
				errors.append({"line": i + 1, "message": "无法解析跳转命令: %s" % stripped})
			i += 1
			continue

		# 包含 ": "（冒号+空格）→ 对话/旁白
		if ": " in stripped or stripped.begins_with(": "):
			var cmd: AVGCommand = _parse_dialogue_line(stripped)
			if cmd != null:
				commands.append(cmd)
			else:
				errors.append({"line": i + 1, "message": "无法解析对话行: %s" % stripped})
			i += 1
			continue

		# 其他 → 报错
		errors.append({"line": i + 1, "message": "无法识别的行格式: %s" % stripped})
		i += 1

	if errors.is_empty():
		return {"success": true, "commands": commands, "errors": []}
	else:
		return {"success": false, "commands": commands, "errors": errors}


## 解析对话行: "角色名(表情): 文本" 或 "角色名: 文本" 或 ": 旁白"
func _parse_dialogue_line(line: String) -> AVGCommand:
	# 以第一个 ": "（冒号+空格）作为分隔符
	var sep_pos: int = line.find(": ")
	if sep_pos == -1:
		return null

	var left: String = line.substr(0, sep_pos)
	var text: String = line.substr(sep_pos + 2)
	var params: Dictionary = {"text": text}

	if left.is_empty():
		# ": 旁白文本" → speaker 为空
		params["speaker"] = ""
	elif "(" in left and left.ends_with(")"):
		# "角色名(表情键): 文本"
		var paren_start: int = left.find("(")
		var speaker: String = left.substr(0, paren_start)
		var expression: String = left.substr(paren_start + 1, left.length() - paren_start - 2)
		params["speaker"] = speaker
		params["expression"] = expression
	else:
		# "角色名: 文本"
		params["speaker"] = left

	return AVGCommand.new("DIALOGUE", params)


## 解析跳转行: "-> target"
func _parse_jump_line(line: String) -> AVGCommand:
	var target: String = line.substr(2).strip_edges()
	if target.is_empty():
		return null

	if target.begins_with("#"):
		# -> #node_id → JUMP_TO_NODE
		var node_id: String = target.substr(1)
		return AVGCommand.new("JUMP_TO_NODE", {"node_id": node_id})
	elif target.begins_with("@"):
		# -> @label_name → JUMP_LABEL
		var label_name: String = target.substr(1)
		return AVGCommand.new("JUMP_LABEL", {"target": label_name})
	else:
		# -> scene_id → JUMP_SCENE
		return AVGCommand.new("JUMP_SCENE", {"scene_id": target})


## 解析方括号指令行: "[COMMAND_TYPE params...]"
func _parse_bracket_command(line: String) -> AVGCommand:
	# 去掉首尾方括号
	if not line.begins_with("[") or not line.ends_with("]"):
		return null
	var content: String = line.substr(1, line.length() - 2).strip_edges()
	if content.is_empty():
		return null

	# 分割 tokens
	var tokens: Array[String] = _tokenize(content)
	if tokens.is_empty():
		return null

	var command_type: String = tokens[0]
	var remaining: Array[String] = []
	for idx in range(1, tokens.size()):
		remaining.append(tokens[idx])

	# SET_VARIABLE 使用专用解析
	if command_type == "SET_VARIABLE":
		var sv_params: Dictionary = _parse_set_variable_shorthand(remaining)
		if sv_params.has("_error"):
			return null
		return AVGCommand.new(command_type, sv_params)

	# 验证指令类型是否已知
	if not _known_command_types.has(command_type):
		return null

	# 解析参数
	var params: Dictionary = _parse_bracket_params(command_type, remaining)
	return AVGCommand.new(command_type, params)


## 将方括号内容分割为 tokens（尊重引号内的空格）
func _tokenize(content: String) -> Array[String]:
	var tokens: Array[String] = []
	var current: String = ""
	var in_quotes: bool = false
	var quote_char: String = ""

	for ch_idx in range(content.length()):
		var ch: String = content[ch_idx]
		if in_quotes:
			if ch == quote_char:
				in_quotes = false
			else:
				current += ch
		elif ch == '"' or ch == "'":
			in_quotes = true
			quote_char = ch
		elif ch == " " or ch == "\t":
			if not current.is_empty():
				tokens.append(current)
				current = ""
		else:
			current += ch

	if not current.is_empty():
		tokens.append(current)

	return tokens


## 解析方括号内的参数（位置参数 + key=value 参数）
func _parse_bracket_params(command_type: String, tokens: Array[String]) -> Dictionary:
	var params: Dictionary = {}
	var positional_names: Array = POSITIONAL_PARAMS.get(command_type, [])
	var positional_idx: int = 0

	for token in tokens:
		if "=" in token:
			# key=value 参数
			var eq_pos: int = token.find("=")
			var key: String = token.substr(0, eq_pos)
			var value_str: String = token.substr(eq_pos + 1)
			params[key] = _infer_value_type(value_str)
		else:
			# 位置参数
			if positional_idx < positional_names.size():
				var param_name: String = positional_names[positional_idx]
				params[param_name] = _infer_value_type(token)
				positional_idx += 1
			else:
				# 超出位置参数定义，作为额外参数存储
				# 使用 _extra_N 作为键名
				params["_extra_%d" % positional_idx] = _infer_value_type(token)
				positional_idx += 1

	return params


## 值类型推断: 字符串 → int/float/bool/String
func _infer_value_type(text: String) -> Variant:
	# bool
	if text == "true":
		return true
	if text == "false":
		return false

	# int（纯数字，可带负号）
	if text.is_valid_int():
		return text.to_int()

	# float（包含小数点的数字）
	if text.is_valid_float():
		return text.to_float()

	# 其他保持为 String
	return text


## SET_VARIABLE 简写解析
## 支持简写: "var_id = 值", "var_id += 值" 等
## 支持高级: "var_id value_source=variable source_variable_id=var_002"
## tokens 是去掉 "SET_VARIABLE" 后的剩余 token 列表
func _parse_set_variable_shorthand(tokens: Array[String]) -> Dictionary:
	var params: Dictionary = {}
	if tokens.is_empty():
		return params

	# 第一个 token 始终是 variable_id
	params["variable_id"] = tokens[0]

	if tokens.size() < 2:
		return params

	# 操作符映射
	var op_map: Dictionary = {
		"=": "set",
		"+=": "add",
		"-=": "subtract",
		"*=": "multiply",
		"/=": "divide",
		"%=": "modulo",
	}

	# 检查第二个 token 是否为简写操作符
	var second: String = tokens[1]
	if second in op_map:
		# 简写语法: var_id op value
		params["operation"] = op_map[second]
		params["value_source"] = "constant"
		if tokens.size() >= 3:
			params["value"] = _infer_value_type(tokens[2])
		else:
			# 操作符后缺少值 → 标记错误
			params["_error"] = "无效的变量值: 操作符 '%s' 后缺少值" % second
		return params

	# 非简写 → 按 key=value 解析（高级语法）
	for idx in range(1, tokens.size()):
		var token: String = tokens[idx]
		if "=" in token:
			var eq_pos: int = token.find("=")
			var key: String = token.substr(0, eq_pos)
			var value_str: String = token.substr(eq_pos + 1)
			params[key] = _infer_value_type(value_str)
		else:
			# 非 key=value 的额外 token，存为 _extra
			params["_extra_%d" % idx] = _infer_value_type(token)

	return params


## CHECK_VAR 简写解析
## tokens: [var_id, operator, value]
## 返回: {variable_id, operator, value, value_source}
func _parse_check_var_shorthand(tokens: Array[String]) -> Dictionary:
	var params: Dictionary = {}
	if tokens.size() < 3:
		# 不足 3 个 token，尽量填充已有的
		if tokens.size() >= 1:
			params["variable_id"] = tokens[0]
		if tokens.size() >= 2:
			params["operator"] = tokens[1]
		return params

	params["variable_id"] = tokens[0]
	params["operator"] = tokens[1]
	params["value"] = _infer_value_type(tokens[2])
	params["value_source"] = "constant"
	return params


## 递归解析一段行范围内的命令（用于 IF/CHOICE 块内部）
## 返回: {commands: Array[AVGCommand], next_index: int, errors: Array[Dictionary]}
## 遇到 stop_tokens 中的关键字时停止并返回
func _parse_block_commands(lines: Array[String], start: int, stop_tokens: Array[String]) -> Dictionary:
	var commands: Array[AVGCommand] = []
	var errors: Array[Dictionary] = []
	var i: int = start

	while i < lines.size():
		var stripped: String = lines[i].strip_edges()

		# 空行或注释 → 跳过
		if stripped.is_empty() or stripped.begins_with("#"):
			i += 1
			continue

		# 检查是否遇到停止标记
		for st in stop_tokens:
			if stripped == st:
				return {"commands": commands, "next_index": i, "errors": errors}

		# [IF 开头 → 递归 IF 块
		if stripped.begins_with("[IF"):
			var result: Dictionary = _parse_if_block(lines, i, 0)
			if result.has("error"):
				errors.append({"line": i + 1, "message": result["error"]})
			elif result.has("command"):
				commands.append(result["command"])
			i = result.get("next_index", i + 1)
			continue

		# [CHOICE] → 递归 CHOICE 块
		if stripped == "[CHOICE]":
			var result: Dictionary = _parse_choice_block(lines, i, 0)
			if result.has("error"):
				errors.append({"line": i + 1, "message": result["error"]})
			elif result.has("command"):
				commands.append(result["command"])
			i = result.get("next_index", i + 1)
			continue

		# [ 开头 → 方括号指令
		if stripped.begins_with("["):
			var cmd: AVGCommand = _parse_bracket_command(stripped)
			if cmd != null:
				commands.append(cmd)
			else:
				var err_msg: String = _get_bracket_error(stripped)
				errors.append({"line": i + 1, "message": err_msg})
			i += 1
			continue

		# -> 开头 → 跳转命令
		if stripped.begins_with("->"):
			var cmd: AVGCommand = _parse_jump_line(stripped)
			if cmd != null:
				commands.append(cmd)
			else:
				errors.append({"line": i + 1, "message": "无法解析跳转命令: %s" % stripped})
			i += 1
			continue

		# 包含 ": " → 对话/旁白
		if ": " in stripped or stripped.begins_with(": "):
			var cmd: AVGCommand = _parse_dialogue_line(stripped)
			if cmd != null:
				commands.append(cmd)
			else:
				errors.append({"line": i + 1, "message": "无法解析对话行: %s" % stripped})
			i += 1
			continue

		# 其他 → 报错
		errors.append({"line": i + 1, "message": "无法识别的行格式: %s" % stripped})
		i += 1

	return {"commands": commands, "next_index": i, "errors": errors}


## 解析 IF 块
## 支持简单 IF: [IF var_id op value] ... [END]
## 支持多条件 IF: [IF] [? ...] [THEN] ... [ELSE] ... [END]
func _parse_if_block(lines: Array[String], start: int, _indent_level: int) -> Dictionary:
	var first_line: String = lines[start].strip_edges()
	var condition_commands: Array[AVGCommand] = []
	var if_commands: Array[AVGCommand] = []
	var else_commands: Array[AVGCommand] = []
	var has_else: bool = false
	var errors: Array[Dictionary] = []
	var i: int = start + 1

	# 判断简单 IF vs 多条件 IF
	# 简单 IF: [IF var_id op value] → 内容不只是 "IF"
	var if_content: String = first_line.substr(1, first_line.length() - 2).strip_edges()  # 去掉 [ ]
	var is_simple: bool = if_content != "IF"

	if is_simple:
		# 简单 IF: [IF var_id op value]
		# 提取 "IF" 后面的 tokens 作为 CHECK_VAR 条件
		var tokens: Array[String] = _tokenize(if_content)
		# tokens[0] == "IF", 剩余为 var_id op value
		var check_tokens: Array[String] = []
		for idx in range(1, tokens.size()):
			check_tokens.append(tokens[idx])
		var check_params: Dictionary = _parse_check_var_shorthand(check_tokens)
		condition_commands.append(AVGCommand.new("CHECK_VAR", check_params))

		# 收集 if_commands 直到 [ELSE] 或 [END]
		var block_result: Dictionary = _parse_block_commands(lines, i, ["[ELSE]", "[END]"])
		if_commands = block_result["commands"]
		errors.append_array(block_result.get("errors", []))
		i = block_result["next_index"]

		# 检查是 [ELSE] 还是 [END]
		if i < lines.size():
			var stop_line: String = lines[i].strip_edges()
			if stop_line == "[ELSE]":
				has_else = true
				i += 1
				var else_result: Dictionary = _parse_block_commands(lines, i, ["[END]"])
				else_commands = else_result["commands"]
				errors.append_array(else_result.get("errors", []))
				i = else_result["next_index"]
				# 跳过 [END]
				if i < lines.size() and lines[i].strip_edges() == "[END]":
					i += 1
				else:
					return {"next_index": i, "error": "未闭合的 IF 块（起始行 %d）" % (start + 1)}
			elif stop_line == "[END]":
				i += 1
			else:
				return {"next_index": i, "error": "未闭合的 IF 块（起始行 %d）" % (start + 1)}
		else:
			return {"next_index": i, "error": "未闭合的 IF 块（起始行 %d）" % (start + 1)}
	else:
		# 多条件 IF: [IF] 后收集 [? ...] 条件行直到 [THEN]
		while i < lines.size():
			var stripped: String = lines[i].strip_edges()
			if stripped.is_empty() or stripped.begins_with("#"):
				i += 1
				continue
			if stripped == "[THEN]":
				i += 1
				break
			if stripped.begins_with("[?"):
				var cond_cmd: AVGCommand = _parse_condition_line(stripped)
				if cond_cmd != null:
					condition_commands.append(cond_cmd)
				else:
					errors.append({"line": i + 1, "message": "无法解析条件行: %s" % stripped})
				i += 1
				continue
			# 非条件行且非 [THEN] → 错误
			errors.append({"line": i + 1, "message": "IF 块中期望条件行 [? ...] 或 [THEN]，得到: %s" % stripped})
			i += 1

		# 收集 if_commands 直到 [ELSE] 或 [END]
		var block_result: Dictionary = _parse_block_commands(lines, i, ["[ELSE]", "[END]"])
		if_commands = block_result["commands"]
		errors.append_array(block_result.get("errors", []))
		i = block_result["next_index"]

		# 检查是 [ELSE] 还是 [END]
		if i < lines.size():
			var stop_line: String = lines[i].strip_edges()
			if stop_line == "[ELSE]":
				has_else = true
				i += 1
				var else_result: Dictionary = _parse_block_commands(lines, i, ["[END]"])
				else_commands = else_result["commands"]
				errors.append_array(else_result.get("errors", []))
				i = else_result["next_index"]
				if i < lines.size() and lines[i].strip_edges() == "[END]":
					i += 1
				else:
					return {"next_index": i, "error": "未闭合的 IF 块（起始行 %d）" % (start + 1)}
			elif stop_line == "[END]":
				i += 1
			else:
				return {"next_index": i, "error": "未闭合的 IF 块（起始行 %d）" % (start + 1)}
		else:
			return {"next_index": i, "error": "未闭合的 IF 块（起始行 %d）" % (start + 1)}

	# 构建 IF 命令
	var params: Dictionary = {
		"condition_commands": _commands_to_dicts(condition_commands),
		"if_commands": _commands_to_dicts(if_commands),
		"has_else": has_else,
		"else_commands": _commands_to_dicts(else_commands),
	}
	var cmd: AVGCommand = AVGCommand.new("IF", params)

	if not errors.is_empty():
		# 有错误但仍返回部分结果
		return {"command": cmd, "next_index": i, "errors": errors}
	return {"command": cmd, "next_index": i}


## 解析条件行: [? CHECK_VAR var_id op value] 或 [? CHECK_HOVER node_id] 等
func _parse_condition_line(line: String) -> AVGCommand:
	# 去掉 [? 和 ]
	if not line.begins_with("[?") or not line.ends_with("]"):
		return null
	var content: String = line.substr(2, line.length() - 3).strip_edges()
	if content.is_empty():
		return null

	var tokens: Array[String] = _tokenize(content)
	if tokens.is_empty():
		return null

	var cond_type: String = tokens[0]
	var remaining: Array[String] = []
	for idx in range(1, tokens.size()):
		remaining.append(tokens[idx])

	if cond_type == "CHECK_VAR":
		var params: Dictionary = _parse_check_var_shorthand(remaining)
		return AVGCommand.new("CHECK_VAR", params)
	elif cond_type == "CHECK_HOVER":
		var params: Dictionary = {}
		if not remaining.is_empty():
			params["node_id"] = remaining[0]
		return AVGCommand.new("CHECK_HOVER", params)
	elif cond_type == "CHECK_CLICK":
		var params: Dictionary = {}
		if not remaining.is_empty():
			params["node_id"] = remaining[0]
		return AVGCommand.new("CHECK_CLICK", params)
	else:
		# 未知条件类型，尝试通用解析
		var params: Dictionary = _parse_bracket_params(cond_type, remaining)
		return AVGCommand.new(cond_type, params)


## 解析 CHOICE 块
## [CHOICE] + 选项列表 + [END]
func _parse_choice_block(lines: Array[String], start: int, _indent_level: int) -> Dictionary:
	var choices: Array[Dictionary] = []
	var errors: Array[Dictionary] = []
	var i: int = start + 1  # 跳过 [CHOICE] 行

	# 收集选项，直到 [END]
	while i < lines.size():
		var stripped: String = lines[i].strip_edges()

		# 空行或注释 → 跳过
		if stripped.is_empty() or stripped.begins_with("#"):
			i += 1
			continue

		# [END] → 结束 CHOICE 块
		if stripped == "[END]":
			i += 1
			var params: Dictionary = {"choices": choices}
			var cmd: AVGCommand = AVGCommand.new("CHOICE", params)
			if not errors.is_empty():
				return {"command": cmd, "next_index": i, "errors": errors}
			return {"command": cmd, "next_index": i}

		# 选项行: 以 "- " 开头（strip_edges 后）
		if stripped.begins_with("- "):
			var option_result: Dictionary = _parse_choice_option(lines, i)
			choices.append(option_result["choice"])
			errors.append_array(option_result.get("errors", []))
			i = option_result["next_index"]
			continue

		# 非选项行 → 错误
		errors.append({"line": i + 1, "message": "CHOICE 块中期望选项行 '- ...' 或 [END]，得到: %s" % stripped})
		i += 1

	# 未找到 [END]
	return {"next_index": i, "error": "未闭合的 CHOICE 块（起始行 %d）" % (start + 1)}


## 解析单个选项及其子命令
## 返回: {choice: Dictionary, next_index: int, errors: Array}
func _parse_choice_option(lines: Array[String], start: int) -> Dictionary:
	var raw_line: String = lines[start]
	var stripped: String = raw_line.strip_edges()
	var errors: Array[Dictionary] = []

	# 去掉 "- " 前缀
	var option_content: String = stripped.substr(2)

	# 解析条件和 HIDDEN 标记
	var condition_commands: Array[AVGCommand] = []
	var hidden_when_unmet: bool = false
	var text: String = option_content

	# 检查 [? ...] 条件
	if text.begins_with("[?"):
		var cond_end: int = text.find("]")
		if cond_end != -1:
			var cond_str: String = text.substr(0, cond_end + 1)
			var cond_cmd: AVGCommand = _parse_condition_line(cond_str)
			if cond_cmd != null:
				condition_commands.append(cond_cmd)
			text = text.substr(cond_end + 1).strip_edges()

	# 检查 [HIDDEN] 标记
	if text.begins_with("[HIDDEN]"):
		hidden_when_unmet = true
		text = text.substr(8).strip_edges()  # len("[HIDDEN]") == 8

	# 确定选项行的缩进级别，子命令需要更深的缩进
	var option_indent: int = _get_indent_length(raw_line)

	# 收集子命令（缩进比选项行更深的行）
	var sub_commands: Array[AVGCommand] = []
	var i: int = start + 1

	while i < lines.size():
		var sub_raw: String = lines[i]
		var sub_stripped: String = sub_raw.strip_edges()

		# 空行 → 跳过
		if sub_stripped.is_empty() or sub_stripped.begins_with("#"):
			i += 1
			continue

		# [END] → 不属于此选项，停止
		if sub_stripped == "[END]":
			break

		# 新选项行（以 "- " 开头且缩进 <= 选项行）→ 停止
		var sub_indent: int = _get_indent_length(sub_raw)
		if sub_stripped.begins_with("- ") and sub_indent <= option_indent:
			break

		# 缩进不够深 → 不属于此选项
		if sub_indent <= option_indent:
			break

		# 递归解析子命令行
		# [IF 开头 → 递归 IF 块
		if sub_stripped.begins_with("[IF"):
			var result: Dictionary = _parse_if_block(lines, i, 0)
			if result.has("error"):
				errors.append({"line": i + 1, "message": result["error"]})
			elif result.has("command"):
				sub_commands.append(result["command"])
			i = result.get("next_index", i + 1)
			continue

		# [CHOICE] → 递归 CHOICE 块
		if sub_stripped == "[CHOICE]":
			var result: Dictionary = _parse_choice_block(lines, i, 0)
			if result.has("error"):
				errors.append({"line": i + 1, "message": result["error"]})
			elif result.has("command"):
				sub_commands.append(result["command"])
			i = result.get("next_index", i + 1)
			continue

		# [ 开头 → 方括号指令
		if sub_stripped.begins_with("["):
			var cmd: AVGCommand = _parse_bracket_command(sub_stripped)
			if cmd != null:
				sub_commands.append(cmd)
			else:
				var err_msg: String = _get_bracket_error(sub_stripped)
				errors.append({"line": i + 1, "message": err_msg})
			i += 1
			continue

		# -> 开头 → 跳转命令
		if sub_stripped.begins_with("->"):
			var cmd: AVGCommand = _parse_jump_line(sub_stripped)
			if cmd != null:
				sub_commands.append(cmd)
			else:
				errors.append({"line": i + 1, "message": "无法解析跳转命令: %s" % sub_stripped})
			i += 1
			continue

		# 包含 ": " → 对话/旁白
		if ": " in sub_stripped or sub_stripped.begins_with(": "):
			var cmd: AVGCommand = _parse_dialogue_line(sub_stripped)
			if cmd != null:
				sub_commands.append(cmd)
			else:
				errors.append({"line": i + 1, "message": "无法解析对话行: %s" % sub_stripped})
			i += 1
			continue

		# 其他 → 报错
		errors.append({"line": i + 1, "message": "无法识别的行格式: %s" % sub_stripped})
		i += 1

	var choice: Dictionary = {
		"text": text,
		"commands": _commands_to_dicts(sub_commands),
		"condition_commands": _commands_to_dicts(condition_commands),
		"hidden_when_unmet": hidden_when_unmet,
	}
	return {"choice": choice, "next_index": i, "errors": errors}


## 获取方括号指令解析失败时的具体错误信息
func _get_bracket_error(line: String) -> String:
	if not line.begins_with("[") or not line.ends_with("]"):
		return "无法解析方括号指令: %s" % line
	var content: String = line.substr(1, line.length() - 2).strip_edges()
	if content.is_empty():
		return "无法解析方括号指令: %s" % line

	var tokens: Array[String] = _tokenize(content)
	if tokens.is_empty():
		return "无法解析方括号指令: %s" % line

	var command_type: String = tokens[0]

	# SET_VARIABLE 的无效变量值错误
	if command_type == "SET_VARIABLE":
		var remaining: Array[String] = []
		for idx in range(1, tokens.size()):
			remaining.append(tokens[idx])
		var sv_params: Dictionary = _parse_set_variable_shorthand(remaining)
		if sv_params.has("_error"):
			return sv_params["_error"]
		return "无法解析方括号指令: %s" % line

	# 未识别的指令类型
	if not _known_command_types.has(command_type):
		return "未识别的指令类型: %s" % command_type

	return "无法解析方括号指令: %s" % line


## 获取行的缩进长度（空格数，tab 算 4 个空格）
func _get_indent_length(line: String) -> int:
	var count: int = 0
	for ch_idx in range(line.length()):
		var ch: String = line[ch_idx]
		if ch == " ":
			count += 1
		elif ch == "\t":
			count += 4
		else:
			break
	return count


## 将 AVGCommand 数组转换为 Dictionary 数组（用于嵌套存储）
func _commands_to_dicts(commands: Array[AVGCommand]) -> Array:
	var result: Array = []
	for cmd in commands:
		result.append({"command_type": cmd.command_type, "params": cmd.params})
	return result
