extends Node


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null:
		print("[FAIL] Creative seed flow test missing DevCycleManager")
		return

	if dcm.has_method("reset_runtime_state"):
		dcm.reset_runtime_state()
	await get_tree().process_frame

	var brief_data: Dictionary = {
		"game_title": "月塔密约",
		"game_genre": "悬疑推理",
		"game_tags": "暧昧, 黑暗",
		"game_outline": "新生入学后意外卷入学院禁书库的秘密，并在调查中逐渐靠近一位立场暧昧的少女。",
	}

	var desc: String = dcm.call("_build_creative_seed_order_description", brief_data)
	var desc_ok: bool = desc.contains("creative_core") \
		and desc.contains("open_design_questions") \
		and desc.contains("女主角给人的第一印象") \
		and desc.contains("第一章开场事件")
	if not desc_ok:
		print("[FAIL] Creative seed order description missing required targets")
		print(desc)
		if dcm.has_method("reset_runtime_state"):
			dcm.reset_runtime_state()
		return
	print("[OK] Creative seed order description includes KB targets and discussion axes")

	dcm.set("_latest_creative_brief", brief_data.duplicate(true))
	dcm.call("_replace_default_concept_tasks_with_seed_flow")
	await get_tree().process_frame

	var old_task_hidden: bool = dcm.get_task("design_protagonist").is_empty() \
		and dcm.get_task("design_heroine").is_empty() \
		and dcm.get_task("plan_story_outline").is_empty()
	if not old_task_hidden:
		print("[FAIL] Default concept tasks were not suppressed after switching to seed flow")
		if dcm.has_method("reset_runtime_state"):
			dcm.reset_runtime_state()
		return
	print("[OK] Default concept tasks are suppressed by creative seed flow")

	var added_count: int = int(dcm.call("_apply_seed_task_generation_result", []))
	await get_tree().process_frame
	if added_count != 3:
		print("[FAIL] Seed flow should register exactly 3 initial dev work tasks, got %d" % added_count)
		if dcm.has_method("reset_runtime_state"):
			dcm.reset_runtime_state()
		return

	var heroine_task: Dictionary = dcm.get_task("seed_discuss_heroine_hook")
	var protagonist_task: Dictionary = dcm.get_task("seed_discuss_protagonist_role")
	var opening_task: Dictionary = dcm.get_task("seed_discuss_opening_scene")
	var task_ok: bool = not heroine_task.is_empty() \
		and not protagonist_task.is_empty() \
		and not opening_task.is_empty() \
		and str(heroine_task.get("task_type", "")) == "chat_topic" \
		and str(protagonist_task.get("task_type", "")) == "chat_topic" \
		and str(opening_task.get("task_type", "")) == "chat_topic"
	if not task_ok:
		print("[FAIL] Seed flow did not create the expected first batch chat tasks")
		if dcm.has_method("reset_runtime_state"):
			dcm.reset_runtime_state()
		return

	var prereqs: Array = opening_task.get("prerequisites", [])
	var prereq_ok: bool = "seed_discuss_heroine_hook" in prereqs \
		and "seed_discuss_protagonist_role" in prereqs
	if not prereq_ok:
		print("[FAIL] Opening discussion task should depend on the first two seed tasks")
		print("  prerequisites: %s" % str(prereqs))
		if dcm.has_method("reset_runtime_state"):
			dcm.reset_runtime_state()
		return

	print("[OK] Creative seed flow registered the expected first batch of dev work")

	if dcm.has_method("reset_runtime_state"):
		dcm.reset_runtime_state()
	print("[OK] Creative seed flow test passed")
