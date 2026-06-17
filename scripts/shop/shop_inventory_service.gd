class_name ShopInventoryService
extends RefCounted
## 库存服务：负责库存管理、礼物/一次性道具使用

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
	return []


func get_active_modifier_map() -> Dictionary:
	return {}


## 添加库存物品（配送到达时由 OrderService 回调）
func add_inventory_item(item: Dictionary) -> void:
	_inventory.append(item.duplicate(true))
	inventory_changed.emit(get_inventory())


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

	if use_mode == "gift":
		_last_gift_day = current_day
	item["state"] = "gifted" if use_mode == "gift" else "consumed"
	item["equipped_slot"] = ""

	var item_stats: Dictionary = item.get("instant_stats", {})
	var resolved_stats: Dictionary = item_stats if not item_stats.is_empty() else effect.get("instant_stats", {})

	if gm != null and gm.has_method("modify_stats"):
		if not resolved_stats.is_empty():
			gm.modify_stats(resolved_stats)

	_inventory.remove_at(index)
	inventory_changed.emit(get_inventory())
	active_effects_changed.emit([])
	return {
		"success": true,
		"mode": use_mode,
		"item": item.duplicate(true),
		"instant_stats": resolved_stats,
		"persistent_modifiers": effect.get("persistent_modifiers", []),
		"effect_summary": str(effect.get("summary", "")),
	}


# ── 存档 ──────────────────────────────────────────────

func get_state() -> Dictionary:
	return {
		"inventory": get_inventory(),
		"active_effects": {},
		"last_gift_day": _last_gift_day,
	}


func load_state(data: Dictionary) -> void:
	_inventory.clear()
	_active_effects.clear()
	_last_gift_day = int(data.get("last_gift_day", -1))
	for inventory_item in data.get("inventory", []):
		if inventory_item is Dictionary:
			var item := (inventory_item as Dictionary).duplicate(true)
			if str(item.get("state", "")) == "equipped":
				item["state"] = "ready"
				item["equipped_slot"] = ""
			_inventory.append(item)


func reset() -> void:
	_inventory.clear()
	_active_effects.clear()
	_last_gift_day = -1


# ── 内部 ──────────────────────────────────────────────

func _auto_equip_if_needed(_inventory_item: Dictionary) -> void:
	pass


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
