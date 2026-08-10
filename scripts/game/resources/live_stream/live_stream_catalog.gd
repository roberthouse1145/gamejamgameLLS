class_name LiveStreamCatalog extends Resource
## 纵切内容目录与静态审计入口。

@export var allowed_tags: Array[StringName] = []
@export var behavior_cards: Array[BehaviorCardResource] = []
@export var material_behavior_cards: Array[BehaviorCardResource] = []
@export var modifier_cards: Array[ModifierCardResource] = []
@export var materials: Array[LiveStreamMaterialResource] = []
@export var personas: Array[StreamPersonaResource] = []


func get_all_cards() -> Array[LiveStreamCardResource]:
	var result: Array[LiveStreamCardResource] = []
	for card: BehaviorCardResource in behavior_cards:
		result.append(card)
	for card: ModifierCardResource in modifier_cards:
		result.append(card)
	return result


func get_card(card_id: StringName) -> LiveStreamCardResource:
	for card: LiveStreamCardResource in get_all_cards():
		if card != null and card.content_id == card_id:
			return card
	for card: BehaviorCardResource in material_behavior_cards:
		if card != null and card.content_id == card_id:
			return card
	return null


func is_material_behavior_card(card_id: StringName) -> bool:
	for card: BehaviorCardResource in material_behavior_cards:
		if card != null and card.content_id == card_id:
			return true
	return false


func get_material(material_id: StringName) -> LiveStreamMaterialResource:
	for material: LiveStreamMaterialResource in materials:
		if material != null and material.content_id == material_id:
			return material
	return null


func get_persona(persona_id: StringName) -> StreamPersonaResource:
	for persona: StreamPersonaResource in personas:
		if persona != null and persona.content_id == persona_id:
			return persona
	return null


func validate_content(expected_behavior_count: int = -1, expected_modifier_count: int = -1) -> PackedStringArray:
	var errors: PackedStringArray = []
	var known_ids: Dictionary = {}
	if expected_behavior_count >= 0 and behavior_cards.size() != expected_behavior_count:
		errors.append("行为卡数量应为 %d，实际为 %d" % [expected_behavior_count, behavior_cards.size()])
	if expected_modifier_count >= 0 and modifier_cards.size() != expected_modifier_count:
		errors.append("修饰卡数量应为 %d，实际为 %d" % [expected_modifier_count, modifier_cards.size()])
	for card: LiveStreamCardResource in get_all_cards():
		_validate_content_entry(card, known_ids, errors)
		if card is BehaviorCardResource:
			var behavior: BehaviorCardResource = card as BehaviorCardResource
			_validate_tags(behavior.material_require, behavior.content_id, errors)
			for boost: StreamTagEffect in behavior.material_boosts:
				if boost != null:
					_validate_tags([boost.with_tag], behavior.content_id, errors)
	for card: BehaviorCardResource in material_behavior_cards:
		_validate_content_entry(card, known_ids, errors)
		if card != null:
			_validate_tags(card.material_require, card.content_id, errors)
			for boost: StreamTagEffect in card.material_boosts:
				if boost != null:
					_validate_tags([boost.with_tag], card.content_id, errors)
	for material: LiveStreamMaterialResource in materials:
		_validate_content_entry(material, known_ids, errors)
		if material != null:
			_validate_tags(material.tags, material.content_id, errors)
			for combo: StreamTagEffect in material.combo_effects:
				if combo != null:
					_validate_tags([combo.with_tag], material.content_id, errors)
			_validate_material_locks(material, errors)
	for persona: StreamPersonaResource in personas:
		_validate_content_entry(persona, known_ids, errors)
	_validate_duplicate_material_card_effects(errors)
	return errors


func _validate_material_locks(material: LiveStreamMaterialResource, errors: PackedStringArray) -> void:
	var strict_positions: Dictionary = {}
	for lock_rule: MaterialLockedCard in material.locked_cards:
		if lock_rule == null:
			continue
		if lock_rule.mode == MaterialLockedCard.MODE_STRICT:
			if strict_positions.has(lock_rule.position):
				errors.append("素材 %s 的严锁槽位重复：%d" % [String(material.content_id), lock_rule.position])
			strict_positions[lock_rule.position] = true
		if not is_material_behavior_card(lock_rule.card_id):
			errors.append("素材 %s 的锁定卡不在素材专属卡目录：%s" % [
				String(material.content_id),
				String(lock_rule.card_id),
			])


func _validate_duplicate_material_card_effects(errors: PackedStringArray) -> void:
	for behavior: BehaviorCardResource in behavior_cards:
		if behavior == null:
			continue
		for material: LiveStreamMaterialResource in materials:
			if material == null:
				continue
			for boost: StreamTagEffect in behavior.material_boosts:
				if boost == null or boost.with_tag not in material.tags:
					continue
				for combo: StreamTagEffect in material.combo_effects:
					if combo != null and combo.with_tag in behavior.tags and combo.axis_key == boost.axis_key:
						errors.append("卡牌 %s 与素材 %s 重复定义了 %s 轴组合倍率" % [
							String(behavior.content_id),
							String(material.content_id),
							String(boost.axis_key),
						])


func _validate_content_entry(entry: StreamContentResource, known_ids: Dictionary, errors: PackedStringArray) -> void:
	if entry == null:
		errors.append("目录包含空 Resource")
		return
	if not entry.is_valid_base():
		errors.append("内容 %s 的公共字段无效" % String(entry.content_id))
	if known_ids.has(entry.content_id):
		errors.append("重复内容 ID：%s" % String(entry.content_id))
	known_ids[entry.content_id] = true
	_validate_tags(entry.tags, entry.content_id, errors)
	if entry is LiveStreamCardResource and not (entry as LiveStreamCardResource).is_valid():
		errors.append("卡牌 %s 的业务字段无效" % String(entry.content_id))
	if entry is LiveStreamMaterialResource and not (entry as LiveStreamMaterialResource).is_valid():
		errors.append("素材 %s 的业务字段无效" % String(entry.content_id))
	if entry is StreamPersonaResource and not (entry as StreamPersonaResource).is_valid():
		errors.append("人设 %s 的业务字段无效" % String(entry.content_id))


func _validate_tags(values: Array[StringName], owner_id: StringName, errors: PackedStringArray) -> void:
	for tag: StringName in values:
		if tag not in allowed_tags:
			errors.append("内容 %s 引用了未登记 tag：%s" % [String(owner_id), String(tag)])
