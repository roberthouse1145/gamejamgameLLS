extends Node

const LabScene = preload("res://tests/lab/work_order/work_order_agent_tool_type_lab.tscn")
const EDITOR_RUNTIME_SETTING: String = "application/run/debug_use_runtime_project_in_editor"
const SOURCE_TYPE: String = "work_order_agent_tool_type_lab"

var _pass_count: int = 0
var _fail_count: int = 0
var _original_editor_runtime_setting: Variant = false
var _old_worker_auto_run: bool = true


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	_original_editor_runtime_setting = ProjectSettings.get_setting(EDITOR_RUNTIME_SETTING, false)
	_old_worker_auto_run = bool(WorkOrderManager.get("_worker_auto_run"))
	WorkOrderManager.set("_worker_auto_run", false)
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

	var step_keys: Array[String] = ["kb", "character", "variable_event"]
	for i in range(step_keys.size()):
		var order: Resource = WorkOrderManager.create_order("Tool type step %d" % [i + 1], "resume test", {
			"source_type": SOURCE_TYPE,
			"source_id": step_keys[i],
		})
		order.surface_status = "completed" if i < 2 else "failed"
		order.inner_status = "ready" if i < 2 else "failed"
		order.status = "completed" if i < 2 else "failed"
		order.updated_at = int(Time.get_unix_time_from_system()) + i

	if StorageManager.has_method("reset_runtime_state"):
		StorageManager.reset_runtime_state()
	ProjectSettings.set_setting(EDITOR_RUNTIME_SETTING, true)
	if StorageManager.has_method("_auto_load_default_project"):
		StorageManager._auto_load_default_project()
	await get_tree().process_frame

	var lab: Node = LabScene.instantiate()
	lab.set("auto_start", false)
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame

	var snapshot: Dictionary = lab.get_pipeline_snapshot()
	_assert("resume snapshot points to variable/event step", int(snapshot.get("next_order_index", -1)) == 2, str(snapshot))
	_assert("resume snapshot keeps active order", str(snapshot.get("active_order_id", "")).begins_with("wo_"), str(snapshot))
	_assert("resume snapshot not finished", not bool(snapshot.get("pipeline_finished", true)), str(snapshot))
	_assert("resume snapshot has three records", int(snapshot.get("record_count", 0)) == 3, str(snapshot))
	_assert("resume remounts runtime project", str(StorageManager.current_project_path) == "user://run/player_project/", str(StorageManager.current_project_path))

	ProjectSettings.set_setting(EDITOR_RUNTIME_SETTING, _original_editor_runtime_setting)
	WorkOrderManager.set("_worker_auto_run", _old_worker_auto_run)
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
