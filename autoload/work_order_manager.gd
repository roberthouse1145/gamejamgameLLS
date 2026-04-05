extends Node

const WorkOrderDataClass = preload("res://scripts/apps/work_order/work_order_data.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const WorkOrderControllerScene = preload("res://scenes/avg/dev_tools/work_order_controller_agent.tscn")
const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")
const ENABLE_PROJECT_WORK_ORDER_PERSISTENCE: bool = false

signal order_created(order_id: String)
signal order_updated(order_id: String)
signal order_status_changed(order_id: String, old_status: String, new_status: String)
signal clarification_requested(order_id: String, npc_id: String, questions: Array)
signal creative_task_requested(context: Dictionary)
signal order_deleted(order_id: String)
signal orders_loaded()
signal order_dispatched(order_id: String, assignee_npc_id: String)

var _orders: Dictionary = {}
var _next_id_num: int = 1
var _worker_agents: Dictionary = {}
var _pending_clarifications: Array = []
var verbose_agent_logging: bool = false


func _ready() -> void:
	_setup_ai_service()
	StorageManager.current_project_changed.connect(_on_project_changed)
	if StorageManager.current_project != null:
		_load_orders_from_project()
		call_deferred("_restore_runtime_order_state")

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("phase_changed"):
		glm.phase_changed.connect(_on_phase_changed_flush_clarifications)

	var cm: Node = get_node_or_null("/root/ChatManager")
	if cm != null and cm.has_signal("topic_completed"):
		cm.topic_completed.connect(_on_topic_completed_flush_clarifications)


func _setup_ai_service() -> void:
	pass


func _on_project_changed(_project: Resource) -> void:
	_load_orders_from_project()
	call_deferred("_restore_runtime_order_state")


func _restore_runtime_order_state() -> void:
	_restore_pending_clarifications()
	resume_pending_generations()


func reset_runtime_state() -> void:
	_reset_runtime_orders()


func _reset_runtime_orders(emit_loaded: bool = true) -> void:
	for order_id in _worker_agents.keys():
		_cleanup_worker(str(order_id))
	_orders.clear()
	_next_id_num = 1
	_pending_clarifications.clear()
	if emit_loaded:
		orders_loaded.emit()


func _is_project_work_order_persistence_enabled() -> bool:
	return ENABLE_PROJECT_WORK_ORDER_PERSISTENCE


func create_order(title: String, description: String = "", source_info: Dictionary = {}) -> Resource:
	var order := WorkOrderDataClass.new()
	order.id = "wo_%d" % _next_id_num
	_next_id_num += 1
	order.title = title
	order.description = description
	order.status = "draft"
	order.source_type = str(source_info.get("source_type", ""))
	order.source_id = str(source_info.get("source_id", ""))
	order.created_at = int(Time.get_unix_time_from_system())
	order.updated_at = order.created_at

	_orders[order.id] = order
	_save_orders_to_project()
	order_created.emit(order.id)
	return order


func get_order(order_id: String) -> Resource:
	return _orders.get(order_id)


func get_all_orders() -> Array:
	var result: Array = []
	for order in _orders.values():
		result.append(order)
	result.sort_custom(func(a: Resource, b: Resource) -> bool:
		return a.updated_at > b.updated_at
	)
	return result


func get_orders_by_status(status: String) -> Array:
	var result: Array = []
	for order in _orders.values():
		if order.status == status:
			result.append(order)
	return result


func update_order(order_id: String, data: Dictionary) -> bool:
	var order: Resource = _orders.get(order_id)
	if order == null:
		return false

	if data.has("title"):
		order.title = data.title
	if data.has("description"):
		order.description = data.description
	if data.has("assignee_npc_id"):
		order.assignee_npc_id = data.assignee_npc_id
	if data.has("priority"):
		order.priority = data.priority
	if data.has("spec"):
		order.spec = data.spec

	order.updated_at = int(Time.get_unix_time_from_system())
	_save_orders_to_project()
	order_updated.emit(order_id)
	return true


func set_order_status(order_id: String, new_status: String) -> bool:
	var order: Resource = _orders.get(order_id)
	if order == null:
		return false

	var old_status: String = order.status
	if old_status == new_status:
		return true

	order.status = new_status
	order.updated_at = int(Time.get_unix_time_from_system())
	_save_orders_to_project()
	order_status_changed.emit(order_id, old_status, new_status)
	return true


func delete_order(order_id: String) -> bool:
	if not _orders.has(order_id):
		return false

	_orders.erase(order_id)
	_save_orders_to_project()
	order_deleted.emit(order_id)
	return true


func set_task_done(order_id: String, task_index: int, done: bool) -> bool:
	var order: Resource = _orders.get(order_id)
	if order == null:
		return false

	var tasks: Array = order.spec.get("tasks", [])
	if task_index < 0 or task_index >= tasks.size():
		return false

	tasks[task_index]["done"] = done
	order.spec["tasks"] = tasks
	order.updated_at = int(Time.get_unix_time_from_system())
	_save_orders_to_project()
	order_updated.emit(order_id)
	return true


func request_spec_generation(_order_id: String) -> bool:
	push_warning("[WorkOrderManager] request_spec_generation is deprecated")
	return false


func dispatch_order(order_id: String, _required_ap: int = 0, _dispatch_day: int = 0) -> bool:
	var order: Resource = _orders.get(order_id)
	if order == null:
		push_warning("[WorkOrderManager] Order not found: %s" % order_id)
		return false

	if order.assignee_npc_id.is_empty():
		push_warning("[WorkOrderManager] Order has no assignee: %s" % order_id)
		return false

	var trunk_err := StorageManager.create_trunk()
	if trunk_err != OK:
		push_warning("[WorkOrderManager] Failed to create trunk, executing on main: %s" % error_string(trunk_err))

	order.surface_status = "in_progress"
	order.inner_status = "generating"
	set_order_status(order_id, "in_progress")

	order_dispatched.emit(order_id, order.assignee_npc_id)
	_spawn_worker_agent_for_order(order_id, order.assignee_npc_id, order.title)
	_save_orders_to_project()
	return true


func send_order(order_id: String) -> bool:
	return dispatch_order(order_id)


func advance_daily_progress() -> Array:
	return []


func progress_order(_order_id: String, _ap_spent: int = 1) -> bool:
	return true


func _mark_order_completed(order_id: String) -> void:
	var order: Resource = _orders.get(order_id)
	if order == null:
		return

	if StorageManager.is_trunk_active:
		var commit_err := StorageManager.commit_trunk()
		if commit_err != OK:
			push_warning("[WorkOrderManager] Trunk commit failed for %s: %s" % [order_id, error_string(commit_err)])

	order.surface_status = "completed"
	order.status = "completed"
	order.updated_at = int(Time.get_unix_time_from_system())
	order_status_changed.emit(order_id, "in_progress", "completed")
	_cleanup_worker(order_id)
	_save_orders_to_project()


func resume_pending_generations() -> void:
	StorageManager.discard_trunk()

	var resumed_count: int = 0
	for order_id in _orders:
		var order: Resource = _orders[order_id]
		if order.surface_status == "completed":
			continue
		if order.surface_status in ["needs_input", "awaiting_player", "milestone_ready", "delivered"]:
			continue
		if order.inner_status in ["ready", "awaiting_clarification", "awaiting_discussion", "milestone_ready"]:
			continue
		if _worker_agents.has(order_id):
			continue

		order.inner_status = "generating"
		var trunk_err := StorageManager.create_trunk()
		if trunk_err != OK:
			push_warning("[WorkOrderManager] Failed to create trunk for resumed order: %s" % order_id)
		_spawn_worker_agent_for_order(order_id, order.assignee_npc_id, order.title)
		resumed_count += 1

	if resumed_count > 0:
		_save_orders_to_project()


func _spawn_worker_agent_for_order(order_id: String, _npc_id: String, _title: String) -> void:
	var worker: ChatAgent = WorkOrderControllerScene.instantiate()
	worker.name = "Controller_%s" % order_id
	add_child(worker)

	_worker_agents[order_id] = worker

	worker.log_entry.connect(func(entry: Dictionary):
		var log_type: String = entry.get("type", "info")
		var log_content: String = str(entry.get("content", "")).strip_edges()
		if log_type == "error":
			push_warning("[Controller-%s][error] %s" % [order_id, log_content])
			return
		if verbose_agent_logging:
			match log_type:
				"ai_response":
					print("[Controller-%s][ai] %s" % [order_id, log_content.left(200)])
				"tool_call":
					print("[Controller-%s][tool] %s" % [order_id, log_content.left(150)])
				"tool_result":
					print("[Controller-%s][result] %s" % [order_id, log_content.left(150)])
				"progress":
					print("[Controller-%s][progress] %s" % [order_id, log_content.left(150)])
			return
		if log_type == "progress" and _should_echo_controller_progress(log_content):
			print("[Controller-%s][progress] %s" % [order_id, log_content.left(150)])
	)

	worker.message_completed.connect(func(_req_id: String, _content: String):
		_on_worker_message_completed(order_id)
	)

	var current_order: Resource = _orders.get(order_id)
	var description: String = current_order.description if current_order != null else ""
	var prompt := "Please execute work order %s.\nRequirement:\n%s" % [order_id, description]
	worker.send_message(prompt)


func _should_echo_controller_progress(log_content: String) -> bool:
	if log_content.is_empty():
		return false
	return (
		log_content.contains("委托子代理")
		or log_content.contains("子代理 [")
	)


func _cleanup_worker(order_id: String) -> void:
	var worker: Node = _worker_agents.get(order_id)
	if worker != null:
		worker.queue_free()
		_worker_agents.erase(order_id)


func _on_worker_message_completed(order_id: String) -> void:
	var order: Resource = _orders.get(order_id)
	if order == null:
		return
	if order.surface_status == "in_progress" and order.inner_status == "generating":
		order.inner_status = "ready"
		order.updated_at = int(Time.get_unix_time_from_system())
		_mark_order_completed(order_id)


func request_clarification(order_id: String, questions: Array) -> void:
	var order: Resource = _orders.get(order_id)
	if order == null:
		return

	_remove_pending_clarifications_for_order(order_id)
	set_order_status(order_id, "needs_input")
	order.surface_status = "needs_input"
	order.inner_status = "awaiting_clarification"
	order.pending_questions.clear()
	for item in questions:
		var question := str(item).strip_edges()
		if not question.is_empty():
			order.pending_questions.append(question)
	_save_orders_to_project()

	var topic := _build_clarification_topic(order, order.pending_questions)
	_pending_clarifications.append({"order_id": order_id, "topic": topic})
	clarification_requested.emit(order_id, order.assignee_npc_id, questions)
	_try_flush_next_clarification()


func _get_dm_channel_for_npc(npc_id: String) -> String:
	match npc_id:
		"npc_lin_xia":
			return "dm_lin_xia"
		_:
			return "dm_%s" % npc_id.replace("npc_", "")


func _get_npc_display_name(npc_id: String) -> String:
	var chat_manager: Node = get_node_or_null("/root/ChatManager")
	if chat_manager != null and chat_manager.has_method("get_npc"):
		var npc: Resource = chat_manager.get_npc(npc_id)
		if npc != null and "display_name" in npc:
			return str(npc.display_name)
	match npc_id:
		"npc_lin_xia":
			return "林夏"
		_:
			return npc_id


func _build_surface_clarification_prompt(npc_name: String, order: Resource, questions: Array) -> String:
	var question_lines: Array[String] = []
	for raw_question in questions:
		var q := str(raw_question).strip_edges()
		if not q.is_empty():
			question_lines.append("- %s" % q)

	return """你是 %s，正在和玩家共同开发一个 AVG 作品。
你需要向玩家确认一些阻塞当前工作的细节。

## 当前工单
标题：%s
描述：%s

## 需要确认的问题
%s

## 对话要求
- 用自然的聊天语气提问，不要像问卷调查
- 只聚焦最关键的 1-2 个缺失细节
- 如果某个问题适合选择，可以给出 2-3 个简短选项（用 > 开头）
- 玩家回答清楚后，以 [TOPIC_COMPLETE] 结束""" % [npc_name, order.title, order.description, "\n".join(question_lines)]


func _can_activate_clarification(topic: Resource) -> bool:
	var chat_manager: Node = get_node_or_null("/root/ChatManager")
	if chat_manager == null:
		return false
	if chat_manager.has_method("has_active_topic") and chat_manager.has_active_topic(topic.channel_id):
		return false
	if not ActivityLockUtilsClass.is_free_period():
		return false
	return true


func _try_flush_next_clarification() -> void:
	if _pending_clarifications.is_empty():
		return

	var chat_manager: Node = get_node_or_null("/root/ChatManager")
	if chat_manager == null:
		return

	for i in range(_pending_clarifications.size()):
		var entry: Dictionary = _pending_clarifications[i]
		var topic: Resource = entry.get("topic")
		if topic == null:
			_pending_clarifications.remove_at(i)
			continue
		if not _can_activate_clarification(topic):
			continue
		if chat_manager.has_method("activate_topic"):
			var channel: Resource = chat_manager.get_channel(topic.channel_id) if chat_manager.has_method("get_channel") else null
			if channel != null and "messages" in channel:
				topic.context_data["start_message_count"] = int(channel.messages.size())
			if chat_manager.activate_topic(topic):
				_pending_clarifications.remove_at(i)
			return


func _on_phase_changed_flush_clarifications(_new_phase: int) -> void:
	_try_flush_next_clarification()


func _on_topic_completed_flush_clarifications(topic: Resource, result: Dictionary) -> void:
	_handle_completed_clarification_topic(topic, result)
	call_deferred("_try_flush_next_clarification")


func get_pending_clarification_count() -> int:
	return _pending_clarifications.size()


func _build_clarification_topic(order: Resource, questions: Array) -> Resource:
	var topic := ChatTopicClass.new()
	topic.topic_id = "clarify_%s_%d" % [order.id, int(Time.get_unix_time_from_system())]
	topic.topic_type = "work_clarification"
	topic.display_title = "工单确认：%s" % order.title
	topic.npc_id = order.assignee_npc_id
	topic.channel_id = _get_dm_channel_for_npc(order.assignee_npc_id)
	topic.context_data = {"order_id": order.id, "questions": questions.duplicate(true)}
	topic.max_turns = 5
	topic.timeout_seconds = 600
	topic.system_prompt = _build_surface_clarification_prompt(_get_npc_display_name(order.assignee_npc_id), order, questions)
	return topic


func _remove_pending_clarifications_for_order(order_id: String) -> void:
	for i in range(_pending_clarifications.size() - 1, -1, -1):
		var entry: Dictionary = _pending_clarifications[i]
		if str(entry.get("order_id", "")) == order_id:
			_pending_clarifications.remove_at(i)


func _restore_pending_clarifications() -> void:
	_pending_clarifications.clear()
	for order in _orders.values():
		if order == null:
			continue
		if order.inner_status != "awaiting_clarification":
			continue
		if order.pending_questions.is_empty():
			continue
		_pending_clarifications.append({
			"order_id": order.id,
			"topic": _build_clarification_topic(order, order.pending_questions),
		})
	if not _pending_clarifications.is_empty():
		call_deferred("_try_flush_next_clarification")


func _handle_completed_clarification_topic(topic: Resource, result: Dictionary) -> void:
	if topic == null or topic.topic_type != "work_clarification":
		return

	var order_id: String = str(topic.context_data.get("order_id", ""))
	if order_id.is_empty():
		return

	var order: Resource = _orders.get(order_id)
	if order == null:
		return

	var transcript: String = _extract_clarification_transcript(topic, result)
	if not transcript.is_empty():
		var clarification_note := "\n\n## 玩家补充说明\n%s" % transcript
		if clarification_note not in order.description:
			order.description += clarification_note

	order.pending_questions.clear()
	order.surface_status = "in_progress"
	order.inner_status = "generating"
	set_order_status(order_id, "in_progress")
	order.updated_at = int(Time.get_unix_time_from_system())
	_save_orders_to_project()

	var resume_prompt := _build_clarification_resume_prompt(order, transcript)
	var worker: ChatAgent = _worker_agents.get(order_id)
	if worker != null:
		if not worker.is_busy():
			worker.send_message(resume_prompt)
		return

	if not StorageManager.is_trunk_active:
		var trunk_err := StorageManager.create_trunk()
		if trunk_err != OK:
			push_warning("[WorkOrderManager] Failed to recreate trunk for clarified order: %s" % order_id)
	_spawn_worker_agent_for_order(order_id, order.assignee_npc_id, order.title)


func _extract_clarification_transcript(topic: Resource, result: Dictionary) -> String:
	var chat_manager: Node = get_node_or_null("/root/ChatManager")
	if chat_manager != null and chat_manager.has_method("get_channel"):
		var channel: Resource = chat_manager.get_channel(topic.channel_id)
		if channel != null and "messages" in channel:
			var start_index: int = max(0, int(topic.context_data.get("start_message_count", 0)))
			var lines: PackedStringArray = []
			for i in range(start_index, channel.messages.size()):
				var msg: Dictionary = channel.messages[i]
				var content := str(msg.get("content", "")).strip_edges()
				if content.is_empty():
					continue
				var sender := str(msg.get("sender_name", msg.get("sender_id", ""))).strip_edges()
				if sender.is_empty():
					sender = "unknown"
				lines.append("%s: %s" % [sender, content])
			if not lines.is_empty():
				return "\n".join(lines)

	var result_messages: Variant = result.get("messages", [])
	if result_messages is Array:
		var fallback_lines: PackedStringArray = []
		for raw_msg in result_messages:
			if not raw_msg is Dictionary:
				continue
			var msg: Dictionary = raw_msg
			var content := str(msg.get("content", "")).strip_edges()
			if content.is_empty():
				continue
			var speaker := str(msg.get("sender_name", msg.get("speaker", msg.get("sender_id", "assistant")))).strip_edges()
			fallback_lines.append("%s: %s" % [speaker, content])
		if not fallback_lines.is_empty():
			return "\n".join(fallback_lines)
	return ""


func _build_clarification_resume_prompt(order: Resource, transcript: String) -> String:
	var prompt := "玩家已经补充了缺失信息。请继续执行工单 %s。" % order.id
	if not transcript.is_empty():
		prompt += "\n\n## 澄清对话记录\n%s" % transcript
	prompt += "\n\n如果信息已经足够，请继续工作。只有在仍有关键阻塞时才再次提问。"
	return prompt


func request_creative_task(context: Dictionary) -> void:
	var topic: String = str(context.get("topic", ""))
	if topic.is_empty():
		push_warning("[WorkOrderManager] request_creative_task: topic is empty")
		return
	creative_task_requested.emit(context)


func _load_orders_from_project() -> void:
	_reset_runtime_orders(false)
	if not _is_project_work_order_persistence_enabled():
		orders_loaded.emit()
		return

	var project_path := StorageManager.main_project_path
	if project_path.is_empty():
		orders_loaded.emit()
		return

	var json_path := project_path + "work_orders/data.json"
	if not FileAccess.file_exists(json_path):
		orders_loaded.emit()
		return

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_warning("[WorkOrderManager] Failed to open: %s" % json_path)
		orders_loaded.emit()
		return

	var content := file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_warning("[WorkOrderManager] Invalid JSON in: %s" % json_path)
		orders_loaded.emit()
		return

	_next_id_num = data.get("next_id_num", 1)
	var orders_dict: Dictionary = data.get("orders", {})
	for order_id in orders_dict:
		var order_data: Dictionary = orders_dict[order_id]
		var order: Resource = WorkOrderDataClass.from_dict(order_data)
		_orders[order_id] = order
	orders_loaded.emit()


func _save_orders_to_project() -> void:
	if not _is_project_work_order_persistence_enabled():
		return

	var project_path := StorageManager.main_project_path
	if project_path.is_empty():
		return

	var dir_path := project_path + "work_orders/"
	var json_path := dir_path + "data.json"
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_warning("[WorkOrderManager] Failed to create directory: %s" % dir_path)
			return

	var orders_dict: Dictionary = {}
	for order_id in _orders:
		var order: Resource = _orders[order_id]
		orders_dict[order_id] = order.to_dict()

	var data: Dictionary = {
		"next_id_num": _next_id_num,
		"orders": orders_dict,
	}

	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		push_warning("[WorkOrderManager] Failed to write: %s" % json_path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _extract_json_from_response(content: String) -> Variant:
	var json_str := content.strip_edges()
	var json_block_regex := RegEx.new()
	json_block_regex.compile("```(?:json)?\\s*([\\s\\S]*?)```")
	var match_result := json_block_regex.search(json_str)
	if match_result:
		json_str = match_result.get_string(1).strip_edges()

	var start_idx := json_str.find("{")
	if start_idx == -1:
		return null
	json_str = json_str.substr(start_idx)

	var result: Variant = JSON.parse_string(json_str)
	if result != null:
		return result
	return _try_fix_incomplete_json(json_str)


func _try_fix_incomplete_json(json_str: String) -> Variant:
	var open_braces := 0
	var open_brackets := 0
	var in_string := false
	var escape_next := false

	for i in range(json_str.length()):
		var c := json_str[i]
		if escape_next:
			escape_next = false
			continue
		if c == "\\":
			escape_next = true
			continue
		if c == "\"":
			in_string = not in_string
			continue
		if in_string:
			continue
		match c:
			"{":
				open_braces += 1
			"}":
				open_braces -= 1
			"[":
				open_brackets += 1
			"]":
				open_brackets -= 1

	if in_string:
		json_str += "\""
	for i in range(open_brackets):
		json_str += "]"
	for i in range(open_braces):
		json_str += "}"
	return JSON.parse_string(json_str)
