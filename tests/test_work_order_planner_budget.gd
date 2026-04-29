extends Node

const ControllerScene = preload("res://scenes/avg/dev_tools/work_order_controller_agent.tscn")


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== WorkOrder Planner Budget Test ===")

	var controller: ChatAgent = ControllerScene.instantiate()
	add_child(controller)
	await get_tree().process_frame

	var planner: Node = controller.get_node_or_null("PlannerAgent")
	if planner == null:
		print("[FAIL] PlannerAgent missing")
		return

	var planner_ai: AIService = planner.get_node_or_null("AIService")
	if planner_ai == null:
		print("[FAIL] PlannerAgent AIService missing")
		return

	if planner_ai.default_max_tokens == 16384:
		print("[OK] PlannerAgent default_max_tokens is default 16384")
	else:
		print("[FAIL] PlannerAgent default_max_tokens expected 16384, got %d" % planner_ai.default_max_tokens)

	var prompt_text: String = PromptManager.resolve("work_order_planner")
	var required_phrases: Array[String] = [
		"## 文档篇幅预算",
		"`story` 文档通常控制在 250-700 字",
		"不要写“为什么这样设计”",
	]
	var missing: Array[String] = []
	for phrase in required_phrases:
		if not prompt_text.contains(phrase):
			missing.append(phrase)

	if missing.is_empty():
		print("[OK] work_order_planner prompt contains brevity guardrails")
	else:
		print("[FAIL] work_order_planner prompt missing brevity guardrails: %s" % ", ".join(missing))

