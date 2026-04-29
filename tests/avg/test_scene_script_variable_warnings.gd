extends Node

const DBToolsClass = preload("res://scripts/avg/dev_tools/db_tools.gd")
const ScriptToolsClass = preload("res://scripts/avg/dev_tools/script_tools.gd")
const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var storage: Node = get_node_or_null("/root/StorageManager")
	if storage == null:
		print("[FAIL] scene_script_variable_warnings missing StorageManager")
		return

	if storage.has_method("_remove_directory_recursive"):
		if DirAccess.dir_exists_absolute("user://run/trunk/"):
			storage._remove_directory_recursive("user://run/trunk/")
		if DirAccess.dir_exists_absolute("user://run/player_project/"):
			storage._remove_directory_recursive("user://run/player_project/")
	if storage.has_method("reset_runtime_state"):
		storage.reset_runtime_state()

	var mount_err: Error = storage.mount_runtime_project("tutorial_project")
	if mount_err != OK:
		print("[FAIL] Failed to mount runtime project: %s" % mount_err)
		return

	var unique_suffix: String = str(Time.get_ticks_msec())
	var scene_id: String = "scene_variable_warning_%s" % unique_suffix
	var variable_key: String = "ending_flag_%s" % unique_suffix
	var create_result: Dictionary = DBToolsClass._db_create({
		"type": "scenes",
		"fields": {
			"scene_id": scene_id,
			"scene_name": "Variable Warning Probe",
		}
	})

	var set_result: Dictionary = {}
	if bool(create_result.get("success", false)):
		set_result = ScriptToolsClass._set_scene_script({
			"scene_id": scene_id,
			"mode": "replace",
			"dsl": "var[%s] = \"route_a\"\nif var[%s] == 1:\n    > 命中" % [variable_key, variable_key],
		})

	var variable: Resource = _find_variable_by_key(storage.current_project, variable_key)
	var message: String = str(set_result.get("message", ""))
	var warning_hit: bool = message.contains("把 string 变量 `%s` 和 int 做比较" % variable_key)
	var type_inferred: bool = variable != null and AVGVariableClass.get_value_type(variable) == AVGVariableClass.VALUE_TYPE_STRING

	var pass_count: int = 0
	if bool(create_result.get("success", false)):
		pass_count += 1
		print("PASS  probe scene created")
	else:
		print("FAIL  probe scene creation failed: %s" % str(create_result))

	if bool(set_result.get("success", false)):
		pass_count += 1
		print("PASS  set_scene_script accepted string variable DSL")
	else:
		print("FAIL  set_scene_script failed: %s" % str(set_result))

	if type_inferred:
		pass_count += 1
		print("PASS  auto-created variable inferred as string")
	else:
		print("FAIL  auto-created variable type mismatch")

	if warning_hit:
		pass_count += 1
		print("PASS  mixed string/int compare warning returned")
	else:
		print("FAIL  mixed string/int compare warning missing: %s" % message)

	print("SUMMARY  pass=%d fail=%d" % [pass_count, 4 - pass_count])


func _find_variable_by_key(project: Resource, variable_key: String) -> Resource:
	if project == null or not ("variables" in project):
		return null
	for variable in project.variables:
		if variable == null:
			continue
		if AVGVariableClass.get_key(variable) == variable_key:
			return variable
	return null
