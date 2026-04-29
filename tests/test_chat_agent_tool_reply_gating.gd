extends Node

const ChatAgentScene = preload("res://scenes/llm/chat_agent.tscn")

var _completed_count: int = 0
var _last_content: String = ""


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	await _test_tool_reply_gating()
	await _test_history_char_trim()
	await _test_skill_metadata_default_on()
	await _test_tool_llm_projection()


func _test_tool_reply_gating() -> void:
	var agent: ChatAgent = ChatAgentScene.instantiate()
	add_child(agent)
	await get_tree().process_frame

	agent.message_completed.connect(func(_request_id: String, content: String) -> void:
		_completed_count += 1
		_last_content = content
	)

	agent.set("prompt_key", "")
	agent.set("role", "")
	agent.set("_is_busy", true)

	var intermediate_response := {
		"choices": [{
			"message": {
				"content": "@npc_lin_xia: 我先看一下当前项目状态。",
				"tool_calls": [{
					"id": "call_kb_1",
					"type": "function",
					"function": {
						"name": "kb_read",
						"arguments": "{\"category\":\"story\"}"
					}
				}]
			}
		}]
	}
	agent._on_request_completed("req_tool_gate", intermediate_response)

	if _completed_count != 0:
		print("[FAIL] ChatAgent should not emit message_completed before tool-call loop finishes")
		agent.queue_free()
		return
	if not agent.is_busy():
		print("[FAIL] ChatAgent should stay busy after intermediate tool-call response")
		agent.queue_free()
		return

	agent._on_tool_executed(
		"req_tool_gate",
		"kb_read",
		{"category": "story"},
		{"success": true, "data": []},
		"call_kb_1"
	)
	var history_after_tool: Array = agent.get_messages()
	if history_after_tool.is_empty():
		print("[FAIL] ChatAgent should keep tool result in history")
		agent.queue_free()
		return
	var tool_msg: Dictionary = history_after_tool[-1]
	var tool_content: String = str(tool_msg.get("content", ""))
	if tool_content != "kb_read success: 0 docs []":
		print("[FAIL] ChatAgent should compact tool result in history: %s" % tool_content)
		agent.queue_free()
		return

	var final_response := {
		"choices": [{
			"message": {
				"content": "@npc_lin_xia: 第一章开场节拍已经有明确方向了。"
			}
		}]
	}
	agent._on_request_completed("req_tool_gate", final_response)

	if _completed_count != 1:
		print("[FAIL] ChatAgent should emit exactly one final message_completed after tool-call loop")
		agent.queue_free()
		return
	if agent.is_busy():
		print("[FAIL] ChatAgent should leave busy state after final response")
		agent.queue_free()
		return
	if not _last_content.contains("第一章开场节拍"):
		print("[FAIL] ChatAgent final reply content mismatch: %s" % _last_content)
		agent.queue_free()
		return

	agent.queue_free()
	print("[OK] ChatAgent only exposes the final reply after tool-call chaining completes")


func _test_history_char_trim() -> void:
	var agent: ChatAgent = ChatAgentScene.instantiate()
	add_child(agent)
	await get_tree().process_frame

	agent.max_history_messages = 0
	agent.max_history_chars = 170
	agent.history_preserve_recent_messages = 2

	var bulky_tool: String = "T".repeat(90)
	agent.add_message("user", "old-user-context")
	agent.add_message("tool", bulky_tool)
	agent.add_message("assistant", "older-assistant-context")
	agent.add_message("user", "recent-user-context")

	var history: Array = agent.get_messages()
	var found_bulky_tool: bool = false
	var found_recent_user: bool = false
	for msg in history:
		var msg_dict: Dictionary = msg
		var content: String = str(msg_dict.get("content", ""))
		if content == bulky_tool:
			found_bulky_tool = true
		if content == "recent-user-context":
			found_recent_user = true

	if found_bulky_tool:
		print("[FAIL] ChatAgent should trim old bulky tool history first when char budget is exceeded")
		agent.queue_free()
		return
	if not found_recent_user:
		print("[FAIL] ChatAgent should preserve recent user context while trimming history")
		agent.queue_free()
		return

	agent.queue_free()
	print("[OK] ChatAgent trims bulky old tool history before recent context")


func _test_skill_metadata_default_on() -> void:
	var agent: ChatAgent = ChatAgentScene.instantiate()
	add_child(agent)
	await get_tree().process_frame

	agent.set_system_prompt_override("BASE")
	agent.register_skill("story_writing", "编写故事实现稿", "详细规则")

	var default_messages: Array = agent._build_messages_for_api()
	var default_msg: Dictionary = default_messages[0]
	var default_system: String = str(default_msg.get("content", ""))
	if not default_system.contains("# 可用 Skills"):
		print("[FAIL] ChatAgent should inject available skill metadata by default")
		agent.queue_free()
		return

	agent.include_available_skills_metadata_in_prompt = false
	var opt_out_messages: Array = agent._build_messages_for_api()
	var opt_out_msg: Dictionary = opt_out_messages[0]
	var opt_out_system: String = str(opt_out_msg.get("content", ""))
	if opt_out_system.contains("# 可用 Skills"):
		print("[FAIL] ChatAgent should allow opting out of available skill metadata injection")
		agent.queue_free()
		return

	agent.queue_free()
	print("[OK] ChatAgent injects available skill metadata by default and supports opt-out")


func _test_tool_llm_projection() -> void:
	var agent: ChatAgent = ChatAgentScene.instantiate()
	add_child(agent)
	await get_tree().process_frame

	var service: AIService = agent.get_node("AIService")
	service.register_tool(
		"project_save",
		"save project",
		{"type": "object", "properties": {}},
		func(_args: Dictionary) -> Variant:
			return {"success": true, "message": "项目已保存", "extra": {"huge": "x".repeat(200)}},
		["success"]
	)
	service.register_tool(
		"get_scene_script",
		"get scene dsl",
		{"type": "object", "properties": {"scene_id": {"type": "string"}}},
		func(_args: Dictionary) -> Variant:
			return {"success": true, "data": {"scene_id": "scene_001", "dsl": "> " + "hello".repeat(120)}},
		["success", "data.scene_id", "data.dsl"]
	)

	var projected_save: String = service._summarize_tool_result_for_conversation(
		"project_save",
		{"success": true, "message": "项目已保存", "extra": {"huge": "x".repeat(200)}},
		{}
	)
	if projected_save != "{\"success\":true}":
		print("[FAIL] AIService should project project_save result for LLM: %s" % projected_save)
		agent.queue_free()
		return

	var projected_script: String = service._summarize_tool_result_for_conversation(
		"get_scene_script",
		{"success": true, "data": {"scene_id": "scene_001", "dsl": "> " + "hello".repeat(120)}},
		{}
	)
	if not projected_script.contains("\"scene_id\":\"scene_001\"") or not projected_script.contains("hellohellohello"):
		print("[FAIL] AIService should keep selected DSL fields visible to LLM: %s" % projected_script)
		agent.queue_free()
		return
	if projected_script.ends_with("..."):
		print("[FAIL] AIService should not truncate explicit LLM-visible DSL content: %s" % projected_script)
		agent.queue_free()
		return

	agent.queue_free()
	print("[OK] AIService respects per-tool LLM-visible result projection")
