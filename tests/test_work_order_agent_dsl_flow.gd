extends Node

const WorkOrderAgentScene = preload("res://scenes/avg/dev_tools/work_order_agent.tscn")
const DBToolsClass = preload("res://scripts/avg/dev_tools/db_tools.gd")

const PROBE_PREFIXES: Array[String] = [
	"scene_agent_dsl_probe_",
	"scene_agent_create_with_dsl_",
]

var _pass_count: int = 0
var _fail_count: int = 0
var _storage: Node = null
var _agent: ChatAgent = null
var _work_order_manager: Node = null
var _old_worker_auto_run: bool = true
var _did_override_worker_auto_run: bool = false
var _scene_id: String = ""
var _direct_dsl_scene_id: String = ""


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== work_order agent DSL flow test ===")

	_storage = get_node_or_null("/root/StorageManager")
	if _storage == null:
		_fail("StorageManager autoload", "未找到 /root/StorageManager")
		_print_summary()
		return

	_disable_worker_auto_run()
	var mount_err: Error = _storage.mount_runtime_project()
	_assert("mount_runtime_project", mount_err == OK, "error=%s" % mount_err)
	if mount_err != OK:
		_print_summary()
		return
	_cleanup_probe_scenes()

	_scene_id = "scene_agent_dsl_probe_%d" % Time.get_ticks_msec()

	_agent = WorkOrderAgentScene.instantiate()
	_agent.name = "TestWorkOrderAgentDSLFlow"
	add_child(_agent)
	await get_tree().process_frame
	await get_tree().process_frame

	var agent_service: AIService = _agent.get_node_or_null("AIService")
	_assert("agent AIService exists", agent_service != null, "")
	if agent_service == null:
		_print_summary()
		return

	var tool_names: Dictionary = _collect_tool_names(agent_service.get_tools_definition())
	for required_tool in ["gather_scene_context", "db_create", "set_scene_script", "project_save", "wo_finish_order", "research"]:
		_assert("agent exposes %s" % required_tool, tool_names.has(required_tool), str(tool_names.keys()))
	_assert("agent does not expose finish", not tool_names.has("finish"), str(tool_names.keys()))

	var create_result: Dictionary = await _call_tool(agent_service, "db_create", {
		"type": "scenes",
		"fields": {
			"scene_id": _scene_id,
			"scene_name": "WorkOrderAgent DSL Probe",
			"scene_note": "自动测试：模拟底层 LLM 创建场景"
		}
	})
	_assert("step 1 create scene via agent tool", bool(create_result.get("success", false)), str(create_result))
	if not bool(create_result.get("success", false)):
		_print_summary()
		return
	_assert("step 1 returns real scene id", str(create_result.get("id", "")) == _scene_id, str(create_result))

	var open_result: Dictionary = await _call_tool(agent_service, "gather_scene_context", {
		"scene_ids": [_scene_id],
		"include_scene_catalog": true
	})
	_assert("step 2 open scene via agent context tool", bool(open_result.get("success", false)), str(open_result))
	var opened_scene: Dictionary = _first_scene_payload(open_result)
	_assert("step 2 opened scene is present", not opened_scene.is_empty() and not bool(opened_scene.get("missing", false)), str(open_result))
	_assert("step 2 opened scene starts empty", str(opened_scene.get("dsl", "")).strip_edges().is_empty(), str(opened_scene))

	var dsl: String = "\n".join([
		"screen.fade(direction=\"in\", duration=0.2)",
		"> 这是底层 LLM 写入 DSL 的探针。",
		"> 如果这行能被重新读出，说明写入链路可用。",
	])
	var set_result: Dictionary = await _call_tool(agent_service, "set_scene_script", {
		"scene_id": _scene_id,
		"mode": "replace",
		"dsl": dsl,
	})
	_assert("step 3 write DSL via agent tool", bool(set_result.get("success", false)), str(set_result))

	var verify_result: Dictionary = await _call_tool(agent_service, "gather_scene_context", {
		"scene_ids": [_scene_id]
	})
	var verify_scene: Dictionary = _first_scene_payload(verify_result)
	var verify_dsl: String = str(verify_scene.get("dsl", ""))
	_assert("step 3 DSL can be read back", verify_dsl.contains("底层 LLM 写入 DSL 的探针"), str(verify_result))

	_direct_dsl_scene_id = "scene_agent_create_with_dsl_%d" % Time.get_ticks_msec()
	var direct_create_result: Dictionary = await _call_tool(agent_service, "db_create", {
		"type": "scenes",
		"fields": {
			"scene_id": _direct_dsl_scene_id,
			"scene_name": "WorkOrderAgent Direct DSL Probe",
			"scene_note": "自动测试：模拟底层 LLM 创建场景时直接写 DSL",
			"dsl": "> 这是 db_create 直接写入 DSL 的探针。"
		}
	})
	_assert("step 3b create scene with dsl via db_create", bool(direct_create_result.get("success", false)), str(direct_create_result))

	var direct_verify_result: Dictionary = await _call_tool(agent_service, "gather_scene_context", {
		"scene_ids": [_direct_dsl_scene_id]
	})
	var direct_verify_scene: Dictionary = _first_scene_payload(direct_verify_result)
	var direct_verify_dsl: String = str(direct_verify_scene.get("dsl", ""))
	_assert("step 3b direct db_create DSL can be read back", direct_verify_dsl.contains("db_create 直接写入 DSL 的探针"), str(direct_verify_result))

	var save_result: Dictionary = await _call_tool(agent_service, "project_save", {})
	_assert("step 4 save project via agent tool", bool(save_result.get("success", false)), str(save_result))

	_print_summary()


func _call_tool(service: AIService, tool_name: String, args: Dictionary) -> Dictionary:
	if service == null:
		return {"success": false, "error": "AIService is null"}
	var result: Variant = await service.execute_tool_callback(tool_name, args)
	if result == null:
		return {"success": false, "error": "tool missing or returned null: %s" % tool_name}
	if result is Dictionary:
		return result
	return {"success": false, "error": "tool returned non-dictionary", "raw": str(result)}


func _first_scene_payload(result: Dictionary) -> Dictionary:
	var data: Dictionary = result.get("data", {})
	var scenes: Array = data.get("scenes", [])
	if scenes.is_empty():
		return {}
	var first: Variant = scenes[0]
	if first is Dictionary:
		return first
	return {}


func _collect_tool_names(tools: Array) -> Dictionary:
	var tool_names: Dictionary = {}
	for tool in tools:
		var function_def: Dictionary = tool.get("function", {})
		var tool_name: String = str(function_def.get("name", "")).strip_edges()
		if not tool_name.is_empty():
			tool_names[tool_name] = true
	return tool_names


func _cleanup_probe_scenes() -> void:
	var project: Resource = DBToolsClass.get_project()
	if project != null and "scenes" in project:
		for i in range(project.scenes.size() - 1, -1, -1):
			var scene: Variant = project.scenes[i]
			if scene == null:
				continue
			var scene_id: String = str(scene.scene_id if "scene_id" in scene else "").strip_edges()
			if _is_probe_scene_id(scene_id):
				project.scenes.remove_at(i)
				_delete_probe_scene_file(scene_id)

	_delete_probe_scene_files_by_prefix()

	if _storage != null and _storage.current_project != null:
		_storage.save_project(_storage.current_project)
		if _storage.has_signal("project_content_changed"):
			_storage.project_content_changed.emit()


func _is_probe_scene_id(scene_id: String) -> bool:
	for prefix in PROBE_PREFIXES:
		if scene_id.begins_with(prefix):
			return true
	return false


func _delete_probe_scene_file(scene_id: String) -> void:
	if scene_id.is_empty():
		return
	var path: String = "user://run/player_project/scenes/%s.tres" % scene_id
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _delete_probe_scene_files_by_prefix() -> void:
	var dir_path: String = "user://run/player_project/scenes/"
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var basename: String = file_name.get_basename()
			if _is_probe_scene_id(basename):
				DirAccess.remove_absolute(dir_path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _assert(assert_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % assert_name)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [assert_name, detail])


func _fail(assert_name: String, detail: String) -> void:
	_fail_count += 1
	print("FAIL  %s  %s" % [assert_name, detail])


func _print_summary() -> void:
	_cleanup_probe_scenes()
	if is_instance_valid(_agent):
		_agent.queue_free()
	_restore_worker_auto_run()
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])


func _disable_worker_auto_run() -> void:
	_work_order_manager = get_node_or_null("/root/WorkOrderManager")
	if _work_order_manager == null:
		return
	_old_worker_auto_run = bool(_work_order_manager.get("_worker_auto_run"))
	_work_order_manager.set("_worker_auto_run", false)
	_did_override_worker_auto_run = true


func _restore_worker_auto_run() -> void:
	if not _did_override_worker_auto_run or _work_order_manager == null:
		return
	_work_order_manager.set("_worker_auto_run", _old_worker_auto_run)
	_did_override_worker_auto_run = false
