extends Node

const WorkOrderAgentScene = preload("res://scenes/avg/dev_tools/work_order_agent.tscn")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")
const AVGTitleConfigClass = preload("res://scripts/avg/resources/avg_title_config.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _storage: Node = null
var _agent: ChatAgent = null
var _work_order_manager: Node = null
var _old_worker_auto_run: bool = true
var _did_override_worker_auto_run: bool = false
var _created_temp_scene_id: String = ""
var _had_original_title_config: bool = false
var _original_first_scene_id: String = ""


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== work_order agent tool surface test ===")

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

	var project: Resource = _storage.current_project
	_assert("current_project exists", project != null, "")
	if project == null:
		_print_summary()
		return

	_had_original_title_config = "title_config" in project and project.title_config != null
	if _had_original_title_config:
		_original_first_scene_id = str(project.title_config.first_scene_id if "first_scene_id" in project.title_config else "").strip_edges()

	_agent = WorkOrderAgentScene.instantiate()
	_agent.name = "TestWorkOrderAgentToolSurface"
	add_child(_agent)
	await get_tree().process_frame
	await get_tree().process_frame

	var tool_names: Dictionary = _collect_tool_names(_agent.get_node("AIService").get_tools_definition())
	for required_tool in [
		"kb_read", "kb_write", "get_project_context", "upsert_scene",
		"edit_scenes", "upsert_character", "upsert_variable", "upsert_event",
		"import_project_asset", "wo_finish_order", "research",
	]:
		_assert("agent has %s" % required_tool, tool_names.has(required_tool), str(tool_names.keys()))

	for hidden_tool in [
		"finish", "db_create", "db_update", "db_delete", "get_scene_script",
		"set_scene_script", "batch_patch_scene_scripts", "project_save",
		"preview_scene", "kb_delete", "wo_complete_task", "wo_get_order_details",
		"list_assets", "project_info", "analyze_story_reachability",
	]:
		_assert("agent hides %s" % hidden_tool, not tool_names.has(hidden_tool), str(tool_names.keys()))

	_assert("agent has no PlannerAgent child", _agent.get_node_or_null("PlannerAgent") == null, "")
	_assert("agent has no WriterAgent child", _agent.get_node_or_null("WriterAgent") == null, "")
	_assert("agent has no ExecutorAgent child", _agent.get_node_or_null("ExecutorAgent") == null, "")

	var target_scene_id: String = _pick_target_scene_id(project)
	_assert("target scene selected", not target_scene_id.is_empty(), "")
	if target_scene_id.is_empty():
		_print_summary()
		return

	var agent_service: AIService = _agent.get_node("AIService")
	var set_result: Dictionary = await _call_tool(agent_service, "upsert_scene", {
		"scene_id": target_scene_id,
		"set_as_initial": true,
		"include_reachability": true,
	})
	_assert("upsert_scene set_as_initial success", bool(set_result.get("success", false)), str(set_result))
	_assert("title_config updated", project.title_config != null and str(project.title_config.first_scene_id) == target_scene_id, str(project.title_config.first_scene_id if project.title_config != null and "first_scene_id" in project.title_config else ""))

	var info_result: Dictionary = await _call_tool(agent_service, "get_project_context", {
		"include_project_info": true,
		"include_reachability": true,
	})
	var context_data: Dictionary = info_result.get("data", {})
	var info_data: Dictionary = context_data.get("project", {})
	_assert("get_project_context reflects initial scene", str(info_data.get("initial_scene_id", "")) == target_scene_id, str(info_result))

	var reachability_data: Dictionary = context_data.get("reachability", {})
	_assert("get_project_context reachability callable", bool(info_result.get("success", false)) and not reachability_data.is_empty(), str(info_result))

	_restore_project()
	_print_summary()


func _pick_target_scene_id(project: Resource) -> String:
	if project == null or not ("scenes" in project):
		return ""

	for scene in project.scenes:
		if scene == null:
			continue
		var scene_id: String = str(scene.scene_id if "scene_id" in scene else "").strip_edges()
		if scene_id.is_empty():
			continue
		if scene_id != _original_first_scene_id:
			return scene_id

	var temp_scene := AVGSceneClass.new()
	temp_scene.scene_id = "scene_999998"
	temp_scene.scene_name = "测试开场切换"
	temp_scene.scene_note = "仅用于 WorkOrderAgent 初始场景测试"

	var root := AVGRootNodeClass.new()
	root.node_id = "node_001"
	root.node_name = "Root"
	root.command_tabs = [{
		"mode": 0,
		"condition_type": 0,
		"commands": [],
		"condition_commands": [],
	}]
	temp_scene.nodes = [root]
	project.scenes.append(temp_scene)
	_created_temp_scene_id = temp_scene.scene_id
	return _created_temp_scene_id


func _collect_tool_names(tools: Array) -> Dictionary:
	var tool_names: Dictionary = {}
	for tool in tools:
		var function_def: Dictionary = tool.get("function", {})
		var tool_name: String = str(function_def.get("name", "")).strip_edges()
		if not tool_name.is_empty():
			tool_names[tool_name] = true
	return tool_names


func _call_tool(service: AIService, tool_name: String, args: Dictionary) -> Dictionary:
	if service == null:
		return {"success": false, "error": "AIService is null"}
	var result: Variant = await service.execute_tool_callback(tool_name, args)
	if result is Dictionary:
		return result
	return {"success": false, "error": "tool returned non-dictionary", "raw": str(result)}


func _restore_project() -> void:
	if _storage == null or _storage.current_project == null:
		return

	var project: Resource = _storage.current_project
	if _created_temp_scene_id != "":
		for i in range(project.scenes.size() - 1, -1, -1):
			var scene: Variant = project.scenes[i]
			if scene == null:
				continue
			var scene_id: String = str(scene.scene_id if "scene_id" in scene else "").strip_edges()
			if scene_id == _created_temp_scene_id:
				project.scenes.remove_at(i)
				break

	if _had_original_title_config:
		if project.title_config == null:
			project.title_config = AVGTitleConfigClass.new()
		project.title_config.first_scene_id = _original_first_scene_id
	else:
		project.title_config = null

	_storage.save_project(project)
	if _storage.has_signal("project_content_changed"):
		_storage.project_content_changed.emit()

	if is_instance_valid(_agent):
		_agent.queue_free()
	_restore_worker_auto_run()


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
	_restore_project()
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
