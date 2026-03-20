extends Control

const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const WindowManagerClass = preload("res://scripts/pseudo_os/window_manager.gd")


func _ready() -> void:
	print("[Test] LinkChat protocol tests start")
	_test_strip_thinking_tag_variants()
	_test_linkchat_response_protocol_parser()
	_test_linkchat_standalone_card_line_parser()
	_test_linkchat_extended_protocol_parser()
	await _ensure_window_manager()
	await _test_linkchat_protocol_effect_dispatch()
	print("[Test] LinkChat protocol tests ready")


func _ensure_window_manager() -> void:
	if AppManager.window_manager != null:
		return

	var window_container := Control.new()
	window_container.name = "TestWindowContainer"
	window_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(window_container)

	var window_manager := WindowManagerClass.new()
	add_child(window_manager)
	await get_tree().process_frame
	window_manager.set_window_container(window_container)
	AppManager.set_window_manager(window_manager)
	print("[OK] WindowManager ready for LinkChat protocol tests")


func _test_strip_thinking_tag_variants() -> void:
	var malformed := "<thinking>\ninternal\n</think>@npc_lin_xia: first line\n@npc_lin_xia: second line"
	var malformed_result: Dictionary = ChatManager.call("_strip_thinking_tags", malformed)
	var malformed_ok: bool = str(malformed_result.get("thinking", "")) == "internal" \
		and str(malformed_result.get("body", "")).begins_with("@npc_lin_xia: first line")
	if not malformed_ok:
		print("[FAIL] Thinking tag stripper malformed compatibility regression")
		print("  malformed_result: %s" % str(malformed_result))
		return

	var short_tag := "<think>internal</think>\n@npc_lin_xia: short tag ok"
	var short_result: Dictionary = ChatManager.call("_strip_thinking_tags", short_tag)
	var short_ok: bool = str(short_result.get("thinking", "")) == "internal" \
		and str(short_result.get("body", "")) == "@npc_lin_xia: short tag ok"
	if not short_ok:
		print("[FAIL] Thinking tag stripper short tag regression")
		print("  short_result: %s" % str(short_result))
		return

	print("[OK] Thinking tag stripper supports think/thinking variants")


func _test_linkchat_response_protocol_parser() -> void:
	var line_protocol_response := "<thinking>test</thinking>\n@npc_lin_xia: theme is out\n@npc_lin_xia: [card:web_page url=gamejam://forum/theme]\n[TOPIC_COMPLETE]\n> ok\n> what theme?"
	var line_stripped: Dictionary = ChatManager.call("_strip_thinking_tags", line_protocol_response)
	var parsed_line: Dictionary = ChatManager.call("_parse_ai_response_text", str(line_stripped.get("body", "")), "npc_lin_xia")
	var line_messages: Array = parsed_line.get("messages", [])
	var line_replies: Array = parsed_line.get("recommended_replies", [])
	var line_ok: bool = line_messages.size() == 2 \
		and str(line_messages[0].get("speaker", "")) == "npc_lin_xia" \
		and "[TOPIC_COMPLETE]" in str(line_messages[1].get("content", "")) \
		and line_messages[1].has("card") \
		and str(line_messages[1].get("card", {}).get("url", "")) == "gamejam://forum/theme" \
		and line_replies.size() == 2

	if not line_ok:
		print("[FAIL] LinkChat line protocol parser regression")
		print("  parsed_line: %s" % str(parsed_line))
		return

	var legacy_json_response := "<thinking>test</thinking>\n{\n  \"messages\": [\n    {\"speaker\": \"npc_lin_xia\", \"content\": \"legacy json still works\"}\n  ],\n  \"recommended_replies\": [\n    \"ok\"\n  ]\n}\n[TOPIC_COMPLETE]"
	var legacy_stripped: Dictionary = ChatManager.call("_strip_thinking_tags", legacy_json_response)
	var parsed_legacy: Dictionary = ChatManager.call("_parse_ai_response_text", str(legacy_stripped.get("body", "")), "npc_lin_xia")
	var legacy_messages: Array = parsed_legacy.get("messages", [])
	var legacy_replies: Array = parsed_legacy.get("recommended_replies", [])
	var legacy_ok: bool = legacy_messages.size() == 1 \
		and str(legacy_messages[0].get("speaker", "")) == "npc_lin_xia" \
		and "legacy json still works" in str(legacy_messages[0].get("content", "")) \
		and "[TOPIC_COMPLETE]" in str(legacy_messages[0].get("content", "")) \
		and legacy_replies.size() == 1

	if not legacy_ok:
		print("[FAIL] LinkChat legacy JSON compatibility regression")
		print("  parsed_legacy: %s" % str(parsed_legacy))
		return

	print("[OK] LinkChat response parser supports line protocol and legacy JSON")


func _test_linkchat_standalone_card_line_parser() -> void:
	var response := "@npc_lin_xia: this should keep the text\n[card:image image_id=linxia_chibi_heart]\n[TOPIC_COMPLETE]"
	var parsed: Dictionary = ChatManager.call("_parse_ai_response_text", response, "npc_lin_xia")
	var messages: Array = parsed.get("messages", [])
	var ok: bool = messages.size() == 1 \
		and str(messages[0].get("speaker", "")) == "npc_lin_xia" \
		and str(messages[0].get("content", "")) == "this should keep the text[TOPIC_COMPLETE]" \
		and messages[0].has("card") \
		and str(messages[0].get("card", {}).get("type", "")) == "image" \
		and str(messages[0].get("card", {}).get("image_id", "")) == "linxia_chibi_heart"

	if not ok:
		print("[FAIL] LinkChat standalone card line regression")
		print("  parsed: %s" % str(parsed))
		return

	print("[OK] LinkChat parser attaches standalone card lines to the previous message")


func _test_linkchat_extended_protocol_parser() -> void:
	var line_protocol_response := "@npc_lin_xia: you check this first.\n!event id=jam_rules_prompted url=\"gamejam://forum/theme\"\n!action type=open_browser url=\"gamejam://forum/theme\" timing=after_messages\n!complete summary=\"check the theme page first\"\n> I am going now\n> tell me your idea first"
	var parsed_line: Dictionary = ChatManager.call("_parse_ai_response_text", line_protocol_response, "npc_lin_xia")
	var line_messages: Array = parsed_line.get("messages", [])
	var line_replies: Array = parsed_line.get("recommended_replies", [])
	var line_events: Array = parsed_line.get("events", [])
	var line_actions: Array = parsed_line.get("actions", [])
	var extended_ok: bool = line_messages.size() == 1 \
		and "[TOPIC_COMPLETE]" in str(line_messages[0].get("content", "")) \
		and bool(parsed_line.get("topic_complete", false)) \
		and str(parsed_line.get("topic_summary", "")) == "check the theme page first" \
		and line_replies.size() == 2 \
		and line_events.size() == 1 \
		and str(line_events[0].get("id", "")) == "jam_rules_prompted" \
		and str(line_events[0].get("payload", {}).get("url", "")) == "gamejam://forum/theme" \
		and line_actions.size() == 1 \
		and str(line_actions[0].get("type", "")) == "open_browser" \
		and str(line_actions[0].get("timing", "")) == "after_messages"

	if not extended_ok:
		print("[FAIL] LinkChat extended line protocol parser regression")
		print("  parsed_line: %s" % str(parsed_line))
		return

	print("[OK] LinkChat extended line protocol parser supports event/action/complete")


func _test_linkchat_protocol_effect_dispatch() -> void:
	if AppManager.is_app_running("browser"):
		AppManager.close_app("browser", true)
	await get_tree().process_frame

	var topic := ChatTopicClass.new()
	topic.topic_id = "test_protocol_effects"
	topic.topic_type = "story_event"
	topic.display_title = "Protocol Effects"
	topic.npc_id = "npc_lin_xia"
	topic.channel_id = "dm_lin_xia"
	topic.context_data = {
		"allowed_events": ["jam_rules_prompted"],
		"allowed_actions": ["open_browser"],
	}

	var capture := {
		"event_id": "",
		"url": "",
	}
	ChatManager.chat_event_emitted.connect(func(emitted_topic: ChatTopic, event_id: String, payload: Dictionary) -> void:
		if emitted_topic.topic_id != topic.topic_id:
			return
		capture["event_id"] = event_id
		capture["url"] = str(payload.get("url", capture.get("url", "")))
	, CONNECT_ONE_SHOT)
	BrowserManager.url_open_requested.connect(func(url: String, _design_prompt: String, _page_context: String) -> void:
		capture["url"] = url
	, CONNECT_ONE_SHOT)

	var events: Array[Dictionary] = [{
		"id": "jam_rules_prompted",
		"timing": "immediate",
		"payload": {"url": "gamejam://forum/theme"},
	}]
	var actions: Array[Dictionary] = [{
		"type": "open_browser",
		"url": "gamejam://forum/theme",
		"timing": "immediate",
	}]

	ChatManager.call("_execute_protocol_effects", topic, events, actions)
	await get_tree().process_frame
	await get_tree().process_frame

	var dispatch_ok: bool = str(capture.get("event_id", "")) == "jam_rules_prompted" \
		and str(capture.get("url", "")) == "gamejam://forum/theme"
	if not dispatch_ok:
		print("[FAIL] LinkChat protocol effects dispatch regression")
		print("  captured_event_id: %s" % str(capture.get("event_id", "")))
		print("  captured_url: %s" % str(capture.get("url", "")))
		return

	print("[OK] LinkChat protocol effects dispatch reaches event bus and browser")
