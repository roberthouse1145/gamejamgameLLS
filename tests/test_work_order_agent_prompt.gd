extends Node

const AgentScene = preload("res://scenes/avg/dev_tools/work_order_agent.tscn")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== WorkOrderAgent Prompt Test ===")
	await _test_agent_prompt_and_budget()
	_print_summary()


func _test_agent_prompt_and_budget() -> void:
	var agent: ChatAgent = AgentScene.instantiate()
	add_child(agent)
	await get_tree().process_frame

	_assert("agent max tokens raised", agent.get_node("AIService").default_max_tokens >= 16384, str(agent.get_node("AIService").default_max_tokens))
	_assert("agent history budget raised", agent.max_history_chars >= 180000, str(agent.max_history_chars))

	var prompt_text: String = PromptManager.resolve("work_order_agent")
	var required_phrases: Array[String] = [
		"直接完成工单",
		"get_project_context",
		"upsert_scene",
		"research(task)",
		"wo_finish_order",
		"不要调用 `finish` 或 `project_save`",
	]
	var missing: Array[String] = []
	for phrase in required_phrases:
		if not prompt_text.contains(phrase):
			missing.append(phrase)

	_assert("work_order_agent prompt contains guardrails", missing.is_empty(), ", ".join(missing))
	agent.queue_free()


func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % label)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [label, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
