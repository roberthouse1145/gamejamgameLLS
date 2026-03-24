class_name ShopInventoryService
extends RefCounted
## 库存服务：负责库存管理、装备/使用物品、效果查询

signal inventory_changed(inventory: Array)
signal active_effects_changed(active_effects: Array)

var _inventory: Array[Dictionary] = []
var _active_effects: Dictionary = {}
var _last_gift_day: int = -1


func get_inventory() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _inventory:
		result.append(item.duplicate(true))
	return result


func get_active_effects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in _active_effects.keys():
		var inventory_id: String = str(_active_effects[slot])
		var inventory_item := _get_inventory_item(inventory_id)
		if inventory_item.is_empty():
			continue
		var effect_id: String = str(inventory_item.get("effect_archetype", ""))
		var effect := ShopCatalogFactory.get_effect_definition(effect_id)
		result.append({
			"slot": str(slot),
			"inventory_id": inventory_id,
			"title": str(inventory_item.get("title", "")),
			"summary": str(effect.get("summary", "")),
			"persistent_modifiers": effect.get("persistent_modifiers", []),
		})
	return result


func get_active_modifier_map() -> Dictionary:
	var result: Dictionary = {}
	for effect_data in get_active_effects():
		result[str(effect_data.get("slot", ""))] = effect_data.get("persistent_modifiers", [])
	return result


## 添加库存物品（配送到达时由 OrderService 回调）
func add_inventory_item(item: Dictionary) -> void:
	_inventory.append(item.duplicate(true))
	_auto_equip_if_needed(item)


## 使用库存物品
func use_item(inventory_id: String, _target: String, current_day: int, gm: Node) -> Dictionary:
	var index: int = _find_inventory_index(inventory_id)
	if index < 0:
		return {"success": false, "error": "库存里没有这件物品。"}

	var item: Dictionary = _inventory[index].duplicate(true)
	var effect_id: String = str(item.get("effect_archetype", ""))
	var effect := ShopCatalogFactory.get_effect_definition(effect_id)
	var use_mode: String = str(effect.get("use_mode", "consume"))

	if use_mode == "gift":
		if _last_gift_day == current_day:
			return {"success": false, "error": "今天已经送过礼物了，明天再送吧。"}

	if use_mode == "equip":
		var slot: String = str(effect.get("modifier_slot", effect_id))
		if _active_effects.has(slot) and str(_active_effects[slot]) == inventory_id:
			return {"success": false, "error": "该物品已在生效中。"}
		if _active_effects.has(slot):
			var previous_id: String = str(_active_effects[slot])
			var previous_index: int = _find_inventory_index(previous_id)
			if previous_index >= 0:
				var prev: Dictionary = _inventory[previous_index].duplicate(true)
				prev["state"] = "ready"
				prev["equipped_slot"] = ""
				_inventory[previous_index] = prev
		_active_effects[slot] = inventory_id
		item["state"] = "equipped"
		item["equipped_slot"] = slot
	else:
		if use_mode == "gift":
			_last_gift_day = current_day
		# 若该物品处于装备中，需清除 active_effects 里的槽位引用
		var equipped_slot: String = str(item.get("equipped_slot", ""))
		if not equipped_slot.is_empty() and str(_active_effects.get(equipped_slot, "")) == inventory_id:
			_active_effects.erase(equipped_slot)
		item["state"] = "gifted" if use_mode == "gift" else "consumed"
		item["equipped_slot"] = ""

	if gm != null and gm.has_method("modify_stats"):
		var instant_stats: Dictionary = effect.get("instant_stats", {})
		if not instant_stats.is_empty():
			gm.modify_stats(instant_stats)

	# equip: 写回更新状态；gift/consume: 直接从库存移除
	if use_mode == "equip":
		_inventory[index] = item
	else:
		_inventory.remove_at(index)
	inventory_changed.emit(get_inventory())
	active_effects_changed.emit(get_active_effects())

	return {
		"success": true,
		"mode": use_mode,
		"item": item.duplicate(true),
		"instant_stats": effect.get("instant_stats", {}),
		"persistent_modifiers": effect.get("persistent_modifiers", []),
		"effect_summary": str(effect.get("summary", "")),
	}


# ── 存档 ──────────────────────────────────────────────

func get_state() -> Dictionary:
	return {
		"inventory": get_inventory(),
		"active_effects": _active_effects.duplicate(true),
		"last_gift_day": _last_gift_day,
	}


func load_state(data: Dictionary) -> void:
	_inventory.clear()
	_active_effects.clear()
	_last_gift_day = int(data.get("last_gift_day", -1))
	for inventory_item in data.get("inventory", []):
		if inventory_item is Dictionary:
			_inventory.append((inventory_item as Dictionary).duplicate(true))
	var active_effects: Variant = data.get("active_effects", {})
	if active_effects is Dictionary:
		_active_effects = (active_effects as Dictionary).duplicate(true)


func reset() -> void:
	_inventory.clear()
	_active_effects.clear()
	_last_gift_day = -1


# ── 内部 ──────────────────────────────────────────────

func _auto_equip_if_needed(inventory_item: Dictionary) -> void:
	var effect_id: String = str(inventory_item.get("effect_archetype", ""))
	var effect := ShopCatalogFactory.get_effect_definition(effect_id)
	var use_mode: String = str(effect.get("use_mode", "consume"))
	if use_mode != "equip":
		return

	var inventory_id: String = str(inventory_item.get("inventory_id", ""))
	var slot: String = str(effect.get("modifier_slot", effect_id))

	if _active_effects.has(slot):
		var previous_id: String = str(_active_effects[slot])
		var previous_index: int = _find_inventory_index(previous_id)
		if previous_index >= 0:
			var prev: Dictionary = _inventory[previous_index].duplicate(true)
			prev["state"] = "ready"
			prev["equipped_slot"] = ""
			_inventory[previous_index] = prev

	_active_effects[slot] = inventory_id
	var idx: int = _find_inventory_index(inventory_id)
	if idx >= 0:
		var updated: Dictionary = _inventory[idx].duplicate(true)
		updated["state"] = "equipped"
		updated["equipped_slot"] = slot
		_inventory[idx] = updated

	active_effects_changed.emit(get_active_effects())


func _find_inventory_index(inventory_id: String) -> int:
	for i in range(_inventory.size()):
		if str(_inventory[i].get("inventory_id", "")) == inventory_id:
			return i
	return -1


func _get_inventory_item(inventory_id: String) -> Dictionary:
	var index: int = _find_inventory_index(inventory_id)
	if index < 0:
		return {}
	return _inventory[index].duplicate(true)
