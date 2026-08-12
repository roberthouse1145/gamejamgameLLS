extends Node
## 开播界面以临时直播构思替代节目卡拖放；等待态与选择态跟随草稿刷新。

var _app: Control = null


func _ready() -> void:
	var manager: Node = get_node_or_null("/root/LiveStreamManager")
	var material_inventory: Node = get_node_or_null("/root/MaterialInventoryManager")
	assert(manager != null and material_inventory != null)
	material_inventory.reset_to_defaults()
	manager.reset_draft()

	_app = preload("res://scenes/apps/obs_live/obs_live_app.tscn").instantiate()
	add_child(_app)
	await get_tree().process_frame
	var material_instance_id: StringName = _find_material_instance(
		material_inventory, &"material_forum_hot_meme"
	)
	assert(manager.select_material(material_instance_id))
	assert(manager.advance_step())
	await get_tree().process_frame
	var approaches: Array[Dictionary] = manager.get_approaches()
	assert(approaches.size() >= 2)
	assert(manager.select_approach(StringName(str(approaches[0].get("approach_id", "")))))
	await get_tree().process_frame
	assert(manager.can_advance(1))
	print("WIZARD_APPROACH_SELECTION_TEST_PASS")


func _find_material_instance(material_inventory: Node, definition_id: StringName) -> StringName:
	for instance: Dictionary in material_inventory.get_instances():
		if StringName(str(instance.get("definition_id", ""))) == definition_id:
			return StringName(str(instance.get("instance_id", "")))
	return &""
