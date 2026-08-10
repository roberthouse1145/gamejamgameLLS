extends Node
## 拖放增量更新：卡实例在牌库与节目槽间流动，不触发全量重建。

const APP_SCENE: PackedScene = preload("res://scenes/apps/obs_live/obs_live_app.tscn")

var _app: Control = null
var _manager: Node = null
var _material_inventory: Node = null


func _ready() -> void:
	_manager = get_node_or_null("/root/LiveStreamManager")
	var card_library: Node = get_node_or_null("/root/CardLibraryManager")
	_material_inventory = get_node_or_null("/root/MaterialInventoryManager")
	assert(_manager != null and card_library != null and _material_inventory != null)

	GameState.streamer_level = 1
	GameState.streamer_exp = 0
	GameState.growth_points = 2
	GameState.skill_levels = GameState.DEFAULT_SKILL_LEVELS.duplicate(true)
	GameState.completed_stream_sessions.clear()
	GameState.stream_history.clear()
	_material_inventory.reset_to_defaults()
	_manager.reset_draft()
	var material_id: StringName = _find_material(&"material_trash_hunter")
	assert(material_id != &"")
	_manager.select_material(material_id)
	assert(_manager.advance_step())
	# 清掉盘上存档，避免 app 实例化时 load_saved_run_state 因槽位为空把步骤回退到 SETUP。
	_manager.clear_saved_run_state()

	_app = APP_SCENE.instantiate()
	add_child(_app)
	await get_tree().process_frame
	await get_tree().process_frame

	var deck: CardDeck = _find_deck(_app)
	assert(deck != null, "script step must expose a library deck")
	var slots: Array = _app.get("_program_slots")
	var material: LiveStreamMaterialResource = _manager.get_material_definition()
	print("[test] step=%d slots=%d material_slots=%d deck_cards=%d" % [
		_manager.get_current_step(), slots.size(), material.program_slot_count if material != null else -1, deck.get_cards().size()
	])
	assert(material != null)
	assert(slots.size() == material.program_slot_count, "program slots must come from material definition")
	assert(deck.get_cards().size() > 0, "library deck must show compatible cards")

	var card_view: LiveStreamCardView = deck.get_cards()[0]
	var card_id: String = String(card_view.content_resource.content_id)
	var deck_count_before: int = deck.get_cards().size()
	var slots_ref: Array = _app.get("_program_slots")

	# 牌库 → 槽 0（先模拟 CardDragController 的 UI 实例移动，再提交业务落账）
	deck.remove_card(card_view)
	slots[0].set_card(card_view)
	_app.call("_on_card_move_committed", card_view, card_view.drag_payload, deck, slots[0])
	await get_tree().process_frame
	assert(slots[0].has_card() and slots[0].get_card() == card_view, "card instance must flow into the slot")
	assert(deck.get_cards().size() == deck_count_before - 1, "library deck must lose the moved card instance")
	assert(card_view.get("drag_payload").get("kind") == "program_card", "slot card must carry program_card payload")
	assert(card_view.get("drag_payload").get("from_slot") == 0, "slot card must remember its slot index")
	assert(_manager.get_draft().get("behavior_slots")[0] == card_id, "draft must record the placed card")
	assert(_app.get("_program_slots") == slots_ref, "incremental update must not rebuild the wizard")

	# 槽 0 → 牌库
	slots[0].clear_card()
	deck.add_card(card_view)
	_app.call("_on_card_move_committed", card_view, card_view.drag_payload, slots[0], deck)
	await get_tree().process_frame
	assert(deck.get_cards().size() == deck_count_before, "deck must regain the card instance")
	assert(not slots[0].has_card(), "slot must be empty after dragging back")
	assert(_manager.get_draft().get("behavior_slots")[0] == "", "draft must clear the slot")
	assert(card_view.get("drag_payload").get("kind") == "behavior", "card must regain library payload")
	assert(_app.get("_program_slots") == slots_ref, "second move must also skip rebuild")

	print("WIZARD_INCREMENTAL_TEST_PASS")


func _find_material(definition_id: StringName) -> StringName:
	for instance: Dictionary in _material_inventory.get_instances():
		if StringName(str(instance.get("definition_id", ""))) == definition_id:
			return StringName(str(instance.get("instance_id", "")))
	return &""


func _find_deck(node: Node) -> CardDeck:
	if node.get_script() != null and "card_deck.gd" in str(node.get_script().resource_path):
		return node as CardDeck
	for child: Node in node.get_children():
		var found: CardDeck = _find_deck(child)
		if found != null:
			return found
	return null
