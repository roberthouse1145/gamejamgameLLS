extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var pm: Node = get_node_or_null("/root/PlanningManager")
	if pm == null:
		print("[FAIL] PlanningManager not found")
		return

	var planner: Node = pm.get_node_or_null("DevPlannerAgent")
	if planner == null:
		print("[FAIL] DevPlannerAgent missing")
		return
	var ai_service: Node = planner.get_node_or_null("AIService")
	if ai_service == null:
		print("[FAIL] DevPlannerAgent AIService missing")
		return
	var tool_defs: Array = ai_service.get_tools_definition() if ai_service.has_method("get_tools_definition") else []
	var tool_names: Array[String] = []
	for item in tool_defs:
		if item is Dictionary:
			var fn: Dictionary = item.get("function", {})
			tool_names.append(str(fn.get("name", "")))
	if "wo_list_order_summaries" not in tool_names:
		print("[FAIL] DevPlannerAgent should expose wo_list_order_summaries")
		return
	print("[OK] DevPlannerAgent exposes work order summary tool")

	var parsed_seed: Variant = pm.call("_parse_json_array_output", """```json
[
  {"title":"任务A","description":"描述A","topic_config":{"goal_description":"目标A"}}
]
```""")
	if not parsed_seed is Array or parsed_seed.size() != 1:
		print("[FAIL] PlanningManager failed to parse seed task JSON array")
		return
	print("[OK] PlanningManager parsed seed task JSON array")

	var parsed_seed_with_preamble: Variant = pm.call("_parse_json_array_output", """当前没有任务，我需要先生成第一批 dev work。

```json
[
  {"title":"任务B","description":"描述B","topic_config":{"goal_description":"目标B"}}
]
```""")
	if not parsed_seed_with_preamble is Array or parsed_seed_with_preamble.size() != 1:
		print("[FAIL] PlanningManager should parse seed task arrays even when the LLM adds preamble text before the JSON block")
		return
	print("[OK] PlanningManager parsed seed task JSON array with preamble text")

	var parsed_seed_with_open_fence: Variant = pm.call("_parse_json_array_output", """我会优先处理最前面的创作缺口。

```json
[
  {"title":"任务C","description":"描述C","topic_config":{"goal_description":"目标C"}}
]""")
	if not parsed_seed_with_open_fence is Array or parsed_seed_with_open_fence.size() != 1:
		print("[FAIL] PlanningManager should parse seed task arrays even when the code fence is left open but the JSON array is complete")
		return
	print("[OK] PlanningManager parsed seed task JSON array with an open code fence")

	var parsed_plan: Variant = pm.call("_parse_json_array_output", """[
	{
		"task_id": "opening_scene",
		"title": "编写开场场景",
		"description": "把已确认内容落成可执行开发任务",
		"task_type": "minigame",
		"minigame_type": "typing_code",
		"stat_changes": {"completion": 8, "quality": 3},
		"stress_cost": 2,
		"weight": 10,
		"one_time": true,
		"prerequisites": [],
		"post_task_work_order": {
			"title": "编写开场场景",
			"description": "具体的写作要求...",
			"kb_sources": ["characters", "world", "story", "notes"],
			"scene_target": "opening_scene",
			"performance_context": "summary"
		}
	}
]""")
	if not parsed_plan is Array or parsed_plan.size() != 1:
		print("[FAIL] PlanningManager failed to parse flat development task JSON array")
		return
	print("[OK] PlanningManager parsed flat development task JSON array")

	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null:
		print("[FAIL] DevCycleManager missing")
		return
	var snapshot: Dictionary = pm.get_node("DevPlannerAgent").call("_get_dev_cycle_snapshot", {})
	if not bool(snapshot.get("success", false)):
		print("[FAIL] DevPlannerAgent failed to read dev cycle snapshot")
		return
	print("[OK] DevPlannerAgent can read dev cycle snapshot")

	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		print("[FAIL] WorkOrderManager missing")
		return
	wom.reset_runtime_state()
	await get_tree().process_frame
	var order: Resource = wom.create_order("测试工单摘要", "这段详情不应该出现在摘要工具里", {
		"source_type": "test",
		"source_id": "planning_manager_test",
	})
	order.priority = 3
	wom.set_order_status(order.id, "in_progress")

	var summary_result: Dictionary = AVGDevWorkOrderTools._wo_list_order_summaries({"limit": 10})
	if not bool(summary_result.get("success", false)):
		print("[FAIL] Failed to get work order summaries")
		wom.reset_runtime_state()
		return
	var rows: Array = summary_result.get("data", [])
	if rows.is_empty():
		print("[FAIL] Work order summary list is empty")
		wom.reset_runtime_state()
		return
	var first: Dictionary = rows[0]
	if str(first.get("title", "")) != "测试工单摘要":
		print("[FAIL] Work order summary title mismatch")
		wom.reset_runtime_state()
		return
	if first.has("description"):
		print("[FAIL] Work order summary should not include description details")
		wom.reset_runtime_state()
		return
	print("[OK] Work order summary tool returns lightweight order snapshots")

	var preflight_text: String = str(pm.call("_build_preflight_context"))
	if preflight_text.find("测试工单摘要") == -1:
		print("[FAIL] PlanningManager preflight context should include work order title")
		wom.reset_runtime_state()
		return
	if preflight_text.find("这段详情不应该出现在摘要工具里") != -1:
		print("[FAIL] PlanningManager preflight context should not include work order description details")
		wom.reset_runtime_state()
		return
	print("[OK] PlanningManager preflight context keeps work order summary lightweight")
	wom.reset_runtime_state()
	print("[OK] PlanningManager test passed")
