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
func create_order(item: ShopItem, current_day: int, is_debug: bool, inventory_callback: Callable) -> Dictionary:
	if has_purchased_item(item.instance_id):
		return {"success": false, "error": "这件商品已经买过了。"}

	var order_id: String = _next_id("order")
	var shipping_days_val: int = maxi(1, item.shipping_days)
	var order := {
		"order_id": order_id,
		"catalog_entry_id": item.instance_id,
		"item_snapshot": item.to_dict(),
		"purchase_day": current_day,
		"delivery_day": current_day + shipping_days_val,
		"status": "shipping",
		"tracking_text": _build_tracking_text(current_day, current_day + shipping_days_val),
	}
	_orders.append(order)
	purchase_completed.emit(order.duplicate(true))
	order_status_changed.emit(order_id, "shipping")

	if is_debug:
		_instant_deliver_order(_orders.size() - 1, inventory_callback)

	var latest_order: Dictionary = _orders[_orders.size() - 1].duplicate(true)
	var msg: String = "已下单，已直接送达（调试模式）。" if is_debug \
		else "已下单，预计 Day %d 送达。" % int(latest_order.get("delivery_day", current_day))
	return {"success": true, "order": latest_order, "message": msg}


## 推进配送：检查所有未送达订单，到期的自动送达
## inventory_callback: Callable(inventory_item: Dictionary) -> void
func advance_orders_for_day(day: int, inventory_callback: Callable) -> bool:
	var did_deliver: bool = false
	for i in range(_orders.size()):
		var order: Dictionary = _orders[i].duplicate(true)
		if str(order.get("status", "")) == "delivered":
			continue
		if day < int(order.get("delivery_day", day)):
			order["tracking_text"] = _build_tracking_text(day, int(order.get("delivery_day", day)))
			_orders[i] = order
			continue

		order["status"] = "delivered"
		order["tracking_text"] = "已送达"
		var inventory_item := _build_inventory_item_from_order(order)
		order["inventory_id"] = str(inventory_item.get("inventory_id", ""))
		_orders[i] = order
		inventory_callback.call(inventory_item)
		order_status_changed.emit(str(order.get("order_id", "")), "delivered")
		delivery_arrived.emit(str(order.get("order_id", "")), inventory_item.duplicate(true))
		did_deliver = true
	return did_deliver


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

func _instant_deliver_order(order_index: int, inventory_callback: Callable) -> void:
	var order: Dictionary = _orders[order_index].duplicate(true)
	order["status"] = "delivered"
	order["tracking_text"] = "已送达（调试模式）"
	order["delivery_day"] = int(order.get("purchase_day", 1))
	var inventory_item := _build_inventory_item_from_order(order)
	order["inventory_id"] = str(inventory_item.get("inventory_id", ""))
	_orders[order_index] = order
	inventory_callback.call(inventory_item)
	order_status_changed.emit(str(order.get("order_id", "")), "delivered")
	delivery_arrived.emit(str(order.get("order_id", "")), inventory_item.duplicate(true))


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


func _build_tracking_text(current_day: int, delivery_day: int) -> String:
	if current_day >= delivery_day:
		return "已送达"
	if delivery_day - current_day <= 1:
		return "正在派送中"
	return "运输中，预计 Day %d 送达" % delivery_day


func _next_id(prefix: String) -> String:
	_id_counter += 1
	return "%s_%04d" % [prefix, _id_counter]
