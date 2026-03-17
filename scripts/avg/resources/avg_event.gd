class_name AVGEvent extends Resource
## AVG Event Resource
## Stores a reusable command list that can be called via CALL_EVENT command.
## Uses slot-based ID system: event_id = "event_NNN" where NNN is the slot number.

## 槽位 ID（如 event_001），由槽位号决定，不可编辑
@export var event_id: String = ""
@export var event_name: String = "New Event"
@export var commands: Array = []  # Array of AVGCommand


func get_avg_properties() -> Array[Dictionary]:
	return [
		{"name": "event_id", "type": TYPE_STRING, "editable": false, "visible": true, "category": "系统"},
		{"name": "event_name", "type": TYPE_STRING, "editable": true, "category": "基本"},
	]


## 从槽位号生成 ID
static func make_id(slot: int) -> String:
	return "event_%03d" % slot
