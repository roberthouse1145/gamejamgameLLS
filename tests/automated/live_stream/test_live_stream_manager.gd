extends Node
## v0.7 开播链路：素材题面、锁定卡、合法空槽、纯预结算和幂等提交。

const CARD_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/live_stream_card.tscn")


func _ready() -> void:
	var manager: Node = get_node_or_null("/root/LiveStreamManager")
	var card_library: Node = get_node_or_null("/root/CardLibraryManager")
	var material_inventory: Node = get_node_or_null("/root/MaterialInventoryManager")
	var history: Node = get_node_or_null("/root/StreamHistoryManager")
	assert(manager != null and card_library != null and material_inventory != null and history != null)

	GameState.streamer_level = 1
	GameState.streamer_exp = 0
	GameState.growth_points = 2
	GameState.skill_levels = GameState.DEFAULT_SKILL_LEVELS.duplicate(true)
	GameState.completed_stream_sessions.clear()
	GameState.stream_history.clear()
	material_inventory.reset_to_defaults()
	manager.reset_draft()

	assert(not manager.can_advance(0), "setup should start incomplete")
	var material_instance_id: StringName = _find_material_instance(material_inventory, &"material_trash_hunter")
	assert(material_instance_id != &"")
	manager.select_material(material_instance_id)
	assert(manager.can_advance(0), "material instance should complete setup")
	var material: LiveStreamMaterialResource = manager.get_material_definition()
	var material_draft: Dictionary = manager.get_draft()
	assert(material_draft.get("behavior_slots", []).size() == material.program_slot_count, "material must define program slot count")
	assert(material_draft.get("title") == material.display_name, "placeholder title must be the material name until the generator refines it")
	assert((material_draft.get("behavior_slots", []) as Array)[2] == "material_boss_fight", "material must inject its locked BOSS card")
	assert(manager.is_behavior_slot_locked(2))
	assert(not manager.clear_behavior_slot(2), "strict material cards cannot be removed")
	assert(manager.advance_step())

	assert(manager.select_behavior_card(&"talk_daily_greeting"))
	assert(manager.select_behavior_card(&"talk_passionate_rant"))
	assert(manager.can_advance(1), "a trailing empty slot is legal and acts as the chain ending")
	assert(manager.get_budget_used() == 6, "material locked cards must not consume performance budget")
	assert(not card_library.is_card_unlocked(&"game_stuck_rage"), "stuck rage follows the v0.6 Tier 2 unlock")
	await _test_puzzle_edges(card_library)
	await _instantiate_obs_live_app()
	assert(manager.advance_step())
	await _instantiate_obs_live_app()

	var plan: StreamPlanSnapshot = manager.build_stream_plan(2468, &"preview_contract")
	assert(plan != null)
	assert(plan.behavior_card_ids == [&"talk_daily_greeting", &"talk_passionate_rant", &"material_boss_fight", &""])
	assert(plan.locked_behavior_slot_indices == PackedInt32Array([2]))
	var first_preview: StreamSettlementResult = manager.get_preview_result()
	var second_preview: StreamSettlementResult = manager.get_preview_result()
	assert(first_preview.to_dict() == second_preview.to_dict(), "same snapshot and seed should be deterministic")

	var exp_before: int = GameState.streamer_exp
	var requested_plan: StreamPlanSnapshot = manager.request_broadcast(2468)
	assert(requested_plan != null and manager.is_broadcast_pending())
	assert(not material_inventory.get_instance(material_instance_id).is_empty(), "preview must not consume the material")
	assert(GameState.streamer_exp == exp_before, "preview must not grant EXP")
	assert(manager.commit_broadcast(requested_plan.session_id), "first commit should succeed")
	assert(not manager.commit_broadcast(requested_plan.session_id), "same session may only be committed once")
	assert(GameState.streamer_exp == exp_before + 50)
	assert(material_inventory.get_instance(material_instance_id).is_empty(), "consumed material must be removed from inventory")
	assert(history.get_records().size() == 1)
	print("LIVE_STREAM_MANAGER_TEST_PASS")


func _instantiate_obs_live_app() -> void:
	var app_scene: PackedScene = load("res://scenes/apps/obs_live/obs_live_app.tscn")
	var app: Control = app_scene.instantiate() as Control
	assert(app != null)
	add_child(app)
	await get_tree().process_frame
	app.queue_free()
	await get_tree().process_frame


func _find_material_instance(material_inventory: Node, definition_id: StringName) -> StringName:
	for instance: Dictionary in material_inventory.get_instances():
		if StringName(str(instance.get("definition_id", ""))) == definition_id:
			return StringName(str(instance.get("instance_id", "")))
	return &""


func _test_puzzle_edges(card_library: Node) -> void:
	var opening_view: LiveStreamCardView = CARD_SCENE.instantiate()
	add_child(opening_view)
	opening_view.configure(card_library.get_card(&"talk_daily_greeting"))
	await get_tree().process_frame
	var opening_edges: CardSlotEdges = opening_view.get_node("SlotEdges") as CardSlotEdges
	assert(not opening_edges.has_left_notches(), "opening card must have a flat left edge")
	assert(opening_edges.has_right_tabs(), "opening card must have right output tabs")
	assert(opening_edges.right_slots == [2, 3], "daily greeting must use the authored D-shaped output")
	assert(opening_view.find_child("InterfaceLabel", true, false) == null, "card faces must express slots through their shape instead of L/R text")
	assert(opening_view.find_child("Background", true, false) == null, "card must not contain a second card frame")
	assert(opening_view.find_child("MainIcon", true, false) == null, "card face texture is drawn by SlotEdges, not a nested icon panel")
	assert(opening_edges.face_texture != null, "card face should use the content icon texture")
	opening_view.queue_free()

	var closing_view: LiveStreamCardView = CARD_SCENE.instantiate()
	add_child(closing_view)
	closing_view.configure(card_library.get_card(&"talk_goodnight"))
	await get_tree().process_frame
	var closing_edges: CardSlotEdges = closing_view.get_node("SlotEdges") as CardSlotEdges
	assert(closing_edges.has_left_notches(), "closing card must have left input notches")
	assert(not closing_edges.has_right_tabs(), "closing card must have a flat right edge")
	assert(closing_edges.left_slots == [1, 3], "goodnight must expose only its two authored left slots")
	closing_view.queue_free()

	var transition_card: BehaviorCardResource = card_library.get_card(&"game_stuck_rage") as BehaviorCardResource
	var probe: LiveStreamCardView = CARD_SCENE.instantiate()
	add_child(probe)
	await get_tree().process_frame
	var probe_edges: CardSlotEdges = probe.get_node("SlotEdges") as CardSlotEdges
	var lane_positions: Array[float] = [
		probe_edges.get_slot_y(1),
		probe_edges.get_slot_y(2),
		probe_edges.get_slot_y(3),
		probe_edges.get_slot_y(4),
	]
	assert(lane_positions[0] < lane_positions[1])
	assert(lane_positions[1] < lane_positions[2])
	assert(lane_positions[2] < lane_positions[3], "four slot positions must occupy four distinct vertical lanes")
	probe.configure(transition_card)
	await get_tree().process_frame
	assert(probe_edges.left_slots == [2, 4], "stuck rage must draw only its two authored left-side notches")
	assert(probe_edges.right_slots == [2], "stuck rage must draw only its authored right-side tab")
	assert(not probe_edges.is_connection_state_visible(), "card library views must not paint connection success or failure")
	probe.configure_connection_state([2], [2])
	assert(probe_edges.is_connection_state_visible(), "placed program cards must enable per-slot connection feedback")
	assert(probe_edges.is_left_slot_connected(2) and not probe_edges.is_left_slot_connected(4))
	assert(probe_edges.is_right_slot_connected(2), "connected slots must expose their green state independently")
	probe.queue_free()
