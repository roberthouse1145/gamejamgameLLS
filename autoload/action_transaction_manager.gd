extends Node
## 时段与金钱的原子提交入口。调用方先 reserve，内容准备成功后再 commit。

signal transaction_reserved(transaction_id: String, snapshot: Dictionary)
signal transaction_committed(transaction_id: String, snapshot: Dictionary)
signal transaction_cancelled(transaction_id: String)

var _reservations: Dictionary = {}


func reserve(
	transaction_id: String,
	owner_id: String,
	money_cost: int,
	time_slots: int
) -> bool:
	var normalized_id: String = transaction_id.strip_edges()
	if normalized_id.is_empty() or money_cost < 0 or time_slots < 0:
		return false
	if is_committed(normalized_id):
		return true
	if _reservations.has(normalized_id):
		return true
	if not _can_prepare(owner_id, money_cost):
		return false
	var snapshot: Dictionary = {
		"transaction_id": normalized_id,
		"owner_id": owner_id.strip_edges(),
		"money_cost": money_cost,
		"time_slots": time_slots,
		"day": int(GameState.day),
		"time_slot": int(GameState.time_slot),
	}
	_reservations[normalized_id] = snapshot
	transaction_reserved.emit(normalized_id, snapshot.duplicate(true))
	return true


func commit(transaction_id: String) -> bool:
	var normalized_id: String = transaction_id.strip_edges()
	if is_committed(normalized_id):
		return true
	if not _reservations.has(normalized_id):
		return false
	var snapshot: Dictionary = _reservations[normalized_id] as Dictionary
	var owner_id: String = str(snapshot.get("owner_id", ""))
	var money_cost: int = int(snapshot.get("money_cost", 0))
	if not _can_prepare(owner_id, money_cost):
		return false
	GameState.add_money(-money_cost)
	_advance_time(int(snapshot.get("time_slots", 0)))
	GameState.completed_action_transactions.append(normalized_id)
	GameState.action_transaction_history.append(snapshot.duplicate(true))
	_reservations.erase(normalized_id)
	transaction_committed.emit(normalized_id, snapshot.duplicate(true))
	return true


func cancel(transaction_id: String) -> bool:
	var normalized_id: String = transaction_id.strip_edges()
	if not _reservations.erase(normalized_id):
		return false
	transaction_cancelled.emit(normalized_id)
	return true


func is_committed(transaction_id: String) -> bool:
	return transaction_id.strip_edges() in GameState.completed_action_transactions


func get_reservation(transaction_id: String) -> Dictionary:
	var value: Variant = _reservations.get(transaction_id.strip_edges(), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _can_prepare(owner_id: String, money_cost: int) -> bool:
	var lock_manager: Node = get_node_or_null("/root/StoryLockManager")
	if lock_manager != null and lock_manager.has_method("can_consume_time") \
		and not bool(lock_manager.call("can_consume_time", owner_id)):
		return false
	return int(GameState.money) >= money_cost


func _advance_time(slot_count: int) -> void:
	for _index: int in range(maxi(slot_count, 0)):
		var old_day: int = int(GameState.day)
		var old_slot: int = int(GameState.time_slot)
		if old_slot >= GameState.TIME_SLOT_NIGHT:
			GameState.day = old_day + 1
			GameState.time_slot = GameState.TIME_SLOT_MORNING
			GameState.day_changed.emit(GameState.day)
		else:
			GameState.time_slot = old_slot + 1
		GameState.time_slot_changed.emit(GameState.time_slot)
