extends Node
## 真实 LLM 生成两类邀约 Chat DSL，由 ChatRunner 解析并执行。

const TOPIC_MANAGER_SCENE = preload("res://scenes/chat/topic_manager.tscn")
const CHAT_TOPIC_CLASS = preload("res://scripts/chat/resources/chat_topic.gd")
const COMPANION_ID: String = "lu_yuanyuan"

var _manager: TopicManager = null
var _case_index: int = 0
var _messages: Array[String] = []
var _cases: Array[Dictionary] = []


func _ready() -> void:
	_cases = [
		{"id": "invite_accepted", "kind": "invitation", "accepted": true},
		{"id": "invite_rejected", "kind": "invitation", "accepted": false},
	]
	_manager = TOPIC_MANAGER_SCENE.instantiate() as TopicManager
	if _manager == null:
		print("LAB_CHAT_REASONING_COMPLETE ok=0 reason=manager_instantiate_failed")
		return
	add_child(_manager)
	_manager.topic_message_emitted.connect(_on_message_emitted)
	_manager.topic_completed.connect(_on_topic_completed)
	_manager.topic_cancelled.connect(_on_topic_cancelled)
	call_deferred("_run_next_case")


func _run_next_case() -> void:
	if _case_index >= _cases.size():
		print("LAB_CHAT_REASONING_COMPLETE ok=1 cases=%d" % _cases.size())
		return
	var case_data: Dictionary = _cases[_case_index]
	var case_id: String = str(case_data.get("id", ""))
	var topic := CHAT_TOPIC_CLASS.new() as ChatTopic
	topic.topic_id = "lab_chat_reasoning_%s" % case_id
	topic.channel_id = COMPANION_ID
	topic.mode = ChatTopic.Mode.LLM
	topic.auto_advance = true
	topic.min_advance_delay = 0.1
	topic.advance_char_seconds = 0.0
	topic.max_advance_delay = 0.5
	topic.prompt = _build_case_prompt(case_data)
	_messages.clear()
	print("[LabChatReasoning] START case=%s" % case_id)
	if topic.prompt.is_empty() or not _manager.activate_topic(topic, {}, [COMPANION_ID]):
		print("[LabChatReasoning] CASE_FAILED case=%s reason=activation_failed" % case_id)
		_advance_case()


func _build_case_prompt(case_data: Dictionary) -> String:
	var companion: CharacterProfile = LinkChatManager.get_character(COMPANION_ID)
	if companion == null:
		return ""
	var accepted: bool = bool(case_data.get("accepted", false))
	var activity: OutingActivity = OutingManager.get_activity("riverside_walk_01")
	var place: MapPlace = OutingManager.get_place("riverside_park")
	if activity == null or place == null:
		return ""
	return OutingManager._resolve_outing_prompt("outing/invitation", {
		"player_profile": OutingManager._player_prompt(),
		"invited_display_name": companion.display_name,
		"invited_persona": companion.persona_prompt,
		"activity_title": activity.title,
		"place_name": place.display_name,
		"conversation_context": "当前私聊没有历史消息。这次邀约是该会话的开场。",
		"conversation_structure": OutingManager._build_invitation_conversation_structure(accepted, companion.character_id),
		"location_card_message": OutingManager._build_invitation_location_card_message(activity, place),
		"authoritative_result": "接受邀约" if accepted else "拒绝邀约",
		"invited_speaker_id": companion.character_id,
		"expected_result": "accepted" if accepted else "rejected",
	})


func _on_message_emitted(
	_topic: ChatTopic,
	speaker_id: String,
	text: String,
	_is_player: bool,
	card: Dictionary
) -> void:
	var rendered: String = text
	if not card.is_empty():
		rendered = "[card:%s]" % str(card.get("type", "unknown"))
	_messages.append("%s: %s" % [speaker_id, rendered])


func _on_topic_completed(topic: ChatTopic, result: Dictionary) -> void:
	print("[LabChatReasoning] RESULT case=%s messages=%d result=%s" % [
		topic.topic_id.trim_prefix("lab_chat_reasoning_"),
		_messages.size(),
		str(result.get("result_id", "")),
	])
	print("[LabChatReasoning] TRANSCRIPT\n%s" % "\n".join(_messages))
	_advance_case()


func _on_topic_cancelled(topic: ChatTopic, reason: String) -> void:
	print("[LabChatReasoning] CASE_FAILED case=%s reason=%s" % [
		topic.topic_id.trim_prefix("lab_chat_reasoning_"),
		reason,
	])
	_advance_case()


func _advance_case() -> void:
	_case_index += 1
	call_deferred("_run_next_case")
