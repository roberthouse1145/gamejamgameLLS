extends Node

const WorkOrderAgentScene = preload("res://scenes/avg/dev_tools/work_order_agent.tscn")
const DBToolsClass = preload("res://scripts/avg/dev_tools/db_tools.gd")

const VARIABLE_KEYS: Array[String] = ["agent_tool_route_score", "agent_event_flag"]

var _pass_count: int = 0
var _fail_count: int = 0
var _agent: ChatAgent = null
var _storage: Node = null
var _work_order_manager: Node = null
var _old_worker_auto_run: bool = true
var _did_override_worker_auto_run: bool = false
var _created_event_id: String = ""
var _restored_character: Resource = null
var _original_character_fields: Dictionary = {}
var _dev_cycle_disconnected: bool = false
var _bithub_disconnected: bool = false


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== work_order game editor tools test ===")
	_storage = get_node_or_null("/root/StorageManager")
	if _storage == null:
		_fail("StorageManager autoload", "未找到 /root/StorageManager")
		_print_summary()
		return

	_disable_worker_auto_run()
	_suspend_background_dev_cycle()
	var mount_err: Error = _storage.mount_runtime_project()
	_assert("mount_runtime_project", mount_err == OK, str(mount_err))
	if mount_err != OK:
		_print_summary()
		return

	_cleanup_created_data()
	_agent = WorkOrderAgentScene.instantiate()
	_agent.name = "TestWorkOrderGameEditorTools"
	add_child(_agent)
	await get_tree().process_frame
	await get_tree().process_frame

	var service: AIService = _agent.get_node_or_null("AIService")
	_assert("agent AIService exists", service != null, "")
	if service == null:
		_print_summary()
		return

	await _test_context_and_data_tools(service)
	await _test_finish_auto_save(service)
	_print_summary()


func _test_context_and_data_tools(service: AIService) -> void:
	var context_result: Dictionary = await _call_tool(service, "get_project_context", {
		"include_project_info": true,
		"include_characters": true,
		"include_variables": true,
		"include_scene_catalog": true,
		"asset_categories": ["backgrounds", "bgm", "characters"]
	})
	_assert("get_project_context succeeds", bool(context_result.get("success", false)), str(context_result))
	var context_data: Dictionary = context_result.get("data", {})
	_assert("context includes project", context_data.has("project"), str(context_data.keys()))
	_assert("context includes characters", context_data.has("characters"), str(context_data.keys()))
	_assert("context includes variables", context_data.has("variables"), str(context_data.keys()))
	_assert("context includes scene catalog", context_data.has("scene_catalog"), str(context_data.keys()))
	_assert("context includes assets", context_data.has("assets"), str(context_data.keys()))

	var character_args: Dictionary = _build_character_probe_args()
	var character_result: Dictionary = await _call_tool(service, "upsert_character", character_args)
	_assert("upsert_character succeeds", bool(character_result.get("success", false)), str(character_result))
	var character_payload: Dictionary = character_result.get("character", {})
	_assert("upsert_character writes key", str(character_payload.get("character_key", "")) == "agent_probe_character", str(character_result))

	var variable_result: Dictionary = await _call_tool(service, "upsert_variable", {
		"variable_key": "agent_tool_route_score",
		"value_type": "int",
		"default_value": 0,
		"description": "自动测试路线分数"
	})
	_assert("upsert_variable succeeds", bool(variable_result.get("success", false)), str(variable_result))
	var variable_payload: Dictionary = variable_result.get("variable", {})
	_assert("upsert_variable writes key", str(variable_payload.get("key", "")) == "agent_tool_route_score", str(variable_result))

	var event_result: Dictionary = await _call_tool(service, "upsert_event", {
		"event_name": "Agent Tool Probe Event",
		"dsl": "var[agent_event_flag] = 1\n> 事件工具探针"
	})
	_assert("upsert_event succeeds", bool(event_result.get("success", false)), str(event_result))
	var event_payload: Dictionary = event_result.get("event", {})
	_created_event_id = str(event_payload.get("id", ""))
	_assert("upsert_event returns event id", _created_event_id.begins_with("event_"), str(event_result))
	_assert("upsert_event auto creates variable", (event_result.get("auto_created_variable_keys", []) as Array).has("agent_event_flag"), str(event_result))


func _test_finish_auto_save(service: AIService) -> void:
	WorkOrderManager.reset_runtime_state()
	var order: Resource = WorkOrderManager.create_order("Finish auto save probe", "验证 wo_finish_order 自动保存并完成", {
		"source_type": "agent_tool_test",
		"source_id": "finish_auto_save",
	})
	_assert("finish test order created", order != null, "")
	if order == null:
		return
	var finish_result: Dictionary = await _call_tool(service, "wo_finish_order", {
		"order_id": str(order.id),
		"summary": "自动保存完成测试"
	})
	_assert("wo_finish_order succeeds", bool(finish_result.get("success", false)), str(finish_result))
	var completed_order: Resource = WorkOrderManager.get_order(str(order.id))
	_assert("wo_finish_order marks completed", completed_order != null and str(completed_order.status) == "completed", str(completed_order.status if completed_order != null else "missing"))

	var fail_order: Resource = WorkOrderManager.create_order("Finish save failure probe", "验证保存失败时不完成工单", {
		"source_type": "agent_tool_test",
		"source_id": "finish_save_failure",
	})
	_assert("finish failure test order created", fail_order != null, "")
	if fail_order == null:
		return
	var previous_project: Resource = StorageManager.current_project
	StorageManager.current_project = null
	var fail_result: Dictionary = await _call_tool(service, "wo_finish_order", {
		"order_id": str(fail_order.id),
		"summary": "这次应因保存失败而拒绝完成"
	})
	StorageManager.current_project = previous_project
	_assert("wo_finish_order rejects save failure", not bool(fail_result.get("success", true)), str(fail_result))
	var not_completed_order: Resource = WorkOrderManager.get_order(str(fail_order.id))
	_assert("wo_finish_order save failure keeps order open", not_completed_order != null and str(not_completed_order.status) != "completed", str(not_completed_order.status if not_completed_order != null else "missing"))


func _build_character_probe_args() -> Dictionary:
	var project: Resource = DBToolsClass.get_project()
	var target: Resource = null
	if project != null and "characters" in project:
		for character in project.characters:
			if character != null and AVGCharacter.looks_like_template_shell(character):
				target = character
				break
		if target == null and not project.characters.is_empty():
			target = project.characters[0]
	if target != null:
		_restored_character = target
		_original_character_fields = {
			"character_key": str(target.character_key if "character_key" in target else ""),
			"character_name": str(target.character_name if "character_name" in target else ""),
			"display_name": str(target.display_name if "display_name" in target else ""),
			"profile": str(target.profile if "profile" in target else ""),
		}
		return {
			"character_id": str(target.character_id),
			"character_key": "agent_probe_character",
			"character_name": "AgentProbeCharacter",
			"display_name": "工具探针角色",
			"profile": "自动测试写入的角色简介"
		}
	return {
		"character_key": "agent_probe_character",
		"character_name": "AgentProbeCharacter",
		"display_name": "工具探针角色",
		"profile": "自动测试写入的角色简介"
	}


func _call_tool(service: AIService, tool_name: String, args: Dictionary) -> Dictionary:
	var result: Variant = await service.execute_tool_callback(tool_name, args)
	if result is Dictionary:
		return result
	return {"success": false, "error": "tool returned non-dictionary", "raw": str(result)}


func _cleanup_created_data() -> void:
	var project: Resource = DBToolsClass.get_project()
	if project == null:
		return

	if _restored_character != null and is_instance_valid(_restored_character):
		for key in _original_character_fields.keys():
			if key in _restored_character:
				_restored_character.set(key, _original_character_fields[key])

	if "variables" in project:
		for i in range(project.variables.size() - 1, -1, -1):
			var variable: Variant = project.variables[i]
			if variable == null:
				continue
			if VARIABLE_KEYS.has(AVGVariable.get_key(variable)):
				_delete_project_resource_file("variables", str(variable.variable_id if "variable_id" in variable else ""))
				project.variables.remove_at(i)

	if "events" in project:
		for i in range(project.events.size() - 1, -1, -1):
			var event: Variant = project.events[i]
			if event == null:
				continue
			var event_id: String = str(event.event_id if "event_id" in event else "")
			var event_name: String = str(event.event_name if "event_name" in event else "")
			if event_id == _created_event_id or event_name == "Agent Tool Probe Event":
				_delete_project_resource_file("events", event_id)
				project.events.remove_at(i)

	if _storage != null and _storage.current_project != null:
		_storage.save_project(_storage.current_project)
		if _storage.has_signal("project_content_changed"):
			_storage.project_content_changed.emit()


func _delete_project_resource_file(folder: String, resource_id: String) -> void:
	if resource_id.is_empty():
		return
	var path: String = "user://run/player_project/%s/%s.tres" % [folder, resource_id]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


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


func _suspend_background_dev_cycle() -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null or _work_order_manager == null:
		return
	var callback := Callable(dcm, "_on_order_status_changed")
	if _work_order_manager.order_status_changed.is_connected(callback):
		_work_order_manager.order_status_changed.disconnect(callback)
		_dev_cycle_disconnected = true
	var bithub: Node = get_node_or_null("/root/BithubManager")
	if bithub == null:
		return
	var bithub_callback := Callable(bithub, "_on_order_status_changed")
	if _work_order_manager.order_status_changed.is_connected(bithub_callback):
		_work_order_manager.order_status_changed.disconnect(bithub_callback)
		_bithub_disconnected = true


func _restore_background_dev_cycle() -> void:
	if _work_order_manager == null:
		return
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if _dev_cycle_disconnected and dcm != null:
		var callback := Callable(dcm, "_on_order_status_changed")
		if not _work_order_manager.order_status_changed.is_connected(callback):
			_work_order_manager.order_status_changed.connect(callback)
		_dev_cycle_disconnected = false
	var bithub: Node = get_node_or_null("/root/BithubManager")
	if _bithub_disconnected and bithub != null:
		var bithub_callback := Callable(bithub, "_on_order_status_changed")
		if not _work_order_manager.order_status_changed.is_connected(bithub_callback):
			_work_order_manager.order_status_changed.connect(bithub_callback)
		_bithub_disconnected = false


func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % label)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [label, detail])


func _fail(label: String, detail: String) -> void:
	_fail_count += 1
	print("FAIL  %s  %s" % [label, detail])


func _print_summary() -> void:
	_cleanup_created_data()
	WorkOrderManager.reset_runtime_state()
	if is_instance_valid(_agent):
		_agent.queue_free()
	_restore_background_dev_cycle()
	_restore_worker_auto_run()
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
