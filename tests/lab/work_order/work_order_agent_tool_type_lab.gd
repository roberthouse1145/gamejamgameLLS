extends Node
## Real LLM lab: one representative WorkOrderAgent order per high-level tool type.
##
## This scene sends real LLM requests when auto_start is true. It will not auto-exit.

const TEMPLATE_NAME: String = "tutorial_project"
const RUNTIME_PLAYER_PROJECT_PATH: String = "user://run/player_project/"
const RUNTIME_TRUNK_PATH: String = "user://run/trunk/"
const RESULT_TIMEOUT_MS: int = 300000
const HEARTBEAT_MS: int = 10000
const SOURCE_TYPE: String = "work_order_agent_tool_type_lab"
const KB_DOC_ID: String = "wo_tool_type_world_note"
const CHARACTER_KEY: String = "agent_lab_hero"
const CHARACTER_NAME: String = "AgentLabHero"
const VARIABLE_KEY: String = "agent_lab_route_score"
const EVENT_NAME: String = "Agent Lab Route Event"
const ENTRY_SCENE_ID: String = "scene_agent_lab_single"
const BRANCH_A_SCENE_ID: String = "scene_agent_lab_branch_a"
const BRANCH_B_SCENE_ID: String = "scene_agent_lab_branch_b"

var auto_start: bool = true

var _pass_count: int = 0
var _fail_count: int = 0
var _active_order_id: String = ""
var _next_order_index: int = 0
var _pipeline_finished: bool = false
var _order_records: Array[Dictionary] = []
var _tool_events: Array[Dictionary] = []
var _connected_worker_instances: Dictionary = {}
var _old_worker_auto_run: bool = true
var _dev_cycle_disconnected: bool = false
var _bithub_disconnected: bool = false

var _order_definitions: Array[Dictionary] = [
	{
		"key": "kb",
		"title": "类型抽样：KB 设定文档",
		"description": "请完成 KB 类工单：使用 kb_write 创建或更新 doc_id=%s，category=world，tags 包含 tool_type_lab。内容写一份很短的校园奇幻 AVG 世界规则，必须包含短语 TOOL_TYPE_KB_MARKER。完成后调用 wo_finish_order。" % KB_DOC_ID,
	},
	{
		"key": "character",
		"title": "类型抽样：角色项目数据",
		"description": "请完成角色/项目数据类工单：使用 upsert_character 绑定或更新一名角色，character_key=%s，character_name=%s，display_name=工具测试主角，profile 中必须包含 TOOL_TYPE_CHARACTER_MARKER。不要写场景 DSL。完成后调用 wo_finish_order。" % [CHARACTER_KEY, CHARACTER_NAME],
	},
	{
		"key": "variable_event",
		"title": "类型抽样：变量与事件",
		"description": "请完成变量/事件类工单：使用 upsert_variable 创建或更新变量 variable_key=%s，value_type=int，default_value=0；再使用 upsert_event 创建一个名为 %s 的轻量事件，事件 DSL 里让 var[%s] += 1，并包含一行旁白文本 TOOL_TYPE_EVENT_MARKER。marker 必须写进 `>` 旁白或对白文本，不要放在 # 注释里，因为注释不会保留到可读 DSL。完成后调用 wo_finish_order。" % [VARIABLE_KEY, EVENT_NAME, VARIABLE_KEY],
	},
	{
		"key": "single_scene",
		"title": "类型抽样：单场景 DSL",
		"description": "请完成单场景 DSL 类工单：使用 upsert_scene 创建或更新 scene_id=%s，设为初始场景。DSL 必须包含一行可序列化旁白或对白文本 TOOL_TYPE_SCENE_MARKER、一段对白、一个 ChoiceBlock 或选择结构、对 var[%s] 的变化，并让两个选择分别跳转到 %s 和 %s。marker 必须写进 `>` 文本，不要放在 # 注释里，因为注释不会保留到可读 DSL。完成后调用 wo_finish_order。" % [ENTRY_SCENE_ID, VARIABLE_KEY, BRANCH_A_SCENE_ID, BRANCH_B_SCENE_ID],
	},
	{
		"key": "batch_integration",
		"title": "类型抽样：批量整合",
		"description": "请完成批量/整合类工单：使用 edit_scenes 批量 replace 两个已存在的占位场景 %s 和 %s。两个场景都要有可运行 DSL，分别包含可序列化旁白或对白文本 TOOL_TYPE_BRANCH_A_MARKER 与 TOOL_TYPE_BRANCH_B_MARKER。marker 必须写进 `>` 文本，不要放在 # 注释里，因为注释不会保留到可读 DSL。include_reachability=true，修掉明显断链。完成后调用 wo_finish_order。" % [BRANCH_A_SCENE_ID, BRANCH_B_SCENE_ID],
	},
]


func _ready() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	if not auto_start:
		_sync_pipeline_from_existing_orders()
		return
	await _run_real_lab()


func _run_real_lab() -> void:
	print("\n=== WorkOrderAgent Tool Type Real LLM Lab ===")
	print("This lab sends real LLM requests. It will not auto-exit.")
	if not _check_ai_config():
		_print_summary()
		return

	_old_worker_auto_run = bool(WorkOrderManager.get("_worker_auto_run"))
	WorkOrderManager.set("_worker_auto_run", true)
	_suspend_background_dev_cycle()

	var mounted: bool = await _reset_runtime_project()
	_assert("runtime project mounted", mounted, str(StorageManager.current_project_path))
	if not mounted:
		_restore_lab_state()
		_print_summary()
		return

	for i in range(_order_definitions.size()):
		_next_order_index = i
		var spec: Dictionary = _order_definitions[i]
		var order: Resource = WorkOrderManager.create_order(str(spec.get("title", "")), str(spec.get("description", "")), {
			"source_type": SOURCE_TYPE,
			"source_id": str(spec.get("key", "")),
			"assignee_npc_id": "npc_lin_xia",
		})
		_assert("created order %s" % str(spec.get("key", "")), order != null, "")
		if order == null:
			break

		_active_order_id = str(order.id)
		_order_records.append({"order_id": _active_order_id, "step_key": str(spec.get("key", "")), "title": str(order.title)})
		print("[LAB] dispatching %d/%d: %s" % [i + 1, _order_definitions.size(), str(order.title)])
		var dispatch_ok: bool = WorkOrderManager.dispatch_order(_active_order_id, 1, 1)
		_assert("dispatch order %s" % str(spec.get("key", "")), dispatch_ok, "")
		if not dispatch_ok:
			break

		var outcome: String = await _wait_for_order_outcome(_active_order_id)
		_assert("order %s completed" % str(spec.get("key", "")), outcome == "completed", outcome)
		if outcome != "completed":
			break
		_active_order_id = ""

	_pipeline_finished = _next_order_index >= _order_definitions.size() - 1 and _active_order_id.is_empty()
	_verify_observable_outputs()
	_restore_lab_state()
	_print_summary()


func _check_ai_config() -> bool:
	var config: Dictionary = AIConfigManager.get_instance().get_config_for_role("work_order_agent")
	if config.is_empty():
		config = AIConfigManager.get_instance().get_config_for_role("work_order")
	if config.is_empty():
		_fail("AI config exists", "missing work_order_agent/work_order config")
		return false
	var ok: bool = not str(config.get("base_url", "")).is_empty() and not str(config.get("model", "")).is_empty() and not str(config.get("api_key", "")).is_empty()
	_assert("AI config complete", ok, JSON.stringify(config))
	return ok


func _reset_runtime_project() -> bool:
	WorkOrderManager.reset_runtime_state()
	if ChatManager != null and ChatManager.has_method("reset_runtime_state"):
		ChatManager.reset_runtime_state(false)
	if StorageManager != null and StorageManager.has_method("discard_trunk"):
		StorageManager.discard_trunk()
	if StorageManager != null and StorageManager.has_method("_remove_directory_recursive"):
		if DirAccess.dir_exists_absolute(RUNTIME_TRUNK_PATH):
			StorageManager._remove_directory_recursive(RUNTIME_TRUNK_PATH)
		if DirAccess.dir_exists_absolute(RUNTIME_PLAYER_PROJECT_PATH):
			StorageManager._remove_directory_recursive(RUNTIME_PLAYER_PROJECT_PATH)
	if StorageManager != null and StorageManager.has_method("reset_runtime_state"):
		StorageManager.reset_runtime_state()

	var mount_err: Error = StorageManager.mount_runtime_project(TEMPLATE_NAME)
	await get_tree().process_frame
	await get_tree().process_frame
	return mount_err == OK and StorageManager.current_project != null and str(StorageManager.current_project_path).begins_with(RUNTIME_PLAYER_PROJECT_PATH)


func _wait_for_order_outcome(order_id: String) -> String:
	var deadline: int = Time.get_ticks_msec() + RESULT_TIMEOUT_MS
	var next_heartbeat: int = Time.get_ticks_msec() + HEARTBEAT_MS
	while Time.get_ticks_msec() <= deadline:
		_connect_worker_signals(order_id)
		var order: Resource = WorkOrderManager.get_order(order_id)
		if order == null:
			return "missing"
		var status: String = str(order.status)
		if status in ["completed", "failed", "needs_input"]:
			return status
		if Time.get_ticks_msec() >= next_heartbeat:
			var agents: Dictionary = WorkOrderManager.get("_worker_agents")
			print("[LAB] waiting: order=%s status=%s inner=%s worker=%s tools=%d" % [
				order_id,
				status,
				str(order.inner_status),
				str(agents.has(order_id)),
				_tool_events.size(),
			])
			next_heartbeat = Time.get_ticks_msec() + HEARTBEAT_MS
		await get_tree().process_frame
	return "timeout"


func _connect_worker_signals(order_id: String) -> void:
	var agents: Dictionary = WorkOrderManager.get("_worker_agents")
	if not agents.has(order_id):
		return
	var worker: ChatAgent = agents.get(order_id)
	if worker == null or not is_instance_valid(worker):
		return
	var instance_key: String = str(worker.get_instance_id())
	if _connected_worker_instances.has(instance_key):
		return
	_connected_worker_instances[instance_key] = true
	worker.log_entry.connect(func(entry: Dictionary) -> void:
		var content: String = str(entry.get("content", "")).strip_edges()
		if not content.is_empty():
			print("[WORKER] %s" % content.left(1000))
	)
	worker.tool_executed.connect(func(_req_id: String, tool_name: String, args: Dictionary, result: Variant, _tool_call_id: String) -> void:
		_tool_events.append({
			"name": tool_name,
			"args": args.duplicate(true),
			"success": bool(result.get("success", false)) if result is Dictionary else false,
		})
		print("[TOOL] %s args=%s success=%s" % [
			tool_name,
			JSON.stringify(args),
			str(bool(result.get("success", false)) if result is Dictionary else false),
		])
	)


func _verify_observable_outputs() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	_assert("KB manager available", kb != null, "")
	if kb != null:
		var doc: Dictionary = kb.get_document(KB_DOC_ID)
		_assert("KB doc created", not doc.is_empty(), str(kb.documents))
		_assert("KB doc marker present", str(doc.get("content", "")).contains("TOOL_TYPE_KB_MARKER"), str(doc.get("content", "")).left(300))
		var doc_path: String = StorageManager.current_project_path.path_join("knowledge_base").path_join("docs").path_join(KB_DOC_ID + ".json")
		_assert("KB doc persisted", FileAccess.file_exists(doc_path), doc_path)

	var project: Resource = StorageManager.current_project
	_assert("project exists", project != null, "")
	if project == null:
		return

	var character: Resource = _find_character_by_key(project, CHARACTER_KEY)
	_assert("character bound", character != null, "")
	if character != null:
		_assert("character profile marker", str(character.profile if "profile" in character else "").contains("TOOL_TYPE_CHARACTER_MARKER"), str(character.profile if "profile" in character else ""))

	var variable: Resource = AVGDevDBTools._find_variable_by_key(project, VARIABLE_KEY)
	_assert("route variable exists", variable != null, "")
	var event: Resource = _find_event_by_name(project, EVENT_NAME)
	_assert("event exists", event != null, "")

	var entry_scene: Resource = AVGDevDBTools._find_item_by_id(project.scenes, "scene_id", ENTRY_SCENE_ID)
	var branch_a: Resource = AVGDevDBTools._find_item_by_id(project.scenes, "scene_id", BRANCH_A_SCENE_ID)
	var branch_b: Resource = AVGDevDBTools._find_item_by_id(project.scenes, "scene_id", BRANCH_B_SCENE_ID)
	_assert("entry scene exists", entry_scene != null, "")
	_assert("branch A scene exists", branch_a != null, "")
	_assert("branch B scene exists", branch_b != null, "")
	if entry_scene != null:
		_assert("entry scene marker", AVGDevDBTools.get_root_dsl(entry_scene, project).contains("TOOL_TYPE_SCENE_MARKER"), AVGDevDBTools.get_root_dsl(entry_scene, project))
	if branch_a != null:
		_assert("branch A marker", AVGDevDBTools.get_root_dsl(branch_a, project).contains("TOOL_TYPE_BRANCH_A_MARKER"), AVGDevDBTools.get_root_dsl(branch_a, project))
	if branch_b != null:
		_assert("branch B marker", AVGDevDBTools.get_root_dsl(branch_b, project).contains("TOOL_TYPE_BRANCH_B_MARKER"), AVGDevDBTools.get_root_dsl(branch_b, project))

	var reachability: Dictionary = AVGDevProjectTools._analyze_story_reachability({})
	_assert("reachability runs", bool(reachability.get("success", false)), str(reachability))
	if bool(reachability.get("success", false)):
		var unreachable_ids: Array[String] = _extract_unreachable_ids(reachability.get("data", {}).get("unreachable_scenes", []))
		_assert("entry/branch scenes reachable", not unreachable_ids.has(ENTRY_SCENE_ID) and not unreachable_ids.has(BRANCH_A_SCENE_ID) and not unreachable_ids.has(BRANCH_B_SCENE_ID), str(unreachable_ids))


func _sync_pipeline_from_existing_orders() -> void:
	_order_records.clear()
	_active_order_id = ""
	_next_order_index = 0
	_pipeline_finished = false

	var by_key: Dictionary = {}
	for order in WorkOrderManager.get_all_orders():
		if order == null or str(order.source_type) != SOURCE_TYPE:
			continue
		by_key[str(order.source_id)] = order

	var first_unfinished: int = -1
	for i in range(_order_definitions.size()):
		var key: String = str(_order_definitions[i].get("key", ""))
		if not by_key.has(key):
			if first_unfinished < 0:
				first_unfinished = i
			continue
		var order: Resource = by_key[key]
		_order_records.append({"order_id": str(order.id), "step_key": key, "title": str(order.title)})
		if str(order.status) != "completed" and first_unfinished < 0:
			first_unfinished = i
			_active_order_id = str(order.id)

	if first_unfinished < 0:
		_next_order_index = _order_definitions.size()
		_pipeline_finished = true
	else:
		_next_order_index = first_unfinished


func get_pipeline_snapshot() -> Dictionary:
	return {
		"active_order_id": _active_order_id,
		"next_order_index": _next_order_index,
		"pipeline_finished": _pipeline_finished,
		"record_count": _order_records.size(),
		"order_count": _order_definitions.size(),
	}


func _find_character_by_key(project: Resource, character_key: String) -> Resource:
	if project == null or not ("characters" in project):
		return null
	var normalized: String = AVGCharacter.normalize_character_key(character_key)
	for character in project.characters:
		if character != null and AVGCharacter.normalize_character_key(str(character.character_key if "character_key" in character else "")) == normalized:
			return character
	return null


func _find_event_by_name(project: Resource, event_name: String) -> Resource:
	if project == null or not ("events" in project):
		return null
	for event in project.events:
		if event != null and str(event.event_name if "event_name" in event else "") == event_name:
			return event
	return null


func _extract_unreachable_ids(rows: Array) -> Array[String]:
	var ids: Array[String] = []
	for row in rows:
		if row is Dictionary:
			var scene_id: String = str(row.get("scene_id", "")).strip_edges()
			if not scene_id.is_empty():
				ids.append(scene_id)
	return ids


func _suspend_background_dev_cycle() -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null:
		var callback := Callable(dcm, "_on_order_status_changed")
		if WorkOrderManager.order_status_changed.is_connected(callback):
			WorkOrderManager.order_status_changed.disconnect(callback)
			_dev_cycle_disconnected = true
	var bithub: Node = get_node_or_null("/root/BithubManager")
	if bithub != null:
		var bithub_callback := Callable(bithub, "_on_order_status_changed")
		if WorkOrderManager.order_status_changed.is_connected(bithub_callback):
			WorkOrderManager.order_status_changed.disconnect(bithub_callback)
			_bithub_disconnected = true


func _restore_lab_state() -> void:
	WorkOrderManager.set("_worker_auto_run", _old_worker_auto_run)
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if _dev_cycle_disconnected and dcm != null:
		var callback := Callable(dcm, "_on_order_status_changed")
		if not WorkOrderManager.order_status_changed.is_connected(callback):
			WorkOrderManager.order_status_changed.connect(callback)
	_dev_cycle_disconnected = false
	var bithub: Node = get_node_or_null("/root/BithubManager")
	if _bithub_disconnected and bithub != null:
		var bithub_callback := Callable(bithub, "_on_order_status_changed")
		if not WorkOrderManager.order_status_changed.is_connected(bithub_callback):
			WorkOrderManager.order_status_changed.connect(bithub_callback)
	_bithub_disconnected = false


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


func _fail(label: String, detail: String) -> void:
	_fail_count += 1
	print("FAIL  %s -- %s" % [label, detail])


func _print_summary() -> void:
	print("\n========== WorkOrderAgent Tool Type Lab Summary ==========")
	print("snapshot: %s" % JSON.stringify(get_pipeline_snapshot()))
	print("tool_events: %s" % JSON.stringify(_tool_events))
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
	print("[DONE] Tool type lab completed. Stop the project manually.")
