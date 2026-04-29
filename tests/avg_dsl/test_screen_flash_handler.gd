extends Node

const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")
const CommandInitializerClass = preload("res://scripts/avg/commands/command_initializer.gd")
const CommandRegistryClass = preload("res://scripts/avg/commands/command_registry.gd")


class MockSceneRunner:
	extends RefCounted

	var last_call: Dictionary = {}


	func screen_flash(color: Color, duration: float, intensity: float) -> void:
		last_call = {
			"color": color,
			"duration": duration,
			"intensity": intensity,
		}


class MockContext:
	extends RefCounted

	var scene_runner: RefCounted = null


	func _init(p_scene_runner: RefCounted) -> void:
		scene_runner = p_scene_runner


var _all_passed: bool = true


func _ready() -> void:
	print("========== SCREEN_FLASH Handler Tests ==========")

	_test_numeric_intensity_validation()
	_test_semantic_intensity_validation()
	_test_invalid_intensity_falls_back()
	_test_semantic_intensity_execution()
	_test_numeric_string_execution()

	if _all_passed:
		print("✅ ALL TESTS PASSED")
	else:
		print("❌ SOME TESTS FAILED")

	print("========== Tests Complete ==========")


func _build_registry() -> RefCounted:
	CommandRegistryClass.reset_instance()
	var registry: RefCounted = CommandRegistryClass.get_instance()
	registry.clear()
	CommandInitializerClass.register_all_commands(registry)
	return registry


func _test_numeric_intensity_validation() -> void:
	var registry: RefCounted = _build_registry()
	var command := AVGCommandClass.new("SCREEN_FLASH", {
		"intensity": 0.8,
		"duration": 0.2,
	})
	var validation = registry.validate_command(command)
	_assert_true(
		"numeric intensity validate",
		validation.is_valid(),
		validation.get_error_string("; ")
	)


func _test_semantic_intensity_validation() -> void:
	var registry: RefCounted = _build_registry()
	var command := AVGCommandClass.new("SCREEN_FLASH", {
		"intensity": "轻",
		"duration": 0.3,
	})
	var validation = registry.validate_command(command)
	_assert_true(
		"semantic intensity validate",
		validation.is_valid(),
		validation.get_error_string("; ")
	)


func _test_invalid_intensity_falls_back() -> void:
	var registry: RefCounted = _build_registry()
	var runner := MockSceneRunner.new()
	var context := MockContext.new(runner)
	var command := AVGCommandClass.new("SCREEN_FLASH", {
		"intensity": "chaos",
	})
	var validation = registry.validate_command(command)
	var result = registry.execute_command(command, context)
	_assert_true(
		"invalid intensity validate",
		validation.is_valid(),
		validation.get_error_string("; ")
	)
	_assert_true("invalid intensity execute", result.is_success(), result.error_message)
	_assert_float_eq("invalid intensity fallback", runner.last_call.get("intensity", -1.0), 1.0)


func _test_semantic_intensity_execution() -> void:
	var registry: RefCounted = _build_registry()
	var runner := MockSceneRunner.new()
	var context := MockContext.new(runner)
	var command := AVGCommandClass.new("SCREEN_FLASH", {
		"color": Color.BLACK,
		"duration": 0.25,
		"intensity": "重",
	})
	var result = registry.execute_command(command, context)

	_assert_true("semantic intensity execute", result.is_success(), result.error_message)
	_assert_float_eq("semantic intensity mapped", runner.last_call.get("intensity", -1.0), 1.0)
	_assert_float_eq("semantic duration forwarded", runner.last_call.get("duration", -1.0), 0.25)
	_assert_true("semantic color forwarded", runner.last_call.get("color", null) == Color.BLACK, "expected black color")


func _test_numeric_string_execution() -> void:
	var registry: RefCounted = _build_registry()
	var runner := MockSceneRunner.new()
	var context := MockContext.new(runner)
	var command := AVGCommandClass.new("SCREEN_FLASH", {
		"intensity": "0.55",
		"duration": "0.75",
	})
	var result = registry.execute_command(command, context)

	_assert_true("numeric string execute", result.is_success(), result.error_message)
	_assert_float_eq("numeric string intensity parsed", runner.last_call.get("intensity", -1.0), 0.55)
	_assert_float_eq("numeric string duration parsed", runner.last_call.get("duration", -1.0), 0.75)


func _assert_true(label: String, condition: bool, details: String = "") -> void:
	if condition:
		print("PASS: %s" % label)
		return

	_all_passed = false
	if details.is_empty():
		print("FAIL: %s" % label)
	else:
		print("FAIL: %s -- %s" % [label, details])


func _assert_float_eq(label: String, actual: Variant, expected: float) -> void:
	var ok: bool = (actual is int or actual is float) and is_equal_approx(float(actual), expected)
	_assert_true(label, ok, "expected=%s actual=%s" % [str(expected), str(actual)])
