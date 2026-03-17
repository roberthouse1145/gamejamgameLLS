class_name DSLGenerators extends RefCounted
## 随机 DSL/AVGCommand 生成器
## 用于属性测试（Property-Based Testing）
## **Validates: Requirements 7.3**

const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")

## 安全的角色名池（不含 `(`, `)`, `: `）
const SPEAKER_POOL: Array[String] = ["角色A", "角色B", "NPC_001", "旅人", "商人", "村长"]

## 表情键池
const EXPRESSION_POOL: Array[String] = ["happy", "sad", "angry", "normal", "surprised", "shy"]

## 对话文本池（不含换行符）
const TEXT_POOL: Array[String] = [
	"你好，欢迎来到这个世界",
	"今天天气真不错",
	"我有一个重要的任务要交给你",
	"这件事情非常紧急",
	"谢谢你的帮助",
	"再见，祝你旅途愉快",
	"请问你知道去城镇的路吗",
	"这是一段包含冒号的文本：测试内容",
]

## 安全的参数值池（不含 `=`, 空格, `[`, `]`, 换行）
const SAFE_STRING_POOL: Array[String] = [
	"abc", "hello", "test_val", "item_001", "res://audio/bgm.ogg",
	"res://bg/forest.png", "effect_shake", "left", "right", "center",
]

## 安全的目标 ID 池（不含 `#`, `@`, 空格, 换行）
const TARGET_ID_POOL: Array[String] = [
	"scene_001", "scene_002", "node_001", "node_002",
	"my_label", "start_label", "end_label", "loop_point",
]

## 变量 ID 池
const VARIABLE_ID_POOL: Array[String] = [
	"var_001", "var_002", "var_003", "var_100",
	"lvar_001", "lvar_002", "lvar_010",
]

## CHECK_VAR 运算符池
const OPERATOR_POOL: Array[String] = ["==", "!=", ">", "<", ">=", "<="]

## SET_VARIABLE 操作符池
const OPERATION_POOL: Array[String] = ["set", "add", "subtract", "multiply", "divide", "modulo"]

## POSITIONAL_PARAMS 映射（与 parser/serializer 保持一致）
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


## ========== Helper Methods ==========

## 从数组中随机选择一个元素
static func _pick(rng: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)]


## 从 String 数组中随机选择
static func _pick_str(rng: RandomNumberGenerator, arr: Array[String]) -> String:
	return arr[rng.randi_range(0, arr.size() - 1)]


## 生成随机安全值（int/float/bool/String，不含特殊字符）
## 注意：float 值必须有小数部分（避免 str(0.0)→"0"→int(0) 的 round-trip 问题）
static func _random_safe_value(rng: RandomNumberGenerator) -> Variant:
	var choice: int = rng.randi_range(0, 3)
	match choice:
		0:  # int
			return rng.randi_range(-100, 100)
		1:  # float（确保有小数部分，避免被 parser 推断为 int）
			var f: float = snapped(rng.randf_range(-50.0, 50.0), 0.01)
			# 确保不是整数值（如 0.0, 1.0 等会被 str() 输出为 "0", "1"）
			if f == int(f):
				f += 0.01
			return f
		2:  # bool
			return rng.randi_range(0, 1) == 1
		_:  # safe string
			return _pick_str(rng, SAFE_STRING_POOL)


## 生成随机正数值（用于 WAIT_TIME, CAMERA_ZOOM 等）
## 确保 float 有小数部分避免 round-trip 问题
static func _random_positive_value(rng: RandomNumberGenerator) -> Variant:
	var choice: int = rng.randi_range(0, 1)
	if choice == 0:
		return rng.randi_range(1, 10)
	else:
		var f: float = snapped(rng.randf_range(0.1, 5.0), 0.1)
		if f == int(f):
			f += 0.1
		return f


## 为指定位置参数名生成合适的值
static func _generate_param_value(rng: RandomNumberGenerator, param_name: String) -> Variant:
	match param_name:
		"character_id":
			return "char_%03d" % rng.randi_range(1, 20)
		"expression":
			return _pick_str(rng, EXPRESSION_POOL)
		"duration", "speed", "zoom_level":
			return _random_positive_value(rng)
		"direction":
			return _pick(rng, ["in", "out"])
		"scene_id":
			return "scene_%03d" % rng.randi_range(1, 50)
		"node_id", "image_id", "shared_node_id":
			return "node_%03d" % rng.randi_range(1, 50)
		"event_id":
			return "evt_%03d" % rng.randi_range(1, 20)
		"audio_path":
			return "res://audio/sfx_%03d.ogg" % rng.randi_range(1, 20)
		"texture_path":
			return "res://bg/bg_%03d.png" % rng.randi_range(1, 20)
		"name", "target":
			return _pick_str(rng, TARGET_ID_POOL)
		"text":
			# For SET_TEXT node text - safe string without spaces
			return _pick_str(rng, SAFE_STRING_POOL)
		_:
			return _pick_str(rng, SAFE_STRING_POOL)


## ========== Generator Methods ==========

## 生成随机 DIALOGUE 命令
## 随机选择：带表情、无表情、旁白（空 speaker）
## Text 不含换行，Speaker 不含 `(`, `)`, `: `
static func random_dialogue(rng: RandomNumberGenerator) -> AVGCommand:
	var params: Dictionary = {}
	var variant: int = rng.randi_range(0, 2)

	match variant:
		0:  # 带表情
			params["speaker"] = _pick_str(rng, SPEAKER_POOL)
			params["expression"] = _pick_str(rng, EXPRESSION_POOL)
			params["text"] = _pick_str(rng, TEXT_POOL)
		1:  # 无表情
			params["speaker"] = _pick_str(rng, SPEAKER_POOL)
			params["text"] = _pick_str(rng, TEXT_POOL)
		2:  # 旁白
			params["speaker"] = ""
			params["text"] = _pick_str(rng, TEXT_POOL)

	return AVGCommand.new("DIALOGUE", params)


## 生成随机方括号指令命令
## 从 POSITIONAL_PARAMS 中随机选择类型，生成合适的参数
## 排除跳转类型（JUMP_SCENE, JUMP_LABEL 有专用语法，由 random_jump 生成）
static func random_bracket_command(rng: RandomNumberGenerator) -> AVGCommand:
	var types: Array = POSITIONAL_PARAMS.keys()
	# 排除跳转类型（它们有专用的 -> 语法，serializer 不会用方括号格式）
	var filtered_types: Array = []
	for t in types:
		if t != "JUMP_SCENE" and t != "JUMP_LABEL":
			filtered_types.append(t)
	var cmd_type: String = _pick(rng, filtered_types)
	var positional_names: Array = POSITIONAL_PARAMS[cmd_type]
	var params: Dictionary = {}

	# 填充位置参数
	for param_name in positional_names:
		params[param_name] = _generate_param_value(rng, param_name)

	# 可选：添加 0-2 个额外 key=value 参数
	var extra_count: int = rng.randi_range(0, 2)
	for idx in range(extra_count):
		var key: String = "extra_%s" % ["alpha", "beta", "gamma"][idx]
		params[key] = _random_safe_value(rng)

	return AVGCommand.new(cmd_type, params)


## 生成随机跳转命令
## 随机选择：JUMP_SCENE, JUMP_TO_NODE, JUMP_LABEL
## Target ID 不含 `#`, `@`, 空格, 换行
static func random_jump(rng: RandomNumberGenerator) -> AVGCommand:
	var variant: int = rng.randi_range(0, 2)

	match variant:
		0:  # JUMP_SCENE
			return AVGCommand.new("JUMP_SCENE", {
				"scene_id": "scene_%03d" % rng.randi_range(1, 50)
			})
		1:  # JUMP_TO_NODE
			return AVGCommand.new("JUMP_TO_NODE", {
				"node_id": "node_%03d" % rng.randi_range(1, 50)
			})
		_:  # JUMP_LABEL
			return AVGCommand.new("JUMP_LABEL", {
				"target": _pick_str(rng, TARGET_ID_POOL)
			})


## 生成随机 SET_VARIABLE 命令（简写+高级）
## 简写：random variable_id, random operation, random value (int/float/bool/string)
## 高级：random variable_id, random value_source (variable/random/game_data)
static func random_set_variable(rng: RandomNumberGenerator) -> AVGCommand:
	var var_id: String = _pick_str(rng, VARIABLE_ID_POOL)
	var params: Dictionary = {"variable_id": var_id}
	var use_advanced: bool = rng.randi_range(0, 2) == 0  # 33% 高级语法

	if use_advanced:
		# 高级语法：value_source 非 constant
		var source_type: int = rng.randi_range(0, 2)
		match source_type:
			0:  # variable
				params["value_source"] = "variable"
				params["source_variable_id"] = _pick_str(rng, VARIABLE_ID_POOL)
			1:  # random
				params["value_source"] = "random"
				params["random_min"] = rng.randi_range(0, 10)
				params["random_max"] = rng.randi_range(50, 100)
			2:  # game_data
				params["value_source"] = "game_data"
				params["game_data_key"] = _pick(rng, ["play_time", "score", "level"])
	else:
		# 简写语法：operation + constant value
		params["operation"] = _pick_str(rng, OPERATION_POOL)
		params["value_source"] = "constant"
		# 生成安全值（不含空格、=、[]、换行）
		var val_type: int = rng.randi_range(0, 3)
		match val_type:
			0:
				params["value"] = rng.randi_range(-100, 100)
			1:
				# 确保 float 有小数部分（避免 round-trip 时被推断为 int）
				var f: float = snapped(rng.randf_range(-50.0, 50.0), 0.01)
				if f == int(f):
					f += 0.01
				params["value"] = f
			2:
				params["value"] = rng.randi_range(0, 1) == 1
			_:
				params["value"] = _pick_str(rng, SAFE_STRING_POOL)

	return AVGCommand.new("SET_VARIABLE", params)


## 生成随机条件命令（CHECK_VAR / CHECK_HOVER / CHECK_CLICK）
static func _random_condition(rng: RandomNumberGenerator) -> Dictionary:
	var cond_type: int = rng.randi_range(0, 2)
	match cond_type:
		0:  # CHECK_VAR
			return {
				"command_type": "CHECK_VAR",
				"params": {
					"variable_id": _pick_str(rng, VARIABLE_ID_POOL),
					"operator": _pick_str(rng, OPERATOR_POOL),
					"value": _random_safe_value(rng),
					"value_source": "constant",
				}
			}
		1:  # CHECK_HOVER
			return {
				"command_type": "CHECK_HOVER",
				"params": {
					"node_id": "node_%03d" % rng.randi_range(1, 50),
				}
			}
		_:  # CHECK_CLICK
			return {
				"command_type": "CHECK_CLICK",
				"params": {
					"node_id": "node_%03d" % rng.randi_range(1, 50),
				}
			}


## 生成不含 IF/CHOICE 的扁平命令（用于嵌套深度耗尽时）
static func _random_flat_command(rng: RandomNumberGenerator) -> AVGCommand:
	var choice: int = rng.randi_range(0, 3)
	match choice:
		0:
			return random_dialogue(rng)
		1:
			return random_bracket_command(rng)
		2:
			return random_jump(rng)
		_:
			return random_set_variable(rng)


## 将 AVGCommand 转为 Dictionary 格式（匹配 parser 输出）
static func _cmd_to_dict(cmd: AVGCommand) -> Dictionary:
	return {"command_type": cmd.command_type, "params": cmd.params}


## 将 AVGCommand 数组转为 Dictionary 数组
static func _cmds_to_dicts(cmds: Array[AVGCommand]) -> Array:
	var result: Array = []
	for cmd in cmds:
		result.append(_cmd_to_dict(cmd))
	return result


## 生成随机 IF 命令（可控嵌套深度）
## max_depth <= 0 时只生成扁平命令（无嵌套 IF/CHOICE）
static func random_if(rng: RandomNumberGenerator, max_depth: int = 2) -> AVGCommand:
	# 生成 1-3 个条件
	var cond_count: int = rng.randi_range(1, 3)
	var condition_commands: Array = []
	for idx in range(cond_count):
		condition_commands.append(_random_condition(rng))

	# 生成 if_commands（1-3 条）
	var if_cmd_count: int = rng.randi_range(1, 3)
	var if_commands: Array = []
	for idx in range(if_cmd_count):
		if max_depth <= 0:
			if_commands.append(_cmd_to_dict(_random_flat_command(rng)))
		else:
			if_commands.append(_cmd_to_dict(_random_nested_command(rng, max_depth - 1)))

	# 50% 概率包含 else 块
	var has_else: bool = rng.randi_range(0, 1) == 1
	var else_commands: Array = []
	if has_else:
		var else_count: int = rng.randi_range(1, 2)
		for idx in range(else_count):
			if max_depth <= 0:
				else_commands.append(_cmd_to_dict(_random_flat_command(rng)))
			else:
				else_commands.append(_cmd_to_dict(_random_nested_command(rng, max_depth - 1)))

	var params: Dictionary = {
		"condition_commands": condition_commands,
		"if_commands": if_commands,
		"has_else": has_else,
		"else_commands": else_commands,
	}
	return AVGCommand.new("IF", params)


## 生成随机 CHOICE 命令（可控嵌套深度）
## max_depth <= 0 时只生成扁平子命令
static func random_choice(rng: RandomNumberGenerator, max_depth: int = 2) -> AVGCommand:
	var choice_count: int = rng.randi_range(2, 4)
	var choices: Array = []

	for idx in range(choice_count):
		var choice_dict: Dictionary = {}
		choice_dict["text"] = _pick_str(rng, TEXT_POOL)

		# 30% 概率有条件
		var has_condition: bool = rng.randi_range(0, 9) < 3
		if has_condition:
			choice_dict["condition_commands"] = [_random_condition(rng)]
			# 20% 概率 HIDDEN（仅在有条件时）
			choice_dict["hidden_when_unmet"] = rng.randi_range(0, 4) == 0
		else:
			choice_dict["condition_commands"] = []
			choice_dict["hidden_when_unmet"] = false

		# 0-3 个子命令
		var sub_count: int = rng.randi_range(0, 3)
		var sub_commands: Array = []
		for sub_idx in range(sub_count):
			if max_depth <= 0:
				sub_commands.append(_cmd_to_dict(_random_flat_command(rng)))
			else:
				sub_commands.append(_cmd_to_dict(_random_nested_command(rng, max_depth - 1)))
		choice_dict["commands"] = sub_commands

		choices.append(choice_dict)

	return AVGCommand.new("CHOICE", {"choices": choices})


## 生成可能包含嵌套的随机命令（内部辅助）
static func _random_nested_command(rng: RandomNumberGenerator, max_depth: int) -> AVGCommand:
	# 加权随机：大部分是扁平命令，少量嵌套
	var roll: int = rng.randi_range(0, 9)
	if roll < 5:
		return random_dialogue(rng)
	elif roll < 7:
		return random_bracket_command(rng)
	elif roll < 8:
		return random_jump(rng)
	elif roll < 9:
		return random_set_variable(rng)
	else:
		# 嵌套命令（仅在 depth > 0 时）
		if max_depth > 0:
			if rng.randi_range(0, 1) == 0:
				return random_if(rng, max_depth - 1)
			else:
				return random_choice(rng, max_depth - 1)
		else:
			return _random_flat_command(rng)


## 生成随机命令数组（混合所有类型）
## 加权随机：dialogue 40%, bracket 25%, jump 10%, set_variable 10%, if 10%, choice 5%
static func random_command_array(rng: RandomNumberGenerator, min_size: int = 1, max_size: int = 20) -> Array[AVGCommand]:
	var size: int = rng.randi_range(min_size, max_size)
	var commands: Array[AVGCommand] = []

	for idx in range(size):
		var roll: int = rng.randi_range(0, 99)
		if roll < 40:
			commands.append(random_dialogue(rng))
		elif roll < 65:
			commands.append(random_bracket_command(rng))
		elif roll < 75:
			commands.append(random_jump(rng))
		elif roll < 85:
			commands.append(random_set_variable(rng))
		elif roll < 95:
			commands.append(random_if(rng, 1))
		else:
			commands.append(random_choice(rng, 1))

	return commands


## 生成随机非法 DSL 文本（用于错误检测测试）
## 包含：未闭合 IF/CHOICE、未知指令、缺失值、垃圾行
static func random_invalid_dsl(rng: RandomNumberGenerator) -> String:
	var error_type: int = rng.randi_range(0, 4)
	var lines: Array[String] = []

	match error_type:
		0:  # 未闭合 IF 块
			lines.append("[IF var_001 == 1]")
			lines.append("  角色A: 没有END的对话")
			# 故意不加 [END]
		1:  # 未闭合 CHOICE 块
			lines.append("[CHOICE]")
			lines.append("  - 选项A")
			lines.append("  - 选项B")
			# 故意不加 [END]
		2:  # 未知指令类型
			var fake_cmds: Array[String] = [
				"UNKNOWN_CMD", "FAKE_ACTION", "DO_SOMETHING",
				"INVALID_TYPE", "BAD_COMMAND",
			]
			lines.append("[%s param1 param2]" % _pick_str(rng, fake_cmds))
		3:  # SET_VARIABLE 缺失值
			var ops: Array[String] = ["=", "+=", "-="]
			lines.append("[SET_VARIABLE var_001 %s ]" % _pick_str(rng, ops))
		4:  # 随机垃圾行
			var garbage: Array[String] = [
				"这不是任何合法格式",
				"!!!随机垃圾!!!",
				"没有冒号空格的行",
				"@#$%^&*()",
			]
			lines.append(_pick_str(rng, garbage))

	return "\n".join(lines)
