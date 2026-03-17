extends Node
## Property tests for AVG DSL Parser/Serializer
## # Feature: avg-dsl, Property 1: DSL Round-Trip 一致性
## **Validates: Requirements 1.1, 1.2, 2.1-2.7, 3.1-3.3, 4.1-4.5, 5.1-5.5, 6.2, 7.2, 7.3, 7.4**

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser.gd")
const SerializerClass = preload("res://scripts/avg/dsl/avg_dsl_serializer.gd")
const RunnerClass = preload("res://tests/deepcode/helpers/property_test_runner.gd")
const GeneratorsClass = preload("res://tests/avg_dsl/helpers/dsl_generators.gd")

var _parser: RefCounted
var _serializer: RefCounted
var _runner: RefCounted


func _ready() -> void:
	_parser = ParserClass.new()
	_serializer = SerializerClass.new()
	_runner = RunnerClass.new()

	print("========== AVG DSL Property Tests ==========")

	# Property 1: Round-Trip 一致性
	var result: Dictionary = _runner.run_property(
		"Property 1: DSL Round-Trip 一致性",
		100,
		Callable(self, "_test_round_trip")
	)
	print(result["summary"])

	# Feature: avg-dsl, Property 2: 非法 DSL 文本错误检测
	var result2: Dictionary = _runner.run_property(
		"Property 2: 非法 DSL 文本错误检测",
		100,
		Callable(self, "_test_error_detection")
	)
	print(result2["summary"])

	print("========== Tests Complete ==========")


## Property 2: 非法 DSL 文本错误检测
## **Validates: Requirements 6.3, 6.5, 11.1, 11.2, 11.3**
func _test_error_detection(rng: RandomNumberGenerator, _iteration: int) -> String:
	# 1. Generate random invalid DSL
	var invalid_dsl: String = GeneratorsClass.random_invalid_dsl(rng)

	# 2. Parse
	var result: Dictionary = _parser.parse(invalid_dsl)

	# 3. Verify failure
	if result["success"]:
		return "Expected failure but got success for: %s" % invalid_dsl

	# 4. Verify errors non-empty
	var errors: Array = result["errors"]
	if errors.is_empty():
		return "Expected errors but got none for: %s" % invalid_dsl

	# 5. Verify error format
	for err in errors:
		if not err.has("line"):
			return "Error missing 'line' field: %s" % str(err)
		if not err.has("message"):
			return "Error missing 'message' field: %s" % str(err)
		if not (err["line"] is int or err["line"] is float):
			return "Error 'line' is not a number: %s" % str(err)
		if not (err["message"] is String):
			return "Error 'message' is not a String: %s" % str(err)

	return ""  # Success


func _test_round_trip(rng: RandomNumberGenerator, _iteration: int) -> String:
	# 1. Generate random commands
	var original_commands: Array = GeneratorsClass.random_command_array(rng, 1, 10)

	# 2. Serialize to DSL text
	var dsl_text: String = _serializer.serialize(original_commands)

	# 3. Parse back
	var parse_result: Dictionary = _parser.parse(dsl_text)
	if not parse_result["success"]:
		return "Parse failed: %s\nDSL text:\n%s" % [str(parse_result["errors"]), dsl_text]

	# 4. Compare
	var parsed_commands: Array = parse_result["commands"]
	if original_commands.size() != parsed_commands.size():
		return "Command count mismatch: original=%d, parsed=%d\nDSL:\n%s" % [
			original_commands.size(), parsed_commands.size(), dsl_text]

	for i in range(original_commands.size()):
		var orig_dict: Dictionary = _normalize_command(original_commands[i])
		var parsed_dict: Dictionary = _normalize_command(parsed_commands[i])
		var error: String = _compare_dicts(orig_dict, parsed_dict, "cmd[%d]" % i)
		if not error.is_empty():
			return error + "\nDSL:\n%s" % dsl_text

	return ""  # Success


## Normalize a command (AVGCommand or Dictionary) to a canonical Dictionary form.
func _normalize_command(cmd: Variant) -> Dictionary:
	var cmd_type: String = ""
	var params: Dictionary = {}

	if cmd is Resource:
		cmd_type = cmd.get("command_type") if cmd.get("command_type") != null else str(cmd.command_type)
		params = cmd.params.duplicate(true)
	elif cmd is Dictionary:
		cmd_type = str(cmd.get("command_type", ""))
		params = cmd.get("params", {}).duplicate(true)
	else:
		return {"command_type": "", "params": {}}

	# Normalize nested command arrays
	var nested_keys: Array[String] = [
		"condition_commands", "if_commands", "else_commands"
	]
	for key in nested_keys:
		if params.has(key) and params[key] is Array:
			var normalized: Array = []
			for sub_cmd in params[key]:
				normalized.append(_normalize_command(sub_cmd))
			params[key] = normalized

	# Normalize choices array (CHOICE command)
	if params.has("choices") and params["choices"] is Array:
		var normalized_choices: Array = []
		for choice in params["choices"]:
			if choice is Dictionary:
				var nc: Dictionary = choice.duplicate(true)
				if nc.has("commands") and nc["commands"] is Array:
					var norm_cmds: Array = []
					for sub_cmd in nc["commands"]:
						norm_cmds.append(_normalize_command(sub_cmd))
					nc["commands"] = norm_cmds
				if nc.has("condition_commands") and nc["condition_commands"] is Array:
					var norm_conds: Array = []
					for sub_cmd in nc["condition_commands"]:
						norm_conds.append(_normalize_command(sub_cmd))
					nc["condition_commands"] = norm_conds
				normalized_choices.append(nc)
		params["choices"] = normalized_choices

	return {"command_type": cmd_type, "params": params}


## Deep compare two command dictionaries.
func _compare_dicts(expected: Dictionary, actual: Dictionary, path: String) -> String:
	if str(expected.get("command_type", "")) != str(actual.get("command_type", "")):
		return "%s: command_type mismatch: '%s' vs '%s'" % [
			path, expected.get("command_type", ""), actual.get("command_type", "")]

	var exp_params: Dictionary = expected.get("params", {})
	var act_params: Dictionary = actual.get("params", {})
	return _compare_params(exp_params, act_params, path)


## Compare two params dictionaries, skipping internal keys starting with '_'.
func _compare_params(expected: Dictionary, actual: Dictionary, path: String) -> String:
	var exp_keys: Array = []
	for k in expected.keys():
		if not str(k).begins_with("_"):
			exp_keys.append(k)

	var act_keys: Array = []
	for k in actual.keys():
		if not str(k).begins_with("_"):
			act_keys.append(k)

	for k in exp_keys:
		if not actual.has(k):
			return "%s: missing key '%s' in parsed result" % [path, k]

	for k in act_keys:
		if not expected.has(k):
			return "%s: unexpected key '%s' in parsed (value: %s)" % [path, k, str(actual[k])]

	for k in exp_keys:
		var error: String = _compare_values(expected[k], actual[k], "%s.%s" % [path, k])
		if not error.is_empty():
			return error

	return ""


## Compare two values with type-aware logic.
func _compare_values(expected: Variant, actual: Variant, path: String) -> String:
	# Both Arrays
	if expected is Array and actual is Array:
		var exp_arr: Array = expected
		var act_arr: Array = actual
		if exp_arr.size() != act_arr.size():
			return "%s: array size mismatch: %d vs %d" % [path, exp_arr.size(), act_arr.size()]
		for i in range(exp_arr.size()):
			var error: String = _compare_values(exp_arr[i], act_arr[i], "%s[%d]" % [path, i])
			if not error.is_empty():
				return error
		return ""

	# Both Dictionaries
	if expected is Dictionary and actual is Dictionary:
		if expected.has("command_type") and actual.has("command_type"):
			return _compare_dicts(expected, actual, path)
		return _compare_params(expected, actual, path)

	# Numeric comparison with tolerance
	if (expected is float or expected is int) and (actual is float or actual is int):
		var exp_f: float = float(expected)
		var act_f: float = float(actual)
		if absf(exp_f - act_f) > 0.001:
			return "%s: numeric mismatch: %s vs %s" % [path, str(expected), str(actual)]
		return ""

	# Bool comparison (strict)
	if expected is bool or actual is bool:
		if str(expected) != str(actual):
			return "%s: bool mismatch: %s vs %s" % [path, str(expected), str(actual)]
		return ""

	# String comparison
	if str(expected) != str(actual):
		return "%s: value mismatch: '%s' (%s) vs '%s' (%s)" % [
			path, str(expected), typeof(expected), str(actual), typeof(actual)]

	return ""
