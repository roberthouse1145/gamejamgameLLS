class_name ShopOrderService
extends RefCounted
## 订单服务：负责下单、配送推进、订单查询
## 不持有场景树引用，所有外部依赖通过方法参数传入

const _ShopItem = preload("res://scripts/shop/shop_item.gd")

signal purchase_completed(order: Dictionary)
signal order_status_changed(order_id: String, status: String)
signal delivery_arrived(order_id: String, inventory_item: Dictionary)

var _orders: Array[Dictionary] = []
var _id_counter: int = 0


func get_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order in _orders:
		result.append(order.duplicate(true))
	return result


func has_purchased_item(item_id: String) -> bool:
	for order in _orders:
		var snapshot: Dictionary = order.get("item_snapshot", {})
		if str(snapshot.get("instance_id", "")) == item_id \
				or str(snapshot.get("item_id", "")) == item_id \
				or str(snapshot.get("base_id", "")) == item_id:
			return true
	return false


## 创建订单。返回 {success, order?, error?, message?}
## inventory_callback: Callable(inventory_item: Dictionary) -> void，配送到达时回调
func create_order(item: ShopItem, current_day: int, _is_debug: bool, inventory_callback: Callable) -> Dictionary:
	if has_purchased_item(item.instance_id):
		return {"success": false, "error": "这件商品已经买过了。"}

	var order_id: String = _next_id("order")
	var order := {
		"order_id": order_id,
		"catalog_entry_id": item.instance_id,
		"item_snapshot": item.to_dict(),
		"purchase_day": current_day,
		"delivery_day": current_day,
		"status": "delivered",
		"tracking_text": "已入库",
	}
	var inventory_item := _build_inventory_item_from_order(order)
	order["inventory_id"] = str(inventory_item.get("inventory_id", ""))
	_orders.append(order)
	inventory_callback.call(inventory_item)
	purchase_completed.emit(order.duplicate(true))
	order_status_changed.emit(order_id, "delivered")
	delivery_arrived.emit(order_id, inventory_item.duplicate(true))

	var latest_order: Dictionary = order.duplicate(true)
	var msg: String = "已购买，已放入库存。"
	return {"success": true, "order": latest_order, "message": msg}


## 推进配送：检查所有未送达订单，到期的自动送达
## inventory_callback: Callable(inventory_item: Dictionary) -> void
func advance_orders_for_day(_day: int, _inventory_callback: Callable) -> bool:
	return false


func normalize_orders_for_instant_inventory(inventory_callback: Callable) -> bool:
	var changed: bool = false
	for i in range(_orders.size()):
		var order: Dictionary = _orders[i].duplicate(true)
		if str(order.get("status", "")) != "delivered":
			order["status"] = "delivered"
			order["delivery_day"] = int(order.get("purchase_day", 1))
			if str(order.get("inventory_id", "")).is_empty():
				var inventory_item := _build_inventory_item_from_order(order)
				order["inventory_id"] = str(inventory_item.get("inventory_id", ""))
				inventory_callback.call(inventory_item)
				order_status_changed.emit(str(order.get("order_id", "")), "delivered")
				delivery_arrived.emit(str(order.get("order_id", "")), inventory_item.duplicate(true))
			changed = true
		if str(order.get("tracking_text", "")) != "已入库":
			order["tracking_text"] = "已入库"
			changed = true
		_orders[i] = order
	return changed


# ── 存档 ──────────────────────────────────────────────

func get_state() -> Dictionary:
	return {
		"orders": get_orders(),
		"id_counter": _id_counter,
	}


func load_state(data: Dictionary) -> void:
	_orders.clear()
	_id_counter = int(data.get("id_counter", 0))
	for order in data.get("orders", []):
		if order is Dictionary:
			_orders.append((order as Dictionary).duplicate(true))


func reset() -> void:
	_orders.clear()
	_id_counter = 0


# ── 内部 ──────────────────────────────────────────────

func _build_inventory_item_from_order(order: Dictionary) -> Dictionary:
	var snap: Dictionary = order.get("item_snapshot", {}).duplicate(true)
	return {
		"inventory_id": _next_id("inv"),
		"instance_id": str(snap.get("instance_id", "")),
		"item_id": str(snap.get("item_id", "")),
		"base_id": str(snap.get("base_id", snap.get("item_id", ""))),
		"title": str(snap.get("title", "")),
		"category": str(snap.get("category", "")),
		"effect_archetype": str(snap.get("effect_archetype", "flavor_no_effect")),
		"giftable": bool(snap.get("giftable", false)),
		"tags": snap.get("tags", []).duplicate(true),
		"state": "ready",
		"equipped_slot": "",
	}

func _next_id(prefix: String) -> String:
	_id_counter += 1
	return "%s_%04d" % [prefix, _id_counter]
