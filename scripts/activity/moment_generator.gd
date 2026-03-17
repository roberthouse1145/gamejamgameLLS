class_name MomentGenerator
extends Node

const ActivityUtilsClass = preload("res://scripts/activity/activity_utils.gd")
const ActivityChatClass = preload("res://scripts/activity/activity_chat.gd")

signal moment_completed(session_id: String, moment: Dictionary)

var _ai_service: AIService = null
var _llm_enabled: bool = false
var _request_to_session: Dictionary = {}
var _session_config: Dictionary = {}


func _ready() -> void:
	_setup_ai_service()


func _setup_ai_service() -> void:
	_ai_service = AIService.new()
	_ai_service.name = "MomentAIService"
	add_child(_ai_service)

	var config_mgr := AIConfigManager.new()
	if config_mgr.load_config():
		_llm_enabled = config_mgr.apply_to_service(_ai_service, "linkchat")
	else:
		_llm_enabled = false

	_ai_service.request_completed.connect(_on_request_completed)
	_ai_service.request_failed.connect(_on_request_failed)


func start(session_id: String, config: Dictionary) -> bool:
	if _ai_service == null or not _llm_enabled:
		return false

	var request_id := _ai_service.chat_simple(
		str(config.get("user_prompt", "")),
		str(config.get("system_prompt", ""))
	)
	if request_id.is_empty():
		return false

	_request_to_session[request_id] = session_id
	_session_config[session_id] = config
	return true


func store_local(session_id: String, text: String, image_hint: String = "") -> Dictionary:
	var chat: Node = _get_chat_manager()
	var moment: Dictionary = {}
	if chat != null and chat.has_method("post_moment"):
		var delay: int = 3 + (abs(hash(session_id)) % 9)
		moment = chat.post_moment(ActivityChatClass.NPC_ID, text, image_hint, delay)
	moment_completed.emit(session_id, moment)
	return moment


func reset_runtime_state() -> void:
	_request_to_session.clear()
	_session_config.clear()


func _on_request_completed(request_id: String, response: Dictionary) -> void:
	if not _request_to_session.has(request_id):
		return
	var session_id := str(_request_to_session.get(request_id, ""))
	_request_to_session.erase(request_id)
	var config: Dictionary = _session_config.get(session_id, {})
	_session_config.erase(session_id)

	var text := ActivityUtilsClass.sanitize_generated_text(ActivityUtilsClass.extract_ai_text(response))
	if text.is_empty():
		text = str(config.get("local_fallback_text", ""))

	var image_hint: String = str(config.get("image_hint", ""))
	var chat: Node = _get_chat_manager()
	var moment: Dictionary = {}
	if chat != null and chat.has_method("post_moment"):
		var delay: int = 3 + (abs(hash(session_id)) % 9)
		moment = chat.post_moment(ActivityChatClass.NPC_ID, text, image_hint, delay)

	moment_completed.emit(session_id, moment)


func _on_request_failed(request_id: String, _error: String, _error_code: int) -> void:
	if not _request_to_session.has(request_id):
		return
	var session_id := str(_request_to_session.get(request_id, ""))
	_request_to_session.erase(request_id)
	var config: Dictionary = _session_config.get(session_id, {})
	_session_config.erase(session_id)

	var text: String = str(config.get("local_fallback_text", ""))
	var image_hint: String = str(config.get("image_hint", ""))
	store_local(session_id, text, image_hint)


func _get_chat_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/ChatManager")
