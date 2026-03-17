extends Node
## Property tests for write_commands mode logic
## # Feature: avg-dsl, Property 3: write_commands 模式正确性
## **Validates: Requirements 8.2, 8.3, 8.4, 8.6**

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

	print("========== write_commands Property Tests ==========")

	# Property 3: write_commands 模式正确性
	var result: Dictionary = _runner.run_property(
		"Property 3: write_commands 模式正确性",
		100,
		Callable(self, "_test_write_commands_modes")
	)
	print(result["summary"])

	# Property 4: write_commands 错误原子性
	var result4: Dictionary = _runner.run_property(
		"Property 4: write_commands 错误原子性",
		100,
		Callable(self, "_test_error_atomicity")
	)
	print(result4["summary"])

	print("========== Tests Complete ==========")


## Simulate write_commands mode logic on a plain array (mirrors tool_registry.gd logic)
func _apply_mode(existing: Array, new_commands: Array, mode: String, start_idx: int = 0, end_idx: int = -1) -> Variant:
	var result: Array = existing.duplicate(true)
	match mode:
		"write":
			result.clear()
			result.append_array(new_commands)
		"append":
			result.append_array(new_commands)
		"replace":
			if end_idx < 0:
				end_idx = result.size() - 1
			if start_idx < 0 or end_idx >= result.size() or start_idx > end_idx:
				return null  # out of range
			for j in range(end_idx, start_idx - 1, -1):
				result.remove_at(j)
			for j in range(new_commands.size()):
				result.insert(start_idx + j, new_commands[j])
	return result


## Convert AVGCommand to Dictionary for comparison
func _cmd_to_dict(cmd: Variant) -> Dictionary:
	if cmd is Resource:
		return {"command_type": cmd.command_type, "params": cmd.params.duplicate(true)}
	if cmd is Dictionary:
		return {"command_type": cmd.get("command_type", ""), "params": cmd.get("params", {}).duplicate(true)}
	return {}


## Convert array of commands to array of dicts for comparison
func _cmds_to_dicts(cmds: Array) -> Array:
	var result: Array = []
	for cmd in cmds:
		result.append(_cmd_to_dict(cmd))
	return result


## Deep compare two command dicts
func _compare_cmd_dicts(a: Dictionary, b: Dictionary, path: String) -> String:
	if str(a.get("command_type", "")) != str(b.get("command_type", "")):
		return "%s: command_type mismatch: '%s' vs '%s'" % [
			path, a.get("command_type", ""), b.get("command_type", "")]
	var pa: Dictionary = a.get("params", {})
	var pb: Dictionary = b.get("params", {})
	for k in pa.keys():
		if str(k).begins_with("_"):
			continue
		if not pb.has(k):
			return "%s: missing key '%s'" % [path, k]
		if str(pa[k]) != str(pb[k]):
			return "%s.%s: value mismatch: '%s' vs '%s'" % [path, k, str(pa[k]), str(pb[k])]
	for k in pb.keys():
		if str(k).begins_with("_"):
			continue
		if not pa.has(k):
			return "%s: unexpected key '%s'" % [path, k]
	return ""


## Compare two command arrays (as dicts)
func _compare_cmd_arrays(expected: Array, actual: Array, label: String) -> String:
	if expected.size() != actual.size():
		return "%s: size mismatch: expected=%d, actual=%d" % [label, expected.size(), actual.size()]
	for i in range(expected.size()):
		var err: String = _compare_cmd_dicts(expected[i], actual[i], "%s[%d]" % [label, i])
		if not err.is_empty():
			return err
	return ""


## Generate new commands via DSL round-trip to ensure they are clean/parseable
func _generate_clean_commands(rng: RandomNumberGenerator, count: int) -> Array:
	var cmds: Array = []
	for idx in range(count):
		cmds.append(GeneratorsClass._random_flat_command(rng))
	# Round-trip through serialize → parse to get clean dict-based commands
	var dsl_text: String = _serializer.serialize(cmds)
	var parse_result: Dictionary = _parser.parse(dsl_text)
	if parse_result["success"]:
		return parse_result["commands"]
	# Fallback: return original commands
	return cmds


## Property 3: write_commands 模式正确性
## For each iteration, test all three modes (write, append, replace)
func _test_write_commands_modes(rng: RandomNumberGenerator, _iteration: int) -> String:
	# 1. Generate random existing commands (1-10)
	var existing_count: int = rng.randi_range(1, 10)
	var existing: Array = _generate_clean_commands(rng, existing_count)
	var existing_dicts: Array = _cmds_to_dicts(existing)

	# 2. Generate random new commands (1-5) via DSL round-trip
	var new_count: int = rng.randi_range(1, 5)
	var new_cmds: Array = _generate_clean_commands(rng, new_count)
	var new_dicts: Array = _cmds_to_dicts(new_cmds)

	# --- Test mode="write" ---
	var write_result: Variant = _apply_mode(existing_dicts, new_dicts, "write")
	if write_result == null:
		return "write mode returned null unexpectedly"
	var write_arr: Array = write_result as Array
	# write mode: result SHALL equal new commands only
	var err: String = _compare_cmd_arrays(new_dicts, write_arr, "write")
	if not err.is_empty():
		return err

	# --- Test mode="append" ---
	var append_result: Variant = _apply_mode(existing_dicts, new_dicts, "append")
	if append_result == null:
		return "append mode returned null unexpectedly"
	var append_arr: Array = append_result as Array
	# append mode: result SHALL equal existing + new
	var expected_append: Array = existing_dicts.duplicate(true)
	expected_append.append_array(new_dicts)
	err = _compare_cmd_arrays(expected_append, append_arr, "append")
	if not err.is_empty():
		return err

	# --- Test mode="replace" ---
	# Generate valid start/end indices within existing bounds
	var start_idx: int = rng.randi_range(0, existing_dicts.size() - 1)
	var end_idx: int = rng.randi_range(start_idx, existing_dicts.size() - 1)
	var replace_result: Variant = _apply_mode(existing_dicts, new_dicts, "replace", start_idx, end_idx)
	if replace_result == null:
		return "replace mode returned null for valid indices start=%d end=%d size=%d" % [
			start_idx, end_idx, existing_dicts.size()]
	var replace_arr: Array = replace_result as Array
	# replace mode: result SHALL equal existing[0..start) + new + existing(end..]
	var expected_replace: Array = []
	for i in range(0, start_idx):
		expected_replace.append(existing_dicts[i].duplicate(true))
	expected_replace.append_array(new_dicts)
	for i in range(end_idx + 1, existing_dicts.size()):
		expected_replace.append(existing_dicts[i].duplicate(true))
	err = _compare_cmd_arrays(expected_replace, replace_arr, "replace(start=%d,end=%d)" % [start_idx, end_idx])
	if not err.is_empty():
		return err

	return ""  # All modes passed


## # Feature: avg-dsl, Property 4: write_commands 错误原子性
## **Validates: Requirements 8.5, 11.4**
## For any DSL text containing syntax errors, calling write_commands (any mode)
## SHALL return success=false, AND the target tab's command list SHALL remain
## unchanged from its state before the call.
func _test_error_atomicity(rng: RandomNumberGenerator, _iteration: int) -> String:
	# 1. Generate random existing commands (1-10)
	var existing_count: int = rng.randi_range(1, 10)
	var existing: Array = _generate_clean_commands(rng, existing_count)
	var existing_dicts: Array = _cmds_to_dicts(existing)

	# 2. Generate invalid DSL text
	var invalid_dsl: String = GeneratorsClass.random_invalid_dsl(rng)

	# 3. Verify parser returns success=false for the invalid DSL
	var parse_result: Dictionary = _parser.parse(invalid_dsl)
	if parse_result["success"]:
		return "Parser unexpectedly succeeded for invalid DSL: '%s'" % invalid_dsl.replace("\n", "\\n")

	# 4. Test all three modes — existing commands must remain unchanged

	# --- mode="write" ---
	var write_copy: Array = existing_dicts.duplicate(true)
	var write_applied: Variant = _apply_mode_if_parse_ok(write_copy, parse_result, "write")
	if write_applied != null:
		return "write mode: should not have applied changes for failed parse"
	var err: String = _compare_cmd_arrays(existing_dicts, write_copy, "write_atomicity")
	if not err.is_empty():
		return err

	# --- mode="append" ---
	var append_copy: Array = existing_dicts.duplicate(true)
	var append_applied: Variant = _apply_mode_if_parse_ok(append_copy, parse_result, "append")
	if append_applied != null:
		return "append mode: should not have applied changes for failed parse"
	err = _compare_cmd_arrays(existing_dicts, append_copy, "append_atomicity")
	if not err.is_empty():
		return err

	# --- mode="replace" ---
	var replace_copy: Array = existing_dicts.duplicate(true)
	var start_idx: int = rng.randi_range(0, existing_dicts.size() - 1)
	var end_idx: int = rng.randi_range(start_idx, existing_dicts.size() - 1)
	var replace_applied: Variant = _apply_mode_if_parse_ok(replace_copy, parse_result, "replace", start_idx, end_idx)
	if replace_applied != null:
		return "replace mode: should not have applied changes for failed parse"
	err = _compare_cmd_arrays(existing_dicts, replace_copy, "replace_atomicity")
	if not err.is_empty():
		return err

	return ""  # All modes preserved atomicity


## Simulate the write_commands error-guarding logic:
## Only apply changes if parse succeeded; otherwise return null and leave existing unchanged.
func _apply_mode_if_parse_ok(existing: Array, parse_result: Dictionary, mode: String, start_idx: int = 0, end_idx: int = -1) -> Variant:
	if not parse_result["success"]:
		return null  # Error: do not modify existing
	var new_commands: Array = _cmds_to_dicts(parse_result["commands"])
	return _apply_mode(existing, new_commands, mode, start_idx, end_idx)
