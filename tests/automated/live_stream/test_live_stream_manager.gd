extends Node
## 素材选择、临时构思、纯预结算、成长与幂等提交契约。

const HISTORY_STORE_SCRIPT = preload("res://scripts/game/live_stream/stream_history_store.gd")


func _ready() -> void:
	var manager: Node = get_node_or_null("/root/LiveStreamManager")
	var material_inventory: Node = get_node_or_null("/root/MaterialInventoryManager")
	assert(manager != null and material_inventory != null)

	GameState.streamer_level = 1
	GameState.streamer_exp = 0
	GameState.growth_points = 2
	GameState.skill_levels = GameState.DEFAULT_SKILL_LEVELS.duplicate(true)
	GameState.skill_experience = GameState.DEFAULT_SKILL_EXPERIENCE.duplicate(true)
	GameState.completed_stream_sessions.clear()
	GameState.stream_history.clear()
	GameState.completed_action_transactions.clear()
	GameState.action_transaction_history.clear()
	GameState.day = 3
	GameState.time_slot = GameState.TIME_SLOT_NIGHT
	material_inventory.reset_to_defaults()
	manager.reset_draft()

	var material_instance_id: StringName = _find_material_instance(
		material_inventory, &"material_trash_hunter"
	)
	assert(material_instance_id != &"")
	assert(manager.select_material(material_instance_id))
	var approaches: Array[Dictionary] = manager.get_approaches()
	assert(approaches.size() >= 2 and approaches.size() <= 3)
	assert(str(manager.get_draft().get("approach_state", "")) == "ready")
	assert(manager.can_advance(0))
	assert(manager.advance_step())
	assert(not manager.can_advance(1), "an explicit approach choice is required")
	var selected_id := StringName(str(approaches[0].get("approach_id", "")))
	assert(manager.select_approach(selected_id))
	assert(manager.can_advance(1))
	assert(manager.advance_step())

	var plan: StreamPlanSnapshot = manager.build_stream_plan(2468, &"preview_contract")
	assert(plan != null)
	assert(plan.approach.get("approach_id") == String(selected_id))
	assert(not plan.approach.get("director_prompt", "").is_empty())
	var first_preview: StreamSettlementResult = manager.get_preview_result()
	var second_preview: StreamSettlementResult = manager.get_preview_result()
	assert(first_preview.to_dict() == second_preview.to_dict())

	var exp_before: int = GameState.streamer_exp
	var skill_exp_before: int = _get_total_skill_experience()
	var requested_plan: StreamPlanSnapshot = manager.request_broadcast(2468)
	assert(requested_plan != null and manager.is_broadcast_pending())
	assert(GameState.day == 3 and GameState.time_slot == GameState.TIME_SLOT_NIGHT)
	assert(GameState.action_transaction_history.is_empty())
	var generated_summary: String = "本场围绕《粪作猎人》的瞬移首领展开挑战，并在识破反向判定后完成通关。"
	assert(manager.set_pending_stream_summary(requested_plan.session_id, generated_summary))
	assert(not material_inventory.get_instance(material_instance_id).is_empty())
	assert(GameState.streamer_exp == exp_before)
	assert(manager.commit_broadcast(requested_plan.session_id))
	assert(not manager.commit_broadcast(requested_plan.session_id))
	assert(GameState.day == 4 and GameState.time_slot == GameState.TIME_SLOT_MORNING)
	assert(GameState.streamer_exp == exp_before + first_preview.streamer_exp_gain)
	assert(_get_total_skill_experience() == skill_exp_before + first_preview.streamer_exp_gain)
	assert(material_inventory.get_instance(material_instance_id).is_empty())
	var history_record: StreamSessionRecord = manager.get_latest_history_record()
	assert(history_record.summary == generated_summary)
	assert(history_record.approach_name == str(requested_plan.approach.get("display_name", "")))
	assert(HISTORY_STORE_SCRIPT.new(GameState).get_record_count_for_persona(requested_plan.persona_id) == 1)
	print("LIVE_STREAM_MANAGER_TEST_PASS")


func _find_material_instance(material_inventory: Node, definition_id: StringName) -> StringName:
	for instance: Dictionary in material_inventory.get_instances():
		if StringName(str(instance.get("definition_id", ""))) == definition_id:
			return StringName(str(instance.get("instance_id", "")))
	return &""


func _get_total_skill_experience() -> int:
	var result: int = 0
	for family: StringName in GameState.SKILL_FAMILIES:
		result += GameState.get_skill_experience(family)
	return result
