extends Node
## Unit tests for AVGDSLParser - Tasks 1.2 & 1.3
## **Validates: Requirements 2.5, 2.6, 2.7, 4.1, 4.2, 4.3, 4.4, 4.5, 5.1, 5.2, 5.3, 5.4, 5.5**

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser.gd")

var _parser: RefCounted
var _all_passed: bool = true


func _ready() -> void:
	_parser = ParserClass.new()
	print("========== AVG DSL Parser: SET_VARIABLE & CHECK_VAR Tests ==========")
	print("")

	# SET_VARIABLE shorthand tests
	_test_set_variable_set()
	_test_set_variable_add()
	_test_set_variable_subtract()
	_test_set_variable_multiply()
	_test_set_variable_divide()
	_test_set_variable_modulo()
	_test_set_variable_string_value()
	_test_set_variable_float_value()
	_test_set_variable_bool_value()

	# SET_VARIABLE advanced syntax tests
	_test_set_variable_advanced_variable_source()
	_test_set_variable_advanced_random()
	_test_set_variable_advanced_game_data()

	# CHECK_VAR shorthand tests
	_test_check_var_equal()
	_test_check_var_greater_equal()
	_test_check_var_not_equal()
	_test_check_var_less_than()
	_test_check_var_string_value()

	# Edge cases
	_test_set_variable_no_params()
	_test_set_variable_only_var_id()
	_test_check_var_insufficient_tokens()

	print("")
	print("========== AVG DSL Parser: IF & CHOICE Block Tests ==========")
	print("")

	# IF block tests (Requirements 4.1-4.5)
	_test_simple_if_no_else()
	_test_simple_if_with_else()
	_test_multi_condition_if()
	_test_multi_condition_if_with_else()
	_test_if_with_check_hover()
	_test_if_with_check_click()

	# CHOICE block tests (Requirements 5.1-5.5)
	_test_simple_choice()
	_test_choice_with_condition()
	_test_choice_with_hidden()
	_test_choice_with_commands()

	# Nesting tests (Requirements 4.5, 5.5)
	_test_if_nested_in_if()
	_test_choice_nested_in_if()
	_test_if_nested_in_choice()
	_test_deep_nesting()

	# Error cases
	_test_unclosed_if()
	_test_unclosed_choice()

	print("")
	print("========== AVG DSL Parser: Error Handling Tests (Task 1.4) ==========")
	print("")

	# Unknown command type (Req 6.5)
	_test_unknown_command_type()
	_test_unknown_command_type_in_block()

	# Unclosed block with line number (Req 11.1)
	_test_unclosed_if_line_number()
	_test_unclosed_choice_line_number()
	_test_unclosed_if_with_else_no_end()

	# Invalid variable value (Req 11.3)
	_test_set_variable_missing_value()
	_test_set_variable_missing_value_add()

	# Multiple errors in one parse
	_test_multiple_errors()

	print("")
	if _all_passed:
		print("✅ ALL TESTS PASSED")
	else:
		print("❌ SOME TESTS FAILED")
	print("========== Tests Complete ==========")


## --- SET_VARIABLE Shorthand Tests ---

func _test_set_variable_set() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 = 5]")
	_assert_success(result, "set_variable_set")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.command_type, "SET_VARIABLE", "set_variable_set: command_type")
	_assert_eq(cmd.params.get("variable_id"), "var_001", "set_variable_set: variable_id")
	_assert_eq(cmd.params.get("operation"), "set", "set_variable_set: operation")
	_assert_eq(cmd.params.get("value_source"), "constant", "set_variable_set: value_source")
	_assert_eq(cmd.params.get("value"), 5, "set_variable_set: value")


func _test_set_variable_add() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 += 1]")
	_assert_success(result, "set_variable_add")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("operation"), "add", "set_variable_add: operation")
	_assert_eq(cmd.params.get("value"), 1, "set_variable_add: value")


func _test_set_variable_subtract() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 -= 3]")
	_assert_success(result, "set_variable_subtract")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("operation"), "subtract", "set_variable_subtract: operation")
	_assert_eq(cmd.params.get("value"), 3, "set_variable_subtract: value")


func _test_set_variable_multiply() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 *= 2]")
	_assert_success(result, "set_variable_multiply")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("operation"), "multiply", "set_variable_multiply: operation")
	_assert_eq(cmd.params.get("value"), 2, "set_variable_multiply: value")


func _test_set_variable_divide() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 /= 4]")
	_assert_success(result, "set_variable_divide")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("operation"), "divide", "set_variable_divide: operation")
	_assert_eq(cmd.params.get("value"), 4, "set_variable_divide: value")


func _test_set_variable_modulo() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 %= 3]")
	_assert_success(result, "set_variable_modulo")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("operation"), "modulo", "set_variable_modulo: operation")
	_assert_eq(cmd.params.get("value"), 3, "set_variable_modulo: value")


func _test_set_variable_string_value() -> void:
	var result: Dictionary = _parser.parse('[SET_VARIABLE lvar_001 = "hello"]')
	_assert_success(result, "set_variable_string")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("variable_id"), "lvar_001", "set_variable_string: variable_id")
	_assert_eq(cmd.params.get("operation"), "set", "set_variable_string: operation")
	_assert_eq(cmd.params.get("value"), "hello", "set_variable_string: value")
	_assert_eq(cmd.params.get("value_source"), "constant", "set_variable_string: value_source")


func _test_set_variable_float_value() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 = 3.14]")
	_assert_success(result, "set_variable_float")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("value"), 3.14, "set_variable_float: value")


func _test_set_variable_bool_value() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 = true]")
	_assert_success(result, "set_variable_bool")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("value"), true, "set_variable_bool: value")


## --- SET_VARIABLE Advanced Syntax Tests ---

func _test_set_variable_advanced_variable_source() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 value_source=variable source_variable_id=var_002]")
	_assert_success(result, "set_variable_advanced_var")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("variable_id"), "var_001", "advanced_var: variable_id")
	_assert_eq(cmd.params.get("value_source"), "variable", "advanced_var: value_source")
	_assert_eq(cmd.params.get("source_variable_id"), "var_002", "advanced_var: source_variable_id")


func _test_set_variable_advanced_random() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 value_source=random random_min=1 random_max=100]")
	_assert_success(result, "set_variable_advanced_random")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("variable_id"), "var_001", "advanced_random: variable_id")
	_assert_eq(cmd.params.get("value_source"), "random", "advanced_random: value_source")
	_assert_eq(cmd.params.get("random_min"), 1, "advanced_random: random_min")
	_assert_eq(cmd.params.get("random_max"), 100, "advanced_random: random_max")


func _test_set_variable_advanced_game_data() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 value_source=game_data game_data_key=play_time]")
	_assert_success(result, "set_variable_advanced_game_data")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("value_source"), "game_data", "advanced_game_data: value_source")
	_assert_eq(cmd.params.get("game_data_key"), "play_time", "advanced_game_data: game_data_key")


## --- CHECK_VAR Shorthand Tests ---

func _test_check_var_equal() -> void:
	# CHECK_VAR is parsed via _parse_check_var_shorthand, test it directly
	var tokens: Array[String] = ["var_001", "==", "1"]
	var params: Dictionary = _parser._parse_check_var_shorthand(tokens)
	_assert_eq(params.get("variable_id"), "var_001", "check_var_equal: variable_id")
	_assert_eq(params.get("operator"), "==", "check_var_equal: operator")
	_assert_eq(params.get("value"), 1, "check_var_equal: value")
	_assert_eq(params.get("value_source"), "constant", "check_var_equal: value_source")


func _test_check_var_greater_equal() -> void:
	var tokens: Array[String] = ["var_001", ">=", "5"]
	var params: Dictionary = _parser._parse_check_var_shorthand(tokens)
	_assert_eq(params.get("operator"), ">=", "check_var_gte: operator")
	_assert_eq(params.get("value"), 5, "check_var_gte: value")


func _test_check_var_not_equal() -> void:
	var tokens: Array[String] = ["var_001", "!=", "hello"]
	var params: Dictionary = _parser._parse_check_var_shorthand(tokens)
	_assert_eq(params.get("operator"), "!=", "check_var_ne: operator")
	_assert_eq(params.get("value"), "hello", "check_var_ne: value")


func _test_check_var_less_than() -> void:
	var tokens: Array[String] = ["var_002", "<", "10"]
	var params: Dictionary = _parser._parse_check_var_shorthand(tokens)
	_assert_eq(params.get("variable_id"), "var_002", "check_var_lt: variable_id")
	_assert_eq(params.get("operator"), "<", "check_var_lt: operator")
	_assert_eq(params.get("value"), 10, "check_var_lt: value")


func _test_check_var_string_value() -> void:
	var tokens: Array[String] = ["var_001", "!=", "abc"]
	var params: Dictionary = _parser._parse_check_var_shorthand(tokens)
	_assert_eq(params.get("value"), "abc", "check_var_string: value")
	_assert_eq(params.get("value_source"), "constant", "check_var_string: value_source")


## --- Edge Cases ---

func _test_set_variable_no_params() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE]")
	_assert_success(result, "set_variable_no_params")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.size(), 0, "set_variable_no_params: empty params")


func _test_set_variable_only_var_id() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001]")
	_assert_success(result, "set_variable_only_var_id")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.params.get("variable_id"), "var_001", "only_var_id: variable_id")
	_assert_eq(cmd.params.size(), 1, "only_var_id: only 1 param")


func _test_check_var_insufficient_tokens() -> void:
	# Only 1 token
	var tokens1: Array[String] = ["var_001"]
	var params1: Dictionary = _parser._parse_check_var_shorthand(tokens1)
	_assert_eq(params1.get("variable_id"), "var_001", "check_var_1token: variable_id")
	_assert_eq(params1.has("value_source"), false, "check_var_1token: no value_source")

	# 2 tokens
	var tokens2: Array[String] = ["var_001", "=="]
	var params2: Dictionary = _parser._parse_check_var_shorthand(tokens2)
	_assert_eq(params2.get("variable_id"), "var_001", "check_var_2token: variable_id")
	_assert_eq(params2.get("operator"), "==", "check_var_2token: operator")
	_assert_eq(params2.has("value"), false, "check_var_2token: no value")


## --- IF Block Tests (Requirements 4.1-4.5) ---

func _test_simple_if_no_else() -> void:
	var dsl: String = "[IF var_001 == 1]\n  角色名: 条件满足\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "simple_if_no_else")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.command_type, "IF", "simple_if: command_type")
	var p: Dictionary = cmd.params
	_assert_eq(p["has_else"], false, "simple_if: has_else")
	_assert_eq(p["else_commands"].size(), 0, "simple_if: else_commands empty")
	# condition_commands
	_assert_eq(p["condition_commands"].size(), 1, "simple_if: 1 condition")
	var cond: Dictionary = p["condition_commands"][0]
	_assert_eq(cond["command_type"], "CHECK_VAR", "simple_if: cond type")
	_assert_eq(cond["params"]["variable_id"], "var_001", "simple_if: cond var_id")
	_assert_eq(cond["params"]["operator"], "==", "simple_if: cond operator")
	_assert_eq(cond["params"]["value"], 1, "simple_if: cond value")
	# if_commands
	_assert_eq(p["if_commands"].size(), 1, "simple_if: 1 if_command")
	_assert_eq(p["if_commands"][0]["command_type"], "DIALOGUE", "simple_if: if_cmd type")


func _test_simple_if_with_else() -> void:
	var dsl: String = "[IF var_001 >= 5]\n  角色名: 满足\n[ELSE]\n  角色名: 不满足\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "simple_if_with_else")
	var p: Dictionary = result["commands"][0].params
	_assert_eq(p["has_else"], true, "if_else: has_else")
	_assert_eq(p["if_commands"].size(), 1, "if_else: 1 if_command")
	_assert_eq(p["else_commands"].size(), 1, "if_else: 1 else_command")
	_assert_eq(p["else_commands"][0]["command_type"], "DIALOGUE", "if_else: else_cmd type")


func _test_multi_condition_if() -> void:
	var dsl: String = "[IF]\n  [? CHECK_VAR var_001 == 1]\n  [? CHECK_HOVER node_001]\n[THEN]\n  角色名: 条件满足\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "multi_cond_if")
	var p: Dictionary = result["commands"][0].params
	_assert_eq(p["condition_commands"].size(), 2, "multi_cond: 2 conditions")
	_assert_eq(p["condition_commands"][0]["command_type"], "CHECK_VAR", "multi_cond: cond0 type")
	_assert_eq(p["condition_commands"][1]["command_type"], "CHECK_HOVER", "multi_cond: cond1 type")
	_assert_eq(p["condition_commands"][1]["params"]["node_id"], "node_001", "multi_cond: hover node_id")
	_assert_eq(p["if_commands"].size(), 1, "multi_cond: 1 if_command")
	_assert_eq(p["has_else"], false, "multi_cond: no else")


func _test_multi_condition_if_with_else() -> void:
	var dsl: String = "[IF]\n  [? CHECK_VAR var_001 == 1]\n[THEN]\n  角色名: 满足\n[ELSE]\n  角色名: 不满足\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "multi_cond_if_else")
	var p: Dictionary = result["commands"][0].params
	_assert_eq(p["has_else"], true, "multi_cond_else: has_else")
	_assert_eq(p["if_commands"].size(), 1, "multi_cond_else: 1 if_cmd")
	_assert_eq(p["else_commands"].size(), 1, "multi_cond_else: 1 else_cmd")


func _test_if_with_check_hover() -> void:
	var dsl: String = "[IF]\n  [? CHECK_HOVER node_002]\n[THEN]\n  角色名: hover了\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "if_check_hover")
	var cond: Dictionary = result["commands"][0].params["condition_commands"][0]
	_assert_eq(cond["command_type"], "CHECK_HOVER", "hover: cond type")
	_assert_eq(cond["params"]["node_id"], "node_002", "hover: node_id")


func _test_if_with_check_click() -> void:
	var dsl: String = "[IF]\n  [? CHECK_CLICK node_003]\n[THEN]\n  角色名: 点击了\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "if_check_click")
	var cond: Dictionary = result["commands"][0].params["condition_commands"][0]
	_assert_eq(cond["command_type"], "CHECK_CLICK", "click: cond type")
	_assert_eq(cond["params"]["node_id"], "node_003", "click: node_id")


## --- CHOICE Block Tests (Requirements 5.1-5.5) ---

func _test_simple_choice() -> void:
	var dsl: String = "[CHOICE]\n  - 选项A\n  - 选项B\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "simple_choice")
	var cmd: AVGCommand = result["commands"][0]
	_assert_eq(cmd.command_type, "CHOICE", "simple_choice: command_type")
	var choices: Array = cmd.params["choices"]
	_assert_eq(choices.size(), 2, "simple_choice: 2 choices")
	_assert_eq(choices[0]["text"], "选项A", "simple_choice: text A")
	_assert_eq(choices[1]["text"], "选项B", "simple_choice: text B")
	_assert_eq(choices[0]["hidden_when_unmet"], false, "simple_choice: not hidden")
	_assert_eq(choices[0]["condition_commands"].size(), 0, "simple_choice: no conditions")


func _test_choice_with_condition() -> void:
	var dsl: String = "[CHOICE]\n  - [? CHECK_VAR var_001 > 5] 条件选项\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "choice_condition")
	var choice: Dictionary = result["commands"][0].params["choices"][0]
	_assert_eq(choice["text"], "条件选项", "choice_cond: text")
	_assert_eq(choice["condition_commands"].size(), 1, "choice_cond: 1 condition")
	var cond: Dictionary = choice["condition_commands"][0]
	_assert_eq(cond["command_type"], "CHECK_VAR", "choice_cond: cond type")
	_assert_eq(cond["params"]["variable_id"], "var_001", "choice_cond: var_id")
	_assert_eq(cond["params"]["operator"], ">", "choice_cond: operator")
	_assert_eq(cond["params"]["value"], 5, "choice_cond: value")
	_assert_eq(choice["hidden_when_unmet"], false, "choice_cond: not hidden")


func _test_choice_with_hidden() -> void:
	var dsl: String = "[CHOICE]\n  - [? CHECK_VAR var_001 > 10] [HIDDEN] 隐藏选项\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "choice_hidden")
	var choice: Dictionary = result["commands"][0].params["choices"][0]
	_assert_eq(choice["text"], "隐藏选项", "choice_hidden: text")
	_assert_eq(choice["hidden_when_unmet"], true, "choice_hidden: hidden_when_unmet")
	_assert_eq(choice["condition_commands"].size(), 1, "choice_hidden: 1 condition")


func _test_choice_with_commands() -> void:
	var dsl: String = "[CHOICE]\n  - 选项A\n    角色名: 选了A\n    [SET_VARIABLE var_001 = 1]\n  - 选项B\n    -> #node_002\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "choice_commands")
	var choices: Array = result["commands"][0].params["choices"]
	_assert_eq(choices[0]["commands"].size(), 2, "choice_cmds: A has 2 commands")
	_assert_eq(choices[0]["commands"][0]["command_type"], "DIALOGUE", "choice_cmds: A cmd0 dialogue")
	_assert_eq(choices[0]["commands"][1]["command_type"], "SET_VARIABLE", "choice_cmds: A cmd1 set_var")
	_assert_eq(choices[1]["commands"].size(), 1, "choice_cmds: B has 1 command")
	_assert_eq(choices[1]["commands"][0]["command_type"], "JUMP_TO_NODE", "choice_cmds: B cmd0 jump")


## --- Nesting Tests (Requirements 4.5, 5.5) ---

func _test_if_nested_in_if() -> void:
	var dsl: String = "[IF var_001 == 1]\n  [IF var_002 == 2]\n    角色名: 内层\n  [END]\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "if_in_if")
	var outer: Dictionary = result["commands"][0].params
	_assert_eq(outer["if_commands"].size(), 1, "if_in_if: outer has 1 if_cmd")
	var inner: Dictionary = outer["if_commands"][0]
	_assert_eq(inner["command_type"], "IF", "if_in_if: inner is IF")
	_assert_eq(inner["params"]["if_commands"].size(), 1, "if_in_if: inner has 1 cmd")


func _test_choice_nested_in_if() -> void:
	var dsl: String = "[IF var_001 == 1]\n  [CHOICE]\n    - 选项A\n      角色名: A\n    - 选项B\n      角色名: B\n  [END]\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "choice_in_if")
	var if_cmds: Array = result["commands"][0].params["if_commands"]
	_assert_eq(if_cmds.size(), 1, "choice_in_if: 1 if_cmd")
	_assert_eq(if_cmds[0]["command_type"], "CHOICE", "choice_in_if: is CHOICE")
	_assert_eq(if_cmds[0]["params"]["choices"].size(), 2, "choice_in_if: 2 choices")


func _test_if_nested_in_choice() -> void:
	var dsl: String = "[CHOICE]\n  - 选项A\n    [IF var_001 == 1]\n      角色名: 条件满足\n    [END]\n  - 选项B\n    角色名: B\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "if_in_choice")
	var choices: Array = result["commands"][0].params["choices"]
	_assert_eq(choices[0]["commands"].size(), 1, "if_in_choice: A has 1 cmd")
	_assert_eq(choices[0]["commands"][0]["command_type"], "IF", "if_in_choice: A cmd is IF")
	_assert_eq(choices[1]["commands"].size(), 1, "if_in_choice: B has 1 cmd")


func _test_deep_nesting() -> void:
	# IF → CHOICE → IF (3 levels deep)
	var dsl: String = "[IF var_001 == 1]\n  [CHOICE]\n    - 选项A\n      [IF var_002 == 2]\n        角色名: 最深层\n      [END]\n  [END]\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_success(result, "deep_nesting")
	var outer_if: Dictionary = result["commands"][0].params
	var choice_cmd: Dictionary = outer_if["if_commands"][0]
	_assert_eq(choice_cmd["command_type"], "CHOICE", "deep: level1 CHOICE")
	var inner_if: Dictionary = choice_cmd["params"]["choices"][0]["commands"][0]
	_assert_eq(inner_if["command_type"], "IF", "deep: level2 IF")
	_assert_eq(inner_if["params"]["if_commands"][0]["command_type"], "DIALOGUE", "deep: level3 DIALOGUE")


## --- Error Cases ---

func _test_unclosed_if() -> void:
	var dsl: String = "[IF var_001 == 1]\n  角色名: 没有END"
	var result: Dictionary = _parser.parse(dsl)
	# Should have errors about unclosed block
	var has_error: bool = not result.get("success", true) or result.get("errors", []).size() > 0
	if has_error:
		print("  ✅ unclosed_if: error detected")
	else:
		print("  ❌ unclosed_if: expected error for unclosed IF block")
		_all_passed = false


func _test_unclosed_choice() -> void:
	var dsl: String = "[CHOICE]\n  - 选项A\n  - 选项B"
	var result: Dictionary = _parser.parse(dsl)
	var has_error: bool = not result.get("success", true) or result.get("errors", []).size() > 0
	if has_error:
		print("  ✅ unclosed_choice: error detected")
	else:
		print("  ❌ unclosed_choice: expected error for unclosed CHOICE block")
		_all_passed = false


## --- Error Handling Tests (Task 1.4) ---

func _test_unknown_command_type() -> void:
	var result: Dictionary = _parser.parse("[UNKNOWN_CMD param1]")
	_assert_failure(result, "unknown_cmd")
	_assert_error_contains(result, "未识别的指令类型: UNKNOWN_CMD", "unknown_cmd: error message")
	_assert_error_has_line(result, 1, "unknown_cmd: line number")


func _test_unknown_command_type_in_block() -> void:
	var dsl: String = "[IF var_001 == 1]\n  [FAKE_COMMAND abc]\n[END]"
	var result: Dictionary = _parser.parse(dsl)
	# The IF block should still parse, but with errors from the inner unknown command
	var all_errors: Array = _collect_all_errors(result)
	var found: bool = false
	for err in all_errors:
		if str(err.get("message", "")).find("未识别的指令类型: FAKE_COMMAND") != -1:
			found = true
			break
	if found:
		print("  ✅ unknown_cmd_in_block: error detected for FAKE_COMMAND")
	else:
		print("  ❌ unknown_cmd_in_block: expected error for FAKE_COMMAND in block")
		_all_passed = false


func _test_unclosed_if_line_number() -> void:
	var dsl: String = "角色名: 第一行\n[IF var_001 == 1]\n  角色名: 条件内"
	var result: Dictionary = _parser.parse(dsl)
	_assert_failure(result, "unclosed_if_line")
	_assert_error_contains(result, "未闭合的 IF 块", "unclosed_if_line: error message")
	_assert_error_has_line(result, 2, "unclosed_if_line: line number")


func _test_unclosed_choice_line_number() -> void:
	var dsl: String = "角色名: 第一行\n[CHOICE]\n  - 选项A\n  - 选项B"
	var result: Dictionary = _parser.parse(dsl)
	_assert_failure(result, "unclosed_choice_line")
	_assert_error_contains(result, "未闭合的 CHOICE 块", "unclosed_choice_line: error message")
	_assert_error_has_line(result, 2, "unclosed_choice_line: line number")


func _test_unclosed_if_with_else_no_end() -> void:
	var dsl: String = "[IF var_001 == 1]\n  角色名: 满足\n[ELSE]\n  角色名: 不满足"
	var result: Dictionary = _parser.parse(dsl)
	_assert_failure(result, "unclosed_if_else")
	_assert_error_contains(result, "未闭合的 IF 块", "unclosed_if_else: error message")


func _test_set_variable_missing_value() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 = ]")
	_assert_failure(result, "set_var_missing_value")
	_assert_error_contains(result, "无效的变量值", "set_var_missing_value: error message")
	_assert_error_has_line(result, 1, "set_var_missing_value: line number")


func _test_set_variable_missing_value_add() -> void:
	var result: Dictionary = _parser.parse("[SET_VARIABLE var_001 += ]")
	_assert_failure(result, "set_var_missing_value_add")
	_assert_error_contains(result, "无效的变量值", "set_var_missing_value_add: error message")


func _test_multiple_errors() -> void:
	var dsl: String = "[UNKNOWN_CMD param1]\n[SET_VARIABLE var_001 = ]\n[ANOTHER_BAD cmd]"
	var result: Dictionary = _parser.parse(dsl)
	_assert_failure(result, "multiple_errors")
	var errs: Array = result.get("errors", [])
	if errs.size() >= 3:
		print("  ✅ multiple_errors: %d errors detected" % errs.size())
	else:
		print("  ❌ multiple_errors: expected >= 3 errors, got %d" % errs.size())
		_all_passed = false


## --- Assertion Helpers ---

func _assert_success(result: Dictionary, test_name: String) -> void:
	if not result.get("success", false):
		print("  ❌ %s: parse failed - %s" % [test_name, result.get("errors", [])])
		_all_passed = false
	elif result.get("commands", []).size() == 0:
		print("  ❌ %s: no commands produced" % test_name)
		_all_passed = false


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		print("  ❌ %s: expected %s, got %s" % [label, str(expected), str(actual)])
		_all_passed = false
	else:
		print("  ✅ %s" % label)


func _assert_failure(result: Dictionary, test_name: String) -> void:
	if result.get("success", true):
		print("  ❌ %s: expected failure but got success" % test_name)
		_all_passed = false
	elif result.get("errors", []).size() == 0:
		print("  ❌ %s: expected errors but got none" % test_name)
		_all_passed = false


func _assert_error_contains(result: Dictionary, substring: String, label: String) -> void:
	var errs: Array = result.get("errors", [])
	var found: bool = false
	for err in errs:
		if str(err.get("message", "")).find(substring) != -1:
			found = true
			break
	if found:
		print("  ✅ %s" % label)
	else:
		print("  ❌ %s: no error containing '%s' in %s" % [label, substring, str(errs)])
		_all_passed = false


func _assert_error_has_line(result: Dictionary, expected_line: int, label: String) -> void:
	var errs: Array = result.get("errors", [])
	var found: bool = false
	for err in errs:
		if err.get("line", -1) == expected_line:
			found = true
			break
	if found:
		print("  ✅ %s" % label)
	else:
		var lines_found: Array = []
		for err in errs:
			lines_found.append(err.get("line", -1))
		print("  ❌ %s: expected error at line %d, found lines %s" % [label, expected_line, str(lines_found)])
		_all_passed = false


## Collect all errors from a parse result, including nested block errors
func _collect_all_errors(result: Dictionary) -> Array:
	var all_errors: Array = []
	all_errors.append_array(result.get("errors", []))
	# Check if commands have nested errors (from blocks that partially parsed)
	for cmd in result.get("commands", []):
		if cmd is AVGCommand and cmd.params.has("_errors"):
			all_errors.append_array(cmd.params["_errors"])
	return all_errors
