extends Node
## test_lock_creative_direction_flow
##
## 验证立项讨论 dev work 的新链路：
## 1) 注入 lock_creative_direction.json → 路由到 creative_decision 小游戏
## 2) 讨论结束 → 派发 post_task_work_order 工单
## 3) 工单完成 → 自动触发首次 _generate_development_plan()
## 4) 整个过程没有任何 seed_task / concept_gate 字段被写入

const TASK_TEMPLATE_PATH: String = "res://resources/dev_work/story_tasks/lock_creative_direction.json"
const TASK_ID: String = "lock_creative_direction"
const CREATIVE_BRIEF_DOC_ID: String = "creative_brief"


class FakePlanningManager:
	extends Node

	var request_count: int = 0
	var last_kb_content: String = ""

	func request_development_plan(kb_content: String) -> String:
		request_count += 1
		last_kb_content = kb_content
		return "fake_development_plan_%d" % request_count


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if dcm == null or kb == null or wom == null:
		print("[FAIL] required autoloads missing (dcm=%s, kb=%s, wom=%s)" % [dcm, kb, wom])
		return

	if wom.has_method("reset_runtime_state"):
		wom.reset_runtime_state()
	if dcm.has_method("reset_runtime_state"):
		dcm.reset_runtime_state()
	var original_docs: Array = kb.documents.duplicate(true)
	kb.documents.clear()
	await get_tree().process_frame

	# ------- 0. 静态契约：seed/concept_gate 已经从 DevCycleManager 与 PlanningManager 完全消失 -------
	var dcm_methods_clean: bool = (
		not dcm.has_method("on_creative_brief_completed")
		and not dcm.has_method("_generate_seed_tasks_from_context")
		and not dcm.has_method("_apply_seed_task_generation_result")
		and not dcm.has_method("_check_concept_completion")
		and not dcm.has_method("_track_concept_gate_follow_up")
		and not dcm.has_method("_persist_creative_brief_to_kb")
	)
	if not dcm_methods_clean:
		print("[FAIL] DevCycleManager still exposes seed/concept_gate/creative_brief methods")
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] DevCycleManager no longer exposes seed/concept_gate/creative_brief methods")

	var planning: Node = get_node_or_null("/root/PlanningManager")
	if planning == null:
		print("[FAIL] PlanningManager missing")
		_cleanup_test_state(dcm, kb, original_docs)
		return
	var planning_clean: bool = (
		not planning.has_method("request_seed_task_plan")
		and not planning.has_signal("seed_task_plan_completed")
	)
	if not planning_clean:
		print("[FAIL] PlanningManager still exposes seed task API")
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] PlanningManager no longer exposes seed task API")

	# ------- 1. 注入立项讨论任务 → 路由到 creative_decision 小游戏 -------
	var task_def: Dictionary = _load_task_template(TASK_TEMPLATE_PATH)
	if task_def.is_empty():
		print("[FAIL] failed to load lock_creative_direction.json template")
		_cleanup_test_state(dcm, kb, original_docs)
		return

	var task_type_ok: bool = (
		str(task_def.get("task_type", "")) == "minigame"
		and str(task_def.get("minigame_type", "")) == "creative_decision"
		and task_def.has("post_task_work_order")
		and not task_def.has("post_task_handler")
	)
	if not task_type_ok:
		print("[FAIL] template should be creative_decision + post_task_work_order, no post_task_handler. got: %s" % str(task_def))
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] template is creative_decision with post_task_work_order")

	var added_id: String = str(dcm.add_dynamic_task(task_def.duplicate(true)))
	if added_id != TASK_ID:
		print("[FAIL] add_dynamic_task returned %s, expected %s" % [added_id, TASK_ID])
		_cleanup_test_state(dcm, kb, original_docs)
		return

	var visible: Array = dcm.get_visible_tasks()
	var visible_id: String = str(visible[0].get("task_id", "")) if not visible.is_empty() else ""
	if visible_id != TASK_ID:
		print("[FAIL] expected visible task = %s, got %s" % [TASK_ID, visible_id])
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] lock_creative_direction is the current visible dev work")

	# ------- 2. 模拟讨论完成 → 应派发 post_task_work_order 工单 -------
	var planning_swap: Dictionary = _swap_in_fake_planning_manager()
	dcm.call("set_debug_direct_execute_interactive_tasks", true)
	if not dcm.activate_task(TASK_ID):
		print("[FAIL] activate_task(lock_creative_direction) failed in lab fast mode")
		_restore_planning_manager(planning_swap)
		dcm.call("set_debug_direct_execute_interactive_tasks", false)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	dcm.call("set_debug_direct_execute_interactive_tasks", false)
	await get_tree().process_frame

	var orders: Array = wom.get_all_orders()
	var dispatched_order: Resource = null
	for order in orders:
		if order != null and str(order.source_type) == "dev_task" and str(order.source_id) == TASK_ID:
			dispatched_order = order
			break
	if dispatched_order == null:
		print("[FAIL] no work order dispatched for source_id=lock_creative_direction. orders=%s" % str(orders))
		_restore_planning_manager(planning_swap)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] worker order dispatched: %s" % dispatched_order.id)

	# 此时 plan_generation 还不应被触发：worker 还在跑，KB 也没有 creative_brief
	var fake_planning: FakePlanningManager = planning_swap.get("fake")
	if fake_planning != null and fake_planning.request_count != 0:
		print("[FAIL] plan generation should not start before worker writes creative_brief")
		_restore_planning_manager(planning_swap)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] plan generation has not started yet (worker still pending)")

	# ------- 3. 模拟 worker 完成（写入 creative_brief 并标记工单 completed） -------
	kb.upsert_document(
		CREATIVE_BRIEF_DOC_ID,
		"项目立项 brief",
		"## 方向\n- 测试用立项内容",
		"notes",
		["brief", "direction"],
		"lin_xia",
		{"doc_kind": "brief", "state": "confirmed"}
	)
	if not wom.finish_order(str(dispatched_order.id)):
		print("[FAIL] finish_order failed for %s" % dispatched_order.id)
		_restore_planning_manager(planning_swap)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	await get_tree().process_frame

	# worker 完成 + KB 已有 creative_brief → _ensure_development_task_supply 应触发首次 plan_generation
	if fake_planning == null or fake_planning.request_count != 1:
		print("[FAIL] expected exactly 1 plan_generation call after worker completion, got %d" % (
			fake_planning.request_count if fake_planning != null else -1
		))
		_restore_planning_manager(planning_swap)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] worker completion triggered the first plan_generation")

	# ------- 4. _plan_generating 已经开启，且 KB 索引被传给 PlanningManager -------
	if not bool(dcm.get("_plan_generating")):
		print("[FAIL] _plan_generating should be true after request issued")
		_restore_planning_manager(planning_swap)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	if not str(fake_planning.last_kb_content).contains("creative_brief"):
		print("[FAIL] kb_content passed to PlanningManager should mention creative_brief, got: %s" % fake_planning.last_kb_content.left(200))
		_restore_planning_manager(planning_swap)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] PlanningManager.request_development_plan received KB index containing creative_brief")

	_restore_planning_manager(planning_swap)
	_cleanup_test_state(dcm, kb, original_docs)
	print("[OK] lock_creative_direction flow test passed")


func _load_task_template(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


func _swap_in_fake_planning_manager() -> Dictionary:
	var root: Node = get_tree().root
	var original: Node = root.get_node_or_null("PlanningManager")
	if original != null:
		original.name = "PlanningManagerOriginal"
	var fake := FakePlanningManager.new()
	fake.name = "PlanningManager"
	root.add_child(fake)
	return {
		"original": original,
		"fake": fake,
	}


func _restore_planning_manager(swap: Dictionary) -> void:
	var fake: Node = swap.get("fake")
	if fake != null and is_instance_valid(fake):
		var parent := fake.get_parent()
		if parent != null:
			parent.remove_child(fake)
		fake.queue_free()

	var original: Node = swap.get("original")
	if original != null and is_instance_valid(original):
		original.name = "PlanningManager"


func _cleanup_test_state(dcm: Node, kb: Node, original_docs: Array) -> void:
	if kb != null:
		kb.documents = original_docs.duplicate(true)
	if dcm != null and dcm.has_method("reset_runtime_state"):
		dcm.reset_runtime_state()
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom != null and wom.has_method("reset_runtime_state"):
		wom.reset_runtime_state()
