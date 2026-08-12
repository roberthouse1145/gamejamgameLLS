class_name StreamHistoryStore extends RefCounted
## 直播历史的 Resource/Dictionary 转换与 GameState 存储边界。

var _game_state: Node


func _init(game_state: Node) -> void:
	_game_state = game_state


func get_records() -> Array[StreamSessionRecord]:
	var result: Array[StreamSessionRecord] = []
	if _game_state == null:
		return result
	var stored_records: Array = _game_state.get("stream_history")
	for index: int in range(stored_records.size() - 1, -1, -1):
		result.append(StreamSessionRecord.from_dict(stored_records[index]))
	return result


func get_latest_record() -> StreamSessionRecord:
	var records: Array[StreamSessionRecord] = get_records()
	return records[0] if not records.is_empty() else null


func get_recent_records_for_persona(
	persona_id: StringName,
	limit: int = 3
) -> Array[StreamSessionRecord]:
	var result: Array[StreamSessionRecord] = []
	if persona_id == &"" or limit <= 0:
		return result
	for record: StreamSessionRecord in get_records():
		if record.persona_id != persona_id or record.summary.strip_edges().is_empty():
			continue
		result.append(record)
		if result.size() >= limit:
			break
	return result


func get_record_count_for_persona(persona_id: StringName) -> int:
	if persona_id == &"":
		return 0
	var count: int = 0
	for record: StreamSessionRecord in get_records():
		if record.persona_id == persona_id:
			count += 1
	return count


func add_record(record: StreamSessionRecord) -> bool:
	if record == null or record.session_id.is_empty() or _game_state == null:
		return false
	var stored_records: Array[Dictionary] = []
	stored_records.assign(_game_state.get("stream_history"))
	stored_records.append(record.to_dict())
	_game_state.set("stream_history", stored_records)
	return true


func create_completed_record(plan: Dictionary, result: Dictionary) -> StreamSessionRecord:
	if _game_state == null:
		return null
	var day: int = int(_game_state.get("day"))
	var time_slot: int = int(_game_state.get("time_slot"))
	var record := StreamSessionRecord.new()
	record.session_id = str(result.get("session_id", "day_%d_slot_%d_%d" % [day, time_slot, Time.get_unix_time_from_system()]))
	record.day = int(result.get("day", day))
	record.time_slot = int(result.get("time_slot", time_slot))
	record.title = str(plan.get("title", "未命名直播"))
	record.persona_id = StringName(str(plan.get("persona_id", "")))
	record.persona_name = str(plan.get("persona_name", ""))
	record.material_name = str(plan.get("material_name", ""))
	record.approach_name = str(plan.get("approach_name", ""))
	record.approach_type = StringName(str(plan.get("approach_type", "")))
	record.heat = int(result.get("heat", 0))
	record.revenue = int(result.get("revenue", 0))
	record.fan_delta = int(result.get("fan_delta", 0))
	record.stress_delta = int(result.get("stress_delta", 0))
	record.flame_delta = float(result.get("flame_delta", 0.0))
	record.summary = str(result.get("summary", ""))
	return record if add_record(record) else null


func reset_history() -> void:
	if _game_state != null:
		_game_state.set("stream_history", [])
