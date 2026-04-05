class_name AVGDSLParserV2 extends RefCounted
## AVG DSL V2 解析器 (采用 Python-like + Markdown 语法)
## 将面向对象的文本块解析为底层 Array[AVGCommand] 结构

# ==============================================================================
# 魔法映射 (Magic Mappings) -> 将对象和方法映射至底层原生指令
# ==============================================================================
const MAGIC_MAPPINGS: Dictionary = {
	# 类别 -> { 方法 -> [底层 COMMAND_TYPE, 位置参数名] }
	"bgm": {
		"play": ["PLAY_BGM", ["audio_path"]],
		"stop": ["STOP_BGM", []]
	},
	"sfx": {
		"play": ["PLAY_SFX", ["audio_path"]]
	},
	"bg": {
		"show": ["CHANGE_BACKGROUND", ["texture_path"]]
	},
	"image": {
		"show": ["SHOW_IMAGE", ["image_path"]],
		"hide": ["HIDE_IMAGE", ["image_id"]]
	},
	"cg": {
		"show": ["SHOW_IMAGE", ["image_path"]],
		"hide": ["HIDE_IMAGE", []]
	},
	"screen": {
		"fade": ["SCREEN_FADE", []],
		"time_of_day": ["SET_TIME_OF_DAY", ["preset"]],
		"flash": ["SCREEN_FLASH", []]
	},
	"time": {
		"wait": ["WAIT_TIME", ["duration"]]
	},
	"camera": {
		"shake": ["SCREEN_SHAKE", []],
		"pan": ["CAMERA_PAN", []],
		"zoom": ["CAMERA_ZOOM", ["zoom"]],
		"reset": ["CAMERA_RESET", []]
	},
	"scene": {
		"jump": ["JUMP_SCENE", ["scene_id"]]
	},
	"event": {
		"call": ["CALL_EVENT", ["event_id"]]
	}
}

# 角色对象与通用 Node 的对象方法映射 (这里不固定前缀，根据执行者判定)
const METHOD_MAPPINGS: Dictionary = {
	# 方法名 -> [底层 COMMAND_TYPE, 预期位置参数 (除自身 id 外)]
	"move": ["MOVE_CHARACTER", []], # 实际会被拆分为 kwargs
	"effect": ["CHARACTER_EFFECT", ["effect"]],
	"jump": ["JUMP_TO_NODE", []],
	"show": ["SHOW_CHARACTER", []],
	"hide": ["HIDE_CHARACTER", []],
	"change_outfit": ["CHANGE_OUTFIT", []]
}

# 常见属性赋值映射 (针对 obj.prop = value)
const PROP_MAPPINGS: Dictionary = {
	"visible": {
		true: "SHOW_CHARACTER", # if value is true/1 -> SHOW
		false: "HIDE_CHARACTER" # if value is false/0 -> HIDE
	},
	"expression": "CHANGE_EXPRESSION",
	"outfit": "CHANGE_OUTFIT"
}

# 运算映射 (针对 var[index] += value)
const OPERATION_MAP: Dictionary = {
	"=": "set",
	"+=": "add",
	"-=": "subtract",
	"*=": "multiply",
	"/=": "divide",
	"%=": "modulo"
}

const IMAGE_POSITION_PRESETS: Dictionary = {
	"left": Vector2(0.05, 0.08),
	"center": Vector2(0.275, 0.08),
	"right": Vector2(0.60, 0.08),
}

const IMAGE_SIZE_PRESETS: Dictionary = {
	"small": Vector2(0.24, 0.48),
	"medium": Vector2(0.32, 0.64),
	"large": Vector2(0.40, 0.78),
	"stage": Vector2(0.40, 0.78),
	"full": Vector2(1.0, 1.0),
	"fullscreen": Vector2(1.0, 1.0),
}

# ==============================================================================
# 解析器状态与正则预编译
# ==============================================================================
var _rx_comment: RegEx
var _rx_text_block_start: RegEx
var _rx_choice_block_start: RegEx
var _rx_choice_item: RegEx
var _rx_dialogue_line: RegEx
var _rx_var_op: RegEx
var _rx_prop_assign: RegEx
var _rx_method_call: RegEx
var _rx_if_stmt: RegEx
var _rx_else_stmt: RegEx
var _rx_kwargs_extractor: RegEx


func _init() -> void:
	_compile_regexes()


## 预编译所有的正则表达式
func _compile_regexes() -> void:
	# 注释 (以 # 打头，但排除 # => )
	_rx_comment = RegEx.new()
	_rx_comment.compile("^\\s*#(?!\\s*=>).*$")

	# => TextBlock(...)
	_rx_text_block_start = RegEx.new()
	_rx_text_block_start.compile("^\\s*#\\s*=>\\s*TextBlock\\((.*)\\)\\s*$")
	
	# => ChoiceBlock(...)
	_rx_choice_block_start = RegEx.new()
	_rx_choice_block_start.compile("^\\s*#\\s*=>\\s*ChoiceBlock\\((.*)\\)\\s*$")
	
	# - Choice Text [if condition]
	_rx_choice_item = RegEx.new()
	_rx_choice_item.compile("^\\s*-\\s+(.*?)(?:\\s+\\[if\\s+(.*?)\\])?\\s*$")
	
	# > 文本行
	_rx_dialogue_line = RegEx.new()
	_rx_dialogue_line.compile("^\\s*>\\s*(.*)$")

	# var[1] += 5
	_rx_var_op = RegEx.new()
	_rx_var_op.compile("^\\s*var\\[(\\w+)\\]\\s*([+\\-*/%]?=)\\s*(.+)$")
	
	# char_001.visible = true
	_rx_prop_assign = RegEx.new()
	_rx_prop_assign.compile("^\\s*(\\w+)\\.(\\w+)\\s*=\\s*(.+)$")
	
	# bgm.play("xyz") 或 char_001.move(...)
	_rx_method_call = RegEx.new()
	_rx_method_call.compile("^\\s*(\\w+)\\.(\\w+)\\((.*)\\)\\s*$")
	
	# if var[1] == 5:
	_rx_if_stmt = RegEx.new()
	_rx_if_stmt.compile("^\\s*if\\s+(.+):\\s*$")
	
	# else:
	_rx_else_stmt = RegEx.new()
	_rx_else_stmt.compile("^\\s*else\\s*:\\s*$")
	
	# key="val" 或 key=123 (用于拆解 kwargs)
	_rx_kwargs_extractor = RegEx.new()
	_rx_kwargs_extractor.compile("(\\w+)\\s*=\\s*(?:\"([^\"]*)\"|([^,\\s]+))")


# ==============================================================================
# 解析入口
# ==============================================================================

## 解析 DSL V2 文本为 AVGCommand 数组
## @return: {success: bool, commands: Array[AVGCommand], errors: Array[Dictionary]}
func parse(dsl_text: String) -> Dictionary:
	var lines: Array[String] = []
	for l in dsl_text.split("\n"):
		lines.append(l)

	var commands: Array[AVGCommand] = []
	var errors: Array[Dictionary] = []
	
	# 采用统一的状态机块解析器入口
	var result: Dictionary = _parse_block(lines, 0, 0)
	errors.append_array(result.get("errors", []))
	commands = result.get("commands", [])

	return {
		"success": errors.is_empty(),
		"commands": commands,
		"errors": errors
	}


## 核心块解析，处理缩进并构建树
## @param indent_level: 基础缩进空格数（1 Tab = 4 空格约定）
func _parse_block(lines: Array[String], start_idx: int, indent_level: int) -> Dictionary:
	var parsed_cmds: Array[AVGCommand] = []
	var errors: Array[Dictionary] = []
	var i: int = start_idx
	
	# 用于在 TextBlock 中跨行聚合文本
	var current_text_block_kwargs: Dictionary = {}
	
	while i < lines.size():
		var raw_line: String = lines[i]
		# 空行跳过
		if raw_line.strip_edges().is_empty():
			i += 1
			continue
			
		# 计算缩进
		var current_indent: int = _get_indent_level(raw_line)
		if current_indent < indent_level:
			# 如果遇到小于当前层级的缩进，说明当前块结束
			break
			
		# 将其视作当前行（去除前导空白后的部分）
		var line: String = raw_line.strip_edges()
		
		# 1. 注释跳过
		if _rx_comment.search(raw_line) != null:
			i += 1
			continue
			
		# 2. 对话块控制 (# => TextBlock)
		var text_match: RegExMatch = _rx_text_block_start.search(raw_line)
		if text_match:
			current_text_block_kwargs = _parse_kwargs(text_match.get_string(1))
			i += 1
			continue
			
		# 3. 对话行 (>)
		var dialogue_match: RegExMatch = _rx_dialogue_line.search(raw_line)
		if dialogue_match:
			var text_content: String = dialogue_match.get_string(1).strip_edges()
			var cmd: AVGCommand = _create_dialogue_command(text_content, current_text_block_kwargs)
			parsed_cmds.append(cmd)
			i += 1
			continue
			
		# 4. 选项块探测 (# => ChoiceBlock)
		var choice_match: RegExMatch = _rx_choice_block_start.search(raw_line)
		if choice_match:
			var block_res: Dictionary = _parse_choice_block(lines, i, current_indent)
			if block_res.has("command"):
				parsed_cmds.append(block_res["command"])
			errors.append_array(block_res.get("errors", []))
			i = block_res.get("next_idx", i + 1)
			continue
			
		# 如果遇到非 `>` 对话行，自动重置 TextBlock 的预存参数
		current_text_block_kwargs.clear()
		
		# ---- 后续的非对话行解析 ----
		
		# 4. IF 控制流
		var if_match: RegExMatch = _rx_if_stmt.search(raw_line)
		if if_match:
			var condition: String = if_match.get_string(1).strip_edges()
			
			var if_cmd: AVGCommand = AVGCommand.new()
			if_cmd.command_type = "IF"
			
			# 解析条件变量名与操作符
			var cond_data: Dictionary = _parse_condition(condition, i + 1, errors)
			if_cmd.params["variable_id"] = cond_data.get("variable_id", "")
			if_cmd.params["operator"] = cond_data.get("operator", "==")
			if_cmd.params["value"] = cond_data.get("value", 0)
			
			# 递归解析 if 下级块（缩进必须严格大于当前）
			var next_indent: int = _find_next_indent(lines, i + 1)
			if next_indent > current_indent:
				var block_res: Dictionary = _parse_block(lines, i + 1, next_indent)
				if_cmd.params["if_commands"] = block_res.get("commands", [])
				errors.append_array(block_res.get("errors", []))
				i = block_res.get("next_idx", i + 1)
			else:
				if_cmd.params["if_commands"] = []
				i += 1
				
			# 处理配套的 else (同级缩进且紧跟其后)
			while i < lines.size():
				var next_raw: String = lines[i]
				if next_raw.strip_edges().is_empty() or _rx_comment.search(next_raw):
					i += 1
					continue
				
				var next_ind: int = _get_indent_level(next_raw)
				if next_ind == current_indent and _rx_else_stmt.search(next_raw):
					var else_next_ind: int = _find_next_indent(lines, i + 1)
					if else_next_ind > current_indent:
						var else_res: Dictionary = _parse_block(lines, i + 1, else_next_ind)
						if_cmd.params["else_commands"] = else_res.get("commands", [])
						errors.append_array(else_res.get("errors", []))
						i = else_res.get("next_idx", i + 1)
					else:
						if_cmd.params["else_commands"] = []
						i += 1
					break
				else:
					break # 不是 else，退出配套寻找
			
			parsed_cmds.append(if_cmd)
			continue
			
		# 5. 变量计算 (var[1] += 5)
		var var_match: RegExMatch = _rx_var_op.search(raw_line)
		if var_match:
			var var_id: String = var_match.get_string(1)
			var op_str: String = var_match.get_string(2)
			var val_str: String = var_match.get_string(3).strip_edges()
			
			var cmd: AVGCommand = AVGCommand.new()
			cmd.command_type = "SET_VARIABLE"
			cmd.params["variable_id"] = "var_%03d" % int(var_id) if var_id.is_valid_int() else var_id
			cmd.params["operation"] = OPERATION_MAP.get(op_str, "set")
			cmd.params["value"] = _safe_convert_int(val_str)
			parsed_cmds.append(cmd)
			i += 1
			continue
			
		# 6. 对象方法调用 (bgm.play("xyz") or char.move(...))
		var method_match: RegExMatch = _rx_method_call.search(raw_line)
		if method_match:
			var obj_name: String = method_match.get_string(1)
			var method_name: String = method_match.get_string(2)
			var args_str: String = method_match.get_string(3)
			
			var c: AVGCommand = _build_method_command(obj_name, method_name, args_str, i + 1, errors)
			if c != null:
				parsed_cmds.append(c)
			i += 1
			continue

		# 7. 对象属性赋值 (char_001.visible = true)
		var prop_match: RegExMatch = _rx_prop_assign.search(raw_line)
		if prop_match:
			var obj_name: String = prop_match.get_string(1)
			var prop_name: String = prop_match.get_string(2)
			var val_str: String = prop_match.get_string(3).strip_edges()
			
			var c: AVGCommand = _build_prop_command(obj_name, prop_name, val_str, i + 1, errors)
			if c != null:
				parsed_cmds.append(c)
			i += 1
			continue
			
		# 其他未识别的行：自动降级为旁白 DIALOGUE（容错 LLM 输出裸文本）
		var bare_text: String = line.strip_edges()
		if not bare_text.is_empty():
			var fallback_cmd: AVGCommand = _create_dialogue_command(bare_text, {})
			parsed_cmds.append(fallback_cmd)
			push_warning("DSL line %d: auto-wrapped bare text as narration: %s" % [i + 1, bare_text])
		i += 1
		
	return {
		"commands": parsed_cmds,
		"errors": errors,
		"next_idx": i
	}


## 解析 Choice 选项块
## @param start_idx: 当前 # => ChoiceBlock 所在行
func _parse_choice_block(lines: Array[String], start_idx: int, indent_level: int) -> Dictionary:
	var cmd: AVGCommand = AVGCommand.new()
	cmd.command_type = "CHOICE"
	cmd.params["choices"] = []
	
	var errs: Array[Dictionary] = []
	var i: int = start_idx + 1
	var current_choice_dict: Dictionary = {}
	
	while i < lines.size():
		var raw_line: String = lines[i]
		if raw_line.strip_edges().is_empty() or _rx_comment.search(raw_line):
			i += 1
			continue
			
		var cur_ind: int = _get_indent_level(raw_line)
		if cur_ind < indent_level:
			break
			
		# 看是否为以 '-' 开头的新选项
		var match_item: RegExMatch = _rx_choice_item.search(raw_line)
		if match_item and cur_ind == indent_level:
			# 如果之前已经有 current_choice_dict 在组装，说明这已经是下一个选项了
			# 之前的选项内容此时已经收集完毕
			current_choice_dict = {}
			
			var choice_text: String = match_item.get_string(1).strip_edges()
			var inline_cond: String = match_item.get_string(2).strip_edges()
			
			current_choice_dict["text"] = choice_text
			current_choice_dict["commands"] = []
			
			if not inline_cond.is_empty():
				var cd: Dictionary = _parse_condition(inline_cond, i + 1, errs)
				if cd.get("variable_id") != "":
					current_choice_dict["condition_variable"] = cd.get("variable_id")
					current_choice_dict["condition_operator"] = cd.get("operator")
					current_choice_dict["condition_value"] = cd.get("value")
					current_choice_dict["condition_action"] = "hide" # 默认隐藏
			
			cmd.params["choices"].append(current_choice_dict)
			
			# 其下方可能存在属于此选项的执行逻辑缩进块
			var next_ind: int = _find_next_indent(lines, i + 1)
			if next_ind > indent_level:
				var res_block: Dictionary = _parse_block(lines, i + 1, next_ind)
				current_choice_dict["commands"] = res_block.get("commands", [])
				errs.append_array(res_block.get("errors", []))
				i = res_block.get("next_idx", i + 1)
				continue
				
		elif cur_ind == indent_level:
			# 同级但不是 '-' 开头，意味着 ChoiceBlock 结束
			break
			
		i += 1

	return {
		"command": cmd,
		"errors": errs,
		"next_idx": i
	}

# ==============================================================================
# 工具与转换函数
# ==============================================================================

## 计算行的缩进级别(强制使用 4 个空格作为一级 Tab)
func _get_indent_level(line: String) -> int:
	var spaces: int = 0
	for j in range(line.length()):
		if line[j] == ' ':
			spaces += 1
		elif line[j] == '\t':
			spaces += 4
		else:
			break
	return spaces

## 往下查找第一个非空、非注释行的缩进级别
func _find_next_indent(lines: Array[String], start_idx: int) -> int:
	var i: int = start_idx
	while i < lines.size():
		var line: String = lines[i]
		var st: String = line.strip_edges()
		if not st.is_empty() and _rx_comment.search(line) == null:
			return _get_indent_level(line)
		i += 1
	return 0

## 从 "speaker='char_001', emotion='smile'" 解析 kwargs 参数字典
func _parse_kwargs(kwargs_str: String) -> Dictionary:
	var result: Dictionary = {}
	var matches: Array[RegExMatch] = _rx_kwargs_extractor.search_all(kwargs_str)
	for m in matches:
		var k: String = m.get_string(1)
		# 提取带引用的全匹配或者非引用值
		var v: String = m.get_string(2) if not m.get_string(2).is_empty() else m.get_string(3)
		
		# 尝试强转为 bool/int (这可以避免 string 的判断错误)
		var final_v: Variant = v
		if v.to_lower() == "true": final_v = true
		elif v.to_lower() == "false": final_v = false
		elif v.is_valid_int(): final_v = int(v)
		elif v.is_valid_float(): final_v = float(v)
		
		result[k] = final_v
	return result

## 生成对单个条件的解析
func _parse_condition(cond_str: String, line_num: int, errors: Array[Dictionary]) -> Dictionary:
	# 例: var[1] == 10
	var rx_cond: RegEx = RegEx.new()
	rx_cond.compile("var\\[(\\w+)\\]\\s*(==|!=|>|<|>=|<=)\\s*(.+)")
	var mat: RegExMatch = rx_cond.search(cond_str)
	if mat:
		var id_str: String = mat.get_string(1)
		return {
			"variable_id": "var_%03d" % int(id_str) if id_str.is_valid_int() else id_str,
			"operator": mat.get_string(2),
			"value": _safe_convert_int(mat.get_string(3).strip_edges())
		}
	else:
		errors.append({"line": line_num, "message": "Failed to parse condition: " + cond_str})
		return {"variable_id": "", "operator": "==", "value": 0}

func _safe_convert_int(val_str: String) -> int:
	if val_str.to_lower() == "true": return 1
	if val_str.to_lower() == "false": return 0
	return val_str.to_int()

## 创建 DIALOGUE 命令
func _create_dialogue_command(text: String, kwargs: Dictionary) -> AVGCommand:
	var cmd: AVGCommand = AVGCommand.new()
	cmd.command_type = "DIALOGUE"
	cmd.params["text"] = text
	
	if kwargs.has("speaker"):
		cmd.params["speaker"] = kwargs["speaker"]
	elif kwargs.has("speaker_name"):
		cmd.params["speaker"] = kwargs["speaker_name"]
		
	for k in kwargs:
		if k in ["speaker", "speaker_name"]:
			continue
		if k == "expression":
			cmd.params["emotion"] = kwargs[k]
			continue
		cmd.params[k] = kwargs[k]
	return cmd

## 生成对象属性赋值命令
func _build_prop_command(obj: String, prop: String, value_str: String, _line_num: int, _errors: Array[Dictionary]) -> AVGCommand:
	var val: Variant = _safe_convert_value(_strip_quotes(value_str.strip_edges()))
	var cmd: AVGCommand = AVGCommand.new()
	
	# 特例1：visible
	if prop == "visible" or prop == "show":
		var mapped_op: String = ""
		var bval: bool = false
		if val is bool: bval = val
		elif val is int: bval = val > 0
		else: bval = val.to_lower() == "true"
		
		mapped_op = PROP_MAPPINGS["visible"][bval] # SHOW_CHARACTER or HIDE_CHARACTER
		cmd.command_type = mapped_op
		cmd.params["character_id"] = obj
		return cmd
		
	# 特例2: expression
	elif prop == "expression":
		cmd.command_type = "CHANGE_EXPRESSION"
		cmd.params["character_id"] = obj
		cmd.params["expression"] = str(val)
		return cmd
	elif prop == "outfit":
		cmd.command_type = "CHANGE_OUTFIT"
		cmd.params["character_id"] = obj
		cmd.params["outfit"] = str(val)
		return cmd
		
	# 通用情况
	cmd.command_type = "SET_CHARACTER_PROPERTY"
	cmd.params["character_id"] = obj
	cmd.params[prop] = val
	return cmd

## 生成方法调用命令 (Magic Mappings / Character mappings)
func _build_method_command(obj: String, method: String, kwargs_str: String, line_num: int, errors: Array[Dictionary]) -> AVGCommand:
	var cmd: AVGCommand = AVGCommand.new()
	var parsed_args: Dictionary = _parse_target_args(kwargs_str)
	var pos_args: Array = parsed_args.get("positional", [])
	var kw: Dictionary = parsed_args.get("kwargs", {})

	if obj == "stage":
		return _build_stage_command(method, pos_args, kw, line_num, errors)
	
	# 检查系统魔法映射
	if MAGIC_MAPPINGS.has(obj):
		var sys_funcs: Dictionary = MAGIC_MAPPINGS[obj]
		if sys_funcs.has(method):
			var map_def: Array = sys_funcs[method]
			var cmd_type: String = map_def[0]
			var expected_pos: Array = map_def[1]
			
			cmd.command_type = cmd_type
			_apply_positional_args(cmd, expected_pos, pos_args, line_num, errors)
			cmd.params.merge(kw)
			if obj == "image" or obj == "cg":
				_finalize_image_command(obj, method, cmd)
			return cmd
			
	# 作为通用对象/节点的方法处理
	if METHOD_MAPPINGS.has(method):
		var map_def: Array = METHOD_MAPPINGS[method]
		cmd.command_type = map_def[0]
		
		# 基于类型猜测写入相关 ID，目前主要处理 character_id 和 node_id
		if cmd.command_type.begins_with("CHARACTER_") or cmd.command_type.ends_with("_CHARACTER") or cmd.command_type in ["CHANGE_EXPRESSION", "CHANGE_OUTFIT"]:
			cmd.params["character_id"] = obj
		else:
			cmd.params["node_id"] = obj
			
		var expected_pos: Array = map_def[1]
		_apply_positional_args(cmd, expected_pos, pos_args, line_num, errors)
		cmd.params.merge(kw)
		return cmd
		
	errors.append({"line": line_num, "message": "Undefined object or method: %s.%s()" % [obj, method]})
	return null


func _build_stage_command(method: String, pos_args: Array, kw: Dictionary, line_num: int, errors: Array[Dictionary]) -> AVGCommand:
	if method != "set" and method != "clear" and method != "enter" and method != "exit":
		errors.append({"line": line_num, "message": "Undefined object or method: stage.%s()" % method})
		return null

	var cmd: AVGCommand = AVGCommand.new()
	match method:
		"enter":
			cmd.command_type = "STAGE_ENTER"
		"exit":
			cmd.command_type = "STAGE_EXIT"
		_:
			cmd.command_type = "STAGE_SET"

	var characters: Array[String] = []
	if method != "clear":
		for entry in pos_args:
			var character_ref: String = str(entry).strip_edges()
			if character_ref.is_empty():
				continue
			characters.append(character_ref)

		var raw_characters: String = str(kw.get("characters", "")).strip_edges()
		if not raw_characters.is_empty():
			characters.append_array(_parse_stage_csv_string(raw_characters))

	cmd.params["characters"] = characters
	cmd.params["characters_csv"] = ",".join(PackedStringArray(characters))

	var kw_copy: Dictionary = kw.duplicate(true)
	kw_copy.erase("characters")
	cmd.params.merge(kw_copy)
	return cmd

## 辅助解析函数：将 args 尝试分类为 position 和 kwargs
func _parse_target_args(s: String) -> Dictionary:
	var pos: Array = []
	var kw: Dictionary = {}
	
	if s.strip_edges().is_empty():
		return {"positional": pos, "kwargs": kw}
		
	var arr: Array[String] = _split_call_arguments(s)
	var found_kw: bool = false
	for p_raw in arr:
		var p: String = p_raw.strip_edges()
		if p.is_empty():
			continue
		if "=" in p:
			found_kw = true
			var parts: PackedStringArray = p.split("=", false, 1)
			var k: String = parts[0].strip_edges()
			var v: String = _strip_quotes(parts[1].strip_edges())
			kw[k] = _safe_convert_value(v)
		else:
			if not found_kw:
				pos.append(_safe_convert_value(_strip_quotes(p)))
	
	return {"positional": pos, "kwargs": kw}


func _split_call_arguments(s: String) -> Array[String]:
	var parts: Array[String] = []
	var current: String = ""
	var quote_char: String = ""

	for i in range(s.length()):
		var ch: String = s.substr(i, 1)
		if not quote_char.is_empty():
			current += ch
			if ch == quote_char:
				quote_char = ""
			continue

		if ch == "\"" or ch == "'":
			quote_char = ch
			current += ch
			continue

		if ch == ",":
			parts.append(current.strip_edges())
			current = ""
			continue

		current += ch

	if not current.strip_edges().is_empty():
		parts.append(current.strip_edges())

	return parts


func _parse_stage_csv_string(raw_value: String) -> Array[String]:
	var result: Array[String] = []
	for entry in raw_value.split(","):
		var trimmed: String = entry.strip_edges()
		if trimmed.is_empty():
			continue
		result.append(trimmed)
	return result

func _apply_positional_args(cmd: AVGCommand, expected: Array, provided: Array, line_num: int, errors: Array[Dictionary]) -> void:
	if provided.size() > expected.size():
		errors.append({"line": line_num, "message": "Too many positional arguments provided."})
	
	for i in range(min(expected.size(), provided.size())):
		cmd.params[expected[i]] = provided[i]


func _finalize_image_command(obj: String, method: String, cmd: AVGCommand) -> void:
	if method == "hide":
		if obj == "cg" and str(cmd.params.get("image_id", "")).strip_edges().is_empty():
			cmd.params["image_id"] = "cg"
		return

	var image_path: String = str(cmd.params.get("image_path", "")).strip_edges()
	if image_path.is_empty():
		return

	if str(cmd.params.get("image_id", "")).strip_edges().is_empty():
		cmd.params["image_id"] = "cg" if obj == "cg" else _build_default_image_id(image_path)

	var default_position: Vector2 = Vector2.ZERO if obj == "cg" else IMAGE_POSITION_PRESETS["center"]
	var default_size: Vector2 = Vector2.ONE if obj == "cg" else IMAGE_SIZE_PRESETS["stage"]

	cmd.params["position"] = _resolve_image_position(cmd.params, default_position)
	cmd.params["size"] = _resolve_image_size(cmd.params, default_size)

	if not cmd.params.has("z_order"):
		cmd.params["z_order"] = 10 if obj == "cg" else 0

	_cleanup_image_layout_keys(cmd.params)


func _resolve_image_position(params: Dictionary, default_position: Vector2) -> Vector2:
	if params.has("position"):
		var raw_position: Variant = params.get("position")
		if raw_position is Vector2:
			return raw_position
		var position_name: String = str(raw_position).strip_edges().to_lower()
		if IMAGE_POSITION_PRESETS.has(position_name):
			return IMAGE_POSITION_PRESETS[position_name]

	var resolved_x: float = float(params.get("x", default_position.x))
	var resolved_y: float = float(params.get("y", default_position.y))
	return Vector2(resolved_x, resolved_y)


func _resolve_image_size(params: Dictionary, default_size: Vector2) -> Vector2:
	if params.has("size"):
		var raw_size: Variant = params.get("size")
		if raw_size is Vector2:
			return raw_size
		var size_name: String = str(raw_size).strip_edges().to_lower()
		if IMAGE_SIZE_PRESETS.has(size_name):
			return IMAGE_SIZE_PRESETS[size_name]

	var resolved_width: float = float(params.get("width", default_size.x))
	var resolved_height: float = float(params.get("height", default_size.y))
	return Vector2(resolved_width, resolved_height)


func _cleanup_image_layout_keys(params: Dictionary) -> void:
	params.erase("x")
	params.erase("y")
	params.erase("width")
	params.erase("height")


func _build_default_image_id(image_path: String) -> String:
	var normalized: String = image_path.strip_edges().to_lower()
	normalized = normalized.replace("res://", "")
	normalized = normalized.replace("user://", "")
	var rx: RegEx = RegEx.new()
	rx.compile("[^a-z0-9_]+")
	normalized = rx.sub(normalized, "_", true)
	normalized = normalized.strip_edges()
	while normalized.contains("__"):
		normalized = normalized.replace("__", "_")
	normalized = normalized.trim_prefix("_")
	normalized = normalized.trim_suffix("_")
	if normalized.is_empty():
		return "image"
	return normalized

func _safe_convert_value(val_str: String) -> Variant:
	if val_str.to_lower() == "true": return true
	elif val_str.to_lower() == "false": return false
	elif val_str.is_valid_int(): return int(val_str)
	elif val_str.is_valid_float(): return float(val_str)
	return val_str

func _strip_quotes(s: String) -> String:
	# 容错：LLM 偶尔会在引号外产生多余的括号等字符，如 "happy")
	# 先尝试用正则提取引号内的内容
	if s.contains("\"") or s.contains("'"):
		var rx: RegEx = RegEx.new()
		rx.compile("[\"']([^\"']*)[\"']")
		var m: RegExMatch = rx.search(s)
		if m:
			return m.get_string(1)
	if s.begins_with("\"") and s.ends_with("\""):
		return s.substr(1, s.length() - 2)
	if s.begins_with("'") and s.ends_with("'"):
		return s.substr(1, s.length() - 2)
	return s
