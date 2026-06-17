extends Node

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
const SerializerClass = preload("res://scripts/avg/dsl/avg_dsl_serializer.gd")

var _parser: RefCounted
var _serializer: RefCounted
var _all_passed: bool = true


func _ready() -> void:
	_parser = ParserClass.new()
	_serializer = SerializerClass.new()
	print("========== AVG DSL V2 Parser Tests ==========")
	_test_if_condition_commands()
	_test_if_condition_key_commands()
	_test_if_condition_variable_to_variable_commands()
	_test_if_condition_and_commands()
	_test_if_condition_or_commands()
	_test_variable_literal_normalization()
	_test_if_else_branch_shape()
	_test_parser_rejects_elif()
	_test_parser_rejects_else_if()
	_test_parser_rejects_orphan_else_after_elif()
	_test_parser_accepts_trailing_inline_comment_on_command()
	_test_parser_accepts_embedded_command_after_comment_prefix()
	_test_parser_strips_misapplied_arrow_prefix_on_command()
	_test_choice_inline_condition()
	_test_choice_inline_compound_condition()
	_test_serializer_compound_if()
	_test_serializer_compound_choice()
	_test_serializer_variable_to_variable_condition()
	_test_serializer_dialogue_round_trip()
	_test_serializer_choice_round_trip()
	_test_serializer_stage_round_trip()
	_test_serializer_variable_lookup()
	_test_serializer_string_variable_round_trip()
	_test_parser_character_methods_with_cjk_name()
	_test_parser_legacy_jump_scene()
	_test_parser_wait_click()
	_test_serializer_runtime_calls_round_trip()
	print("========== Tests Complete ==========")
	if _all_passed:
		print("PASS")
	else:
		print("FAIL")


func _test_if_condition_commands() -> void:
	var dsl: String = "if var[1] == 3:\n    > 命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "if parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "if command count")
	if commands.is_empty():
		return
	var if_cmd: AVGCommand = commands[0]
	_assert_eq(if_cmd.command_type, "IF", "if command type")
	_assert_eq(if_cmd.params.get("has_else", false), false, "if has_else default")
	var condition_commands: Array = if_cmd.params.get("condition_commands", [])
	_assert_eq(condition_commands.size(), 1, "if condition command count")
	if condition_commands.is_empty():
		return
	var cond: AVGCommand = condition_commands[0]
	_assert_eq(cond.command_type, "CHECK_VAR", "if condition type")
	_assert_eq(cond.params.get("variable_id", ""), "var_001", "if variable id")
	_assert_eq(cond.params.get("operator", ""), "==", "if operator")
	_assert_eq(cond.params.get("value"), 3, "if value")
	_assert_eq(cond.params.get("value_source", ""), "constant", "if value source")


func _test_if_else_branch_shape() -> void:
	var dsl: String = "if var[2] >= 5:\n    > 满足\nelse:\n    > 不满足"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "if else parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "if else command count")
	if commands.is_empty():
		return
	var if_cmd: AVGCommand = commands[0]
	_assert_eq(if_cmd.params.get("has_else", false), true, "if else has_else")
	_assert_eq((if_cmd.params.get("if_commands", []) as Array).size(), 1, "if branch count")
	_assert_eq((if_cmd.params.get("else_commands", []) as Array).size(), 1, "else branch count")


func _test_parser_rejects_elif() -> void:
	var dsl: String = "if var[akari_choice] >= 4:\n    > 命中\nelif var[rin_choice] >= 4:\n    > 次命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(not result.get("success", true), "parser rejects elif")
	var errors: Array = result.get("errors", [])
	var found_elif_error: bool = false
	for err in errors:
		if str(err.get("message", "")).contains("Unsupported control flow: elif"):
			found_elif_error = true
			break
	_assert_true(found_elif_error, "parser reports elif unsupported")
	var commands: Array = result.get("commands", [])
	if commands.is_empty():
		return
	var serialized: String = _serializer.serialize(commands)
	_assert_true(not serialized.contains("elif"), "parser does not keep elif as narration")


func _test_parser_rejects_else_if() -> void:
	var dsl: String = "if var[akari_choice] >= 4:\n    > 命中\nelse if var[rin_choice] >= 4:\n    > 次命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(not result.get("success", true), "parser rejects else if")
	var errors: Array = result.get("errors", [])
	var found_else_if_error: bool = false
	for err in errors:
		if str(err.get("message", "")).contains("Unsupported control flow: else if"):
			found_else_if_error = true
			break
	_assert_true(found_else_if_error, "parser reports else if unsupported")
	var commands: Array = result.get("commands", [])
	if commands.is_empty():
		return
	var serialized: String = _serializer.serialize(commands)
	_assert_true(not serialized.contains("else if"), "parser does not keep else if as narration")


func _test_parser_rejects_orphan_else_after_elif() -> void:
	var dsl: String = "if var[akari_choice] >= 4:\n    > 命中\nelif var[rin_choice] >= 4:\n    > 次命中\nelse:\n    > 未命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(not result.get("success", true), "parser rejects orphan else after elif")
	var errors: Array = result.get("errors", [])
	var found_else_error: bool = false
	for err in errors:
		if str(err.get("message", "")).contains("Unexpected else without matching if"):
			found_else_error = true
			break
	_assert_true(found_else_error, "parser reports orphan else instead of narration fallback")
	var commands: Array = result.get("commands", [])
	for cmd in commands:
		if cmd is AVGCommand and (cmd as AVGCommand).command_type == "DIALOGUE":
			_assert_true(str((cmd as AVGCommand).params.get("text", "")) != "else:", "parser does not keep orphan else as dialogue")


func _test_parser_accepts_trailing_inline_comment_on_command() -> void:
	var dsl: String = "bg.show(\"bg_classroom\") # 切换到教室"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "parser accepts trailing inline comment")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "trailing inline comment command count")
	if commands.is_empty():
		return
	var cmd: AVGCommand = commands[0]
	_assert_eq(cmd.command_type, "CHANGE_BACKGROUND", "trailing inline comment command type")
	_assert_eq(cmd.params.get("texture_path", ""), "bg_classroom", "trailing inline comment texture path")


func _test_parser_accepts_embedded_command_after_comment_prefix() -> void:
	var dsl: String = "# 切换背景 bg.show(\"bg_library\")"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "parser accepts embedded command after comment prefix")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "embedded command count")
	if commands.is_empty():
		return
	var cmd: AVGCommand = commands[0]
	_assert_eq(cmd.command_type, "CHANGE_BACKGROUND", "embedded command type")
	_assert_eq(cmd.params.get("texture_path", ""), "bg_library", "embedded command texture path")


## LLM 经常把 `# =>` 错误地加在 screen.fade / bg.show / stage.set / xx.expression= 等
## 普通命令前面，导致整行被兜底成旁白。parser 必须把这种前缀剥掉，让命令正确解析。
## 同时合法的 `# => TextBlock(...)` / `# => ChoiceBlock(...)` 必须照常工作。
func _test_parser_strips_misapplied_arrow_prefix_on_command() -> void:
	var dsl: String = "# => screen.fade(direction=\"out\", duration=0.3)\n" \
		+ "# => bg.show(\"bg_apartment_living\", fade_duration=0.4)\n" \
		+ "# => bgm.play(\"bgm_happy_end\")\n" \
		+ "# => stage.set(\"LinXia\", emotions=\"happy\", outfits=\"loungewear\")\n" \
		+ "# => LinXia.expression = \"happy\"\n" \
		+ "# => TextBlock()\n" \
		+ "> 客厅的窗帘半拉着。"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "parser accepts misapplied # => prefix on commands")
	var commands: Array = result.get("commands", [])
	# 5 条命令 + 1 条旁白 = 6
	_assert_eq(commands.size(), 6, "misapplied arrow prefix command count")
	if commands.size() < 6:
		return
	_assert_eq((commands[0] as AVGCommand).command_type, "SCREEN_FADE", "fade survived # => strip")
	_assert_eq((commands[1] as AVGCommand).command_type, "CHANGE_BACKGROUND", "bg.show survived # => strip")
	_assert_eq((commands[2] as AVGCommand).command_type, "PLAY_BGM", "bgm.play survived # => strip")
	# stage.set 的 command_type 由 _build_method_command 决定，这里只验证不再是兜底的 DIALOGUE
	_assert_true((commands[3] as AVGCommand).command_type != "DIALOGUE", "stage.set not dropped to narration")
	_assert_true((commands[4] as AVGCommand).command_type != "DIALOGUE", "prop assign not dropped to narration")
	var narration_cmd: AVGCommand = commands[5]
	_assert_eq(narration_cmd.command_type, "DIALOGUE", "narration after legit TextBlock")
	_assert_eq(str(narration_cmd.params.get("text", "")), "客厅的窗帘半拉着。", "narration text preserved")


func _test_if_condition_key_commands() -> void:
	var dsl: String = "if var[linxia_affection] >= 3:\n    > 命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "if key parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "if key command count")
	if commands.is_empty():
		return
	var if_cmd: AVGCommand = commands[0]
	var condition_commands: Array = if_cmd.params.get("condition_commands", [])
	_assert_eq(condition_commands.size(), 1, "if key condition command count")
	if condition_commands.is_empty():
		return
	var cond: AVGCommand = condition_commands[0]
	_assert_eq(cond.params.get("variable_key", ""), "linxia_affection", "if key variable key")
	_assert_eq(cond.params.get("operator", ""), ">=", "if key operator")
	_assert_eq(cond.params.get("value"), 3, "if key value")


func _test_if_condition_variable_to_variable_commands() -> void:
	var dsl: String = "if var[linxia_choice] > var[sujing_choice]:\n    > 命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "if var-to-var parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "if var-to-var command count")
	if commands.is_empty():
		return
	var if_cmd: AVGCommand = commands[0]
	var condition_commands: Array = if_cmd.params.get("condition_commands", [])
	_assert_eq(condition_commands.size(), 1, "if var-to-var condition command count")
	if condition_commands.is_empty():
		return
	var cond: AVGCommand = condition_commands[0]
	_assert_eq(cond.params.get("variable_key", ""), "linxia_choice", "if var-to-var lhs key")
	_assert_eq(cond.params.get("operator", ""), ">", "if var-to-var operator")
	_assert_eq(cond.params.get("value_source", ""), "variable", "if var-to-var value source")
	_assert_eq(cond.params.get("source_variable_key", ""), "sujing_choice", "if var-to-var rhs key")


func _test_if_condition_and_commands() -> void:
	var dsl: String = "if var[linxia_affection] >= 3 and var[player_confidence] >= 5:\n    > 命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "if and parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "if and command count")
	if commands.is_empty():
		return
	var if_cmd: AVGCommand = commands[0]
	var condition_commands: Array = if_cmd.params.get("condition_commands", [])
	_assert_eq(condition_commands.size(), 2, "if and condition count")
	if condition_commands.size() < 2:
		return
	var cond_a: AVGCommand = condition_commands[0]
	var cond_b: AVGCommand = condition_commands[1]
	_assert_eq(cond_a.command_type, "CHECK_VAR", "if and first condition type")
	_assert_eq(cond_b.command_type, "CHECK_VAR", "if and second condition type")
	_assert_eq(cond_a.params.get("variable_key", ""), "linxia_affection", "if and first key")
	_assert_eq(cond_b.params.get("variable_key", ""), "player_confidence", "if and second key")


func _test_if_condition_or_commands() -> void:
	var dsl: String = "if var[linxia_affection] >= 3 or (var[player_confidence] >= 5 and var[rain_route_unlocked] == true):\n    > 命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "if or parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "if or command count")
	if commands.is_empty():
		return
	var if_cmd: AVGCommand = commands[0]
	var condition_commands: Array = if_cmd.params.get("condition_commands", [])
	_assert_eq(condition_commands.size(), 1, "if or top-level condition count")
	if condition_commands.is_empty():
		return
	var or_cond: AVGCommand = condition_commands[0]
	_assert_eq(or_cond.command_type, "IF", "if or nested command type")
	_assert_eq(or_cond.params.get("has_else", false), true, "if or has_else")
	_assert_eq((or_cond.params.get("condition_commands", []) as Array).size(), 1, "if or left branch count")
	_assert_eq((or_cond.params.get("else_condition_commands", []) as Array).size(), 2, "if or right branch count")


func _test_variable_literal_normalization() -> void:
	var dsl: String = "var[bool_flag] = true\nvar[score] = 1.8\nif var[bool_flag] == true:\n    > 命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "variable literal normalization parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 3, "variable literal normalization command count")
	if commands.size() < 3:
		return
	_assert_eq((commands[0] as AVGCommand).params.get("value", null), 1, "bool literal coerces to 1")
	_assert_eq((commands[1] as AVGCommand).params.get("value", null), 1, "float literal coerces to int")
	var if_cmd: AVGCommand = commands[2]
	var condition_commands: Array = if_cmd.params.get("condition_commands", [])
	if condition_commands.is_empty():
		return
	_assert_eq((condition_commands[0] as AVGCommand).params.get("value", null), 1, "bool condition literal coerces to 1")


func _test_choice_inline_condition() -> void:
	var dsl: String = "# => ChoiceBlock()\n- 普通选项\n    > 正常\n- 条件选项 [if var[5] > 1]\n    > 条件分支"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "choice parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "choice command count")
	if commands.is_empty():
		return
	var choice_cmd: AVGCommand = commands[0]
	_assert_eq(choice_cmd.command_type, "CHOICE", "choice command type")
	var choices: Array = choice_cmd.params.get("choices", [])
	_assert_eq(choices.size(), 2, "choice option count")
	if choices.size() < 2:
		return
	var conditional_choice: Dictionary = choices[1]
	_assert_eq(conditional_choice.get("hidden_when_unmet", false), true, "choice hidden_when_unmet")
	var condition_commands: Array = conditional_choice.get("condition_commands", [])
	_assert_eq(condition_commands.size(), 1, "choice condition count")
	if condition_commands.is_empty():
		return
	var cond: AVGCommand = condition_commands[0]
	_assert_eq(cond.command_type, "CHECK_VAR", "choice condition type")
	_assert_eq(cond.params.get("variable_id", ""), "var_005", "choice variable id")
	_assert_eq(cond.params.get("operator", ""), ">", "choice operator")
	_assert_eq(cond.params.get("value"), 1, "choice value")


func _test_choice_inline_compound_condition() -> void:
	var dsl: String = "# => ChoiceBlock()\n- 复合条件 [if var[linxia_affection] >= 3 and (var[player_confidence] >= 5 or var[rain_route_unlocked] == 1)]\n    > 条件分支"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "choice compound parse success")
	var commands: Array = result.get("commands", [])
	if commands.is_empty():
		return
	var choice_cmd: AVGCommand = commands[0]
	var choices: Array = choice_cmd.params.get("choices", [])
	if choices.is_empty():
		return
	var conditional_choice: Dictionary = choices[0]
	var condition_commands: Array = conditional_choice.get("condition_commands", [])
	_assert_eq(condition_commands.size(), 2, "choice compound top-level condition count")


func _test_serializer_compound_if() -> void:
	var dsl: String = "if var[linxia_affection] >= 3 and (var[player_confidence] >= 5 or var[rain_route_unlocked] == true):\n    > 命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "serializer if parse success")
	var serialized: String = _serializer.serialize(result.get("commands", []))
	_assert_contains(serialized, "if var[linxia_affection] >= 3 and (var[player_confidence] >= 5 or var[rain_route_unlocked] == 1):", "serializer if compound output")


func _test_serializer_compound_choice() -> void:
	var dsl: String = "# => ChoiceBlock()\n- 复合条件 [if var[linxia_affection] >= 3 and (var[player_confidence] >= 5 or var[rain_route_unlocked] == true)]\n    > 条件分支"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "serializer choice parse success")
	var serialized: String = _serializer.serialize(result.get("commands", []))
	_assert_contains(serialized, "[if var[linxia_affection] >= 3 and (var[player_confidence] >= 5 or var[rain_route_unlocked] == 1)]", "serializer choice compound output")


func _test_serializer_dialogue_round_trip() -> void:
	var dsl: String = "# => TextBlock(speaker=\"LinXia\", expression=\"happy\")\n> 你好"
	var initial: Dictionary = _parser.parse(dsl)
	_assert_true(initial.get("success", false), "serializer dialogue initial parse")
	var serialized: String = _serializer.serialize(initial.get("commands", []))
	_assert_contains(serialized, "# => TextBlock(speaker=\"LinXia\", expression=\"happy\")", "serializer dialogue textblock output")
	_assert_contains(serialized, "> 你好", "serializer dialogue text output")
	var round_trip: Dictionary = _parser.parse(serialized)
	_assert_true(round_trip.get("success", false), "serializer dialogue round trip parse")
	var commands: Array = round_trip.get("commands", [])
	_assert_eq(commands.size(), 1, "serializer dialogue round trip count")
	if commands.is_empty():
		return
	var dialogue_cmd: AVGCommand = commands[0]
	_assert_eq(dialogue_cmd.params.get("speaker", ""), "LinXia", "serializer dialogue speaker")
	_assert_eq(dialogue_cmd.params.get("emotion", ""), "happy", "serializer dialogue emotion")
	_assert_eq(dialogue_cmd.params.get("text", ""), "你好", "serializer dialogue text")


func _test_serializer_choice_round_trip() -> void:
	var dsl: String = "# => ChoiceBlock()\n- 普通选项\n    > 正常\n- 条件选项 [if var[linxia_affection] > 1]\n    > 条件分支"
	var initial: Dictionary = _parser.parse(dsl)
	_assert_true(initial.get("success", false), "serializer choice initial parse")
	var serialized: String = _serializer.serialize(initial.get("commands", []))
	_assert_contains(serialized, "# => ChoiceBlock()", "serializer choice block output")
	_assert_contains(serialized, "- 条件选项 [if var[linxia_affection] > 1]", "serializer choice inline condition output")
	var round_trip: Dictionary = _parser.parse(serialized)
	_assert_true(round_trip.get("success", false), "serializer choice round trip parse")
	var commands: Array = round_trip.get("commands", [])
	_assert_eq(commands.size(), 1, "serializer choice round trip count")
	if commands.is_empty():
		return
	var choice_cmd: AVGCommand = commands[0]
	var choices: Array = choice_cmd.params.get("choices", [])
	_assert_eq(choices.size(), 2, "serializer choice round trip option count")
	if choices.size() < 2:
		return
	var conditional_choice: Dictionary = choices[1]
	_assert_eq(conditional_choice.get("hidden_when_unmet", false), true, "serializer choice round trip hidden")
	_assert_eq((conditional_choice.get("condition_commands", []) as Array).size(), 1, "serializer choice round trip condition count")


func _test_serializer_variable_to_variable_condition() -> void:
	var dsl: String = "if var[linxia_choice] > var[sujing_choice]:\n    > 命中"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "serializer var-to-var parse success")
	var serialized: String = _serializer.serialize(result.get("commands", []))
	_assert_contains(serialized, "if var[linxia_choice] > var[sujing_choice]:", "serializer var-to-var output")
	var round_trip: Dictionary = _parser.parse(serialized)
	_assert_true(round_trip.get("success", false), "serializer var-to-var round trip parse")


func _test_serializer_stage_round_trip() -> void:
	var dsl: String = "stage.set(\"LinXia\", \"Shopkeeper\", emotions=\"happy,neutral\")\n" + \
		"stage.enter(\"Professor\", emotions=\"serious\")\n" + \
		"stage.exit(\"Shopkeeper\")\n" + \
		"stage.clear()"
	var initial: Dictionary = _parser.parse(dsl)
	_assert_true(initial.get("success", false), "serializer stage initial parse")
	var serialized: String = _serializer.serialize(initial.get("commands", []))
	_assert_contains(serialized, "stage.set(\"LinXia\", \"Shopkeeper\", emotions=\"happy,neutral\")", "serializer stage set output")
	_assert_contains(serialized, "stage.enter(\"Professor\", emotions=\"serious\")", "serializer stage enter output")
	_assert_contains(serialized, "stage.exit(\"Shopkeeper\")", "serializer stage exit output")
	_assert_contains(serialized, "stage.clear()", "serializer stage clear output")
	var round_trip: Dictionary = _parser.parse(serialized)
	_assert_true(round_trip.get("success", false), "serializer stage round trip parse")
	var commands: Array = round_trip.get("commands", [])
	_assert_eq(commands.size(), 4, "serializer stage round trip count")
	if commands.size() < 4:
		return
	_assert_eq((commands[0] as AVGCommand).command_type, "STAGE_SET", "serializer stage set type")
	_assert_eq((commands[1] as AVGCommand).command_type, "STAGE_ENTER", "serializer stage enter type")
	_assert_eq((commands[2] as AVGCommand).command_type, "STAGE_EXIT", "serializer stage exit type")
	_assert_eq((commands[3] as AVGCommand).command_type, "STAGE_SET", "serializer stage clear type")
	_assert_eq(((commands[3] as AVGCommand).params.get("characters", []) as Array).size(), 0, "serializer stage clear empty characters")


func _test_serializer_variable_lookup() -> void:
	var commands: Array = [
		AVGCommand.new("SET_VARIABLE", {
			"variable_id": "var_001",
			"operation": "add",
			"value_source": "constant",
			"value": 2,
		}),
		AVGCommand.new("IF", {
			"condition_commands": [
				AVGCommand.new("CHECK_VAR", {
					"variable_id": "var_001",
					"operator": ">=",
					"value_source": "constant",
					"value": 3,
				})
			],
			"if_commands": [AVGCommand.new("DIALOGUE", {"text": "命中"})],
			"else_commands": [],
			"has_else": false,
		})
	]
	var serialized: String = _serializer.serialize(commands, 0, {"var_001": "linxia_affection"})
	_assert_contains(serialized, "var[linxia_affection] += 2", "serializer variable lookup set")
	_assert_contains(serialized, "if var[linxia_affection] >= 3:", "serializer variable lookup if")


func _test_serializer_string_variable_round_trip() -> void:
	var dsl: String = "var[ending_flag] = \"route_a\"\nif var[ending_flag] == \"route_a\":\n    > 命中"
	var initial: Dictionary = _parser.parse(dsl)
	_assert_true(initial.get("success", false), "serializer string variable initial parse")
	var serialized: String = _serializer.serialize(initial.get("commands", []))
	_assert_contains(serialized, "var[ending_flag] = route_a", "serializer string variable set output")
	_assert_contains(serialized, "if var[ending_flag] == route_a:", "serializer string variable condition output")
	var round_trip: Dictionary = _parser.parse(serialized)
	_assert_true(round_trip.get("success", false), "serializer string variable round trip parse")
	var commands: Array = round_trip.get("commands", [])
	if commands.size() < 2:
		return
	_assert_eq((commands[0] as AVGCommand).params.get("value", null), "route_a", "serializer string variable value preserved")
	var condition_commands: Array = (commands[1] as AVGCommand).params.get("condition_commands", [])
	if condition_commands.is_empty():
		return
	_assert_eq((condition_commands[0] as AVGCommand).params.get("value", null), "route_a", "serializer string variable condition preserved")


func _test_parser_character_methods_with_cjk_name() -> void:
	var dsl: String = "林晓月.show(position=\"center\", outfit=\"cos\", emotion=\"serious\", enter_effect=\"fade\")"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "parser cjk character method parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "parser cjk character method command count")
	if commands.is_empty():
		return
	var cmd: AVGCommand = commands[0]
	_assert_eq(cmd.command_type, "SHOW_CHARACTER", "parser cjk character method type")
	_assert_eq(cmd.params.get("character_id", ""), "林晓月", "parser cjk character method object name")
	_assert_eq(cmd.params.get("position", ""), "center", "parser cjk character method position")
	_assert_eq(cmd.params.get("outfit", ""), "cos", "parser cjk character method outfit")
	_assert_eq(cmd.params.get("emotion", ""), "serious", "parser cjk character method emotion")
	_assert_eq(cmd.params.get("enter_effect", ""), "fade", "parser cjk character method enter effect")


func _test_parser_wait_click() -> void:
	var dsl: String = "wait.click()"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "parser wait click parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "parser wait click command count")
	if commands.is_empty():
		return
	var cmd: AVGCommand = commands[0]
	_assert_eq(cmd.command_type, "WAIT_CLICK", "parser wait click type")


func _test_parser_legacy_jump_scene() -> void:
	var dsl: String = "jump_scene(\"scene_03_first_meet_suyuqing_day3\")"
	var result: Dictionary = _parser.parse(dsl)
	_assert_true(result.get("success", false), "parser legacy jump_scene parse success")
	var commands: Array = result.get("commands", [])
	_assert_eq(commands.size(), 1, "parser legacy jump_scene command count")
	if commands.is_empty():
		return
	var cmd: AVGCommand = commands[0]
	_assert_eq(cmd.command_type, "JUMP_SCENE", "parser legacy jump_scene type")
	_assert_eq(cmd.params.get("scene_id", ""), "scene_03_first_meet_suyuqing_day3", "parser legacy jump_scene target")


func _test_serializer_runtime_calls_round_trip() -> void:
	var commands: Array = [
		AVGCommand.new("FLIP_CHARACTER", {"character_id": "林晓月"}),
		AVGCommand.new("WAIT_CLICK", {}),
		AVGCommand.new("CAMERA_RESET", {"duration": 0.4}),
	]
	var serialized: String = _serializer.serialize(commands)
	_assert_contains(serialized, "林晓月.flip()", "serializer flip output")
	_assert_contains(serialized, "wait.click()", "serializer wait click output")
	_assert_contains(serialized, "camera.reset(duration=0.4)", "serializer camera reset output")
	var round_trip: Dictionary = _parser.parse(serialized)
	_assert_true(round_trip.get("success", false), "serializer runtime calls round trip parse")
	var round_trip_commands: Array = round_trip.get("commands", [])
	_assert_eq(round_trip_commands.size(), 3, "serializer runtime calls round trip count")
	if round_trip_commands.size() < 3:
		return
	_assert_eq((round_trip_commands[0] as AVGCommand).command_type, "FLIP_CHARACTER", "serializer flip round trip type")
	_assert_eq((round_trip_commands[1] as AVGCommand).command_type, "WAIT_CLICK", "serializer wait click round trip type")
	_assert_eq((round_trip_commands[2] as AVGCommand).command_type, "CAMERA_RESET", "serializer camera reset round trip type")
	_assert_eq((round_trip_commands[2] as AVGCommand).params.get("duration", 0.0), 0.4, "serializer camera reset round trip duration")


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("  PASS " + label)
		return
	_all_passed = false
	push_error("FAIL " + label)


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		print("  PASS " + label)
		return
	_all_passed = false
	push_error("FAIL %s actual=%s expected=%s" % [label, str(actual), str(expected)])


func _assert_contains(actual: String, expected_substring: String, label: String) -> void:
	if actual.contains(expected_substring):
		print("  PASS " + label)
		return
	_all_passed = false
	push_error("FAIL %s actual=%s expected_substring=%s" % [label, actual, expected_substring])
