extends Node
## v0.5 开播链路：素材实例、拼图结构、纯预结算和幂等提交。

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
	manager.set_title("第一次试播")
	manager.select_persona(&"persona_default")
	var material_instance_id: StringName = _find_material_instance(material_inventory, &"material_trash_hunter")
	assert(material_instance_id != &"")
	manager.select_material(material_instance_id)
	assert(manager.can_advance(0), "title, persona and material instance should complete setup")
	assert(manager.advance_step())

	assert(manager.select_behavior_card(&"talk_goodnight"))
	assert(manager.select_behavior_card(&"talk_daily_greeting"))
	assert(not manager.can_advance(1), "opening and closing cards must occupy their structural positions")
	assert(manager.clear_behavior_slot(0) and manager.clear_behavior_slot(1))
	assert(manager.select_behavior_card(&"talk_daily_greeting"))
	assert(manager.select_behavior_card(&"talk_goodnight"))
	assert(manager.can_advance(1), "opening followed by closing should be a valid two-slot program")
	assert(card_library.is_card_unlocked(&"game_stuck_rage"), "the vertical slice should expose a hot-to-gloom transition at Lv1")
	await _test_puzzle_edges(card_library)
	await _instantiate_obs_live_app()
	assert(manager.advance_step())
	await _instantiate_obs_live_app()

	var plan: StreamPlanSnapshot = manager.build_stream_plan(2468, &"preview_contract")
	assert(plan != null)
	assert(plan.behavior_card_ids == [&"talk_daily_greeting", &"talk_goodnight"])
	var first_preview: StreamSettlementResult = manager.get_preview_result()
	var second_preview: StreamSettlementResult = manager.get_preview_result()
	assert(first_preview.to_dict() == second_preview.to_dict(), "same snapshot and seed should be deterministic")

	var material_before: Dictionary = material_inventory.get_instance(material_instance_id)
	var exp_before: int = GameState.streamer_exp
	var requested_plan: StreamPlanSnapshot = manager.request_broadcast(2468)
	assert(requested_plan != null and manager.is_broadcast_pending())
	assert(material_inventory.get_instance(material_instance_id) == material_before, "preview must not mutate material state")
	assert(GameState.streamer_exp == exp_before, "preview must not grant EXP")
	assert(manager.commit_broadcast(requested_plan.session_id), "first commit should succeed")
	assert(not manager.commit_broadcast(requested_plan.session_id), "same session may only be committed once")
	assert(GameState.streamer_exp == exp_before + 50)
	assert(material_inventory.get_instance(material_instance_id).get("depth") == float(material_before.get("depth")) - 1.0)
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
	var opening_edges: CardMoodEdges = opening_view.get_node("MoodEdges") as CardMoodEdges
	assert(not opening_edges.has_input_notches(), "opening card must have a flat left edge")
	assert(opening_edges.has_output_tabs(), "opening card must have right output tabs")
	assert(opening_edges.get_output_lanes() == [0, 2], "an opening card may expose multiple output connectors")
	assert(opening_view.find_child("Background", true, false) == null, "card must not contain a second card frame")
	assert(opening_view.find_child("IconArea", true, false) == null, "icon must not be wrapped in another panel")
	var main_icon: TextureRect = opening_view.find_child("MainIcon", true, false) as TextureRect
	assert(main_icon != null and main_icon.get_parent() is VBoxContainer, "icon should live directly in card content")
	opening_view.queue_free()

	var closing_view: LiveStreamCardView = CARD_SCENE.instantiate()
	add_child(closing_view)
	closing_view.configure(card_library.get_card(&"talk_goodnight"))
	await get_tree().process_frame
	var closing_edges: CardMoodEdges = closing_view.get_node("MoodEdges") as CardMoodEdges
	assert(closing_edges.has_input_notches(), "closing card must have left input notches")
	assert(not closing_edges.has_output_tabs(), "closing card must have a flat right edge")
	assert(closing_edges.get_input_lanes() == [2, 3], "a closing card may accept multiple input moods")
	closing_view.queue_free()

	var transition_card: BehaviorCardResource = card_library.get_card(&"game_stuck_rage") as BehaviorCardResource
	var probe: LiveStreamCardView = CARD_SCENE.instantiate()
	add_child(probe)
	await get_tree().process_frame
	var probe_edges: CardMoodEdges = probe.get_node("MoodEdges") as CardMoodEdges
	var lane_positions: Array[float] = [
		probe_edges.get_lane_y(BehaviorCardResource.MOOD_HOT),
		probe_edges.get_lane_y(BehaviorCardResource.MOOD_CALM),
		probe_edges.get_lane_y(BehaviorCardResource.MOOD_WARM),
		probe_edges.get_lane_y(BehaviorCardResource.MOOD_GLOOM),
	]
	assert(lane_positions[0] < lane_positions[1])
	assert(lane_positions[1] < lane_positions[2])
	assert(lane_positions[2] < lane_positions[3], "four moods must occupy four distinct vertical lanes")
	probe.configure(transition_card)
	await get_tree().process_frame
	assert(probe_edges.get_input_lanes() == [0, 1], "the card must draw both authored left-side notches")
	assert(probe_edges.get_output_lanes() == [0, 3], "the card must draw both authored right-side tabs")
	probe.queue_free()
