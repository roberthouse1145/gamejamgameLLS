class_name StreamSessionRecord extends Resource
## 一场已结束直播的只读快照。

@export var session_id: String = ""
@export var day: int = 1
@export var time_slot: int = 0
@export var title: String = ""
@export var persona_name: String = ""
@export var material_name: String = ""
@export var card_ids: Array[StringName] = []
@export var heat: int = 0
@export var revenue: int = 0
@export var fan_delta: int = 0
@export var stress_delta: int = 0
@export var flame_delta: float = 0.0
@export_multiline var summary: String = ""


func to_dict() -> Dictionary:
	var serialized_card_ids: Array[String] = []
	for card_id: StringName in card_ids:
		serialized_card_ids.append(String(card_id))
	return {
		"session_id": session_id,
		"day": day,
		"time_slot": time_slot,
		"title": title,
		"persona_name": persona_name,
		"material_name": material_name,
		"card_ids": serialized_card_ids,
		"heat": heat,
		"revenue": revenue,
		"fan_delta": fan_delta,
		"stress_delta": stress_delta,
		"flame_delta": flame_delta,
		"summary": summary,
	}


static func from_dict(data: Dictionary) -> StreamSessionRecord:
	var record := StreamSessionRecord.new()
	record.session_id = str(data.get("session_id", ""))
	record.day = int(data.get("day", 1))
	record.time_slot = int(data.get("time_slot", 0))
	record.title = str(data.get("title", ""))
	record.persona_name = str(data.get("persona_name", ""))
	record.material_name = str(data.get("material_name", ""))
	for card_id: Variant in data.get("card_ids", []):
		record.card_ids.append(StringName(str(card_id)))
	record.heat = int(data.get("heat", 0))
	record.revenue = int(data.get("revenue", 0))
	record.fan_delta = int(data.get("fan_delta", 0))
	record.stress_delta = int(data.get("stress_delta", 0))
	record.flame_delta = float(data.get("flame_delta", 0.0))
	record.summary = str(data.get("summary", ""))
	return record
