extends Node

const ActivityOptionLLMServiceClass = preload("res://scripts/activity/activity_option_llm_service.gd")
const CreativeDecisionScene = preload("res://scenes/minigames/creative_decision.tscn")

var _failures: int = 0


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	_test_activity_option_agent_tools()
	_test_creative_decision_agent_tools()
	if _failures == 0:
		print("[TestMinigameAgentTools] PASS")
	else:
		print("[TestMinigameAgentTools] FAIL count=%d" % _failures)
	print("[DONE] 测试完毕。请通过 mcp_godot_mcp_stop_project 手动停止。")


func _test_activity_option_agent_tools() -> void:
	var service: ActivityOptionLLMService = ActivityOptionLLMServiceClass.new()
	add_child(service)
	service.configure(
		"TestMinigameAgentService",
		"minigame",
		["chat_default"],
		{
			"use_chat_agent": true,
			"enable_project_tools": true,
			"max_tool_iterations": 0,
		},
		{}
	)
	var agent: Node = service.get("_agent")
	var ai_service: Node = agent.get_node_or_null("AIService") if agent != null else null
	_assert_tool(ai_service, "kb_read", "ActivityOptionLLMService agent")
	_assert_tool(ai_service, "wo_list_order_summaries", "ActivityOptionLLMService agent")
	_assert_tool(ai_service, "get_dev_cycle_snapshot", "ActivityOptionLLMService agent")
	_assert_tool_iterations_unlimited(ai_service, "ActivityOptionLLMService agent")
	service.queue_free()


func _test_creative_decision_agent_tools() -> void:
	var cd: Node = CreativeDecisionScene.instantiate()
	add_child(cd)
	cd.call("_setup_ai_services")
	for agent_name in ["CreativeDecisionDialogAI", "CreativeDecisionProposalAI", "CreativeDecisionWorkOrderBriefAI"]:
		var ai_service: Node = cd.get_node_or_null("%s/AIService" % agent_name)
		_assert_tool(ai_service, "kb_read", agent_name)
		_assert_tool(ai_service, "wo_list_order_summaries", agent_name)
		_assert_tool(ai_service, "get_dev_cycle_snapshot", agent_name)
		_assert_tool_iterations_unlimited(ai_service, agent_name)
	cd.queue_free()


func _assert_tool(ai_service: Node, tool_name: String, label: String) -> void:
	if ai_service == null or not ai_service.has_method("get_tools_definition"):
		_fail("%s missing AIService" % label)
		return
	for tool in ai_service.get_tools_definition():
		if not tool is Dictionary:
			continue
		var fn: Dictionary = tool.get("function", {})
		if str(fn.get("name", "")) == tool_name:
			print("[PASS] %s has %s" % [label, tool_name])
			return
	_fail("%s missing %s" % [label, tool_name])


func _assert_tool_iterations_unlimited(ai_service: Node, label: String) -> void:
	if ai_service == null:
		_fail("%s missing AIService" % label)
		return
	var max_iterations := int(ai_service.get("max_tool_iterations"))
	if max_iterations == 0:
		print("[PASS] %s uses unlimited tool iterations" % label)
		return
	_fail("%s max_tool_iterations should be 0, got %d" % [label, max_iterations])


func _fail(message: String) -> void:
	_failures += 1
	print("[FAIL] %s" % message)
