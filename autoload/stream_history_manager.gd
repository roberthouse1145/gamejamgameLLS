extends Node
## 已结束直播的持久化记录入口。

signal history_changed()
signal record_added(record: StreamSessionRecord)


func get_records() -> Array[StreamSessionRecord]:
	var result: Array[StreamSessionRecord] = []
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state == null:
		return result
	var stored_records: Array = game_state.get("stream_history")
	for index: int in range(stored_records.size() - 1, -1, -1):
		result.append(StreamSessionRecord.from_dict(stored_records[index]))
	return result


func get_latest_record() -> StreamSessionRecord:
	var records: Array[StreamSessionRecord] = get_records()
	return records[0] if not records.is_empty() else null


func add_record(record: StreamSessionRecord) -> bool:
	if record == null or record.session_id.is_empty():
		return false
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state == null:
		return false
	var stored_records: Array[Dictionary] = []
	stored_records.assign(game_state.get("stream_history"))
	stored_records.append(record.to_dict())
	game_state.set("stream_history", stored_records)
	record_added.emit(record)
	history_changed.emit()
	return true


func record_completed_stream(plan: Dictionary, result: Dictionary) -> StreamSessionRecord:
	var record := StreamSessionRecord.new()
	record.session_id = str(result.get("session_id", "day_%d_slot_%d_%d" % [GameState.day, GameState.time_slot, Time.get_unix_time_from_system()]))
	record.day = int(result.get("day", GameState.day))
	record.time_slot = int(result.get("time_slot", GameState.time_slot))
	record.title = str(plan.get("title", "未命名直播"))
	record.persona_name = str(plan.get("persona_name", ""))
	record.material_name = str(plan.get("material_name", ""))
	for card_value: Variant in plan.get("card_ids", []):
		record.card_ids.append(StringName(str(card_value)))
	record.heat = int(result.get("heat", 0))
	record.revenue = int(result.get("revenue", 0))
	record.fan_delta = int(result.get("fan_delta", 0))
	record.stress_delta = int(result.get("stress_delta", 0))
	record.flame_delta = float(result.get("flame_delta", 0.0))
	record.summary = str(result.get("summary", ""))
	return record if add_record(record) else null


func reset_history() -> void:
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.set("stream_history", [])
	history_changed.emit()
