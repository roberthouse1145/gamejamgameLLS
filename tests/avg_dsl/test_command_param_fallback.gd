extends Node

const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")
const CommandInitializerClass = preload("res://scripts/avg/commands/command_initializer.gd")
const CommandRegistryClass = preload("res://scripts/avg/commands/command_registry.gd")


class DummyContext:
	extends RefCounted

	var scene_runner: Variant = null
	var character_display: Variant = null


class MockCharacterDisplay:
	extends RefCounted

	var last_effect: Dictionary = {}


	func play_effect(character_id: String, effect_name: String, intensity: String, duration: float) -> void:
		last_effect = {
			"character_id": character_id,
			"effect": effect_name,
			"intensity": intensity,
			"duration": duration,
		}


class MockSceneRunner:
	extends Node

	var last_shake: Dictionary = {}


	func screen_shake(intensity: float, duration: float, frequency: float) -> void:
		last_shake = {
			"intensity": intensity,
			"duration": duration,
			"frequency": frequency,
		}


var _all_passed: bool = true


func _ready() -> void:
	print("========== Command Param Fallback Tests ==========")

	_test_screen_fade_accepts_string_params()
	_test_wait_time_invalid_string_falls_back_to_default()
	_test_screen_shake_invalid_strings_fall_back()
	_test_character_effect_semantic_intensity_alias()

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


func _test_screen_fade_accepts_string_params() -> void:
	var registry: RefCounted = _build_registry()
	var command := AVGCommandClass.new("SCREEN_FADE", {
		"direction": "IN",
		"color": "#ffffff",
		"duration": "0.25",
		"transition": "WIPE_LEFT",
	})
	var validation = registry.validate_command(command)
	var result = registry.execute_command(command, DummyContext.new())

	_assert_true("screen fade validate", validation.is_valid(), validation.get_error_string("; "))
	_assert_true("screen fade execute", result.is_success(), result.error_message)
	_assert_equal("screen fade direction normalized", result.get_data("direction"), "in")
	_assert_float_eq("screen fade duration parsed", result.get_data("duration"), 0.25)
	_assert_true("screen fade color parsed", result.get_data("color") == Color("#ffffff"), "expected parsed html color")
	_assert_equal("screen fade transition normalized", result.get_data("transition"), "wipe_left")


func _test_wait_time_invalid_string_falls_back_to_default() -> void:
	var registry: RefCounted = _build_registry()
	var command := AVGCommandClass.new("WAIT_TIME", {
		"duration": "later",
	})
	var validation = registry.validate_command(command)
	var result = registry.execute_command(command, DummyContext.new())

	_assert_true("wait time validate", validation.is_valid(), validation.get_error_string("; "))
	_assert_true("wait time execute", result.is_success(), result.error_message)
	_assert_float_eq("wait time fallback default", result.get_data("duration"), 1.0)


func _test_screen_shake_invalid_strings_fall_back() -> void:
	var registry: RefCounted = _build_registry()
	var runner := MockSceneRunner.new()
	var context := DummyContext.new()
	context.scene_runner = runner
	var command := AVGCommandClass.new("SCREEN_SHAKE", {
		"intensity": "随便",
		"duration": "fast",
		"frequency": "crazy",
	})
	var validation = registry.validate_command(command)
	var result = registry.execute_command(command, context)

	_assert_true("screen shake validate", validation.is_valid(), validation.get_error_string("; "))
	_assert_true("screen shake execute", result.is_success(), result.error_message)
	_assert_float_eq("screen shake intensity fallback", runner.last_shake.get("intensity", -1.0), 10.0)
	_assert_float_eq("screen shake duration fallback", runner.last_shake.get("duration", -1.0), 0.5)
	_assert_float_eq("screen shake frequency fallback", runner.last_shake.get("frequency", -1.0), 20.0)


func _test_character_effect_semantic_intensity_alias() -> void:
	var registry: RefCounted = _build_registry()
	var display := MockCharacterDisplay.new()
	var context := DummyContext.new()
	context.character_display = display
	var command := AVGCommandClass.new("CHARACTER_EFFECT", {
		"character_id": "LinXia",
		"effect": "shake",
		"intensity": "轻",
		"duration": "0.3",
	})
	var validation = registry.validate_command(command)
	var result = registry.execute_command(command, context)

	_assert_true("character effect validate", validation.is_valid(), validation.get_error_string("; "))
	_assert_true("character effect execute", result.is_success(), result.error_message)
	_assert_equal("character effect semantic intensity mapped", display.last_effect.get("intensity", ""), "small")
	_assert_float_eq("character effect duration parsed", display.last_effect.get("duration", -1.0), 0.3)


func _assert_true(label: String, condition: bool, details: String = "") -> void:
	if condition:
		print("PASS: %s" % label)
		return

	_all_passed = false
	if details.is_empty():
		print("FAIL: %s" % label)
	else:
		print("FAIL: %s -- %s" % [label, details])


func _assert_equal(label: String, actual: Variant, expected: Variant) -> void:
	_assert_true(label, actual == expected, "expected=%s actual=%s" % [str(expected), str(actual)])


func _assert_float_eq(label: String, actual: Variant, expected: float) -> void:
	var ok: bool = (actual is int or actual is float) and is_equal_approx(float(actual), expected)
	_assert_true(label, ok, "expected=%s actual=%s" % [str(expected), str(actual)])
