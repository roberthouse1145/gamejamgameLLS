class_name ActivityOptionLLMService
extends Node

signal request_completed(request_id: String, context: Dictionary, raw_text: String, response: Dictionary)
signal request_failed(request_id: String, context: Dictionary, error_message: String, error_code: int)

var _ai_service: AIService = null
var _enabled: bool = false
var _default_request_options: Dictionary = {}
var _request_contexts: Dictionary = {}


func configure(
		service_name: String,
		primary_role: String,
		fallback_roles: Array[String] = [],
		service_overrides: Dictionary = {},
		default_request_options: Dictionary = {}
	) -> bool:
	_ensure_ai_service(service_name)
	_apply_service_overrides(service_overrides)
	_default_request_options = default_request_options.duplicate(true)
	_request_contexts.clear()
	_enabled = _apply_config_roles(primary_role, fallback_roles)
	return _enabled


func is_enabled() -> bool:
	return _enabled and _ai_service != null


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
	var request_id: String = _ai_service.chat_simple(prompt_text, system_prompt, merged_options)
	if request_id.is_empty():
		return ""
	_request_contexts[request_id] = context.duplicate(true)
	return request_id


func clear_request(request_id: String) -> void:
	_request_contexts.erase(request_id)


func clear_pending_requests() -> void:
	_request_contexts.clear()


func _ensure_ai_service(service_name: String) -> void:
	if _ai_service == null:
		_ai_service = AIService.new()
		add_child(_ai_service)
	if not _ai_service.request_completed.is_connected(_on_ai_request_completed):
		_ai_service.request_completed.connect(_on_ai_request_completed)
	if not _ai_service.request_failed.is_connected(_on_ai_request_failed):
		_ai_service.request_failed.connect(_on_ai_request_failed)
	_ai_service.name = service_name


func _apply_service_overrides(service_overrides: Dictionary) -> void:
	if _ai_service == null:
		return
	for key_variant in service_overrides.keys():
		var property_name := str(key_variant).strip_edges()
		if property_name.is_empty():
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


func _has_property(target: Object, property_name: String) -> bool:
	for prop in target.get_property_list():
		if str(prop.get("name", "")) == property_name:
			return true
	return false