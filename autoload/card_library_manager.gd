extends Node
## 正式卡牌目录、等级/技能解锁和素材兼容性的唯一业务入口。

signal library_changed()

const CATALOG: LiveStreamCatalog = preload("res://resources/live_stream/catalogs/vertical_slice_catalog.tres")
const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")


func _ready() -> void:
	GameState.streamer_progress_changed.connect(_on_progress_changed)
	GameState.skill_levels_changed.connect(_on_skill_level_changed)
	var errors: PackedStringArray = CATALOG.validate_content(20, 4)
	for error: String in errors:
		push_error("CardLibraryManager: %s" % error)


func get_catalog() -> LiveStreamCatalog:
	return CATALOG


func get_balance() -> LiveStreamBalance:
	return BALANCE


func get_card(card_id: StringName) -> LiveStreamCardResource:
	return CATALOG.get_card(card_id)


func get_all_cards(card_kind: StringName = &"", family: StringName = &"") -> Array[LiveStreamCardResource]:
	var result: Array[LiveStreamCardResource] = []
	for card: LiveStreamCardResource in CATALOG.get_all_cards():
		if card == null:
			continue
		if card_kind != &"" and card.get_card_kind() != card_kind:
			continue
		if family != &"" and card.family != family:
			continue
		result.append(card)
	return result


func get_behavior_cards(family: StringName = &"") -> Array[BehaviorCardResource]:
	var result: Array[BehaviorCardResource] = []
	for card: BehaviorCardResource in CATALOG.behavior_cards:
		if card != null and (family == &"" or card.family == family):
			result.append(card)
	return result


func get_modifier_cards() -> Array[ModifierCardResource]:
	var result: Array[ModifierCardResource] = []
	result.assign(CATALOG.modifier_cards)
	return result


func is_card_unlocked(card_id: StringName) -> bool:
	var card: LiveStreamCardResource = get_card(card_id)
	if card == null:
		return false
	if GameState.streamer_level < BALANCE.get_tier_unlock_level(card.tier):
		return false
	if card.required_skill_family != &"" and GameState.get_skill_level(card.required_skill_family) < card.required_skill_level:
		return false
	return true


func get_unlock_reason(card_id: StringName) -> String:
	var card: LiveStreamCardResource = get_card(card_id)
	if card == null:
		return "卡牌不存在"
	var tier_level: int = BALANCE.get_tier_unlock_level(card.tier)
	if GameState.streamer_level < tier_level:
		return "主播 Lv.%d 解锁" % tier_level
	if card.required_skill_family != &"" and GameState.get_skill_level(card.required_skill_family) < card.required_skill_level:
		return "%s力 Lv.%d 解锁" % [card.get_family_display_name(), card.required_skill_level]
	return "已解锁"


func get_unlocked_cards(card_kind: StringName = &"", family: StringName = &"") -> Array[LiveStreamCardResource]:
	var result: Array[LiveStreamCardResource] = []
	for card: LiveStreamCardResource in get_all_cards(card_kind, family):
		if is_card_unlocked(card.content_id):
			result.append(card)
	return result


func get_compatible_behavior_cards(material_instance_id: StringName, include_locked: bool = false) -> Array[BehaviorCardResource]:
	var result: Array[BehaviorCardResource] = []
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	if material_manager == null:
		return result
	var material: LiveStreamMaterialResource = material_manager.get_definition_for_instance(material_instance_id)
	if material == null:
		return result
	for card: BehaviorCardResource in CATALOG.behavior_cards:
		if card == null or not card.is_compatible_with(material.tags):
			continue
		if include_locked or is_card_unlocked(card.content_id):
			result.append(card)
	return result


func is_compatible(card_id: StringName, material_instance_id: StringName) -> bool:
	var card: BehaviorCardResource = get_card(card_id) as BehaviorCardResource
	var material_manager: Node = get_node_or_null("/root/MaterialInventoryManager")
	if card == null or material_manager == null:
		return false
	var material: LiveStreamMaterialResource = material_manager.get_definition_for_instance(material_instance_id)
	return material != null and card.is_compatible_with(material.tags)


func get_unlocked_count() -> int:
	return get_unlocked_cards().size()


func get_total_count() -> int:
	return CATALOG.get_all_cards().size()


func _on_progress_changed(_level: int, _exp: int, _points: int) -> void:
	library_changed.emit()


func _on_skill_level_changed(_family: StringName, _level: int) -> void:
	library_changed.emit()
