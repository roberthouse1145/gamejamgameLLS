extends Node
## ShopManager 鈥?鍟嗗簵杩愯惀鏍稿績锛氳鍗?搴撳瓨/瑁呭鐘舵€佺鐞?+ 瀛樻。
## 鐩綍鐢熸垚閫昏緫濮旀墭缁?ShopCatalogFactory

signal catalog_refreshed(catalog: Array)
signal catalog_generation_started(day: int)
signal catalog_generation_failed(error_msg: String)
signal purchase_completed(order: Dictionary)
signal order_status_changed(order_id: String, status: String)
signal delivery_arrived(order_id: String, inventory_item: Dictionary)
signal inventory_changed(inventory: Array)
signal active_effects_changed(active_effects: Array)
signal shop_state_changed()

const FIXED_CORE_ITEMS_PATH: String = "res://resources/data/shop/fixed_core_items.json"
const SHOP_ROLE: String = "shop_generator"
const FALLBACK_ROLE: String = "chat_default"

var _ai_service: AIService = null
var _llm_enabled: bool = false
var _catalog_request_id: String = ""
var _catalog_request_day: int = -1
var _is_generating_catalog: bool = false
var _fixed_core_items: Array[Dictionary] = []
var _catalog: Array[Dictionary] = []
var _catalog_day: int = -1
var _orders: Array[Dictionary] = []
var _inventory: Array[Dictionary] = []
var _active_effects: Dictionary = {}
var _id_counter: int = 0
var _last_gift_day: int = -1


func _ready() -> void:
	name = "ShopManager"
	_load_fixed_core_items()
	_setup_ai_service()
	_connect_signals()
	_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(_get_current_day(), _fixed_core_items, _get_gm()), _get_current_day())


func _connect_signals() -> void:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("day_changed") and not glm.day_changed.is_connected(_on_day_changed):
		glm.day_changed.connect(_on_day_changed)


func _setup_ai_service() -> void:
	_ai_service = AIService.new()
	_ai_service.name = "ShopAIService"
	_ai_service.max_history_messages = 0
	_ai_service.auto_execute_tools = false
	_ai_service.stream_enabled = false
	_ai_service.max_concurrent_requests = 1
	_ai_service.default_temperature = 0.9
	add_child(_ai_service)

	if not _ai_service.request_completed.is_connected(_on_ai_request_completed):
		_ai_service.request_completed.connect(_on_ai_request_completed)
	if not _ai_service.request_failed.is_connected(_on_ai_request_failed):
		_ai_service.request_failed.connect(_on_ai_request_failed)

	var config_mgr := AIConfigManager.new()
	if config_mgr.load_config():
		if not config_mgr.get_config_for_role(SHOP_ROLE).is_empty():
			_llm_enabled = config_mgr.apply_to_service(_ai_service, SHOP_ROLE)
		if not _llm_enabled and not config_mgr.get_config_for_role(FALLBACK_ROLE).is_empty():
			_llm_enabled = config_mgr.apply_to_service(_ai_service, FALLBACK_ROLE)


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
#  鍏叡鏌ヨ API
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func get_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _catalog:
		result.append((item as Dictionary).duplicate(true))
	return result


func get_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order in _orders:
		result.append((order as Dictionary).duplicate(true))
	return result


func get_inventory() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _inventory:
		result.append((item as Dictionary).duplicate(true))
	return result


func get_catalog_day() -> int:
	return _catalog_day


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


func has_pending_requests() -> bool:
	return _is_generating_catalog and not _catalog_request_id.is_empty()


func has_purchased_item(item_id: String) -> bool:
	for order in _orders:
		var snapshot: Dictionary = (order as Dictionary).get("item_snapshot", {})
		if str(snapshot.get("item_id", "")) == item_id:
			return true
	return false


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
#  鐩綍鍒锋柊
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func refresh_daily_catalog(force: bool = false, use_local_only: bool = false) -> void:
	var day: int = _get_current_day()
	if not force and day == _catalog_day and not _catalog.is_empty():
		catalog_refreshed.emit(get_catalog())
		return

	if use_local_only or _ai_service == null or not _llm_enabled:
		_cancel_pending_catalog_request()
		_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(day, _fixed_core_items, _get_gm()), day)
		return

	_cancel_pending_catalog_request()
	_is_generating_catalog = true
	_catalog_request_day = day
	catalog_generation_started.emit(day)
	_catalog_request_id = _ai_service.chat_simple(
		ShopCatalogFactory.build_generation_prompt(day, _fixed_core_items.size(), _get_gm()),
		ShopCatalogFactory.build_generation_system_prompt()
	)
	if _catalog_request_id.is_empty():
		_is_generating_catalog = false
		catalog_generation_failed.emit("商品生成请求未能发出，已回退到本地商品。")
		_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(day, _fixed_core_items, _get_gm()), day)


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
#  璐拱 / 浣跨敤
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func purchase_item(item_ref: String) -> Dictionary:
	var item := _find_catalog_item(item_ref)
	if item.is_empty():
		return {"success": false, "error": "没有找到这件商品。"}

	var item_id: String = str(item.get("item_id", ""))
	if has_purchased_item(item_id):
		return {"success": false, "error": "这件商品已经买过了。"}

	var price: int = int(item.get("price", 0))
	var gm: Node = _get_gm()
	if gm == null:
		return {"success": false, "error": "GameManager 不存在。"}
	if int(gm.get("money")) < price:
		return {"success": false, "error": "余额不足。"}

	gm.modify_stat("money", -price)
	var current_day: int = _get_current_day()
	var order_id: String = _next_id("order")
	var shipping_days: int = maxi(1, int(item.get("shipping_days", 1)))
	var order := {
		"order_id": order_id,
		"catalog_entry_id": str(item.get("instance_id", item.get("item_id", ""))),
		"item_snapshot": item.duplicate(true),
		"purchase_day": current_day,
		"delivery_day": current_day + shipping_days,
		"status": "shipping",
		"tracking_text": _build_tracking_text(current_day, current_day + shipping_days),
	}
	_orders.append(order)
	purchase_completed.emit(order.duplicate(true))
	order_status_changed.emit(order_id, "shipping")

	var storage: Node = get_node_or_null("/root/StorageManager")
	var is_debug: bool = storage != null and bool(storage.get("developer_mode"))
	if is_debug:
		_instant_deliver_order(_orders.size() - 1)

	var latest_order: Dictionary = (_orders[_orders.size() - 1] as Dictionary).duplicate(true)
	_emit_state_changed()
	var msg: String = "已下单，已直接送达（调试模式）。" if is_debug else "已下单，预计 Day %d 送达。" % int(latest_order.get("delivery_day", current_day))
	return {
		"success": true,
		"order": latest_order,
		"message": msg,
	}


func use_inventory_item(inventory_id: String, target: String = "self") -> Dictionary:
	var index: int = _find_inventory_index(inventory_id)
	if index < 0:
		return {"success": false, "error": "库存里没有这件物品。"}

	var item: Dictionary = (_inventory[index] as Dictionary).duplicate(true)
	var state: String = str(item.get("state", "ready"))
	if state == "consumed" or state == "gifted":
		return {"success": false, "error": "这件物品已经使用过了。"}

	var effect_id: String = str(item.get("effect_archetype", ""))
	var effect := ShopCatalogFactory.get_effect_definition(effect_id)
	var use_mode: String = str(effect.get("use_mode", "consume"))
	var gm: Node = _get_gm()

	if use_mode == "gift":
		var current_day: int = _get_current_day()
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
				var previous_item: Dictionary = (_inventory[previous_index] as Dictionary).duplicate(true)
				previous_item["state"] = "ready"
				previous_item["equipped_slot"] = ""
				_inventory[previous_index] = previous_item
		_active_effects[slot] = inventory_id
		item["state"] = "equipped"
		item["equipped_slot"] = slot
	else:
		if use_mode == "gift":
			_last_gift_day = _get_current_day()
		item["state"] = "gifted" if use_mode == "gift" else "consumed"
		item["equipped_slot"] = ""

	if gm != null and gm.has_method("modify_stats"):
		var instant_stats: Dictionary = effect.get("instant_stats", {})
		if not instant_stats.is_empty():
			gm.modify_stats(instant_stats)

	_inventory[index] = item
	inventory_changed.emit(get_inventory())
	active_effects_changed.emit(get_active_effects())
	_emit_state_changed()

	return {
		"success": true,
		"mode": use_mode,
		"item": item.duplicate(true),
		"instant_stats": effect.get("instant_stats", {}),
		"persistent_modifiers": effect.get("persistent_modifiers", []),
		"effect_summary": str(effect.get("summary", "")),
		"reaction_text": _build_reaction_text(item, target, use_mode),
	}


func process_day_transition(day: int) -> void:
	_advance_orders_for_day(day)


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
#  瀛樻。
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func get_run_state() -> Dictionary:
	return {
		"catalog_day": _catalog_day,
		"catalog": get_catalog(),
		"orders": get_orders(),
		"inventory": get_inventory(),
		"active_effects": _active_effects.duplicate(true),
		"id_counter": _id_counter,
		"last_gift_day": _last_gift_day,
	}


func load_run_state(data: Dictionary) -> bool:
	_cancel_pending_catalog_request()
	_catalog_day = int(data.get("catalog_day", -1))
	_catalog.clear()
	_orders.clear()
	_inventory.clear()
	_active_effects.clear()
	_id_counter = int(data.get("id_counter", 0))
	_last_gift_day = int(data.get("last_gift_day", -1))

	for item in data.get("catalog", []):
		if item is Dictionary:
			_catalog.append((item as Dictionary).duplicate(true))
	for order in data.get("orders", []):
		if order is Dictionary:
			_orders.append((order as Dictionary).duplicate(true))
	for inventory_item in data.get("inventory", []):
		if inventory_item is Dictionary:
			_inventory.append((inventory_item as Dictionary).duplicate(true))

	var active_effects: Variant = data.get("active_effects", {})
	if active_effects is Dictionary:
		_active_effects = (active_effects as Dictionary).duplicate(true)

	if _catalog.is_empty():
		_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(_get_current_day(), _fixed_core_items, _get_gm()), _get_current_day())
	else:
		catalog_refreshed.emit(get_catalog())
		inventory_changed.emit(get_inventory())
		active_effects_changed.emit(get_active_effects())
		_emit_state_changed()
	return true


func reset_runtime_state() -> void:
	_cancel_pending_catalog_request()
	_catalog.clear()
	_orders.clear()
	_inventory.clear()
	_active_effects.clear()
	_id_counter = 0
	_last_gift_day = -1
	_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(_get_current_day(), _fixed_core_items, _get_gm()), _get_current_day())


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
#  鍐呴儴锛氶厤閫?/ 瑁呭
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
func _on_day_changed(new_day: int) -> void:
	_advance_orders_for_day(new_day)
	refresh_daily_catalog(true)



func _instant_deliver_order(order_index: int) -> void:
	var order: Dictionary = (_orders[order_index] as Dictionary).duplicate(true)
	order["status"] = "delivered"
	order["tracking_text"] = "宸查€佽揪锛堣皟璇曟ā寮忥級"
	order["delivery_day"] = int(order.get("purchase_day", _get_current_day()))
	var inventory_item := _build_inventory_item_from_order(order)
	order["inventory_id"] = str(inventory_item.get("inventory_id", ""))
	_orders[order_index] = order
	_inventory.append(inventory_item)
	_auto_equip_if_needed(inventory_item)
	order_status_changed.emit(str(order.get("order_id", "")), "delivered")
	delivery_arrived.emit(str(order.get("order_id", "")), inventory_item.duplicate(true))
	inventory_changed.emit(get_inventory())


func _advance_orders_for_day(day: int) -> void:
	var inventory_did_change: bool = false
	for i in range(_orders.size()):
		var order: Dictionary = (_orders[i] as Dictionary).duplicate(true)
		if str(order.get("status", "")) == "delivered":
			continue
		if day < int(order.get("delivery_day", day)):
			order["tracking_text"] = _build_tracking_text(day, int(order.get("delivery_day", day)))
			_orders[i] = order
			continue

		order["status"] = "delivered"
		order["tracking_text"] = "宸查€佽揪"
		var inventory_item := _build_inventory_item_from_order(order)
		order["inventory_id"] = str(inventory_item.get("inventory_id", ""))
		_orders[i] = order
		_inventory.append(inventory_item)
		_auto_equip_if_needed(inventory_item)
		order_status_changed.emit(str(order.get("order_id", "")), "delivered")
		delivery_arrived.emit(str(order.get("order_id", "")), inventory_item.duplicate(true))
		inventory_did_change = true

	if inventory_did_change:
		inventory_changed.emit(get_inventory())
		_emit_state_changed()


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
			var previous_item: Dictionary = (_inventory[previous_index] as Dictionary).duplicate(true)
			previous_item["state"] = "ready"
			previous_item["equipped_slot"] = ""
			_inventory[previous_index] = previous_item

	_active_effects[slot] = inventory_id
	var index: int = _find_inventory_index(inventory_id)
	if index >= 0:
		var updated: Dictionary = (_inventory[index] as Dictionary).duplicate(true)
		updated["state"] = "equipped"
		updated["equipped_slot"] = slot
		_inventory[index] = updated

	var gm: Node = _get_gm()
	if gm != null and gm.has_method("modify_stats"):
		var instant_stats: Dictionary = effect.get("instant_stats", {})
		if not instant_stats.is_empty():
			gm.modify_stats(instant_stats)

	active_effects_changed.emit(get_active_effects())


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
#  鍐呴儴锛歀LM 鍥炶皟
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _catalog_request_id:
		return

	var request_day: int = _catalog_request_day
	_cancel_pending_catalog_request()

	var raw_text: String = AIService.extract_content(response).strip_edges()
	var max_llm: int = maxi(1, ShopCatalogFactory.CATALOG_SIZE - _fixed_core_items.size())
	var llm_items := ShopCatalogFactory.parse_llm_catalog_items(raw_text, request_day, max_llm)
	if llm_items.is_empty():
		catalog_generation_failed.emit("LLM 商品结果解析失败，已回退到本地商品。")
		_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(request_day, _fixed_core_items, _get_gm()), request_day)
		return

	var catalog: Array[Dictionary] = []
	var index: int = 0
	for fixed_item in _fixed_core_items:
		catalog.append(ShopCatalogFactory.decorate_catalog_item((fixed_item as Dictionary).duplicate(true), request_day, index))
		index += 1
	for item in llm_items:
		catalog.append(ShopCatalogFactory.decorate_catalog_item(item.duplicate(true), request_day, index))
		index += 1
		if catalog.size() >= ShopCatalogFactory.CATALOG_SIZE:
			break

	var local_fill_candidates: Array[Dictionary] = ShopCatalogFactory.generate_local_daily_catalog(request_day, [], _get_gm())
	var used_fill_item_ids: Dictionary = {}
	for existing_item in catalog:
		used_fill_item_ids[str((existing_item as Dictionary).get("item_id", ""))] = true

	while catalog.size() < ShopCatalogFactory.CATALOG_SIZE:
		var appended: bool = false
		for candidate in local_fill_candidates:
			var candidate_item: Dictionary = candidate as Dictionary
			var candidate_item_id: String = str(candidate_item.get("item_id", ""))
			if used_fill_item_ids.has(candidate_item_id):
				continue
			catalog.append(candidate_item.duplicate(true))
			used_fill_item_ids[candidate_item_id] = true
			appended = true
			break
		if not appended:
			break

	_apply_catalog(catalog, request_day)


func _on_ai_request_failed(request_id: String, error_msg: String, _error_code: int) -> void:
	if request_id != _catalog_request_id:
		return
	var request_day: int = _catalog_request_day
	_cancel_pending_catalog_request()
	catalog_generation_failed.emit("LLM 商品生成失败：%s，已回退到本地商品。" % error_msg)
	_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(request_day, _fixed_core_items, _get_gm()), request_day)



# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
#  鍐呴儴锛氬伐鍏峰嚱鏁?# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func _build_inventory_item_from_order(order: Dictionary) -> Dictionary:
	var item: Dictionary = order.get("item_snapshot", {}).duplicate(true)
	return {
		"inventory_id": _next_id("inv"),
		"order_id": str(order.get("order_id", "")),
		"item_id": str(item.get("item_id", "")),
		"title": str(item.get("title", "")),
		"subtitle": str(item.get("subtitle", "")),
		"category": str(item.get("category", "")),
		"sub_category": str(item.get("sub_category", "")),
		"effect_archetype": str(item.get("effect_archetype", "flavor_no_effect")),
		"source_type": str(item.get("source_type", "")),
		"giftable": bool(item.get("giftable", false)),
		"tags": item.get("tags", []).duplicate(true),
		"heroine_reaction_hint": str(item.get("heroine_reaction_hint", "")),
		"detail_desc": str(item.get("detail_desc", "")),
		"state": "ready",
		"equipped_slot": "",
		"delivered_day": int(order.get("delivery_day", _get_current_day())),
	}


func _load_fixed_core_items() -> void:
	_fixed_core_items.clear()
	if not FileAccess.file_exists(FIXED_CORE_ITEMS_PATH):
		push_warning("[ShopManager] fixed core items file missing: %s" % FIXED_CORE_ITEMS_PATH)
		return
	var file := FileAccess.open(FIXED_CORE_ITEMS_PATH, FileAccess.READ)
	if file == null:
		push_warning("[ShopManager] failed to open fixed core items file")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Array:
		push_warning("[ShopManager] invalid fixed core items json")
		return
	for raw_item in parsed:
		if raw_item is Dictionary:
			_fixed_core_items.append((raw_item as Dictionary).duplicate(true))


func _apply_catalog(items: Array[Dictionary], day: int) -> void:
	_catalog = []
	for item in items:
		_catalog.append(item.duplicate(true))
	_catalog_day = day
	catalog_refreshed.emit(get_catalog())
	_emit_state_changed()


func _find_catalog_item(item_ref: String) -> Dictionary:
	for item in _catalog:
		var catalog_item: Dictionary = item as Dictionary
		if str(catalog_item.get("instance_id", "")) == item_ref or str(catalog_item.get("item_id", "")) == item_ref:
			return catalog_item.duplicate(true)
	return {}


func _find_inventory_index(inventory_id: String) -> int:
	for i in range(_inventory.size()):
		if str((_inventory[i] as Dictionary).get("inventory_id", "")) == inventory_id:
			return i
	return -1


func _get_inventory_item(inventory_id: String) -> Dictionary:
	var index: int = _find_inventory_index(inventory_id)
	if index < 0:
		return {}
	return (_inventory[index] as Dictionary).duplicate(true)


func _build_tracking_text(current_day: int, delivery_day: int) -> String:
	if current_day >= delivery_day:
		return "宸查€佽揪"
	if delivery_day - current_day <= 1:
		return "姝ｅ湪娲鹃€佷腑"
	return "杩愯緭涓紝棰勮 Day %d 閫佽揪" % delivery_day


func _build_reaction_text(item: Dictionary, target: String, use_mode: String) -> String:
	var hint: String = str(item.get("heroine_reaction_hint", "")).strip_edges()
	if not hint.is_empty():
		return hint
	if use_mode == "gift" or target == "heroine":
		return "她应该会先看你一眼，再决定要不要把这份心意收下。"
	if use_mode == "equip":
		return "这件东西会开始常驻在房间里，慢慢改变你们的生活气味。"
	if use_mode == "consume":
		return "它的效果会来得快一点，也会过去得快一点。"
	return "它更像是给生活添了一点细节。"


func _next_id(prefix: String) -> String:
	_id_counter += 1
	return "%s_%04d" % [prefix, _id_counter]


func _cancel_pending_catalog_request() -> void:
	_catalog_request_id = ""
	_catalog_request_day = -1
	_is_generating_catalog = false


func _get_current_day() -> int:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		return 1
	return maxi(1, int(glm.get("current_day")))


func _get_gm() -> Node:
	return get_node_or_null("/root/GameManager")


func _emit_state_changed() -> void:
	shop_state_changed.emit()

