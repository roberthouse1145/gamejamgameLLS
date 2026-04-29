extends Node

const LabScene = preload("res://tests/test_llm_build_pipeline_lab.tscn")
const EDITOR_RUNTIME_SETTING: String = "application/run/debug_use_runtime_project_in_editor"

var _pass_count: int = 0
var _fail_count: int = 0
var _original_editor_runtime_setting: Variant = false


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	_original_editor_runtime_setting = ProjectSettings.get_setting(EDITOR_RUNTIME_SETTING, false)
	WorkOrderManager.reset_runtime_state()
	if StorageManager.has_method("_remove_directory_recursive"):
		if DirAccess.dir_exists_absolute("user://run/trunk/"):
			StorageManager._remove_directory_recursive("user://run/trunk/")
		if DirAccess.dir_exists_absolute("user://run/player_project/"):
			StorageManager._remove_directory_recursive("user://run/player_project/")
	if StorageManager.has_method("reset_runtime_state"):
		StorageManager.reset_runtime_state()
	var mount_err: Error = StorageManager.mount_runtime_project("tutorial_project")
	_assert("mount runtime project", mount_err == OK, str(mount_err))
	await get_tree().process_frame

	var step_keys: Array[String] = ["world", "protagonist", "heroine_2"]
	for i in range(step_keys.size()):
		var order: Resource = WorkOrderManager.create_order("Step %d" % [i + 1], "pipeline resume test", {
			"source_type": "llm_build_pipeline_lab",
			"source_id": step_keys[i],
		})
		order.surface_status = "in_progress"
		order.inner_status = "ready" if i < 2 else "idle"
		order.status = "completed" if i < 2 else "failed"
		order.updated_at = int(Time.get_unix_time_from_system()) + i

	if StorageManager.has_method("reset_runtime_state"):
		StorageManager.reset_runtime_state()
	ProjectSettings.set_setting(EDITOR_RUNTIME_SETTING, true)
	if StorageManager.has_method("_auto_load_default_project"):
		StorageManager._auto_load_default_project()
	await get_tree().process_frame

	var lab: Control = LabScene.instantiate()
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame

	var snapshot: Dictionary = lab.get_pipeline_snapshot()
	_assert("resume snapshot points to third step", int(snapshot.get("next_order_index", -1)) == 2, str(snapshot))
	_assert("resume snapshot keeps active order", str(snapshot.get("active_order_id", "")).begins_with("wo_"), str(snapshot))
	_assert("resume snapshot not finished", not bool(snapshot.get("pipeline_finished", true)), str(snapshot))
	_assert("resume snapshot has three records", int(snapshot.get("record_count", 0)) == 3, str(snapshot))
	_assert("resume remounts runtime project after reboot", str(StorageManager.current_project_path) == "user://run/player_project/", str(StorageManager.current_project_path))

	ProjectSettings.set_setting(EDITOR_RUNTIME_SETTING, _original_editor_runtime_setting)
	WorkOrderManager.reset_runtime_state()
	lab.queue_free()
	_print_summary()


func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % label)
	else:
		_fail_count += 1
		if detail.is_empty():
			print("FAIL  %s" % label)
		else:
			print("FAIL  %s -- %s" % [label, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
