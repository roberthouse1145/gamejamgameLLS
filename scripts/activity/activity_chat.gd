class_name ActivityChat
extends RefCounted

const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const ActivityUtilsClass = preload("res://scripts/activity/activity_utils.gd")

const DM_CHANNEL_ID: String = "dm_lin_xia"
const NPC_ID: String = "npc_lin_xia"

signal stage_completed(session_id: String, stage: String, summary: String)
signal stage_timeout(session_id: String, stage: String)

var _activity_type: String = ""
var _stage_key: String = ""


func _init(activity_type: String = "", stage_key: String = "") -> void:
	_activity_type = activity_type
	_stage_key = stage_key


func connect_signals() -> void:
	var chat: Node = _get_chat_manager()
	if chat == null:
		return
	if not chat.topic_completed.is_connected(_on_topic_completed):
		chat.topic_completed.connect(_on_topic_completed)
	if not chat.topic_timeout.is_connected(_on_topic_timeout):
		chat.topic_timeout.connect(_on_topic_timeout)


func disconnect_signals() -> void:
	var chat: Node = _get_chat_manager()
	if chat == null:
		return
	if chat.topic_completed.is_connected(_on_topic_completed):
		chat.topic_completed.disconnect(_on_topic_completed)
	if chat.topic_timeout.is_connected(_on_topic_timeout):
		chat.topic_timeout.disconnect(_on_topic_timeout)


func start_topic(session_id: String, stage: String, config: Dictionary) -> bool:
	var chat: Node = _get_chat_manager()
	if chat == null or not chat.has_method("activate_topic") or not chat.has_method("request_topic_npc_reply"):
		return false
	if chat.has_method("has_active_topic") and chat.has_active_topic(DM_CHANNEL_ID):
		return false

	var topic := ChatTopicClass.new()
	topic.topic_id = "%s_%s" % [stage, session_id]
	topic.topic_type = "relationship_event"
	topic.display_title = "%s_%s" % [stage, str(config.get("display_label", _activity_type))]
	topic.npc_id = NPC_ID
	topic.channel_id = DM_CHANNEL_ID
	topic.system_prompt = str(config.get("system_prompt", ""))
	topic.goal_description = str(config.get("goal", ""))
	topic.max_turns = int(config.get("max_turns", 1))
	topic.timeout_seconds = int(config.get("timeout_seconds", 120))
	topic.context_data = {
		"session_id": session_id,
		_stage_key: stage,
		"suppress_system_notice": true,
	}
	var extra_context: Dictionary = config.get("extra_context", {})
	for key in extra_context:
		topic.context_data[key] = extra_context[key]

	if not chat.activate_topic(topic):
		return false

	var seed_message: String = str(config.get("seed_message", ""))
	if chat.request_topic_npc_reply(DM_CHANNEL_ID, seed_message, false, true):
		return true

	var topic_mgr: Variant = chat.get("topic_manager")
	if topic_mgr != null:
		var active_topic: ChatTopic = chat.get_active_topic(DM_CHANNEL_ID)
		if active_topic != null and active_topic.topic_id == topic.topic_id:
			topic_mgr.timeout_topic(active_topic)
	return false


func send_local_message(text: String) -> void:
	var chat: Node = _get_chat_manager()
	if chat != null and chat.has_method("store_npc_message"):
		chat.store_npc_message(DM_CHANNEL_ID, NPC_ID, text)


func post_moment(text: String, image_hint: String = "", delay_minutes: int = 5) -> Dictionary:
	var chat: Node = _get_chat_manager()
	if chat != null and chat.has_method("post_moment"):
		return chat.post_moment(NPC_ID, text, image_hint, delay_minutes)
	return {}


func _on_topic_completed(topic: ChatTopic, result: Dictionary) -> void:
	if topic == null:
		return
	var context: Dictionary = topic.context_data
	var session_id := str(context.get("session_id", "")).strip_edges()
	if session_id.is_empty():
		return
	var stage := str(context.get(_stage_key, "")).strip_edges()
	if stage.is_empty():
		return
	var summary: String = ActivityUtilsClass.extract_topic_summary(result)
	stage_completed.emit(session_id, stage, summary)


func _on_topic_timeout(topic: ChatTopic) -> void:
	if topic == null:
		return
	var context: Dictionary = topic.context_data
	var session_id := str(context.get("session_id", "")).strip_edges()
	if session_id.is_empty():
		return
	var stage := str(context.get(_stage_key, "")).strip_edges()
	if stage.is_empty():
		return
	stage_timeout.emit(session_id, stage)


func _get_chat_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/ChatManager")
