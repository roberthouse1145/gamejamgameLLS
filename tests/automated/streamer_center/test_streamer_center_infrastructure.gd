extends Node
## v0.5 主播中心：正式目录、五系成长、素材实例与存档往返。


func _ready() -> void:
	var card_library: Node = get_node_or_null("/root/CardLibraryManager")
	var skill_tree: Node = get_node_or_null("/root/SkillTreeManager")
	var material_inventory: Node = get_node_or_null("/root/MaterialInventoryManager")
	assert(card_library != null and skill_tree != null and material_inventory != null)

	GameState.streamer_level = 1
	GameState.streamer_exp = 0
	GameState.skill_levels = GameState.DEFAULT_SKILL_LEVELS.duplicate(true)
	skill_tree.reset_to_defaults()
	material_inventory.reset_to_defaults()

	var catalog: LiveStreamCatalog = card_library.get_catalog()
	assert(catalog.validate_content(20, 4).is_empty(), "vertical slice content audit should pass")
	assert(card_library.get_behavior_cards().size() == 20)
	assert(card_library.get_modifier_cards().size() == 4)
	assert(card_library.get_total_count() == 24)
	assert(skill_tree.get_skills().size() == 15, "five families should each author Lv1-Lv3")
	assert(skill_tree.get_skill_points() == 2)
	var balance: LiveStreamBalance = card_library.get_balance()
	assert(balance.get_behavior_slot_count(1) == 2)
	assert(balance.get_behavior_slot_count(3) == 3)
	assert(balance.get_behavior_slot_count(5) == 4)
	assert(balance.get_behavior_slot_count(7) == 5)
	assert(balance.get_modifier_slot_count(2) == 0 and balance.get_modifier_slot_count(3) == 1)
	assert(balance.get_modifier_slot_count(8) == 2)
	assert(balance.get_budget(1, 79) == 10 and balance.get_budget(1, 80) == 7)

	assert(not skill_tree.can_unlock(&"game_lv3"), "a linear branch cannot skip Lv2")
	assert(skill_tree.unlock_skill(&"game_lv2"))
	assert(GameState.get_skill_level(&"game") == 2)
	assert(skill_tree.get_skill_points() == 1)
	assert(not card_library.is_card_unlocked(&"talk_recovery"), "Tier 2 also requires streamer Lv4")
	GameState.streamer_level = 4
	assert(card_library.is_card_unlocked(&"talk_recovery"), "tier and skill gates should both be satisfied")
	GameState.streamer_level = 1
	GameState.streamer_exp = 50
	var points_before_level: int = GameState.growth_points
	assert(GameState.add_streamer_exp(50, balance) == 1)
	assert(GameState.streamer_level == 2 and GameState.growth_points == points_before_level + 1)

	var duplicate_a: StringName = material_inventory.grant_material(&"material_trash_hunter")
	var duplicate_b: StringName = material_inventory.grant_material(&"material_trash_hunter")
	assert(duplicate_a != duplicate_b)
	var duplicate_b_before: Dictionary = material_inventory.get_instance(duplicate_b)
	assert(material_inventory.commit_use(material_inventory.preview_use(duplicate_a)))
	assert(material_inventory.get_instance(duplicate_b) == duplicate_b_before, "duplicate instances must keep independent state")

	var consumable_id: StringName = material_inventory.grant_material(&"material_forum_hot_meme")
	assert(material_inventory.commit_use(material_inventory.preview_use(consumable_id)))
	assert(material_inventory.get_instance(consumable_id).is_empty(), "consumable material should be removed after settlement")

	var saved_state: Dictionary = GameState.to_dict()
	GameState.skill_levels = GameState.DEFAULT_SKILL_LEVELS.duplicate(true)
	GameState.material_instances.clear()
	GameState.from_dict(saved_state)
	assert(GameState.get_skill_level(&"game") == 2)
	assert(not material_inventory.get_instance(duplicate_b).is_empty())
	assert(AppManager.is_app_registered("streamer_center"))

	var app_scene: PackedScene = load("res://scenes/apps/streamer_center/streamer_center_app.tscn")
	var app: Control = app_scene.instantiate() as Control
	assert(app != null)
	add_child(app)
	await get_tree().process_frame
	app.queue_free()
	print("STREAMER_CENTER_INFRASTRUCTURE_TEST_PASS")
