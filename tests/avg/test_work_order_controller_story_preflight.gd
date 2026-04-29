extends Node

const WorkOrderControllerScene = preload("res://scenes/avg/dev_tools/work_order_controller_agent.tscn")
const ProjectToolsClass = preload("res://scripts/avg/dev_tools/project_tools.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")
const AVGTitleConfigClass = preload("res://scripts/avg/resources/avg_title_config.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _storage: Node = null
var _controller: ChatAgent = null
var _created_temp_scene_id: String = ""
var _had_original_title_config: bool = false
var _original_first_scene_id: String = ""


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== work_order controller story preflight test ===")

	_storage = get_node_or_null("/root/StorageManager")
	if _storage == null:
		_fail("StorageManager autoload", "未找到 /root/StorageManager")
		_print_summary()
		return

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

	_controller = WorkOrderControllerScene.instantiate()
	_controller.name = "TestWorkOrderControllerStoryPreflight"
	add_child(_controller)
	await get_tree().process_frame
	await get_tree().process_frame

	var tool_names: Dictionary = {}
	var tools: Array = _controller.get_node("AIService").get_tools_definition()
	for tool in tools:
		var function_def: Dictionary = tool.get("function", {})
		var tool_name: String = str(function_def.get("name", "")).strip_edges()
		if not tool_name.is_empty():
			tool_names[tool_name] = true

	_assert("controller has set_initial_scene", tool_names.has("set_initial_scene"), str(tool_names.keys()))
	_assert("controller has analyze_story_reachability", tool_names.has("analyze_story_reachability"), str(tool_names.keys()))

	var writer_tool_names: Dictionary = _collect_tool_names(_controller.get_node("WriterAgent/AIService").get_tools_definition())
	_assert("writer has gather_scene_context", writer_tool_names.has("gather_scene_context"), str(writer_tool_names.keys()))
	_assert("writer hides kb_read", not writer_tool_names.has("kb_read"), str(writer_tool_names.keys()))
	_assert("writer hides db_list", not writer_tool_names.has("db_list"), str(writer_tool_names.keys()))
	_assert("writer hides db_get", not writer_tool_names.has("db_get"), str(writer_tool_names.keys()))
	_assert("writer hides get_scene_script", not writer_tool_names.has("get_scene_script"), str(writer_tool_names.keys()))
	_assert("writer hides list_assets", not writer_tool_names.has("list_assets"), str(writer_tool_names.keys()))

	var executor_tool_names: Dictionary = _collect_tool_names(_controller.get_node("ExecutorAgent/AIService").get_tools_definition())
	_assert("executor has gather_scene_context", executor_tool_names.has("gather_scene_context"), str(executor_tool_names.keys()))
	_assert("executor has batch_patch_scene_scripts", executor_tool_names.has("batch_patch_scene_scripts"), str(executor_tool_names.keys()))
	_assert("executor hides db_list", not executor_tool_names.has("db_list"), str(executor_tool_names.keys()))
	_assert("executor hides db_get", not executor_tool_names.has("db_get"), str(executor_tool_names.keys()))
	_assert("executor hides get_scene_script", not executor_tool_names.has("get_scene_script"), str(executor_tool_names.keys()))
	_assert("executor hides list_assets", not executor_tool_names.has("list_assets"), str(executor_tool_names.keys()))

	var target_scene_id: String = _pick_target_scene_id(project)
	_assert("target scene selected", not target_scene_id.is_empty(), "")
	if target_scene_id.is_empty():
		_print_summary()
		return

	var set_result: Dictionary = ProjectToolsClass._set_initial_scene({"scene_id": target_scene_id})
	_assert("set_initial_scene success", bool(set_result.get("success", false)), str(set_result))
	_assert("title_config updated", project.title_config != null and str(project.title_config.first_scene_id) == target_scene_id, str(project.title_config.first_scene_id if project.title_config != null and "first_scene_id" in project.title_config else ""))

	var info_result: Dictionary = ProjectToolsClass._project_info({})
	var info_data: Dictionary = info_result.get("data", {})
	_assert("project_info reflects initial scene", str(info_data.get("initial_scene_id", "")) == target_scene_id, str(info_result))

	var reachability_result: Dictionary = ProjectToolsClass._analyze_story_reachability({})
	_assert("reachability analysis callable", bool(reachability_result.get("success", false)), str(reachability_result))

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
	temp_scene.scene_note = "仅用于 controller 初始场景测试"

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

	if is_instance_valid(_controller):
		_controller.queue_free()


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
