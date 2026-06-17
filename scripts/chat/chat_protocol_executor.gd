class_name ChatProtocolExecutor extends Node
## LinkChat 协议副作用执行器
## 负责事件通知、APP/浏览器动作以及工单生成

const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")

signal event_emitted(topic: ChatTopic, event_id: String, payload: Dictionary)
signal action_requested(topic: ChatTopic, action: Dictionary)

var _post_moment_callback: Callable = Callable()
var _get_channel_messages_callback: Callable = Callable()


func setup(post_moment_callback: Callable, get_channel_messages_callback: Callable) -> ChatProtocolExecutor:
	_post_moment_callback = post_moment_callback
	_get_channel_messages_callback = get_channel_messages_callback
	return self


func execute_effects(topic: ChatTopic, events: Array[Dictionary], actions: Array[Dictionary]) -> void:
	if topic == null:
		return

	for event_data in events:
		var event_id := str(event_data.get("id", "")).strip_edges()
		if event_id.is_empty():
			continue

		var payload: Dictionary = event_data.get("payload", {})
		event_emitted.emit(topic, event_id, payload)

		var story_director: Node = get_node_or_null("/root/StoryDirector")
		if story_director != null and story_director.has_method("notify_condition_met"):
			story_director.notify_condition_met(event_id, payload)

	for action in actions:
		var action_type := str(action.get("type", "")).strip_edges().to_lower()
		if action_type.is_empty():
			continue

		action_requested.emit(topic, action)
		_execute_action(topic, action)


func _execute_action(topic: ChatTopic, action: Dictionary) -> void:
	var action_type := str(action.get("type", "")).strip_edges().to_lower()
	match action_type:
		"open_browser":
			_execute_open_browser(action)
		"focus_app":
			_execute_focus_app(action)
		"launch_app":
			_execute_launch_app(action)
		"post_moment":
			_execute_post_moment(topic, action)
		"lock_app_window":
			_execute_lock_app_window(action)
		"unlock_app_window":
			_execute_unlock_app_window(action)
		"set_activity_lock":
			_execute_set_activity_lock(action)
		"clear_activity_lock":
			_execute_clear_activity_lock()
		"generate_work_order":
			_execute_generate_work_order(topic, action)
		_:
			push_warning("[ChatProtocolExecutor] Unsupported protocol action: %s" % action_type)


func _execute_open_browser(action: Dictionary) -> void:
	var browser: Node = get_node_or_null("/root/BrowserManager")
	if browser == null or not browser.has_method("request_open_url"):
		return

	var url := str(action.get("url", "")).strip_edges()
	if url.is_empty():
		return

	browser.request_open_url(
		url,
		str(action.get("design_prompt", "")),
		str(action.get("page_context", ""))
	)


func _execute_focus_app(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null:
		return

	var app_id := str(action.get("app_id", "")).strip_edges()
	if app_id.is_empty():
		return

	var force_launch: bool = bool(action.get("force_launch", true))
	var window: Control = null
	if app_mgr.has_method("focus_app"):
		window = app_mgr.focus_app(app_id, force_launch)
	elif force_launch and app_mgr.has_method("launch_app"):
		window = app_mgr.launch_app(app_id, true)

	_focus_protocol_window_channel(window, app_id, str(action.get("channel_id", "")))


func _execute_launch_app(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("launch_app"):
		return

	var app_id := str(action.get("app_id", "")).strip_edges()
	if app_id.is_empty():
		return

	var window: Control = app_mgr.launch_app(app_id, bool(action.get("force", false)))
	_focus_protocol_window_channel(window, app_id, str(action.get("channel_id", "")))


func _execute_post_moment(topic: ChatTopic, action: Dictionary) -> void:
	if _post_moment_callback.is_null():
		return

	var npc_id := str(action.get("npc_id", topic.npc_id)).strip_edges()
	var content := str(action.get("content", "")).strip_edges()
	if npc_id.is_empty() or content.is_empty():
		return

	_post_moment_callback.call(
		npc_id,
		content,
		str(action.get("image_hint", "")),
		int(action.get("likes", 0))
	)


func _execute_lock_app_window(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("lock_app_window"):
		return

	var app_id := str(action.get("app_id", "")).strip_edges()
	if app_id.is_empty():
		return

	app_mgr.lock_app_window(
		app_id,
		bool(action.get("close_locked", true)),
		bool(action.get("minimize_locked", true))
	)
	if bool(action.get("focus", true)) and app_mgr.has_method("focus_app"):
		app_mgr.focus_app(app_id, false)


func _execute_unlock_app_window(action: Dictionary) -> void:
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr == null or not app_mgr.has_method("unlock_app_window"):
		return

	var app_id := str(action.get("app_id", "")).strip_edges()
	if app_id.is_empty():
		return

	app_mgr.unlock_app_window(app_id)


func _execute_set_activity_lock(action: Dictionary) -> void:
	var mode := str(action.get("mode", "blacklist")).strip_edges().to_lower()
	var activities := _parse_activity_lock_list(action.get("activities", []))
	var reason := str(action.get("reason", "")).strip_edges()
	if activities.is_empty():
		return
	ActivityLockUtilsClass.set_narrative_lock(mode, activities, reason)


func _execute_clear_activity_lock() -> void:
	ActivityLockUtilsClass.clear_narrative_lock()


func _parse_activity_lock_list(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw_value is Array:
		for item in raw_value:
			_append_activity_lock_token(result, str(item))
	else:
		var text := str(raw_value).strip_edges()
		if not text.is_empty():
			for token in text.replace(",", "|").split("|", false):
				_append_activity_lock_token(result, token)
	return result


func _append_activity_lock_token(result: Array[String], raw_token: String) -> void:
	var token := raw_token.strip_edges()
	if token.is_empty() or token in result:
		return
	result.append(token)


func _execute_generate_work_order(topic: ChatTopic, action: Dictionary) -> void:
	var wo_mgr: Node = get_node_or_null("/root/WorkOrderManager")
	if wo_mgr == null:
		push_warning("[ChatProtocolExecutor] WorkOrderManager not found, cannot generate work order")
		return

	var hint_title := str(action.get("title", "")).strip_edges()
	if hint_title.is_empty():
		hint_title = topic.display_title

	var conversation_log := _build_conversation_log(topic.channel_id)
	var kb_context := _build_kb_context_for_work_order()
	var extra_prompt := str(action.get("prompt", "")).strip_edges()

	var user_prompt := _resolve_prompt_template("work_order_from_chat_user", {
		"hint_title": hint_title,
		"topic_prompt": topic.system_prompt,
		"conversation_log": conversation_log,
	}, "以下是一段关于「%s」的讨论记录，请根据讨论中达成的共识生成结构化工单。\n\n讨论背景：\n%s\n\n对话记录：\n%s" % [hint_title, topic.system_prompt, conversation_log])

	var requirement_section := ""
	if not extra_prompt.is_empty():
		requirement_section = "\n\n工单内容必须覆盖以下要点：\n%s\n" % extra_prompt

	var system_prompt := _resolve_prompt_template("work_order_from_chat_system", {
		"requirement_section": requirement_section.strip_edges(),
		"kb_context": kb_context,
	}, "你是游戏开发项目的工单撰写助手。description 必须明确可执行。只输出 JSON：{\"title\":\"工单标题\",\"description\":\"详细需求\"}\n%s\n\n当前项目知识库摘要：\n%s" % [requirement_section, kb_context])

	var ai := AIService.new()
	ai.name = "ChatProtocolGenWO"
	add_child(ai)
	var config_mgr := AIConfigManager.get_instance()
	config_mgr.apply_to_service(ai, "work_order")

	ai.request_completed.connect(
		func(_request_id: String, response: Dictionary) -> void:
			_on_protocol_work_order_generated(response, wo_mgr, hint_title, topic.topic_id)
			ai.queue_free()
	)
	ai.request_failed.connect(
		func(_request_id: String, error: String, _error_code: int) -> void:
			push_warning("[ChatProtocolExecutor] generate_work_order LLM failed: %s" % error)
			ai.queue_free()
	)

	print("[ChatProtocolExecutor] generate_work_order: 开始 LLM 生成工单 (hint: %s)" % hint_title)
	ai.chat_simple(user_prompt, system_prompt)


func _on_protocol_work_order_generated(response: Dictionary, wo_mgr: Node, fallback_title: String, source_topic_id: String) -> void:
	var content := AIService.extract_content(response).strip_edges()
	if content.is_empty():
		push_warning("[ChatProtocolExecutor] generate_work_order: empty LLM response")
		return

	if content.begins_with("```"):
		var first_nl := content.find("\n")
		if first_nl >= 0:
			content = content.substr(first_nl + 1)
		if content.ends_with("```"):
			content = content.substr(0, content.length() - 3).strip_edges()

	var json := JSON.new()
	if json.parse(content) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("[ChatProtocolExecutor] generate_work_order: failed to parse LLM JSON: %s" % content)
		return

	var data: Dictionary = json.data
	var title := str(data.get("title", "")).strip_edges()
	var desc := str(data.get("description", "")).strip_edges()
	if title.is_empty():
		title = fallback_title

	var order: Resource = null
	if wo_mgr.has_method("create_order"):
		order = wo_mgr.create_order(title, desc, {
			"source_type": "linkchat",
			"source_id": source_topic_id,
		})
	if order == null:
		push_warning("[ChatProtocolExecutor] generate_work_order: failed to create order")
		return

	if not wo_mgr.dispatch_order(order.id):
		push_warning("[ChatProtocolExecutor] generate_work_order: failed to dispatch order %s" % order.id)
		return
	print("[ChatProtocolExecutor] generate_work_order: 工单已派发 %s (%s)" % [order.id, title])


func _build_conversation_log(channel_id: String) -> String:
	var lines: PackedStringArray = []
	if _get_channel_messages_callback.is_null():
		return ""

	var result: Variant = _get_channel_messages_callback.call(channel_id)
	if not (result is Array):
		return ""

	for item in result:
		if not (item is Dictionary):
			continue
		var msg := item as Dictionary
		var sender := str(msg.get("sender_name", msg.get("sender_id", "???"))).strip_edges()
		var content := str(msg.get("content", "")).strip_edges()
		if sender.is_empty() or content.is_empty():
			continue
		lines.append("%s: %s" % [sender, content])
	return "\n".join(lines)


func _build_kb_context_for_work_order() -> String:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null:
		return "(知识库不可用)"
	if not kb.has_method("get_documents"):
		return "(知识库接口不可用)"
	var docs: Array = kb.get_documents()
	if docs.is_empty():
		return "(知识库为空)"
	var lines: PackedStringArray = []
	for doc in docs:
		lines.append("- [%s] %s: %s" % [
			str(doc.get("category", "")),
			str(doc.get("title", "")),
			str(doc.get("content", "")).left(100),
		])
	return "\n".join(lines)


func _resolve_prompt_template(prompt_key: String, vars: Dictionary, fallback: String) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("has_prompt") and pm.has_method("resolve_with_vars"):
		if pm.has_prompt(prompt_key):
			var resolved := str(pm.resolve_with_vars(prompt_key, vars)).strip_edges()
			if not resolved.is_empty():
				return resolved
	return fallback


func _focus_protocol_window_channel(window: Control, app_id: String, channel_id: String) -> void:
	var normalized_channel_id := channel_id.strip_edges()
	if app_id != "linkchat" or normalized_channel_id.is_empty():
		return
	if window == null or not is_instance_valid(window):
		return
	if not ("content" in window):
		return

	var content: Variant = window.content
	if not (content is Node):
		return

	var app: Node = content as Node
	if app.has_method("open_topic_channel"):
		app.call_deferred("open_topic_channel", normalized_channel_id)
	elif app.has_method("select_channel"):
		app.call_deferred("select_channel", normalized_channel_id)
