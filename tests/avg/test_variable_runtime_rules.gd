extends Node

const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")
const VariableManagerClass = preload("res://scripts/avg/runtime/variable_manager.gd")
const AVGSceneRunnerClass = preload("res://scripts/avg/runtime/avg_scene_runner.gd")


func _ready() -> void:
	_run_test()


func _run_test() -> void:
	var pass_count: int = 0
	var total_count: int = 7

	var int_var := AVGVariableClass.new()
	int_var.variable_id = "var_001"
	AVGVariableClass.apply_key(int_var, "score")
	int_var.value_type = AVGVariableClass.VALUE_TYPE_INT
	int_var.default_value = 0

	var string_var := AVGVariableClass.new()
	string_var.variable_id = "var_002"
	AVGVariableClass.apply_key(string_var, "ending_flag")
	string_var.value_type = AVGVariableClass.VALUE_TYPE_STRING
	string_var.default_value = ""

	var manager := VariableManagerClass.new()
	manager.initialize([int_var, string_var])

	if manager.get_value("score") == 0:
		pass_count += 1
		print("PASS  int variable default preserved")
	else:
		print("FAIL  int variable default mismatch: %s" % str(manager.get_value("score")))

	if manager.get_value("ending_flag") == "":
		pass_count += 1
		print("PASS  string variable default preserved")
	else:
		print("FAIL  string variable default mismatch: %s" % str(manager.get_value("ending_flag")))

	manager.set_value("score", 1.8)
	if manager.get_value("score") == 1:
		pass_count += 1
		print("PASS  float assignment coerces to int")
	else:
		print("FAIL  float assignment did not coerce to int: %s" % str(manager.get_value("score")))

	manager.set_value("ending_flag", "route_a")
	if manager.get_value("ending_flag") == "route_a":
		pass_count += 1
		print("PASS  string variable stores string values")
	else:
		print("FAIL  string variable did not store string: %s" % str(manager.get_value("ending_flag")))

	var runner := AVGSceneRunnerClass.new()
	if runner._compare_values("", "==", 0):
		pass_count += 1
		print("PASS  empty string compares to 0 at runtime")
	else:
		print("FAIL  empty string did not compare to 0")

	if runner._compare_values("route_a", "==", 1):
		pass_count += 1
		print("PASS  non-empty string compares to 1 at runtime")
	else:
		print("FAIL  non-empty string did not compare to 1")

	if runner._compare_values("route_a", ">", 0):
		pass_count += 1
		print("PASS  non-empty string uses 0/1 fallback for ordered compare")
	else:
		print("FAIL  non-empty string ordered compare fallback failed")

	print("SUMMARY  pass=%d fail=%d" % [pass_count, total_count - pass_count])
