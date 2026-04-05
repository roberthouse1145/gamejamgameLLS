extends Node

const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")
const CommandDisplayUtilsClass = preload("res://scripts/apps/scene_editor/command_display_utils.gd")
const CameraPanHandlerClass = preload("res://scripts/avg/commands/handlers/camera_pan_handler.gd")


class MockSceneRunner:
	extends Node

	var last_call: Dictionary = {}


	func camera_pan(norm_x: float, norm_y: float, duration: float) -> void:
		last_call = {
			"norm_x": norm_x,
			"norm_y": norm_y,
			"duration": duration,
		}


class MockContext:
	extends RefCounted

	var scene_runner: Node = null


	func _init(p_scene_runner: Node) -> void:
		scene_runner = p_scene_runner


var _all_passed: bool = true


func _ready() -> void:
	print("========== CAMERA_PAN Handler Tests ==========")

	_test_target_right_execution()
	_test_numeric_execution()
	_test_display_with_target()

	if _all_passed:
		print("✅ ALL TESTS PASSED")
	else:
		print("❌ SOME TESTS FAILED")

	print("========== Tests Complete ==========")


func _test_target_right_execution() -> void:
	var handler = CameraPanHandlerClass.new()
	var runner := MockSceneRunner.new()
	var context := MockContext.new(runner)
	var command := AVGCommandClass.new("CAMERA_PAN", {
		"target": "right",
		"duration": 0.6,
	})
	var result = handler.execute(command, context)

	_assert_true("target right execute", result.is_success(), result.error_message)
	_assert_float_eq("target right norm_x", runner.last_call.get("norm_x", -999.0), 0.15)
	_assert_float_eq("target right norm_y", runner.last_call.get("norm_y", -999.0), 0.0)
	_assert_float_eq("target right duration", runner.last_call.get("duration", -999.0), 0.6)


func _test_numeric_execution() -> void:
	var handler = CameraPanHandlerClass.new()
	var runner := MockSceneRunner.new()
	var context := MockContext.new(runner)
	var command := AVGCommandClass.new("CAMERA_PAN", {
		"norm_x": -0.2,
		"norm_y": 0.1,
		"duration": 0.4,
	})
	var result = handler.execute(command, context)

	_assert_true("numeric pan execute", result.is_success(), result.error_message)
	_assert_float_eq("numeric pan norm_x", runner.last_call.get("norm_x", -999.0), -0.2)
	_assert_float_eq("numeric pan norm_y", runner.last_call.get("norm_y", -999.0), 0.1)


func _test_display_with_target() -> void:
	var display: String = CommandDisplayUtilsClass.get_command_display({
		"command_type": "CAMERA_PAN",
		"params": {
			"target": "right",
			"duration": 0.6,
		}
	})
	_assert_equal("display keeps target", display, "镜头平移 right 0.6s")


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
	_assert_true(
		label,
		(actual is int or actual is float) and is_equal_approx(float(actual), expected),
		"expected=%s actual=%s" % [str(expected), str(actual)]
	)