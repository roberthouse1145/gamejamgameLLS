class_name AVGDSLParserV2 extends RefCounted
## AVG DSL V2 解析器 (采用 Python-like + Markdown 语法)
## 将面向对象的文本块解析为底层 Array[AVGCommand] 结构

const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")

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
	"wait": {
		"click": ["WAIT_CLICK", []]
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
	"flip": ["FLIP_CHARACTER", []],
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
var _rx_elif_stmt: RegEx
var _rx_else_if_stmt: RegEx
var _rx_else_stmt: RegEx
var _rx_kwargs_extractor: RegEx
var _rx_legacy_jump_scene: RegEx
var _rx_uppercase_command: RegEx
var _rx_embedded_var_op: RegEx
var _rx_embedded_method_call: RegEx
var _rx_embedded_prop_assign: RegEx
var _rx_embedded_if_stmt: RegEx
var _rx_embedded_else_stmt: RegEx
var _rx_embedded_elif_stmt: RegEx
var _rx_embedded_else_if_stmt: RegEx
var _rx_embedded_legacy_jump_scene: RegEx


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
	# 对象名允许使用中文角色名等任意非空白 token，方法/属性名仍限制为 ASCII 标识符
	_rx_prop_assign.compile("^\\s*([^\\.\\s]+)\\.(\\w+)\\s*=\\s*(.+)$")
	
	# bgm.play("xyz") 或 char_001.move(...)
	_rx_method_call = RegEx.new()
	_rx_method_call.compile("^\\s*([^\\.\\s]+)\\.(\\w+)\\((.*)\\)\\s*$")
	
	# if var[1] == 5:
	_rx_if_stmt = RegEx.new()
	_rx_if_stmt.compile("^\\s*if\\s+(.+):\\s*$")

	# elif ...:
	_rx_elif_stmt = RegEx.new()
	_rx_elif_stmt.compile("^\\s*elif\\s+(.+):\\s*$")

	# else if ...:
	_rx_else_if_stmt = RegEx.new()
	_rx_else_if_stmt.compile("^\\s*else\\s+if\\s+(.+):\\s*$")
	
	# else:
	_rx_else_stmt = RegEx.new()
	_rx_else_stmt.compile("^\\s*else\\s*:\\s*$")

	# jump_scene("scene_id") - legacy syntax compatibility
	_rx_legacy_jump_scene = RegEx.new()
	_rx_legacy_jump_scene.compile("^\\s*jump_scene\\((.*)\\)\\s*$")

	# 引擎内部 command_type 形式（如 JUMP_SCENE(...) / SHOW_CHARACTER(...)）。
	# 这些不是用户语法，LLM 偶尔会"还原"出来。匹配后必须报错而非降级旁白，
	# 否则玩家会在游戏画面看到字面命令文本。
	_rx_uppercase_command = RegEx.new()
	_rx_uppercase_command.compile("^\\s*([A-Z][A-Z_]+)\\s*\\(.*\\)\\s*$")

	_rx_embedded_var_op = RegEx.new()
	_rx_embedded_var_op.compile("var\\[(\\w+)\\]\\s*([+\\-*/%]?=)\\s*.+$")

	_rx_embedded_method_call = RegEx.new()
	_rx_embedded_method_call.compile("([^\\.\\s]+)\\.(\\w+)\\((.*)\\)\\s*$")

	_rx_embedded_prop_assign = RegEx.new()
	_rx_embedded_prop_assign.compile("([^\\.\\s]+)\\.(\\w+)\\s*=\\s*.+$")

	_rx_embedded_if_stmt = RegEx.new()
	_rx_embedded_if_stmt.compile("\\bif\\s+.+:\\s*$")

	_rx_embedded_else_stmt = RegEx.new()
	_rx_embedded_else_stmt.compile("\\belse\\s*:\\s*$")

	_rx_embedded_elif_stmt = RegEx.new()
	_rx_embedded_elif_stmt.compile("\\belif\\s+.+:\\s*$")

	_rx_embedded_else_if_stmt = RegEx.new()
	_rx_embedded_else_if_stmt.compile("\\belse\\s+if\\s+.+:\\s*$")

	_rx_embedded_legacy_jump_scene = RegEx.new()
	_rx_embedded_legacy_jump_scene.compile("jump_scene\\((.*)\\)\\s*$")
	
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
	var warnings: Array[Dictionary] = []
	
	# 采用统一的状态机块解析器入口
	var result: Dictionary = _parse_block(lines, 0, 0)
	errors.append_array(result.get("errors", []))
	warnings.append_array(result.get("warnings", []))
	commands = result.get("commands", [])

	return {
		"success": errors.is_empty(),
		"commands": commands,
		"errors": errors,
		"warnings": warnings
	}


## 核心块解析，处理缩进并构建树
## @param indent_level: 基础缩进空格数（1 Tab = 4 空格约定）
func _parse_block(lines: Array[String], start_idx: int, indent_level: int) -> Dictionary:
	var parsed_cmds: Array[AVGCommand] = []
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []
	var i: int = start_idx
	
	# 用于在 TextBlock 中跨行聚合文本
	var current_text_block_kwargs: Dictionary = {}
	
	while i < lines.size():
		var raw_line: String = lines[i]
		# 空行跳过
		if raw_line.strip_edges().is_empty():
			i += 1
			continue

		var prepared_line: String = _prepare_line_for_parse(raw_line)
		if prepared_line.strip_edges().is_empty():
			i += 1
			continue
			
		# 计算缩进
		var current_indent: int = _get_indent_level(raw_line)
		if current_indent < indent_level:
			# 如果遇到小于当前层级的缩进，说明当前块结束
			break
			
		# 将其视作当前行（去除前导空白后的部分）
		var line: String = prepared_line.strip_edges()
		
		# 1. 注释跳过
		if _rx_comment.search(prepared_line) != null:
			i += 1
			continue
			
		# 2. 对话块控制 (# => TextBlock)
		var text_match: RegExMatch = _rx_text_block_start.search(prepared_line)
		if text_match:
			current_text_block_kwargs = _parse_kwargs(text_match.get_string(1))
			i += 1
			continue
			
		# 3. 对话行 (>)
		# 连续、同缩进的 > 行属于同一个 TextBlock，合并为一个带换行的 DIALOGUE。
		# 这样角色可以在同一个对话框里自然分行；要切到旁白或其他 speaker，
		# 必须显式写新的 # => TextBlock(...)。
		var dialogue_match: RegExMatch = _rx_dialogue_line.search(prepared_line)
		if dialogue_match:
			var dialogue_block: Dictionary = _collect_dialogue_lines(lines, i, current_indent)
			var text_content: String = str(dialogue_block.get("text", ""))
			var cmd: AVGCommand = _create_dialogue_command(text_content, current_text_block_kwargs)
			parsed_cmds.append(cmd)
			current_text_block_kwargs.clear()
			i = int(dialogue_block.get("next_idx", i + 1))
			continue
			
		# 4. 选项块探测 (# => ChoiceBlock)
		var choice_match: RegExMatch = _rx_choice_block_start.search(prepared_line)
		if choice_match:
			var block_res: Dictionary = _parse_choice_block(lines, i, current_indent)
			if block_res.has("command"):
				parsed_cmds.append(block_res["command"])
			errors.append_array(block_res.get("errors", []))
			warnings.append_array(block_res.get("warnings", []))
			i = block_res.get("next_idx", i + 1)
			continue
			
		# 如果遇到非 `>` 对话行，自动重置 TextBlock 的预存参数
		current_text_block_kwargs.clear()
		
		# ---- 后续的非对话行解析 ----
		
		# 4. IF 控制流
		var if_match: RegExMatch = _rx_if_stmt.search(prepared_line)
		if if_match:
			var condition: String = if_match.get_string(1).strip_edges()
			
			var if_cmd: AVGCommand = AVGCommand.new()
			if_cmd.command_type = "IF"
			if_cmd.params["condition_commands"] = []
			if_cmd.params["if_commands"] = []
			if_cmd.params["else_commands"] = []
			if_cmd.params["has_else"] = false
			
			# 解析条件并转换为标准 condition_commands 结构
			if_cmd.params["condition_commands"] = _parse_condition_commands(condition, i + 1, errors)
			
			# 递归解析 if 下级块（缩进必须严格大于当前）
			var next_indent: int = _find_next_indent(lines, i + 1)
			if next_indent > current_indent:
				var block_res: Dictionary = _parse_block(lines, i + 1, next_indent)
				if_cmd.params["if_commands"] = block_res.get("commands", [])
				errors.append_array(block_res.get("errors", []))
				warnings.append_array(block_res.get("warnings", []))
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
					if_cmd.params["has_else"] = true
					var else_next_ind: int = _find_next_indent(lines, i + 1)
					if else_next_ind > current_indent:
						var else_res: Dictionary = _parse_block(lines, i + 1, else_next_ind)
						if_cmd.params["else_commands"] = else_res.get("commands", [])
						errors.append_array(else_res.get("errors", []))
						warnings.append_array(else_res.get("warnings", []))
						i = else_res.get("next_idx", i + 1)
					else:
						if_cmd.params["else_commands"] = []
						i += 1
					break
				else:
					break # 不是 else，退出配套寻找
			
			parsed_cmds.append(if_cmd)
			continue

		# 4.5. 显式拒绝不支持的 elif，避免被自动包装成旁白
		var elif_match: RegExMatch = _rx_elif_stmt.search(prepared_line)
		if elif_match:
			errors.append({
				"line": i + 1,
				"message": "Unsupported control flow: elif. Please rewrite as nested/continued if-else."
			})
			i += 1
			continue

		# 4.6. 显式拒绝 LLM 常写出的 else if 变体
		var else_if_match: RegExMatch = _rx_else_if_stmt.search(prepared_line)
		if else_if_match:
			errors.append({
				"line": i + 1,
				"message": "Unsupported control flow: else if. Please rewrite as nested/continued if-else."
			})
			i += 1
			continue

		# 4.7. `else:` 只能由前面的 IF 分支消费。走到这里说明它没有匹配到同级 if。
		var else_match: RegExMatch = _rx_else_stmt.search(prepared_line)
		if else_match:
			errors.append({
				"line": i + 1,
				"message": "Unexpected else without matching if. Make sure else: immediately follows the if block and uses the same indentation."
			})
			i += 1
			continue
			
		# 5. 变量计算 (var[1] += 5)
		var var_match: RegExMatch = _rx_var_op.search(prepared_line)
		if var_match:
			var var_ref: String = var_match.get_string(1)
			var op_str: String = var_match.get_string(2)
			var val_str: String = var_match.get_string(3).strip_edges()
			
			var cmd: AVGCommand = AVGCommand.new()
			cmd.command_type = "SET_VARIABLE"
			cmd.params.merge(_parse_variable_ref_token(var_ref), true)
			cmd.params["operation"] = OPERATION_MAP.get(op_str, "set")
			cmd.params["value_source"] = "constant"
			cmd.params["value"] = _parse_variable_literal(val_str)
			parsed_cmds.append(cmd)
			i += 1
			continue
			
		# 6. 对象方法调用 (bgm.play("xyz") or char.move(...))
		var method_match: RegExMatch = _rx_method_call.search(prepared_line)
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
		var prop_match: RegExMatch = _rx_prop_assign.search(prepared_line)
		if prop_match:
			var obj_name: String = prop_match.get_string(1)
			var prop_name: String = prop_match.get_string(2)
			var val_str: String = prop_match.get_string(3).strip_edges()
			
			var c: AVGCommand = _build_prop_command(obj_name, prop_name, val_str, i + 1, errors)
			if c != null:
				parsed_cmds.append(c)
			i += 1
			continue

		# 8. 兼容旧式全局跳转函数 jump_scene("scene_xxx")
		var legacy_jump_match: RegExMatch = _rx_legacy_jump_scene.search(prepared_line)
		if legacy_jump_match:
			var legacy_jump_args: String = legacy_jump_match.get_string(1)
			var legacy_jump_cmd: AVGCommand = _build_legacy_jump_scene_command(legacy_jump_args, i + 1, errors)
			if legacy_jump_cmd != null:
				parsed_cmds.append(legacy_jump_cmd)
			i += 1
			continue

		# 8.5. 显式拒绝引擎内部 command_type 形式（JUMP_SCENE / SHOW_CHARACTER 等）。
		# 必须在第 9 步旁白兜底之前拦截，否则会被当作旁白文本说给玩家听。
		var upper_cmd_match: RegExMatch = _rx_uppercase_command.search(prepared_line)
		if upper_cmd_match:
			var upper_name: String = upper_cmd_match.get_string(1)
			errors.append({
				"line": i + 1,
				"message": "Forbidden uppercase internal command '%s(...)'. Use the documented user-facing syntax instead (e.g. scene.jump(...), 角色.show(...))." % upper_name
			})
			i += 1
			continue

		# 9. 其他未识别的行：自动降级为旁白 DIALOGUE（容错 LLM 输出裸文本）
		var bare_text: String = line.strip_edges()
		if not bare_text.is_empty():
			var fallback_cmd: AVGCommand = _create_dialogue_command(bare_text, {})
			parsed_cmds.append(fallback_cmd)
			warnings.append({
				"line": i + 1,
				"message": "auto-wrapped bare text as narration: %s" % bare_text,
				"text": bare_text,
			})
		i += 1
		
	return {
		"commands": parsed_cmds,
		"errors": errors,
		"warnings": warnings,
		"next_idx": i
	}


func _collect_dialogue_lines(lines: Array[String], start_idx: int, indent: int) -> Dictionary:
	var text_lines: Array[String] = []
	var i: int = start_idx
	while i < lines.size():
		var raw_line: String = lines[i]
		if raw_line.strip_edges().is_empty():
			break
		if _get_indent_level(raw_line) != indent:
			break
		var prepared_line: String = _prepare_line_for_parse(raw_line)
		if prepared_line.strip_edges().is_empty():
			break
		if _rx_comment.search(prepared_line) != null:
			break
		var dialogue_match: RegExMatch = _rx_dialogue_line.search(prepared_line)
		if dialogue_match == null:
			break
		text_lines.append(dialogue_match.get_string(1).strip_edges())
		i += 1
	return {
		"text": "\n".join(text_lines),
		"next_idx": i,
	}


func _build_legacy_jump_scene_command(args_str: String, line_num: int, errors: Array[Dictionary]) -> AVGCommand:
	var parsed: Dictionary = _parse_target_args(args_str)
	var args: Array = parsed.get("positional", [])
	var kwargs: Dictionary = parsed.get("kwargs", {})
	var scene_id: String = ""
	if kwargs.has("scene_id"):
		scene_id = str(kwargs.get("scene_id", "")).strip_edges()
	elif not args.is_empty():
		scene_id = str(args[0]).strip_edges()

	if scene_id.is_empty():
		errors.append({"line": line_num, "message": "jump_scene() requires a target scene_id"})
		return null

	var cmd := AVGCommand.new()
	cmd.command_type = "JUMP_SCENE"
	cmd.params["scene_id"] = scene_id
	if kwargs.has("transition"):
		cmd.params["transition"] = kwargs["transition"]
	if kwargs.has("duration"):
		cmd.params["duration"] = kwargs["duration"]
	if kwargs.has("color"):
		cmd.params["color"] = kwargs["color"]
	return cmd


## 解析 Choice 选项块
## @param start_idx: 当前 # => ChoiceBlock 所在行
func _parse_choice_block(lines: Array[String], start_idx: int, indent_level: int) -> Dictionary:
	var cmd: AVGCommand = AVGCommand.new()
	cmd.command_type = "CHOICE"
	cmd.params["choices"] = []
	
	var errs: Array[Dictionary] = []
	var warns: Array[Dictionary] = []
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
			current_choice_dict["condition_commands"] = []
			current_choice_dict["hidden_when_unmet"] = false
			
			if not inline_cond.is_empty():
				current_choice_dict["condition_commands"] = _parse_condition_commands(inline_cond, i + 1, errs)
				if not current_choice_dict["condition_commands"].is_empty():
					current_choice_dict["hidden_when_unmet"] = true
			
			cmd.params["choices"].append(current_choice_dict)
			
			# 其下方可能存在属于此选项的执行逻辑缩进块
			var next_ind: int = _find_next_indent(lines, i + 1)
			if next_ind > indent_level:
				var res_block: Dictionary = _parse_block(lines, i + 1, next_ind)
				current_choice_dict["commands"] = res_block.get("commands", [])
				errs.append_array(res_block.get("errors", []))
				warns.append_array(res_block.get("warnings", []))
				i = res_block.get("next_idx", i + 1)
				continue
				
		elif cur_ind == indent_level:
			# 同级但不是 '-' 开头，意味着 ChoiceBlock 结束
			break
			
		i += 1

	return {
		"command": cmd,
		"errors": errs,
		"warnings": warns,
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
		var line: String = _prepare_line_for_parse(lines[i])
		var st: String = line.strip_edges()
		if not st.is_empty() and _rx_comment.search(line) == null:
			return _get_indent_level(line)
		i += 1
	return 0


func _prepare_line_for_parse(raw_line: String) -> String:
	var embedded: String = _extract_embedded_command_from_comment(raw_line)
	if not embedded.is_empty():
		return embedded
	var stripped: String = _strip_inline_comment_suffix(raw_line)
	return stripped


func _strip_inline_comment_suffix(raw_line: String) -> String:
	var trimmed_left: String = raw_line.strip_edges(true, false)
	if trimmed_left.begins_with(">") or trimmed_left.begins_with("-") or trimmed_left.begins_with("# =>"):
		return raw_line

	var quote_char: String = ""
	var idx: int = 0
	while idx < raw_line.length():
		var ch: String = raw_line.substr(idx, 1)
		if not quote_char.is_empty():
			if ch == "\\" and idx + 1 < raw_line.length():
				idx += 1
			elif ch == quote_char:
				quote_char = ""
			idx += 1
			continue
		if ch == "\"" or ch == "'":
			quote_char = ch
			idx += 1
			continue
		if ch == "#":
			return raw_line.substr(0, idx).strip_edges(false, true)
		idx += 1
	return raw_line


func _extract_embedded_command_from_comment(raw_line: String) -> String:
	var trimmed_left: String = raw_line.strip_edges(true, false)
	if not trimmed_left.begins_with("#"):
		return ""
	# `# => TextBlock(...)` 和 `# => ChoiceBlock(...)` 是合法控制块，让上层正则处理。
	# 但 LLM 经常把 `# =>` 错误地加在 screen.fade / bg.show / stage.set / xx.expression= 这类
	# 普通命令前面，一旦不剥离前缀，整行会被兜底当成旁白。这里允许嵌入提取识别这类情况。
	if trimmed_left.begins_with("# =>"):
		var after_marker: String = trimmed_left.substr(4).strip_edges()
		if after_marker.begins_with("TextBlock(") or after_marker.begins_with("ChoiceBlock("):
			return ""

	var candidate_patterns: Array[RegEx] = [
		_rx_embedded_else_if_stmt,
		_rx_embedded_elif_stmt,
		_rx_embedded_if_stmt,
		_rx_embedded_else_stmt,
		_rx_embedded_var_op,
		_rx_embedded_prop_assign,
		_rx_embedded_method_call,
		_rx_embedded_legacy_jump_scene,
	]

	var best_start: int = -1
	for rx in candidate_patterns:
		var match: RegExMatch = rx.search(trimmed_left)
		if match == null:
			continue
		var start_idx: int = match.get_start()
		if best_start == -1 or start_idx < best_start:
			best_start = start_idx

	if best_start == -1:
		return ""

	return trimmed_left.substr(best_start).strip_edges()

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

## 解析布尔条件表达式为 condition_commands
func _parse_condition_commands(cond_str: String, line_num: int, errors: Array[Dictionary]) -> Array[AVGCommand]:
	var node: Variant = _parse_condition_expression(cond_str, line_num, errors)
	if node == null:
		return []
	return _compile_condition_node(node)


## 递归解析条件表达式，支持 and / or / 括号
func _parse_condition_expression(cond_str: String, line_num: int, errors: Array[Dictionary]) -> Variant:
	var trimmed: String = _trim_wrapping_parentheses(cond_str.strip_edges())
	if trimmed.is_empty():
		errors.append({"line": line_num, "message": "Empty condition expression"})
		return null

	var or_parts: Array[String] = _split_condition_top_level(trimmed, "or")
	if or_parts.size() > 1:
		return {
			"type": "or",
			"children": _parse_condition_expression_parts(or_parts, line_num, errors)
		}

	var and_parts: Array[String] = _split_condition_top_level(trimmed, "and")
	if and_parts.size() > 1:
		return {
			"type": "and",
			"children": _parse_condition_expression_parts(and_parts, line_num, errors)
		}

	return _parse_atomic_condition(trimmed, line_num, errors)


func _parse_condition_expression_parts(parts: Array[String], line_num: int, errors: Array[Dictionary]) -> Array:
	var result: Array = []
	for part in parts:
		var child: Variant = _parse_condition_expression(part, line_num, errors)
		if child != null:
			result.append(child)
	return result


func _compile_condition_node(node: Variant) -> Array[AVGCommand]:
	if node == null:
		return []
	if node is AVGCommand:
		return [node]
	if not (node is Dictionary):
		return []

	var node_type: String = str(node.get("type", ""))
	var children: Array = node.get("children", [])
	if children.is_empty():
		return []

	if node_type == "and":
		var combined: Array[AVGCommand] = []
		for child in children:
			combined.append_array(_compile_condition_node(child))
		return combined

	if node_type == "or":
		return [_build_or_condition(children)]

	return []


func _build_or_condition(children: Array) -> AVGCommand:
	var cond_if: AVGCommand = AVGCommand.new()
	cond_if.command_type = "IF"
	cond_if.params["condition_commands"] = _compile_condition_node(children[0])
	cond_if.params["if_condition_commands"] = []
	cond_if.params["has_else"] = true
	if children.size() == 2:
		cond_if.params["else_condition_commands"] = _compile_condition_node(children[1])
	else:
		cond_if.params["else_condition_commands"] = [_build_or_condition(children.slice(1))]
	return cond_if


## 生成对单个原子条件的解析
func _parse_atomic_condition(cond_str: String, line_num: int, errors: Array[Dictionary]) -> AVGCommand:
	var rx_cond: RegEx = RegEx.new()
	rx_cond.compile("var\\[(\\w+)\\]\\s*(==|!=|>=|<=|>|<)\\s*(.+)")
	var mat: RegExMatch = rx_cond.search(cond_str)
	if mat:
		var ref_str: String = mat.get_string(1)
		var params: Dictionary = _parse_variable_ref_token(ref_str)
		var rhs_text: String = mat.get_string(3).strip_edges()
		var rhs_var_match: RegExMatch = _match_variable_ref_expr(rhs_text)
		params["operator"] = mat.get_string(2)
		if rhs_var_match != null:
			params["value_source"] = "variable"
			params.merge(_prefix_variable_ref_fields(_parse_variable_ref_token(rhs_var_match.get_string(1)), "source_"), true)
		else:
			params["value"] = _parse_variable_literal(rhs_text)
			params["value_source"] = "constant"
		return AVGCommand.new("CHECK_VAR", params)
	errors.append({"line": line_num, "message": "Failed to parse condition: " + cond_str})
	return null


func _match_variable_ref_expr(expr: String) -> RegExMatch:
	var rx_var_ref: RegEx = RegEx.new()
	rx_var_ref.compile("^var\\[(\\w+)\\]$")
	return rx_var_ref.search(expr.strip_edges())


func _prefix_variable_ref_fields(fields: Dictionary, prefix: String) -> Dictionary:
	var result: Dictionary = {}
	for key in fields.keys():
		result["%s%s" % [prefix, str(key)]] = fields[key]
	return result


func _split_condition_top_level(cond_str: String, keyword: String) -> Array[String]:
	var parts: Array[String] = []
	var start: int = 0
	var paren_depth: int = 0
	var bracket_depth: int = 0
	var quote_char: String = ""
	var i: int = 0
	var keyword_len: int = keyword.length()

	while i < cond_str.length():
		var ch: String = cond_str.substr(i, 1)
		if not quote_char.is_empty():
			if ch == "\\" and i + 1 < cond_str.length():
				i += 2
				continue
			if ch == quote_char:
				quote_char = ""
			i += 1
			continue

		if ch == "\"" or ch == "'":
			quote_char = ch
			i += 1
			continue

		if ch == "[":
			bracket_depth += 1
			i += 1
			continue
		if ch == "]":
			bracket_depth = maxi(bracket_depth - 1, 0)
			i += 1
			continue
		if bracket_depth == 0:
			if ch == "(":
				paren_depth += 1
				i += 1
				continue
			if ch == ")":
				paren_depth = maxi(paren_depth - 1, 0)
				i += 1
				continue

		if paren_depth == 0 and bracket_depth == 0 and _matches_logic_keyword(cond_str, i, keyword):
			parts.append(cond_str.substr(start, i - start).strip_edges())
			i += keyword_len
			start = i
			continue

		i += 1

	parts.append(cond_str.substr(start).strip_edges())
	return parts


func _matches_logic_keyword(text: String, index: int, keyword: String) -> bool:
	var keyword_len: int = keyword.length()
	if index + keyword_len > text.length():
		return false
	if text.substr(index, keyword_len).to_lower() != keyword:
		return false
	var prev_char: String = text.substr(index - 1, 1) if index > 0 else ""
	var next_char: String = text.substr(index + keyword_len, 1) if index + keyword_len < text.length() else ""
	return _is_logic_boundary(prev_char) and _is_logic_boundary(next_char)


func _is_logic_boundary(ch: String) -> bool:
	return ch.is_empty() or ch == "(" or ch == ")" or ch == " " or ch == "\t"


func _trim_wrapping_parentheses(text: String) -> String:
	var trimmed: String = text.strip_edges()
	while trimmed.begins_with("(") and trimmed.ends_with(")") and _is_outer_parentheses_pair(trimmed):
		trimmed = trimmed.substr(1, trimmed.length() - 2).strip_edges()
	return trimmed


func _is_outer_parentheses_pair(text: String) -> bool:
	var paren_depth: int = 0
	var bracket_depth: int = 0
	var quote_char: String = ""
	for i in range(text.length()):
		var ch: String = text.substr(i, 1)
		if not quote_char.is_empty():
			if ch == "\\" and i + 1 < text.length():
				i += 1
				continue
			if ch == quote_char:
				quote_char = ""
			continue
		if ch == "\"" or ch == "'":
			quote_char = ch
			continue
		if ch == "[":
			bracket_depth += 1
			continue
		if ch == "]":
			bracket_depth = maxi(bracket_depth - 1, 0)
			continue
		if bracket_depth > 0:
			continue
		if ch == "(":
			paren_depth += 1
		elif ch == ")":
			paren_depth -= 1
			if paren_depth == 0 and i < text.length() - 1:
				return false
	return paren_depth == 0

func _parse_variable_ref_token(raw_ref: String) -> Dictionary:
	var ref: String = raw_ref.strip_edges()
	if ref.is_empty():
		return {}
	if ref.is_valid_int():
		return {"variable_id": "var_%03d" % int(ref)}
	if ref.begins_with("var_"):
		return {"variable_id": ref}
	return {"variable_key": ref}

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
		if obj == "cg" and not cmd.params.has("fade_duration"):
			cmd.params["fade_duration"] = 0.2
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
	if obj == "cg":
		if not cmd.params.has("fade_duration"):
			cmd.params["fade_duration"] = 0.25
		if not cmd.params.has("transition"):
			cmd.params["transition"] = "crossfade"

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


func _parse_variable_literal(raw_value: String) -> Variant:
	var trimmed: String = raw_value.strip_edges()
	if _is_wrapped_in_quotes(trimmed):
		return _strip_quotes(trimmed)
	return AVGVariableClass.normalize_script_literal(_strip_quotes(trimmed))


func _is_wrapped_in_quotes(text: String) -> bool:
	if text.length() < 2:
		return false
	return (text.begins_with("\"") and text.ends_with("\"")) or (text.begins_with("'") and text.ends_with("'"))

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
