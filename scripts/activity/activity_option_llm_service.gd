class_name ActivityOptionLLMService
extends Node

const ChatAgentScene = preload("res://scenes/llm/chat_agent.tscn")
const AVGDevKBToolsClass = preload("res://scripts/avg/dev_tools/kb_tools.gd")
const AVGDevWorkOrderToolsClass = preload("res://scripts/avg/dev_tools/work_order_tools.gd")

signal request_completed(request_id: String, context: Dictionary, raw_text: String, response: Dictionary)
signal request_failed(request_id: String, context: Dictionary, error_message: String, error_code: int)

var _ai_service: AIService = null
var _agent: ChatAgent = null
var _enabled: bool = false
var _default_request_options: Dictionary = {}
var _request_contexts: Dictionary = {}
var _use_chat_agent: bool = false
var _enable_project_tools: bool = false
var _max_tool_iterations: int = 2


func configure(
		service_name: String,
		primary_role: String,
		fallback_roles: Array[String] = [],
		service_overrides: Dictionary = {},
		default_request_options: Dictionary = {}
	) -> bool:
	_use_chat_agent = bool(service_overrides.get("use_chat_agent", false))
	_enable_project_tools = bool(service_overrides.get("enable_project_tools", false))
	_max_tool_iterations = max(1, int(service_overrides.get("max_tool_iterations", 2)))
	if _use_chat_agent:
		_ensure_agent(service_name)
	else:
		_ensure_ai_service(service_name)
	_apply_service_overrides(service_overrides)
	_default_request_options = default_request_options.duplicate(true)
	_request_contexts.clear()
	_enabled = _apply_config_roles(primary_role, fallback_roles)
	return _enabled


func is_enabled() -> bool:
	return _enabled and (_agent != null if _use_chat_agent else _ai_service != null)


func has_pending_requests() -> bool:
	return not _request_contexts.is_empty()


func request_text(
		prompt_text: String,
		system_prompt: String = "",
		context: Dictionary = {},
		options: Dictionary = {}
	) -> String:
	if not is_enabled():
		return ""
	if prompt_text.strip_edges().is_empty():
		return ""

	var merged_options: Dictionary = _default_request_options.duplicate(true)
	merged_options.merge(options, true)
	if _use_chat_agent:
		return _request_text_with_agent(prompt_text, system_prompt, context, merged_options)
	var request_id: String = _ai_service.chat_simple(prompt_text, system_prompt, merged_options)
	if request_id.is_empty():
		return ""
	_request_contexts[request_id] = context.duplicate(true)
	return request_id


func clear_request(request_id: String) -> void:
	_request_contexts.erase(request_id)


func clear_pending_requests() -> void:
	_request_contexts.clear()
	if _agent != null:
		_agent.reset()


func _ensure_ai_service(service_name: String) -> void:
	if _ai_service == null:
		_ai_service = AIService.new()
		add_child(_ai_service)
	if not _ai_service.request_completed.is_connected(_on_ai_request_completed):
		_ai_service.request_completed.connect(_on_ai_request_completed)
	if not _ai_service.request_failed.is_connected(_on_ai_request_failed):
		_ai_service.request_failed.connect(_on_ai_request_failed)
	_ai_service.name = service_name


func _ensure_agent(service_name: String) -> void:
	if _agent == null:
		_agent = ChatAgentScene.instantiate()
		add_child(_agent)
	if not _agent.message_completed.is_connected(_on_agent_message_completed):
		_agent.message_completed.connect(_on_agent_message_completed)
	if not _agent.message_failed.is_connected(_on_agent_message_failed):
		_agent.message_failed.connect(_on_agent_message_failed)
	_agent.name = service_name
	_ai_service = _agent.get_node_or_null("AIService") as AIService
	if _ai_service != null:
		_ai_service.auto_execute_tools = true
		_ai_service.max_tool_iterations = _max_tool_iterations
		if _enable_project_tools:
			_register_project_tools(_agent, _ai_service)


func _apply_service_overrides(service_overrides: Dictionary) -> void:
	if _ai_service == null:
		return
	for key_variant in service_overrides.keys():
		var property_name := str(key_variant).strip_edges()
		if property_name.is_empty():
			continue
		if property_name in ["use_chat_agent", "enable_project_tools", "max_tool_iterations"]:
			continue
		if not _has_property(_ai_service, property_name):
			continue
		_ai_service.set(property_name, service_overrides[key_variant])


func _apply_config_roles(primary_role: String, fallback_roles: Array[String]) -> bool:
	var config_mgr := AIConfigManager.get_instance()
	if config_mgr == null or _ai_service == null:
		return false

	var enabled: bool = false
	var normalized_primary := primary_role.strip_edges()
	if not normalized_primary.is_empty() and not config_mgr.get_config_for_role(normalized_primary).is_empty():
		enabled = config_mgr.apply_to_service(_ai_service, normalized_primary)
	if enabled:
		return true

	for fallback_role in fallback_roles:
		var normalized_role := str(fallback_role).strip_edges()
		if normalized_role.is_empty():
			continue
		if config_mgr.get_config_for_role(normalized_role).is_empty():
			continue
		enabled = config_mgr.apply_to_service(_ai_service, normalized_role)
		if enabled:
			return true
	return false


func _request_text_with_agent(prompt_text: String, system_prompt: String, context: Dictionary, options: Dictionary) -> String:
	if _agent == null:
		return ""
	_agent.reset()
	_agent.set_system_prompt_override(system_prompt)
	var request_id: String = _agent.send_message_with_options(prompt_text, options)
	if request_id.is_empty():
		return ""
	_request_contexts[request_id] = context.duplicate(true)
	return request_id


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if not _request_contexts.has(request_id):
		return
	var context: Dictionary = (_request_contexts[request_id] as Dictionary).duplicate(true)
	_request_contexts.erase(request_id)
	var raw_text: String = AIService.extract_content(response).strip_edges()
	request_completed.emit(request_id, context, raw_text, response)


func _on_ai_request_failed(request_id: String, error_message: String, error_code: int) -> void:
	if not _request_contexts.has(request_id):
		return
	var context: Dictionary = (_request_contexts[request_id] as Dictionary).duplicate(true)
	_request_contexts.erase(request_id)
	request_failed.emit(request_id, context, error_message, error_code)


func _on_agent_message_completed(request_id: String, content: String) -> void:
	if not _request_contexts.has(request_id):
		return
	var context: Dictionary = (_request_contexts[request_id] as Dictionary).duplicate(true)
	_request_contexts.erase(request_id)
	request_completed.emit(request_id, context, content.strip_edges(), {"content": content})


func _on_agent_message_failed(request_id: String, error_message: String) -> void:
	if not _request_contexts.has(request_id):
		return
	var context: Dictionary = (_request_contexts[request_id] as Dictionary).duplicate(true)
	_request_contexts.erase(request_id)
	request_failed.emit(request_id, context, error_message, ERR_CANT_CONNECT)


func _register_project_tools(agent: ChatAgent, ai_service: AIService) -> void:
	if ai_service == null:
		return
	AVGDevKBToolsClass.register_read_only(ai_service)
	AVGDevWorkOrderToolsClass.register_summary_read_only(ai_service)
	agent.register_tool(
		"get_dev_cycle_snapshot",
		"获取当前开发循环的简要状态，包括当前天数、可见任务、已完成任务数量、后台队列和计划状态。",
		{"type": "object", "properties": {}},
		func(_args: Dictionary) -> Variant: return _build_dev_cycle_snapshot()
	)


func _build_dev_cycle_snapshot() -> Dictionary:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null:
		return {"success": false, "error": "DevCycleManager not available"}
	var visible_tasks: Array = dcm.get_visible_tasks() if dcm.has_method("get_visible_tasks") else []
	var visible_summary: Array = []
	for task in visible_tasks:
		if task is Dictionary:
			visible_summary.append({
				"task_id": str(task.get("task_id", "")),
				"title": str(task.get("title", "")),
				"status": str(task.get("status", "")),
				"minigame_type": str(task.get("minigame_type", "")),
			})
	return {
		"success": true,
		"completed_count": int(dcm.get_completed_count()) if dcm.has_method("get_completed_count") else 0,
		"queue_size": int(dcm.get_queue_size()) if dcm.has_method("get_queue_size") else 0,
		"order_active": bool(dcm.is_order_active()) if dcm.has_method("is_order_active") else false,
		"plan_generated": bool(dcm.get("_plan_generated")),
		"visible_tasks": visible_summary,
	}


func _has_property(target: Object, property_name: String) -> bool:
	for prop in target.get_property_list():
		if str(prop.get("name", "")) == property_name:
			return true
	return false