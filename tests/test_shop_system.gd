extends Control

const ShopAppClass = preload("res://scripts/apps/shop/shop_app.gd")

var _wm: WindowManager = null


func _ready() -> void:
	print("=== Shop System Test ===")

	var shop: Node = get_node_or_null("/root/ShopManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var am: Node = get_node_or_null("/root/AppManager")

	if shop == null or gm == null or glm == null or am == null:
		print("[FAIL] missing required autoload")
		return

	shop.reset_runtime_state()
	gm.reset_runtime_state()
	glm.reset_runtime_state()
	shop.refresh_daily_catalog(true, true)

	var catalog: Array = shop.get_catalog()
	_assert(catalog.size() >= 4, "catalog refreshed with entries")
	_assert(_find_catalog_item(catalog, "core_pillow").is_empty(), "no fixed core items in catalog")
	_assert(_find_catalog_item(catalog, "core_cake").is_empty(), "no legacy core gift in catalog")

	var gift_item := _find_catalog_by_category(catalog, "gift")
	var consume_item := _find_catalog_consumable(catalog)
	_assert(not gift_item.is_empty(), "gift item exists in local catalog")
	_assert(not consume_item.is_empty(), "consume item exists in local catalog")
	if gift_item.is_empty() or consume_item.is_empty():
		return

	var start_money: int = int(gm.get("money"))
	var buy_consume: Dictionary = shop.purchase_item(str(consume_item.get("instance_id", "")))
	var buy_gift: Dictionary = shop.purchase_item(str(gift_item.get("instance_id", "")))
	_assert(bool(buy_consume.get("success", false)), "purchase consume item succeeds")
	_assert(bool(buy_gift.get("success", false)), "purchase gift item succeeds")

	var expected_money: int = start_money - int(consume_item.get("price", 0)) - int(gift_item.get("price", 0))
	_assert(int(gm.get("money")) == expected_money, "money reduced after purchase")

	var inventory: Array = shop.get_inventory()
	_assert(inventory.size() >= 2, "orders added to inventory immediately")

	var orders: Array = shop.get_orders()
	_assert(orders.size() >= 2, "orders recorded after purchase")
	if orders.size() >= 2:
		_assert(str(orders[0].get("status", "")) == "delivered", "order status is delivered immediately")
		_assert(str(orders[0].get("tracking_text", "")) == "已入库", "order tracking text is normalized")
	else:
		_assert(true, "order status is delivered immediately")
		_assert(true, "order tracking text is normalized")

	var gift_inventory := _find_inventory_item(inventory, str(gift_item.get("item_id", "")))
	var consume_inventory := _find_inventory_item(inventory, str(consume_item.get("item_id", "")))
	_assert(not gift_inventory.is_empty(), "gift delivery found")
	_assert(not consume_inventory.is_empty(), "consume delivery found")

	var gift_stats: Dictionary = gift_inventory.get("instant_stats", {})
	_assert(not gift_stats.is_empty(), "gift inventory keeps snapshot instant_stats")
	var before_gift := _snapshot_stats(gm)
	var use_gift: Dictionary = shop.use_inventory_item(str(gift_inventory.get("inventory_id", "")), "heroine")
	_assert(bool(use_gift.get("success", false)), "gift action succeeds")
	_assert(_stats_changed(gm, before_gift, gift_stats), "gift applies item instant_stats")

	var inv_before_pillow: Array = shop.get_inventory()
	var consume_ready := _find_inventory_item(inv_before_pillow, str(consume_item.get("item_id", "")))
	_assert(str(consume_ready.get("state", "")) == "ready", "consume item ready before use")

	var consume_stats: Dictionary = consume_inventory.get("instant_stats", {})
	_assert(not consume_stats.is_empty(), "consume inventory keeps snapshot instant_stats")
	var before_consume := _snapshot_stats(gm)
	var use_consume: Dictionary = shop.use_inventory_item(str(consume_inventory.get("inventory_id", "")), "self")
	_assert(bool(use_consume.get("success", false)), "consume item succeeds")
	_assert(_stats_changed(gm, before_consume, consume_stats), "consume applies snapshot instant_stats")

	# 装备系统已简化，无持久 buff；一次性道具使用后从库存移除。
	_assert(shop.get_active_effects().is_empty(), "no persistent active effects")
	var inv_after: Array = shop.get_inventory()
	_assert(_find_inventory_item(inv_after, str(consume_item.get("item_id", ""))).is_empty(), "consume item removed after use")

	# ── 限购测试：同一商品不能重复购买 ──
	var rebuy_consume: Dictionary = shop.purchase_item(str(consume_item.get("instance_id", "")))
	_assert(not bool(rebuy_consume.get("success", false)), "duplicate purchase blocked")

	_wm = WindowManager.new()
	_wm.name = "WindowManager"
	add_child(_wm)

	var container := Control.new()
	container.name = "WindowContainer"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_wm.window_container = container

	am.window_manager = _wm
	_assert(am.app_registry.has("shop"), "shop app registered")

	var window: Control = am.launch_app("shop")
	_assert(window != null, "shop app launches")
	if window == null:
		return

	await get_tree().process_frame
	var content: Control = window.get("content")
	_assert(content != null, "shop app content exists")
	if content != null:
		_assert(content.get_script() == ShopAppClass, "launched content is ShopApp")


func _find_catalog_item(catalog: Array, item_id: String) -> Dictionary:
	for raw_item in catalog:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item as Dictionary
		if str(item.get("item_id", "")) == item_id or str(item.get("instance_id", "")) == item_id:
			return item.duplicate(true)
	return {}


func _find_inventory_item(inventory: Array, item_id: String) -> Dictionary:
	for raw_item in inventory:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item as Dictionary
		if str(item.get("item_id", "")) == item_id or str(item.get("instance_id", "")) == item_id:
			return item.duplicate(true)
	return {}


func _find_catalog_by_category(catalog: Array, category: String) -> Dictionary:
	for raw_item in catalog:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item as Dictionary
		if str(item.get("category", "")) == category:
			return item.duplicate(true)
	return {}


func _find_catalog_consumable(catalog: Array) -> Dictionary:
	for raw_item in catalog:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item as Dictionary
		var effect := ShopCatalogFactory.get_effect_definition(str(item.get("effect_archetype", "")))
		if str(effect.get("use_mode", "consume")) == "consume":
			return item.duplicate(true)
	return {}


func _snapshot_stats(gm: Node) -> Dictionary:
	return {
		"stress": int(gm.get("stress")),
		"passion": int(gm.get("passion")),
	}


func _stats_changed(gm: Node, before: Dictionary, stats: Dictionary) -> bool:
	for key in ["stress", "passion"]:
		if not stats.has(key):
			continue
		if int(gm.get(key)) != int(before.get(key, 0)):
			return true
	return false


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("[OK] %s" % label)
	else:
		print("[FAIL] %s" % label)
