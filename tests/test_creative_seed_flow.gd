extends Node

const OPEN_DESIGN_QUESTIONS_DOC_ID: String = "open_design_questions"
const SEED_DEVELOPMENT_BACKBONE_DOC_ID: String = "seed_development_backbone"


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
	if dcm == null:
		print("[FAIL] Creative seed flow test missing DevCycleManager")
		return

	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null:
		print("[FAIL] Creative seed flow test missing KnowledgeBaseManager")
		return

	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom == null:
		print("[FAIL] Creative seed flow test missing WorkOrderManager")
		return

	if wom.has_method("reset_runtime_state"):
		wom.reset_runtime_state()

	var original_docs: Array = kb.documents.duplicate(true)

	if dcm.has_method("reset_runtime_state"):
		dcm.reset_runtime_state()
	kb.documents.clear()
	await get_tree().process_frame

	var brief_data: Dictionary = {
		"game_title": "月塔密约",
		"game_genre": "悬疑推理",
		"game_tags": "暧昧, 黑暗",
		"game_outline": "新生入学后意外卷入学院禁书库的秘密，并在调查中逐渐靠近一位立场暧昧的少女。",
	}

	var hidden_helper_ok: bool = not dcm.has_method("_build_creative_seed_order_description") \
		and not dcm.has_method("_dispatch_creative_seed_setup_order")
	if not hidden_helper_ok:
		print("[FAIL] Creative seed flow should not keep hidden seed setup order helpers in DevCycleManager")
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] Hidden creative seed setup order helpers are removed from DevCycleManager")

	dcm.set("_latest_creative_brief", brief_data.duplicate(true))
	dcm.call("_persist_creative_brief_to_kb", brief_data)
	await get_tree().process_frame

	var brief_doc: Dictionary = kb.get_document("creative_brief")
	var brief_doc_ok: bool = not brief_doc.is_empty() \
		and str(brief_doc.get("title", "")) == "项目企划书" \
		and str(brief_doc.get("content", "")).contains("月塔密约") \
		and str(brief_doc.get("content", "")).contains("悬疑推理") \
		and str(brief_doc.get("content", "")).contains("学院禁书库的秘密")
	if not brief_doc_ok:
		print("[FAIL] Creative brief should be written directly into KB before seed tasks are generated")
		print(str(brief_doc))
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] Creative brief is written directly into KB")

	var seed_context: String = dcm.call("_build_creative_seed_context")
	var seed_context_ok: bool = seed_context.contains("项目企划书") \
		and seed_context.contains("月塔密约") \
		and seed_context.contains("学院禁书库的秘密") \
		and not seed_context.contains("待讨论设计问题") \
		and not seed_context.contains("前期开发骨架")
	if not seed_context_ok:
		print("[FAIL] Seed context should be buildable directly from the raw creative brief when derived docs do not exist yet")
		print(seed_context)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] Seed context can be built directly from the raw creative brief")

	var initial_visible: Array = dcm.get_visible_tasks()
	if not initial_visible.is_empty():
		print("[FAIL] Brief-only flow should not expose preset dev work before seed generation")
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] Brief-only flow starts without preset dev work")

	kb.upsert_document(
		OPEN_DESIGN_QUESTIONS_DOC_ID,
		"待讨论设计问题",
		"- 这部作品最先抓住玩家的情绪钩子到底是什么？\n- 第一段可写内容应该先落到哪一块？\n- 女主第一次正式出场时应该先带出哪种距离感？",
		"notes"
	)
	kb.upsert_document(
		SEED_DEVELOPMENT_BACKBONE_DOC_ID,
		"前期开发骨架",
		"## 已确定锚点\n- 校园悬疑恋爱气质\n\n## 阻塞缺口\n- 第一段真正要先做什么还没拍板\n\n## 下一步建议\n- [discussion] 先定作品最先抓人的情绪钩子\n- [production] 整理第一段可写场景节拍\n- [discussion] 决定第一章第一幕先让玩家看到什么\n- [production] 收束学院禁书库规则底稿\n- [discussion] 决定女主第一次正式出场该保留哪种距离感",
		"notes"
	)

	var fallback_tasks: Array = dcm.call("_build_seed_task_fallbacks")
	var fallback_ok: bool = fallback_tasks.size() >= 5 \
		and _is_discussion_task(fallback_tasks[0]) \
		and str(fallback_tasks[1].get("task_type", "")) == "minigame" \
		and str(fallback_tasks[1].get("minigame_type", "")) == "typing_code" \
		and fallback_tasks[1].has("post_task_work_order") \
		and str(fallback_tasks[0].get("title", "")).contains("情绪钩子") \
		and str(fallback_tasks[1].get("title", "")).contains("场景节拍")
	if not fallback_ok:
		print("[FAIL] Seed fallback tasks should keep all meaningful backbone suggestions instead of truncating to the visible-task limit")
		print(str(fallback_tasks))
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] Seed fallback tasks are derived from KB backbone suggestions without being capped by UI limits")

	var semantic_ok: bool = bool(dcm.call("_looks_like_seed_discussion_intent", "讨论魔法系统规则", "和林夏把这个关键问题聊清楚")) \
		and not bool(dcm.call("_looks_like_seed_production_intent", "讨论魔法系统规则", "和林夏把这个关键问题聊清楚")) \
		and bool(dcm.call("_looks_like_seed_production_intent", "撰写主角角色设定文档", "产出一份角色设定文档")) \
		and not bool(dcm.call("_looks_like_seed_discussion_intent", "撰写主角角色设定文档", "产出一份角色设定文档"))
	if not semantic_ok:
		print("[FAIL] Seed task semantic heuristics should distinguish discussion intent from production intent")
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] Seed task semantic heuristics distinguish discussion and production intent")

	var raw_tasks: Array = [
		{
			"task_id": "seed_lock_hook",
			"title": "先定作品最先抓人的那一下",
			"description": "把作品最先吸引玩家的情绪钩子聊清楚，后面场景才不会写散。",
			"task_type": "chat_topic",
			"stat_changes": {"quality": 5, "completion": 2},
			"stress_cost": 1,
			"weight": 10,
			"topic_config": {
				"system_prompt": "你是林夏，{player_name}的搭档。这次只讨论作品最先抓人的情绪钩子。不要替玩家拍板，主动提出 2-3 个方向，最后加 [TOPIC_COMPLETE]。",
				"goal_description": "与搭档讨论作品最先抓人的情绪钩子",
				"kb_category": "story",
				"kb_entry_id": "hook_seed"
			}
		},
		{
			"task_id": "seed_opening_beat",
			"title": "整理第一段可写场景节拍",
			"description": "把目前已经确认的内容收束成第一段能继续接力的场景节拍。",
			"task_type": "minigame",
			"minigame_type": "typing_code",
			"stat_changes": {"quality": 3, "completion": 6},
			"stress_cost": 2,
			"weight": 10,
			"prerequisites": ["seed_lock_hook"],
			"post_task_work_order": {
				"title": "整理第一段可写场景节拍",
				"description": "根据已有创作基点和已确认内容，整理第一段可直接交给后续开发的场景节拍。只写有信息支撑的部分。",
				"kb_sources": ["story", "characters", "notes"],
				"scene_target": "seed_opening_beat",
				"performance_context": "summary"
			}
		},
		{
			"task_id": "seed_pick_relationship_axis",
			"title": "决定关系推进先从哪种距离感起手",
			"description": "把两人的相处距离先拍板，避免后面场景一会儿太近一会儿太远。",
			"task_type": "chat_topic",
			"stat_changes": {"quality": 4, "completion": 2},
			"stress_cost": 1,
			"weight": 9,
			"topic_config": {
				"system_prompt": "你是林夏，{player_name}的搭档。这次只讨论关系推进的起手距离感。不要预设答案，提出不同方向，最后加 [TOPIC_COMPLETE]。",
				"goal_description": "与搭档讨论关系推进的起手距离感",
				"kb_category": "characters",
				"kb_entry_id": "relationship_axis_seed"
			}
		},
		{
			"task_id": "seed_define_rule_floor",
			"title": "收束学院禁书库规则底稿",
			"description": "把已经确认过的世界规则先整理成能继续承接写作的底稿。",
			"stat_changes": {"quality": 4, "completion": 5},
			"stress_cost": 2,
			"weight": 8,
			"work_order_template": {
				"title": "收束学院禁书库规则底稿",
				"description": "根据当前创作基点与现有讨论，整理学院禁书库相关的已确认规则。未定部分明确标注待定。",
				"kb_sources": ["world", "notes"],
				"scene_target": "seed_rule_floor"
			}
		},
		{
			"task_id": "seed_opening_conflict_card",
			"title": "整理开场冲突卡点",
			"description": "在情绪钩子确定之后，把开场最先抛出的冲突卡点收束成一份短纲。",
			"task_type": "minigame",
			"minigame_type": "typing_code",
			"stat_changes": {"quality": 3, "completion": 6},
			"stress_cost": 2,
			"weight": 11,
			"prerequisites": ["seed_lock_hook"],
			"post_task_work_order": {
				"title": "整理开场冲突卡点",
				"description": "基于已确认的情绪钩子与开场方向，收束一份可继续写作的开场冲突卡点短纲。",
				"kb_sources": ["story", "notes"],
				"scene_target": "seed_opening_conflict_card",
				"performance_context": "summary"
			}
		},
		{
			"task_id": "seed_collect_visual_motifs",
			"title": "讨论这部作品最该先抓住的视觉意象",
			"description": "先把视觉记忆点聊清楚，避免后面的场景气质东一块西一块。",
			"task_type": "chat_topic",
			"stat_changes": {"quality": 4, "completion": 2},
			"stress_cost": 1,
			"weight": 7,
			"topic_config": {
				"system_prompt": "你是林夏，{player_name}的搭档。这次只讨论作品最该先抓住的视觉意象。给出 2-3 个差异明显的方向，最后加 [TOPIC_COMPLETE]。",
				"goal_description": "与搭档讨论作品最该先抓住的视觉意象",
				"kb_category": "notes",
				"kb_entry_id": "visual_motif_seed"
			}
		}
	]

	var added_count: int = int(dcm.call("_apply_seed_task_generation_result", raw_tasks))
	await get_tree().process_frame
	if added_count != 6:
		print("[FAIL] Seed flow should keep the full planner-provided task batch instead of truncating it to the visible-task limit, got %d" % added_count)
		_cleanup_test_state(dcm, kb, original_docs)
		return

	var hook_task: Dictionary = dcm.get_task("seed_lock_hook")
	var beat_task: Dictionary = dcm.get_task("seed_opening_beat")
	var relationship_task: Dictionary = dcm.get_task("seed_pick_relationship_axis")
	var rule_task: Dictionary = dcm.get_task("seed_define_rule_floor")
	var conflict_task: Dictionary = dcm.get_task("seed_opening_conflict_card")
	var motif_task: Dictionary = dcm.get_task("seed_collect_visual_motifs")
	var task_ok: bool = not hook_task.is_empty() \
		and not beat_task.is_empty() \
		and not relationship_task.is_empty() \
		and not rule_task.is_empty() \
		and not conflict_task.is_empty() \
		and not motif_task.is_empty() \
		and _is_discussion_task(hook_task) \
		and str(beat_task.get("task_type", "")) == "minigame" \
		and str(beat_task.get("minigame_type", "")) == "typing_code" \
		and beat_task.has("post_task_work_order") \
		and _is_discussion_task(relationship_task) \
		and str(rule_task.get("task_type", "")) == "minigame" \
		and rule_task.has("post_task_work_order") \
		and str(conflict_task.get("task_type", "")) == "minigame" \
		and conflict_task.has("post_task_work_order") \
		and _is_discussion_task(motif_task)
	if not task_ok:
		print("[FAIL] Seed flow should normalize production tasks into minigame + post_task_work_order")
		_cleanup_test_state(dcm, kb, original_docs)
		return

	var prereqs: Array = beat_task.get("prerequisites", [])
	if "seed_lock_hook" not in prereqs:
		print("[FAIL] Planner-provided prerequisites should be preserved in seed tasks")
		print("  prerequisites: %s" % str(prereqs))
		_cleanup_test_state(dcm, kb, original_docs)
		return

	var initial_seed_visible: Array = dcm.get_visible_tasks()
	var initial_visible_ids: Array[String] = []
	for task in initial_seed_visible:
		initial_visible_ids.append(str(task.get("task_id", "")))
	if initial_seed_visible.size() != 1 \
		or "seed_lock_hook" not in initial_visible_ids \
		or "seed_opening_beat" in initial_visible_ids \
		or "seed_opening_conflict_card" in initial_visible_ids:
		print("[FAIL] Seed flow should only expose the current reachable task to the player")
		print("  visible_ids: %s" % str(initial_visible_ids))
		_cleanup_test_state(dcm, kb, original_docs)
		return

	var upcoming_seed_tasks: Array = dcm.get_upcoming_surface_tasks(2) if dcm.has_method("get_upcoming_surface_tasks") else []
	var upcoming_seed_ids: Array[String] = []
	for task in upcoming_seed_tasks:
		upcoming_seed_ids.append(str(task.get("task_id", "")))
	if upcoming_seed_ids.size() != 2 \
		or "seed_pick_relationship_axis" not in upcoming_seed_ids \
		or "seed_define_rule_floor" not in upcoming_seed_ids:
		print("[FAIL] Seed flow should keep later reachable tasks as read-only upcoming work in planner order")
		print("  upcoming_ids: %s" % str(upcoming_seed_ids))
		_cleanup_test_state(dcm, kb, original_docs)
		return

	var completed_ids: Array = dcm.get("_completed_task_ids")
	if "seed_lock_hook" not in completed_ids:
		completed_ids.append("seed_lock_hook")
	dcm.set("_completed_task_ids", completed_ids)
	var task_pool: Dictionary = dcm.get("_task_pool")
	var hook_entry: Dictionary = task_pool.get("seed_lock_hook", {})
	hook_entry["status"] = "completed"
	task_pool["seed_lock_hook"] = hook_entry
	dcm.set("_task_pool", task_pool)

	var unlocked_visible: Array = dcm.get_visible_tasks()
	var unlocked_visible_ids: Array[String] = []
	for task in unlocked_visible:
		unlocked_visible_ids.append(str(task.get("task_id", "")))
	if unlocked_visible.size() != 1 \
		or "seed_opening_beat" not in unlocked_visible_ids:
		print("[FAIL] After the current seed work completes, the next planner-ordered reachable task should become current")
		print("  visible_ids_after_unlock: %s" % str(unlocked_visible_ids))
		_cleanup_test_state(dcm, kb, original_docs)
		return

	var unlocked_upcoming: Array = dcm.get_upcoming_surface_tasks(3) if dcm.has_method("get_upcoming_surface_tasks") else []
	var unlocked_upcoming_ids: Array[String] = []
	for task in unlocked_upcoming:
		unlocked_upcoming_ids.append(str(task.get("task_id", "")))
	if "seed_pick_relationship_axis" not in unlocked_upcoming_ids \
		or "seed_define_rule_floor" not in unlocked_upcoming_ids \
		or "seed_opening_conflict_card" not in unlocked_upcoming_ids:
		print("[FAIL] Later seed tasks should remain queued internally in planner order after unlock")
		print("  upcoming_ids_after_unlock: %s" % str(unlocked_upcoming_ids))
		_cleanup_test_state(dcm, kb, original_docs)
		return

	var planning_swap: Dictionary = _swap_in_fake_planning_manager()
	var concept_gate_ids: Array = dcm.get("_concept_gate_task_ids").duplicate(true)
	var concept_completed_ids: Array = dcm.get("_completed_task_ids").duplicate(true)
	for raw_concept_id in concept_gate_ids:
		var concept_id: String = str(raw_concept_id).strip_edges()
		if concept_id.is_empty() or concept_id in concept_completed_ids:
			continue
		concept_completed_ids.append(concept_id)
	dcm.set("_plan_generated", false)
	dcm.set("_plan_generating", false)
	dcm.set("_plan_gen_request_id", "")
	dcm.set("_completed_task_ids", concept_completed_ids)
	dcm.call("_track_concept_gate_follow_up", hook_task, {"chat_task": true, "work_order_created": true})
	dcm.call("_check_concept_completion")
	var fake_planning: FakePlanningManager = planning_swap.get("fake")
	if fake_planning == null or fake_planning.request_count != 0 or bool(dcm.get("_plan_generating")):
		print("[FAIL] Formal planning should not start while a concept task's hidden work order is still pending")
		_restore_planning_manager(planning_swap)
		_cleanup_test_state(dcm, kb, original_docs)
		return

	var pending_order: Resource = wom.create_order("整理讨论结果：先定作品最先抓人的那一下", "测试用 concept gate 工单", {
		"source_type": "dev_task",
		"source_id": "seed_lock_hook",
	})
	if pending_order == null or not wom.finish_order(str(pending_order.id)):
		print("[FAIL] Creative seed flow test could not complete the fake concept-gate work order")
		_restore_planning_manager(planning_swap)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	await get_tree().process_frame
	if fake_planning.request_count == 0:
		dcm.call("_sync_concept_gate_follow_up_state", str(pending_order.id), "completed")
	if fake_planning.request_count != 1 \
		or not bool(dcm.get("_plan_generating")) \
		or str(dcm.get("_plan_gen_request_id")) != "fake_development_plan_1":
		print("[FAIL] Formal planning should wait for concept follow-up orders, then start exactly once after they complete")
		print("  request_count: %d" % fake_planning.request_count)
		print("  plan_generating: %s" % str(bool(dcm.get("_plan_generating"))))
		print("  plan_request_id: %s" % str(dcm.get("_plan_gen_request_id")))
		print("  pending_concept_orders: %s" % str(dcm.get("_concept_gate_pending_order_task_ids")))
		print("  completed_task_ids: %s" % str(dcm.get("_completed_task_ids")))
		print("  concept_gate_task_ids: %s" % str(dcm.get("_concept_gate_task_ids")))
		_restore_planning_manager(planning_swap)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	_restore_planning_manager(planning_swap)
	print("[OK] Formal planning waits until concept follow-up work orders are actually completed")

	wom.reset_runtime_state()
	dcm.call("set_debug_direct_execute_interactive_tasks", true)
	dcm.add_dynamic_task({
		"task_id": "debug_fast_chat_topic_order",
		"title": "快速跳过讨论也要派单",
		"description": "测试场景下跳过 chat_topic 互动后，仍然应该创建整理讨论结果的工单。",
		"task_type": "chat_topic",
		"stat_changes": {"quality": 1},
		"stress_cost": 0,
		"topic_config": {
			"system_prompt": "只讨论 lab fast mode 是否仍然保留工单派发。",
			"goal_description": "验证 lab fast mode 的 chat_topic 工单派发",
			"kb_category": "notes",
			"kb_entry_id": "debug_fast_chat_topic_order"
		}
	})
	if not dcm.activate_task("debug_fast_chat_topic_order"):
		print("[FAIL] Lab fast mode should allow a chat-topic task to activate")
		dcm.call("set_debug_direct_execute_interactive_tasks", false)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	var debug_orders: Array = wom.get_all_orders()
	var fast_mode_order_ok: bool = debug_orders.size() == 1 \
		and str(debug_orders[0].title).contains("整理讨论结果：快速跳过讨论也要派单") \
		and str(debug_orders[0].source_id) == "debug_fast_chat_topic_order"
	if not fast_mode_order_ok:
		print("[FAIL] Lab fast mode should skip chat discussion but still dispatch a follow-up work order for chat_topic tasks")
		print(str(debug_orders))
		dcm.call("set_debug_direct_execute_interactive_tasks", false)
		_cleanup_test_state(dcm, kb, original_docs)
		return
	print("[OK] Lab fast mode skips chat discussion but still dispatches a work order for chat-topic tasks")
	dcm.call("set_debug_direct_execute_interactive_tasks", false)

	print("[OK] Creative seed flow now keeps the full planner batch while the UI only reveals the current task and upcoming previews")
	_cleanup_test_state(dcm, kb, original_docs)
	print("[OK] Creative seed flow test passed")


func _cleanup_test_state(dcm: Node, kb: Node, original_docs: Array) -> void:
	if kb != null:
		kb.documents = original_docs.duplicate(true)
	if dcm != null and dcm.has_method("reset_runtime_state"):
		dcm.reset_runtime_state()


func _is_discussion_task(task: Dictionary) -> bool:
	return str(task.get("task_type", "")) == "chat_topic" \
		or (
			str(task.get("task_type", "")) == "minigame" \
			and str(task.get("minigame_type", "")) == "creative_decision"
		)


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
