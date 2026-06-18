extends Node
## 真实 LLM 验收：WorkOrderAgent 能否读取内部材料、写 KB、保存并完成工单。
##
## 该场景会实际调用 ai_config.cfg 中 work_order_agent/work_order 配置的 LLM。
## 结束后不会自动退出，请通过 MCP stop_project 停止。

const TEMPLATE_NAME: String = "tutorial_project"
const RUNTIME_PLAYER_PROJECT_PATH: String = "user://run/player_project/"
const RUNTIME_TRUNK_PATH: String = "user://run/trunk/"
const MATERIAL_DOC_ID: String = "wo_agent_llm_e2e_material"
const RESULT_DOC_ID: String = "wo_agent_llm_e2e_result"
const RESULT_TIMEOUT_MS: int = 240000
const HEARTBEAT_MS: int = 10000

var _pass_count: int = 0
var _fail_count: int = 0
var _order_id: String = ""
var _marker: String = ""
var _tool_events: Array[Dictionary] = []
var _connected_worker_instances: Dictionary = {}
var _old_worker_auto_run: bool = true
var _dev_cycle_disconnected: bool = false


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== WorkOrderAgent Real LLM E2E Lab ===")
	print("This lab sends a real LLM request. It will not auto-exit.")

	if not _check_ai_config():
		_print_summary()
		return

	_old_worker_auto_run = bool(WorkOrderManager.get("_worker_auto_run"))
	WorkOrderManager.set("_worker_auto_run", true)
	_suspend_background_dev_cycle()

	var mount_ok: bool = await _reset_runtime_project()
	_assert("runtime project mounted", mount_ok, str(StorageManager.current_project_path))
	if not mount_ok:
		_restore_lab_state()
		_print_summary()
		return

	_seed_internal_material()
	var order: Resource = _create_probe_order()
	_assert("probe order created", order != null, "")
	if order == null:
		_restore_lab_state()
		_print_summary()
		return

	_order_id = str(order.id)
	print("[LAB] dispatching order: %s" % _order_id)
	var dispatch_ok: bool = WorkOrderManager.dispatch_order(_order_id, 1, 1)
	_assert("dispatch order starts real worker", dispatch_ok, "")
	if not dispatch_ok:
		_restore_lab_state()
		_print_summary()
		return

	var outcome: String = await _wait_for_order_outcome(_order_id)
	print("[LAB] order outcome: %s" % outcome)
	_assert("order completed", outcome == "completed", outcome)

	_verify_result_document()
	_verify_tool_trace()
	_restore_lab_state()
	_print_summary()


func _check_ai_config() -> bool:
	var config: Dictionary = AIConfigManager.get_instance().get_config_for_role("work_order_agent")
	if config.is_empty():
		config = AIConfigManager.get_instance().get_config_for_role("work_order")
	if config.is_empty():
		print("[FAIL] missing AI config for work_order_agent/work_order")
		_fail_count += 1
		return false

	var base_url: String = str(config.get("base_url", ""))
	var model: String = str(config.get("model", ""))
	var api_key: String = str(config.get("api_key", ""))
	print("[LAB] AI config: base_url=%s model=%s api_key_present=%s" % [
		base_url,
		model,
		str(not api_key.is_empty()),
	])
	if base_url.is_empty() or model.is_empty() or api_key.is_empty():
		print("[FAIL] AI config incomplete")
		_fail_count += 1
		return false
	return true


func _reset_runtime_project() -> bool:
	if WorkOrderManager != null and WorkOrderManager.has_method("reset_runtime_state"):
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
	if mount_err != OK:
		print("[LAB] mount_runtime_project failed: %s" % error_string(mount_err))
		return false
	return StorageManager.current_project != null and str(StorageManager.current_project_path).begins_with(RUNTIME_PLAYER_PROJECT_PATH)


func _seed_internal_material() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null:
		return

	kb.delete_document(MATERIAL_DOC_ID)
	kb.delete_document(RESULT_DOC_ID)

	_marker = "WO_AGENT_E2E_MARKER_%d" % Time.get_ticks_msec()
	var padding: String = "这段文字只是为了把验收标记放到项目索引预览之外。".repeat(8)
	var material: String = "\n".join([
		"# WorkOrderAgent 真实 LLM 验收材料",
		"目标文档 ID：%s" % RESULT_DOC_ID,
		"目标分类：notes",
		"目标标签：work_order_agent, llm_e2e",
		"",
		padding,
		"",
		"验收标记：%s" % _marker,
		"",
		"执行要求：读取本材料后，创建或更新目标文档。目标文档内容必须原样包含验收标记，并用一两句话说明你已经读到了内部材料。写入后调用 wo_finish_order，它会自动保存项目。",
	])
	kb.upsert_document(
		MATERIAL_DOC_ID,
		"WorkOrderAgent 真实 LLM 验收材料",
		material,
		"notes",
		["work_order_agent", "llm_e2e", "material"],
		"codex"
	)
	kb.save_data()
	print("[LAB] seeded material doc: %s" % MATERIAL_DOC_ID)
	print("[LAB] hidden marker: %s" % _marker)


func _create_probe_order() -> Resource:
	return WorkOrderManager.create_order(
		"真实 LLM 验收：读取内部材料并写入结果文档",
		"\n".join([
			"请完成一次最小但真实的后台工单验收。",
			"1. 使用 kb_read 精确读取 doc_id=%s 的内部材料全文。" % MATERIAL_DOC_ID,
			"2. 根据材料中的目标文档 ID、分类、标签和验收标记，使用 kb_write 创建或更新结果文档。",
			"3. 结果文档内容必须原样包含材料里的验收标记。",
			"4. 最后调用 wo_finish_order 完成当前工单；它会自动保存项目和 KB。",
			"不要编造验收标记；如果没有读到材料，请先读取材料。",
		]),
		{
			"source_type": "work_order_agent_llm_e2e",
			"source_id": "kb_hidden_marker_probe",
			"assignee_npc_id": "npc_lin_xia",
		}
	)


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
			print("[LAB] waiting: status=%s surface=%s inner=%s worker=%s tools=%d" % [
				status,
				str(order.surface_status),
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


func _verify_result_document() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	_assert("KnowledgeBaseManager available", kb != null, "")
	if kb == null:
		return

	var doc: Dictionary = kb.get_document(RESULT_DOC_ID)
	_assert("result KB doc created", not doc.is_empty(), str(kb.documents))
	if doc.is_empty():
		return

	var content: String = str(doc.get("content", ""))
	_assert("result doc contains hidden marker", content.contains(_marker), content.left(500))

	var file_path: String = StorageManager.current_project_path.path_join("knowledge_base").path_join("docs").path_join(RESULT_DOC_ID + ".json")
	_assert("result KB doc persisted to disk", FileAccess.file_exists(file_path), file_path)
	if FileAccess.file_exists(file_path):
		var file := FileAccess.open(file_path, FileAccess.READ)
		var persisted: String = file.get_as_text() if file != null else ""
		if file != null:
			file.close()
		_assert("persisted doc contains hidden marker", persisted.contains(_marker), persisted.left(500))


func _verify_tool_trace() -> void:
	_assert("tool trace includes kb_read material", _has_tool_call("kb_read", "doc_id", MATERIAL_DOC_ID), JSON.stringify(_tool_events))
	_assert("tool trace includes kb_write result", _has_tool_call("kb_write", "doc_id", RESULT_DOC_ID), JSON.stringify(_tool_events))
	_assert("tool trace includes wo_finish_order", _has_tool_call("wo_finish_order", "order_id", _order_id), JSON.stringify(_tool_events))


func _has_tool_call(tool_name: String, arg_key: String = "", arg_value: String = "") -> bool:
	for event in _tool_events:
		if str(event.get("name", "")) != tool_name:
			continue
		if arg_key.is_empty():
			return true
		var args: Dictionary = event.get("args", {})
		if str(args.get(arg_key, "")) == arg_value:
			return true
	return false


func _suspend_background_dev_cycle() -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null:
		return
	var callback := Callable(dcm, "_on_order_status_changed")
	if WorkOrderManager.order_status_changed.is_connected(callback):
		WorkOrderManager.order_status_changed.disconnect(callback)
		_dev_cycle_disconnected = true
		print("[LAB] DevCycleManager order completion hook temporarily disconnected.")


func _restore_lab_state() -> void:
	WorkOrderManager.set("_worker_auto_run", _old_worker_auto_run)
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if _dev_cycle_disconnected and dcm != null:
		var callback := Callable(dcm, "_on_order_status_changed")
		if not WorkOrderManager.order_status_changed.is_connected(callback):
			WorkOrderManager.order_status_changed.connect(callback)
	_dev_cycle_disconnected = false


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
	print("\n========== WorkOrderAgent Real LLM E2E Summary ==========")
	print("order_id: %s" % _order_id)
	print("marker: %s" % _marker)
	print("tool_events: %s" % JSON.stringify(_tool_events))
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
	print("[DONE] Real LLM lab completed. Stop the project manually.")
