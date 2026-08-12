extends Node
## 主播中心：素材库存、五系成长与存档往返。


func _ready() -> void:
	var live_stream_manager: Node = get_node_or_null("/root/LiveStreamManager")
	var skill_tree: Node = get_node_or_null("/root/SkillTreeManager")
	var material_inventory: Node = get_node_or_null("/root/MaterialInventoryManager")
	assert(live_stream_manager != null and skill_tree != null and material_inventory != null)

	GameState.streamer_level = 1
	GameState.streamer_exp = 0
	GameState.skill_levels = GameState.DEFAULT_SKILL_LEVELS.duplicate(true)
	GameState.skill_experience = GameState.DEFAULT_SKILL_EXPERIENCE.duplicate(true)
	skill_tree.reset_to_defaults()
	material_inventory.reset_to_defaults()

	var catalog: LiveStreamCatalog = live_stream_manager.get_catalog()
	assert(catalog.validate_content().is_empty(), "vertical slice content audit should pass")
	assert(catalog.materials.size() == 7)
	assert(skill_tree.get_skills().size() == 20, "five authored trunks should each expose a real fork")
	assert(skill_tree.get_skill_points() == 2)
	var balance: LiveStreamBalance = live_stream_manager.get_balance()
	assert(not balance.get_approach_profile(&"analysis").is_empty())
	assert(not balance.get_approach_profile(&"challenge").is_empty())

	assert(not skill_tree.can_unlock(&"game_lv3"), "a branch cannot skip its authored prerequisite")
	assert(skill_tree.unlock_skill(&"game_lv2"))
	assert(GameState.get_skill_level(&"game") == 1, "skill-tree spending must not replace activity proficiency")
	assert(skill_tree.get_skill_points() == 1)
	assert(skill_tree.unlock_skill(&"act_lv2"))
	var points_before_level: int = GameState.growth_points
	var growth: Dictionary = GameState.apply_skill_experience({"game": 100}, balance)
	assert(int(growth.get("streamer_levels_gained", 0)) == 1)
	assert(GameState.streamer_level == 2 and GameState.growth_points == points_before_level + 1)
	assert(GameState.get_skill_level(&"game") == 2)

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
	GameState.skill_experience = GameState.DEFAULT_SKILL_EXPERIENCE.duplicate(true)
	GameState.material_instances.clear()
	GameState.from_dict(saved_state)
	assert(GameState.get_skill_level(&"game") == 2)
	assert(GameState.get_skill_experience(&"game") == 100)
	assert(not material_inventory.get_instance(duplicate_b).is_empty())
	assert(AppManager.is_app_registered("streamer_center"))

	var app_scene: PackedScene = load("res://scenes/apps/streamer_center/streamer_center_app.tscn")
	var app: Control = app_scene.instantiate() as Control
	assert(app != null)
	add_child(app)
	await get_tree().process_frame
	app.queue_free()
	print("STREAMER_CENTER_INFRASTRUCTURE_TEST_PASS")
